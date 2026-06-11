import Foundation

/// Runs the bundled wallsy_import.py as a subprocess with live log output.
@MainActor
final class ImportRunner: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var log: String = ""

    private var process: Process?

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
    }

    func run(_ options: Options) {
        guard !isRunning else { return }
        guard let script = Bundle.main.url(forResource: "wallsy_import", withExtension: "py") else {
            log += "[!] Bundled import script not found.\n"
            return
        }

        var arguments: [String] = [script.path]
        arguments += options.csvFiles.map(\.path)
        // The password is passed via environment, not argv, so it never
        // shows up in `ps` output.
        arguments += ["--server", options.server,
                      "--user", options.username,
                      "--format", options.format,
                      "--platform", options.platform]
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
        task.environment = env

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.log += text
            }
        }

        task.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            Task { @MainActor [weak self] in
                guard let self else { return }
                pipe.fileHandleForReading.readabilityHandler = nil
                self.log += code == 0
                    ? "\n✔ Finished successfully.\n"
                    : "\n[!] Exited with code \(code).\n"
                self.isRunning = false
                self.process = nil
            }
        }

        log = "Launching import…\n"
        do {
            try task.run()
            process = task
            isRunning = true
        } catch {
            log += "[!] Failed to launch \(options.pythonPath): \(error.localizedDescription)\n"
        }
    }

    func stop() {
        process?.terminate()
    }

    func clearLog() {
        log = ""
    }
}
