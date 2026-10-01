import SwiftUI
import UniformTypeIdentifiers

/// GUI for the CSV playlist importer (Exportify CSVs -> Navidrome playlists,
/// missing tracks downloaded from YouTube via SpotFetch).
struct ImportView: View {
    @EnvironmentObject private var app: AppState
    @StateObject private var runner = ImportRunner()

    @State private var csvFiles: [URL] = []
    @State private var showCSVPicker = false
    @State private var showMusicDirPicker = false
    @State private var showSpotFetchPicker = false

    @AppStorage("importMusicDir") private var musicDir = ""
    @AppStorage("importSpotFetchDir") private var spotfetchDir =
        NSString(string: "~/Documents/Projects/spotiloader/SpotFetch").expandingTildeInPath
    @AppStorage("importPythonPath") private var pythonPath = "/usr/bin/python3"
    @AppStorage("importFormat") private var format = "mp3"
    @AppStorage("importPlatform") private var platform = "youtube"
    @AppStorage("importDownloadMissing") private var downloadMissing = true
    @AppStorage("importStarLikedSongs") private var starLikedSongs = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Import Playlists")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.spText)

                Text("Move your Spotify playlists from Exportify CSV files. Wallsy matches library tracks first, then downloads missing tracks through SpotFetch and saves a report for retrying unmatched songs.")
                    .font(.system(size: 12))
                    .foregroundColor(.spSubtext)

                Link(destination: URL(string: "https://exportify.app/")!) {
                    Label("Export Spotify playlists and Liked Songs as CSV", systemImage: "arrow.up.right.square")
                        .font(.system(size: 12, weight: .medium))
                }

