import Foundation

/// Runs the bundled wallsy_import.py as a subprocess with live log output.
@MainActor
final class ImportRunner: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var log: String = ""
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var missing = 0
    @Published private(set) var downloaded = 0
    @Published private(set) var alreadyInLibrary = 0
    @Published private(set) var didFinish = false
    @Published private(set) var currentTrack = ""

    private var process: Process?
    private var lastOptions: Options?
    private var pendingOutput = ""
    private var scopedURLs: [URL] = []

    struct Options {
        var csvFiles: [URL]
        var server: String
        var username: String
        var password: String
        var musicDir: String
        var spotfetchDir: String
        var pythonPath: String
        var format: String
        var platform: String
        var downloadMissing: Bool
        var starLikedSongs: Bool
    }

    func run(_ options: Options, retryMissing: Bool = false) {
        guard !isRunning else { return }
        guard let script = Bundle.main.url(forResource: "wallsy_import", withExtension: "py") else {
            log += "[!] Bundled import script not found.\n"
            return
        }

        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: options.pythonPath) else {
            log = "[!] Python is not executable: \(options.pythonPath)\n"
            return
        }
        guard options.csvFiles.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
            log = "[!] One or more CSV files are missing. Select them again.\n"
            return
        }
        if options.downloadMissing {
            guard fileManager.fileExists(atPath: options.spotfetchDir + "/functions.py") else {
                log = "[!] SpotFetch functions.py is missing. Choose the SpotFetch folder.\n"
                return
            }
            guard fileManager.isWritableFile(atPath: options.musicDir) else {
                log = "[!] Music folder is not writable: \(options.musicDir)\n"
                return
            }
            let systemPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
            let inheritedPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
                .split(separator: ":").map(String.init)
            guard (systemPaths + inheritedPaths).contains(where: {
                fileManager.isExecutableFile(atPath: $0 + "/ffmpeg")
            }) else {
                log = "[!] ffmpeg is required by SpotFetch. Install it with Homebrew before downloading.\n"
                return
            }
        }

        scopedURLs = options.csvFiles.filter { $0.startAccessingSecurityScopedResource() }
        let reportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wallsy/Imports", isDirectory: true)
        var arguments: [String] = [script.path]
        arguments += options.csvFiles.map(\.path)
        // The password is passed via environment, not argv, so it never
        // shows up in `ps` output.
        arguments += ["--server", options.server,
                      "--user", options.username,
                      "--format", options.format,
                      "--platform", options.platform,
                      "--report-dir", reportDir.path]
        if retryMissing { arguments.append("--retry-missing") }
        if options.starLikedSongs { arguments.append("--star-liked") }
        if options.downloadMissing {
            arguments += ["--music-dir", options.musicDir,
                          "--spotfetch", options.spotfetchDir]
        } else {
            arguments += ["--no-download"]
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: options.pythonPath)
        task.arguments = arguments
        // Line-buffered output so the log streams promptly.
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        env["WALLSY_PASSWORD"] = options.password
        env["PATH"] = (["/opt/homebrew/bin", "/usr/local/bin"] +
                       (env["PATH"] ?? "").split(separator: ":").map(String.init))
            .joined(separator: ":")
        task.environment = env

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor [weak self] in
                self?.consume(text)
            }
        }

        task.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                pipe.fileHandleForReading.readabilityHandler = nil
                let tail = pipe.fileHandleForReading.readDataToEndOfFile()
                self.consume(String(decoding: tail, as: UTF8.self) + "\n")
                self.log += code == 0
                    ? "\n✔ Import complete. See file counts above.\n"
                    : code == 2
                        ? "\n[!] Import incomplete: some tracks are still missing.\n"
                        : "\n[!] Exited with code \(code).\n"
                self.isRunning = false
                self.process = nil
                self.scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
                self.scopedURLs = []
            }
        }

        log = "Launching import…\n"
        completed = 0
        total = 0
        missing = 0
        downloaded = 0
        alreadyInLibrary = 0
        didFinish = false
        currentTrack = ""
        pendingOutput = ""
        lastOptions = options
        do {
            try task.run()
            process = task
            isRunning = true
        } catch {
            log += "[!] Failed to launch \(options.pythonPath): \(error.localizedDescription)\n"
            scopedURLs.forEach { $0.stopAccessingSecurityScopedResource() }
            scopedURLs = []
        }
    }

    var canRetryMissing: Bool { !isRunning && missing > 0 && lastOptions != nil }

    func retryMissing() {
        guard canRetryMissing, let lastOptions else { return }
        run(lastOptions, retryMissing: true)
    }

    private func consume(_ chunk: String) {
        pendingOutput += chunk
        while let newline = pendingOutput.firstIndex(of: "\n") {
            let line = String(pendingOutput[..<newline]).trimmingCharacters(in: .newlines)
            pendingOutput.removeSubrange(...newline)
            guard line.hasPrefix("WALLSY_EVENT ") else {
                if !line.isEmpty { log += line + "\n" }
                continue
            }
            let payload = Data(line.dropFirst("WALLSY_EVENT ".count).utf8)
            guard let value = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                  let event = value["event"] as? String else { continue }
            switch event {
            case "playlist":
                completed = value["completed"] as? Int ?? 0
                total = value["total"] as? Int ?? 0
                currentTrack = value["name"] as? String ?? ""
            case "progress":
                completed = value["completed"] as? Int ?? completed
                total = value["total"] as? Int ?? total
                currentTrack = value["title"] as? String ?? currentTrack
            case "finished":
                missing = value["missing"] as? Int ?? 0
                downloaded = value["downloaded"] as? Int ?? 0
                alreadyInLibrary = value["existing"] as? Int ?? 0
                didFinish = true
            default: break
            }
        }
    }

    func stop() {
        process?.terminate()
    }

    func clearLog() {
        log = ""
    }
}
