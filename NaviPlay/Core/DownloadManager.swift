import Foundation

/// Downloads original audio files into a local cache for offline playback.
/// Keeps a JSON index of song metadata so the cache is browsable offline.
@MainActor
final class DownloadManager: ObservableObject {
    @Published private(set) var activeCount = 0
    @Published private(set) var cachedFiles: [String: URL] = [:] // songId -> file URL
    @Published private(set) var cachedIndex: [String: Song] = [:] // songId -> metadata
    @Published private(set) var cacheSizeBytes: Int64 = 0
    @Published private(set) var lastError: String?

    var client: SubsonicClient?

    private static let dirKey = "cacheDirectoryPath"
    private var downloadQueue: [Song] = []
    private var working = false

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

    func setCacheDirectory(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: Self.dirKey)
        refresh()
    }

    func refresh() {
        let dir = cacheDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Load metadata index.
        if let data = try? Data(contentsOf: indexURL),
           let index = try? JSONDecoder().decode([String: Song].self, from: data) {
            cachedIndex = index
        } else {
            cachedIndex = [:]
        }

        // Scan audio files.
        var files: [String: URL] = [:]
        var total: Int64 = 0
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for file in contents where file.lastPathComponent != "wallsy_index.json" {
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

    func clearCache() {
        for url in cachedFiles.values {
            try? FileManager.default.removeItem(at: url)
        }
        try? FileManager.default.removeItem(at: indexURL)
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

    // MARK: - Downloading

    func download(_ songs: [Song]) {
        let new = songs.filter { song in
            !isCached(song) && !downloadQueue.contains(where: { $0.id == song.id })
        }
        guard !new.isEmpty else { return }
        downloadQueue.append(contentsOf: new)
        activeCount = downloadQueue.count
        if !working {
            working = true
            Task { await processQueue() }
        }
    }

    private func processQueue() async {
        defer {
            working = false
            activeCount = 0
            persistIndex()
            refresh()
        }
        while !downloadQueue.isEmpty {
            let song = downloadQueue.removeFirst()
            activeCount = downloadQueue.count + 1
            await downloadOne(song)
        }
    }

    private func downloadOne(_ song: Song) async {
        guard let client, !isCached(song) else { return }
        // format=raw asks Navidrome for the original file (no transcoding).
        let url = client.url(for: "stream", params: ["id": song.id, "format": "raw"])
        do {
            let (tmp, response) = try await URLSession.shared.download(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            // Sanitize server-provided values before using them as a filename.
            let safeId = Self.safeKey(song.id)
            let ext = (song.suffix ?? "mp3").replacingOccurrences(of: "[^A-Za-z0-9]", with: "", options: .regularExpression)
            let dest = cacheDirectory.appendingPathComponent("\(safeId).\(ext.isEmpty ? "mp3" : ext)")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            cachedFiles[safeId] = dest
            cachedIndex[song.id] = song
        } catch {
            lastError = "Failed to download \u{201C}\(song.title)\u{201D}: \(error.localizedDescription)"
        }
    }
}