                // CSV files
                groupBox("CSV FILES") {
                    if csvFiles.isEmpty {
                        Text("No files selected")
                            .font(.system(size: 12))
                            .foregroundColor(.spSubtext)
                    } else {
                        ForEach(csvFiles, id: \.self) { url in
                            HStack {
                                Image(systemName: "doc.text")
                                    .foregroundColor(.spAccent)
                                Text(url.lastPathComponent)
                                    .font(.system(size: 12))
                                    .foregroundColor(.spText)
                                Spacer()
                                Button {
                                    csvFiles.removeAll { $0 == url }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.spSubtext)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Button("Add CSV Files…") { showCSVPicker = true }
                        .controlSize(.small)
                    Toggle("Add tracks from Liked Songs CSV to Navidrome favorites", isOn: $starLikedSongs)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                }

                // Download options
                groupBox("DOWNLOAD MISSING TRACKS") {
                    Toggle("Download tracks that aren't in the library", isOn: $downloadMissing)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))

                    if downloadMissing {
                        pathRow(label: "Navidrome music folder (mounted on this Mac)", value: musicDir.isEmpty ? "not set" : musicDir) {
                            showMusicDirPicker = true
                        }
                        Text("Downloads are saved on this Mac. If Navidrome runs on another machine, choose a mounted share of its music folder; a local Downloads folder will not be scanned by the server.")
                            .font(.system(size: 11))
                            .foregroundColor(.spSubtext)
                        pathRow(label: "SpotFetch folder", value: spotfetchDir) {
                            showSpotFetchPicker = true
                        }
                        HStack(spacing: 14) {
                            Picker("Format", selection: $format) {
                                Text("mp3").tag("mp3")
                                Text("m4a").tag("m4a")
                                Text("flac").tag("flac")
                            }
                            .frame(width: 140)
                            Picker("Source", selection: $platform) {
                                Text("YouTube").tag("youtube")
                                Text("YT Music").tag("ytmusic")
                            }
                            .frame(width: 160)
                        }
                        .font(.system(size: 12))
                        if format == "flac" {
                            Text("YouTube audio is usually lossy; converting it to FLAC does not make it lossless.")
                                .font(.system(size: 11))
                                .foregroundColor(.spSubtext)
                        }

                        HStack {
                            Text("Python")
                                .font(.system(size: 12))
                                .foregroundColor(.spSubtext)
                            TextField("/usr/bin/python3", text: $pythonPath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                                .frame(maxWidth: 360)
                        }
                        Text("The built-in importer supports Python 3.9+. For downloads, choose SpotFetch's Python environment with its dependencies installed.")
                            .font(.system(size: 11))
                            .foregroundColor(.spSubtext)
                    }
                }

                // Run controls
                HStack(spacing: 12) {
                    Button {
                        startImport()
                    } label: {
                        Label(runner.isRunning ? "Running…" : "Run Import", systemImage: "play.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.spText)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(canRun ? Color.spAccentFill : Color.spAccentFill.opacity(0.35)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canRun)

                    if runner.isRunning {
                        Button("Stop") { runner.stop() }
                            .controlSize(.small)
                    }
                    if !runner.log.isEmpty && !runner.isRunning {
                        Button("Clear Log") { runner.clearLog() }
                            .controlSize(.small)
                    }
                    if runner.canRetryMissing {
                        Button("Retry \(runner.missing) missing") { runner.retryMissing() }
                            .controlSize(.small)
                    }
                }

                if runner.isRunning && runner.total > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(runner.currentTrack)
                                .lineLimit(1)
                            Spacer()
                            Text("\(runner.completed)/\(runner.total)")
                                .monospacedDigit()
                        }
                        .font(.system(size: 12))
                        .foregroundColor(.spSubtext)
                        ProgressView(value: Double(runner.completed), total: Double(runner.total))
                            .tint(.spAccent)
                    }
                }

                if runner.didFinish && !runner.isRunning {
                    Text("Already in Navidrome: \(runner.alreadyInLibrary) · Downloaded: \(runner.downloaded) · Still missing: \(runner.missing)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.spSubtext)
                }

                // Log output
                if !runner.log.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            Text(runner.log)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .textSelection(.enabled)
                            Color.clear.frame(height: 1).id("logEnd")
                        }
                        .frame(height: 260)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.6)))
                        .onChange(of: runner.log) {
                            proxy.scrollTo("logEnd", anchor: .bottom)
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.spBackground)
        .onChange(of: runner.didFinish) {
            if runner.didFinish { Task { await app.refreshLibrary() } }
        }
        .fileImporter(isPresented: $showCSVPicker,
                      allowedContentTypes: [.commaSeparatedText, .plainText],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for url in urls where !csvFiles.contains(url) {
                    csvFiles.append(url)
                }
            }
        }
        .fileImporter(isPresented: $showMusicDirPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { musicDir = url.path }
        }
        .fileImporter(isPresented: $showSpotFetchPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { spotfetchDir = url.path }
        }
        .onAppear(perform: selectSpotFetchPythonIfAvailable)
        .onChange(of: spotfetchDir) {
            selectSpotFetchPythonIfAvailable()
        }
    }

    private var canRun: Bool {
        guard !runner.isRunning, !csvFiles.isEmpty, app.client != nil else { return false }
        if downloadMissing && musicDir.isEmpty { return false }
        return true
    }

    private func selectSpotFetchPythonIfAvailable() {
        guard pythonPath == "/usr/bin/python3" else { return }
        let candidate = URL(fileURLWithPath: spotfetchDir)
            .appendingPathComponent(".venv/bin/python3").path
        if FileManager.default.isExecutableFile(atPath: candidate) {
            pythonPath = candidate
        }
    }

    private func startImport() {
        guard let client = app.client else { return }
        runner.run(ImportRunner.Options(
            csvFiles: csvFiles,
            server: client.config.baseURL.absoluteString,
            username: client.config.username,
            password: client.config.password,
            musicDir: musicDir,
            spotfetchDir: spotfetchDir,
            pythonPath: pythonPath,
            format: format,
            platform: platform,
            downloadMissing: downloadMissing,
            starLikedSongs: starLikedSongs
        ))
    }

    // MARK: - Small helpers

    private func groupBox<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(1.3)
                .foregroundColor(.spSubtext)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.spCard))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.spBorder, lineWidth: 1)
        }
    }

    private func pathRow(label: String, value: String, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.spSubtext)
                Text(value)
                    .font(.system(size: 12))
                    .foregroundColor(.spText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Choose…", action: action)
                .controlSize(.small)
        }
    }
}
