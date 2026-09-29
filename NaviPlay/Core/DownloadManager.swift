import Foundation

/// Downloads original audio files into a local cache for offline playback.
/// Keeps a JSON index of song metadata so the cache is browsable offline.
/// Per-song download state for UI badges.
enum DownloadStatus: Equatable {
    case notCached
    case queued
    case downloading(Double) // 0...1
    case cached
}

@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var activeCount = 0
    @Published private(set) var cachedFiles: [String: URL] = [:] // songId -> file URL
    @Published private(set) var cachedIndex: [String: Song] = [:] // songId -> metadata
    @Published private(set) var cacheSizeBytes: Int64 = 0
    @Published private(set) var lastError: String?

    // Live progress state.
    @Published private(set) var queuedIds: Set<String> = []
    @Published private(set) var currentId: String?
    @Published private(set) var currentProgress: Double = 0
    @Published private(set) var batchTotal = 0
    @Published private(set) var batchDone = 0
    @Published private(set) var isPaused = false

    var client: SubsonicClient? {
        didSet { if client != nil { startProcessingIfNeeded() } }
    }

    private static let dirKey = "cacheDirectoryPath"
    private var downloadQueue: [Song] = []
    private var working = false
    private var processingTask: Task<Void, Never>?
    private var inFlightSong: Song?

    init() {
        refresh()
    }

    /// Filesystem-safe key derived from a song id; used consistently for
    /// filenames and cache lookups.
    static func safeKey(_ id: String) -> String {
        id.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "_", options: .regularExpression)
    }

    /// Cached songs with metadata, for the offline Downloads view.
    var cachedSongs: [Song] {
        cachedIndex.values
            .filter { cachedFiles[Self.safeKey($0.id)] != nil }
            .sorted {
                ($0.artist ?? "", $0.title) < ($1.artist ?? "", $1.title)
            }
    }

    // MARK: - Cache directory

    var cacheDirectory: URL {
        if let path = UserDefaults.standard.string(forKey: Self.dirKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Wallsy", isDirectory: true)
    }

    private var indexURL: URL {
        cacheDirectory.appendingPathComponent("wallsy_index.json")
    }

    private var pendingQueueURL: URL {
        cacheDirectory.appendingPathComponent("wallsy_pending_downloads.json")
    }

    private func persistQueue() {
        let pending = (inFlightSong.map { [$0] } ?? []) + downloadQueue
        if let data = try? JSONEncoder().encode(pending) {
            try? data.write(to: pendingQueueURL, options: .atomic)
        }
    }

    func setCacheDirectory(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: Self.dirKey)
        refresh()
    }

    func refresh() {
        let dir = cacheDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Load the metadata index from disk and MERGE it with in-memory
        // entries (in-memory wins) so refreshing mid-download never loses
        // metadata that hasn't been persisted yet.
        var index: [String: Song] = [:]
        if let data = try? Data(contentsOf: indexURL),
           let stored = try? JSONDecoder().decode([String: Song].self, from: data) {
            index = stored
        }
        for (id, song) in cachedIndex {
            index[id] = song
        }
        cachedIndex = index
        if !working, downloadQueue.isEmpty,
           let data = try? Data(contentsOf: pendingQueueURL),
           let pending = try? JSONDecoder().decode([Song].self, from: data) {
            downloadQueue = pending
            queuedIds = Set(pending.map(\.id))
            activeCount = pending.count
            batchTotal = pending.count
        }

        // Scan audio files.
        var files: [String: URL] = [:]
        var total: Int64 = 0
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for file in contents where !["wallsy_index.json", "wallsy_pending_downloads.json"].contains(file.lastPathComponent) && file.pathExtension != "part" {
            let id = file.deletingPathExtension().lastPathComponent
            files[id] = file
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        cachedFiles = files
        cacheSizeBytes = total
    }

    private func persistIndex() {
        if let data = try? JSONEncoder().encode(cachedIndex) {
            try? data.write(to: indexURL)
        }
    }

    /// Files on disk that have no metadata entry (e.g. downloaded by an older
    /// app version, or after an index mishap). Keyed by filename stem.
    private var orphanFileKeys: [String] {
        let indexedKeys = Set(cachedIndex.keys.map { Self.safeKey($0) })
        return cachedFiles.keys.filter { !indexedKeys.contains($0) }
    }

    /// Fetches metadata from the server for cached files missing from the
    /// index, so they show up in the Downloads tab. Safe to call repeatedly.
    func reconcileMissingMetadata() async {
        guard let client else { return }
        let orphans = orphanFileKeys
        guard !orphans.isEmpty else { return }
        var healed = 0
        for key in orphans {
            // Navidrome IDs are alphanumeric, so the filename stem is the id.
            if let song = try? await client.song(id: key) {
                cachedIndex[song.id] = song
                healed += 1
            }
        }
        if healed > 0 {
            persistIndex()
        }
    }

    func clearCache() {
        for url in cachedFiles.values {
            try? FileManager.default.removeItem(at: url)
        }
        try? FileManager.default.removeItem(at: indexURL)
        try? FileManager.default.removeItem(at: pendingQueueURL)
        downloadQueue = []
        inFlightSong = nil
        queuedIds = []
        refresh()
    }

    // MARK: - Lookup

    func localURL(for song: Song) -> URL? {
        cachedFiles[Self.safeKey(song.id)]
    }

    func isCached(_ song: Song) -> Bool {
        cachedFiles[Self.safeKey(song.id)] != nil
    }

    func allCached(_ songs: [Song]) -> Bool {
        !songs.isEmpty && songs.allSatisfy { isCached($0) }
    }

    func status(for song: Song) -> DownloadStatus {
        if isCached(song) { return .cached }
        if song.id == currentId { return .downloading(currentProgress) }
        if queuedIds.contains(song.id) { return .queued }
        return .notCached
    }

    /// Overall batch progress 0...1 (includes the partially downloaded track).
    var batchProgress: Double {
        guard batchTotal > 0 else { return 0 }
        return min((Double(batchDone) + currentProgress) / Double(batchTotal), 1)
    }

    // MARK: - Downloading

    func download(_ songs: [Song]) {
        let new = songs.filter { song in
            !isCached(song) && !downloadQueue.contains(where: { $0.id == song.id })
        }
        guard !new.isEmpty else { return }
        downloadQueue.append(contentsOf: new)
        for song in new {
            queuedIds.insert(song.id)
        }
        activeCount = downloadQueue.count
        persistQueue()
        if working {
            batchTotal += new.count
        } else {
            batchTotal = downloadQueue.count
            batchDone = 0
            startProcessingIfNeeded()
        }
    }

    func pauseDownloads() {
        guard working else { return }
        isPaused = true
        processingTask?.cancel()
    }

    func resumeDownloads() {
        isPaused = false
        lastError = nil
        startProcessingIfNeeded()
    }

    private func startProcessingIfNeeded() {
        guard client != nil, !working, !isPaused, !downloadQueue.isEmpty else { return }
        working = true
        processingTask = Task { await processQueue() }
    }

    private func processQueue() async {
        defer {
            working = false
            processingTask = nil
            activeCount = downloadQueue.count
            currentId = nil
            currentProgress = 0
            if downloadQueue.isEmpty {
                queuedIds = []
                batchTotal = 0
                batchDone = 0
            }
            persistQueue()
            persistIndex()
            refresh()
            if !isPaused && !downloadQueue.isEmpty {
                Task { self.startProcessingIfNeeded() }
            }
        }
        while !downloadQueue.isEmpty && !isPaused && !Task.isCancelled {
            let song = downloadQueue.removeFirst()
            inFlightSong = song
            queuedIds.remove(song.id)
            persistQueue()
            activeCount = downloadQueue.count + 1
            currentId = song.id
            currentProgress = 0
            let succeeded = await downloadOne(song)
            if isPaused || Task.isCancelled || !succeeded {
                downloadQueue.insert(song, at: 0)
                queuedIds.insert(song.id)
                inFlightSong = nil
                if !succeeded && !Task.isCancelled { isPaused = true }
                break
            }
            batchDone += 1
            currentId = nil
            inFlightSong = nil
            persistQueue()
        }
    }

    private func downloadOne(_ song: Song) async -> Bool {
        guard let client else { return false }
        if isCached(song) { return true }
        // format=raw asks Navidrome for the original file (no transcoding).
        let url = client.url(for: "stream", params: ["id": song.id, "format": "raw"])

        // Sanitize server-provided values before using them as a filename.
        let safeId = Self.safeKey(song.id)
        let ext = (song.suffix ?? "mp3").replacingOccurrences(of: "[^A-Za-z0-9]", with: "", options: .regularExpression)
        let dest = cacheDirectory.appendingPathComponent("\(safeId).\(ext.isEmpty ? "mp3" : ext)")
        let partial = cacheDirectory.appendingPathComponent("\(safeId).part")

        for attempt in 0..<3 {
            do {
                try await Self.fetchFile(from: url, to: partial) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.currentId == song.id else { return }
                        self.currentProgress = progress
                    }
                }
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: partial, to: dest)
                cachedFiles[safeId] = dest
                cachedIndex[song.id] = song
                persistIndex()
                lastError = nil
                return true
            } catch {
                if Task.isCancelled || isPaused { return false }
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 1_000_000_000)
                } else {
                    lastError = "Failed to download \u{201C}\(song.title)\u{201D}: \(error.localizedDescription). Select it again to resume."
                }
            }
        }
        return false
    }

    /// Streams a URL to disk off the main actor, reporting progress in ~2% steps.
    private nonisolated static func fetchFile(
        from url: URL,
        to destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let existing = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        var request = URLRequest(url: url)
        if existing > 0 { request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range") }
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let rangeMatches = http.statusCode == 206
            && http.value(forHTTPHeaderField: "Content-Range")?.hasPrefix("bytes \(existing)-") == true
        let offset = rangeMatches ? existing : 0
        let expected = response.expectedContentLength > 0
            ? offset + response.expectedContentLength : -1

        if offset == 0 {
            FileManager.default.createFile(atPath: destination.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }
        if offset > 0 { try handle.seekToEnd() }
        else { try handle.truncate(atOffset: 0) }

        let chunkSize = 512 * 1024
        var buffer = Data()
        buffer.reserveCapacity(chunkSize)
        var written: Int64 = 0
        var lastReported = 0.0

        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= chunkSize {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if expected > 0 {
                    let progress = Double(offset + written) / Double(expected)
                    if progress - lastReported >= 0.02 {
                        lastReported = progress
                        onProgress(min(progress, 1))
                    }
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }
        onProgress(1)
    }
}
