import Foundation

/// Reboots the A1200 through wasabid, the daemon running on it: its REBOOT verb calls exec's
/// ColdReboot. Keys cannot do it: the Ctrl-Amiga-Amiga reset lives in the A1200's keyboard
/// hardware, and keys that arrive over Synergy never pass through it.
/// Stored in UserDefaults (keys: amigaHost, amigaPort, amigaKeyFile) and edited in the Settings
/// window. The key wasabid checks comes from the Keychain when one was typed in Settings, else
/// from UP-Term's key file, because UP-Term installs wasabid on the Amiga with that key; wasabi's
/// own config can hold an older one.
public struct AmigaReset: Equatable {
    public var host: String
    public var port: Int
    public var keyFile: String
    public var keychain: Keychain

    public static let defaults = AmigaReset(host: "192.168.0.74", port: 1234,
                                            keyFile: "~/.config/up-term/replay-wasabi.key")
    public static let python = URL(fileURLWithPath: "/usr/bin/python3")
    public static let confirmText = "Reset the Amiga?"
    public static let confirmDetail = "The Amiga reboots at once. Anything open there is lost."
    public static let startedStatus = "Resetting the Amiga"
    public static let doneStatus = "Amiga is rebooting"

    public init(host: String, port: Int, keyFile: String, keychain: Keychain = .wasabi) {
        self.host = host; self.port = port; self.keyFile = keyFile; self.keychain = keychain
    }

    public static func load(from store: UserDefaults = .standard, keychain: Keychain = .wasabi) -> AmigaReset {
        let d = AmigaReset.defaults
        let port = store.integer(forKey: "amigaPort")
        return AmigaReset(host: store.string(forKey: "amigaHost") ?? d.host, port: port > 0 ? port : d.port,
                          keyFile: store.string(forKey: "amigaKeyFile") ?? d.keyFile, keychain: keychain)
    }

    /// Checks the Settings fields and returns them as settings, or the reason they cannot be saved.
    public static func parse(host: String, port: String, keyFile: String,
                             keychain: Keychain = .wasabi) -> Result<AmigaReset, ParseError> {
        let host = host.trimmingCharacters(in: .whitespaces)
        let keyFile = keyFile.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !host.contains(where: \.isWhitespace) else { return .failure(ParseError("Enter the Amiga's address")) }
        guard let p = Int(port.trimmingCharacters(in: .whitespaces)), (1...65535).contains(p) else {
            return .failure(ParseError("Port must be a number from 1 to 65535"))
        }
        return .success(AmigaReset(host: host, port: p, keyFile: keyFile.isEmpty ? defaults.keyFile : keyFile,
                                   keychain: keychain))
    }

    public struct ParseError: Error, Equatable {
        public let message: String
        public init(_ message: String) { self.message = message }
    }

    public func save(to store: UserDefaults = .standard) {
        store.set(host, forKey: "amigaHost")
        store.set(port, forKey: "amigaPort")
        store.set(keyFile, forKey: "amigaKeyFile")
    }

    /// The key typed in Settings (Keychain), else the key file's first line; nil when neither has one.
    public func key() -> String? {
        if let stored = keychain.read()?.trimmingCharacters(in: .whitespacesAndNewlines), !stored.isEmpty { return stored }
        return fileKey()
    }

    /// The key file's first line, or nil when it is missing or empty.
    public func fileKey() -> String? {
        let path = (keyFile as NSString).expandingTildeInPath
        guard let text = try? String(contentsOfFile: path, encoding: .utf8),
              let line = text.split(whereSeparator: \.isNewline).first?.trimmingCharacters(in: .whitespaces),
              !line.isEmpty else { return nil }
        return line
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
    /// `environment` nil inherits this process's environment. The key goes in WASABI_KEY, not
    /// the arguments, so other users cannot read it from the process list.
    public func run(script: URL, environment: [String: String]? = nil, done: @escaping (String) -> Void) {
        guard let key = key() else {
            let text = "Reset failed: no key in Settings or in \(keyFile)"
            DispatchQueue.main.async { done(text) }
            return
        }
        let arguments = arguments(script: script)
        var environment = environment ?? ProcessInfo.processInfo.environment
        environment["WASABI_KEY"] = key
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = Self.python
            p.arguments = arguments
            p.environment = environment
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
