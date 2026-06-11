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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Import Playlists")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(.white)

                Text("Builds Navidrome playlists from Exportify CSV files. Tracks missing from the library are downloaded from YouTube via SpotFetch, then the library is rescanned.")
                    .font(.system(size: 12))
                    .foregroundColor(.spSubtext)

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
                                    .foregroundColor(.spGreen)
                                Text(url.lastPathComponent)
                                    .font(.system(size: 12))
                                    .foregroundColor(.white)
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
                }

                // Download options
                groupBox("DOWNLOAD MISSING TRACKS") {
                    Toggle("Download tracks that aren't in the library", isOn: $downloadMissing)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))

                    if downloadMissing {
                        pathRow(label: "Music folder (scanned by Navidrome)", value: musicDir.isEmpty ? "not set" : musicDir) {
                            showMusicDirPicker = true
                        }
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

                        HStack {
                            Text("Python")
                                .font(.system(size: 12))
                                .foregroundColor(.spSubtext)
                            TextField("/usr/bin/python3", text: $pythonPath)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 12))
                                .frame(maxWidth: 360)
                        }
                        Text("Use the SpotFetch virtualenv's python if yt-dlp isn't installed globally, e.g. …/SpotFetch/venv/bin/python3")
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
                            .foregroundColor(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(canRun ? Color.spGreen : Color.spGreen.opacity(0.35)))
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
    }

    private var canRun: Bool {
        guard !runner.isRunning, !csvFiles.isEmpty, app.client != nil else { return false }
        if downloadMissing && musicDir.isEmpty { return false }
        return true
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
            downloadMissing: downloadMissing
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
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.spCard))
    }

    private func pathRow(label: String, value: String, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(.spSubtext)
                Text(value)
                    .font(.system(size: 12))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button("Choose…", action: action)
                .controlSize(.small)
        }
    }
}
