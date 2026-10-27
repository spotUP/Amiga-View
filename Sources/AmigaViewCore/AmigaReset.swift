import Foundation

/// Reboots the A1200 through wasabid, the daemon running on it: its REBOOT verb calls exec's
/// ColdReboot. Keys cannot do it: the Ctrl-Amiga-Amiga reset lives in the A1200's keyboard
/// hardware, and keys that arrive over Synergy never pass through it.
/// Stored in UserDefaults (keys: amigaHost, amigaPort); the key wasabid checks comes from
/// wasabi's own config (~/.config/wasabi/config).
public struct AmigaReset: Equatable {
    public var host: String
    public var port: Int

    public static let defaults = AmigaReset(host: "192.168.0.66", port: 1234)
    public static let python = URL(fileURLWithPath: "/usr/bin/python3")
    public static let confirmText = "Reset the Amiga?"
    public static let confirmDetail = "The Amiga reboots at once. Anything open there is lost."
    public static let startedStatus = "Resetting the Amiga"
    public static let doneStatus = "Amiga is rebooting"

    public init(host: String, port: Int) {
        self.host = host; self.port = port
    }

    public static func load(from store: UserDefaults = .standard) -> AmigaReset {
        let d = AmigaReset.defaults
        let port = store.integer(forKey: "amigaPort")
        return AmigaReset(host: store.string(forKey: "amigaHost") ?? d.host, port: port > 0 ? port : d.port)
    }

    /// Always names the host: without one, wasabi finds daemons by broadcast, and an emulator
    /// running wasabid on this Mac answers too.
    public func arguments(script: URL) -> [String] {
        ["-I", script.path, "--host", host, "--port", String(port), "reboot", "--yes"]
    }

    /// The status line text for a finished run: wasabi's last stderr line on failure.
    public static func outcome(status: Int32, stderr: String) -> String {
        if status == 0 { return doneStatus }
        let line = stderr.split(whereSeparator: \.isNewline).last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        let reason = line.hasPrefix("wasabi: ") ? String(line.dropFirst("wasabi: ".count)) : line
        return reason.isEmpty ? "Reset failed (exit \(status))" : "Reset failed: \(reason)"
    }

    /// The client bundled by scripts/bundle.sh; a `swift build` binary has no bundle, so it falls
    /// back to the copy in the source tree.
    public static func scriptURL(bundle: Bundle = .main) -> URL {
        bundle.url(forResource: "wasabi", withExtension: "py")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Resources/wasabi/wasabi.py")
    }

    /// Runs the client off the main thread. `done` gets the status line text on the main queue.
    /// `environment` nil inherits this process's environment.
    public func run(script: URL, environment: [String: String]? = nil, done: @escaping (String) -> Void) {
        let arguments = arguments(script: script)
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = Self.python
            p.arguments = arguments
            if let environment { p.environment = environment }
            let err = Pipe()
            p.standardError = err
            p.standardOutput = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            let text: String
            do {
                try p.run()
                let data = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                text = Self.outcome(status: p.terminationStatus, stderr: String(decoding: data, as: UTF8.self))
            } catch {
                text = "Reset failed: cannot start python3 (\(error.localizedDescription))"
            }
            DispatchQueue.main.async { done(text) }
        }
    }
}
