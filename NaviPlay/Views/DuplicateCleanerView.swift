import SwiftUI
import AppKit

struct DuplicateCleanerView: View {
    @EnvironmentObject private var app: AppState
    @State private var isWorking = false
    @State private var scanTask: Task<Void, Never>?
    @State private var groups: [DuplicateGroup] = []
    @State private var selectedIDs: Set<String> = []
    @State private var keepers: [String: String] = [:]
    @State private var message = "Scan the connected Navidrome library for matching audio streams."
    @State private var progress = ""

    private var selectedExtras: [Song] {
        groups.filter { selectedIDs.contains($0.id) }.flatMap { group in
            let keeper = keepers[group.id] ?? group.songs[0].id
            return group.songs.filter { $0.id != keeper }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Server duplicates")
                    .font(.system(size: 18, weight: .semibold))
                Text("Compare the original audio files in your Navidrome library by SHA-256.")
                    .font(.system(size: 12))
                    .foregroundColor(.spSubtext)
            }

            HStack {
                Text(app.client?.config.baseURL.host ?? "No server connected")
                    .font(.system(size: 12))
                    .foregroundColor(.spSubtext)
                    .lineLimit(1)
                Spacer()
                if isWorking {
                    Button("Cancel") { scanTask?.cancel() }
                } else {
                    Button("Scan Server") { scan() }
                        .disabled(app.client == nil || app.isOffline)
                }
            }

            if isWorking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(progress).font(.system(size: 11)).foregroundColor(.spSubtext)
                }
            }
            Text(message)
                .font(.system(size: 12))
                .foregroundColor(.spSubtext)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(groups) { group in groupCard(group) }
                }
            }

            HStack {
                Text("Selected: \(selectedExtras.count) entries to review")
                    .font(.system(size: 12))
                    .foregroundColor(.spSubtext)
                Spacer()
                Button("Copy Review Report") { copyCleanupList() }
                    .disabled(selectedExtras.isEmpty)
            }
            Text("Matching streams may be two files or two library entries for one file. Navidrome paths may be virtual. Verify real server files before deleting anything.")
                .font(.system(size: 11))
                .foregroundColor(.spSubtext)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .background(Color.spBackground)
        .onDisappear { scanTask?.cancel() }
    }

    private func groupCard(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Toggle(isOn: Binding(
                get: { selectedIDs.contains(group.id) },
                set: { enabled in
                    if enabled { selectedIDs.insert(group.id) }
                    else { selectedIDs.remove(group.id) }
                }
            )) {
                Text("\(group.songs.count) matching streams • \(ByteCountFormatter.string(fromByteCount: group.bytesPerSong, countStyle: .file)) each")
                    .font(.system(size: 12, weight: .semibold))
            }
            .toggleStyle(.checkbox)

            if group.hasSameReportedPath {
                Text("Same reported path — this may be one file indexed twice.")
                    .font(.system(size: 11))
                    .foregroundColor(.spSubtext)
            }

            Picker("Preferred entry", selection: Binding(
                get: { keepers[group.id] ?? group.songs[0].id },
                set: { keepers[group.id] = $0 }
            )) {
                ForEach(group.songs) { song in
                    Text("\(song.artist ?? "Unknown artist") — \(song.title) · \(song.path ?? song.id)")
                        .tag(song.id)
                }
            }
            .font(.system(size: 11))
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.spCard))
    }

    private func scan() {
        guard let client = app.client, !app.isOffline else { return }
        isWorking = true
        groups = []
        selectedIDs = []
        keepers = [:]
        progress = "Loading the server library…"
        message = "Reading song metadata from Navidrome."

        scanTask = Task {
            do {
                let songs = try await client.allSongs(maxSongs: Int.max)
                try Task.checkCancellation()
                let candidates = DuplicateScanner.candidates(from: songs)
                let missingSize = songs.filter { ($0.size ?? 0) <= 0 }.count
                progress = "Checking 0 of \(candidates.count) possible copies…"
                var fingerprints: [ServerSongFingerprint] = []
                for (index, song) in candidates.enumerated() {
                    try Task.checkCancellation()
                    let result = try await client.rawSongDigest(id: song.id)
                    fingerprints.append(ServerSongFingerprint(song: song, digest: result.digest, size: result.size))
                    progress = "Checking \(index + 1) of \(candidates.count) possible copies…"
                }
                groups = DuplicateScanner.exactGroups(from: fingerprints)
                let sharedPaths = groups.filter(\.hasSameReportedPath).count
                message = groups.isEmpty
                    ? "No matching streams among \(songs.count) server tracks."
                    : "Found \(groups.count) matching stream groups among \(songs.count) server tracks; \(sharedPaths) have the same reported path."
                if missingSize > 0 {
                    message += " \(missingSize) tracks had no file size and could not be compared."
                }
            } catch is CancellationError {
                message = "Scan canceled."
            } catch {
                message = "Scan failed: \(error.localizedDescription)"
            }
            isWorking = false
            scanTask = nil
            progress = ""
        }
    }

    private func copyCleanupList() {
        guard let server = app.client?.config.baseURL.absoluteString else { return }
        var lines = ["Navidrome duplicate review — no files have been removed", "Server: \(server)", "Reported paths may be virtual. Confirm real files on the server before deleting anything.", ""]
        for group in groups where selectedIDs.contains(group.id) {
            let keeper = keepers[group.id] ?? group.songs[0].id
            lines.append("SHA-256: \(group.id.split(separator: ":").last.map(String.init) ?? group.id)")
            if group.hasSameReportedPath {
                lines.append("SAME REPORTED PATH: possibly one physical file indexed twice; do not delete by this path alone.")
            }
            for song in group.songs {
                let action = song.id == keeper ? "PREFERRED ENTRY" : "CHECK ENTRY"
                lines.append("\(action) | \(song.artist ?? "Unknown artist") — \(song.title) | ID: \(song.id) | Reported path: \(song.path ?? "unavailable")")
            }
            lines.append("")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
        message = "Review report copied. Verify real server files before removing anything."
    }
}
