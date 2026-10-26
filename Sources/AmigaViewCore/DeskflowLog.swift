import Foundation

/// What the Deskflow server log tells us. Lines look like
/// `[2026-10-26T23:59:44.572] INFO: switch from "BMS-MAC001" to "replay" at 0,539` and
/// `[2026-10-26T16:58:02.515] DEBUG: locked by mouse buttonID: 0`.
public enum DeskflowEvent: Equatable {
    case switched(to: String)
    case lockedByMouse
}

public enum DeskflowLog {
    public static let defaultsKey = "deskflowLog"
    /// The Deskflow client screen that is the Amiga.
    public static let amigaScreen = "replay"

    /// `deskflowLog` in the store, else ~/deskflow.log (the `[log] file=` of Deskflow.conf here).
    public static func path(in store: UserDefaults = .standard) -> String {
        store.string(forKey: defaultsKey) ?? NSHomeDirectory() + "/deskflow.log"
    }

    public static func parse(_ line: String) -> DeskflowEvent? {
        
        if line.contains("locked by mouse button") { return .lockedByMouse }
        guard let from = line.range(of: "INFO: switch from \""),
              let to = line.range(of: "\" to \"", range: from.upperBound..<line.endIndex),
              let end = line.range(of: "\"", range: to.upperBound..<line.endIndex) else { return nil }
        return .switched(to: String(line[to.upperBound..<end.lowerBound]))
    }
}

/// Which screen has the input and when Deskflow last refused a switch, from the parsed log.
public struct DeskflowState {
    public static let lockWindow: TimeInterval = 2
    public static let lockThreshold = 3
    public static let releaseInterval: TimeInterval = 2

    public private(set) var amigaHasInput = false
    private var lockTimes: [TimeInterval] = []
    private var lastRelease: TimeInterval?

    public init() {}

    public mutating func apply(_ event: DeskflowEvent, at now: TimeInterval) {
        switch event {
        case .switched(let screen):
            amigaHasInput = screen == DeskflowLog.amigaScreen
            lockTimes = []
        case .lockedByMouse:
            lockTimes.append(now)
            lockTimes.removeAll { now - $0 > Self.lockWindow }
        }
    }

    /// Whether to post a mouseUp now: the Amiga has the input, Deskflow refused 3 times within 2 s
    /// (the user pushes at the edge while it thinks a button is held), and none went out in the
    /// last 2 s. This mitigates a Deskflow state bug whose root cause is still open.
    public mutating func shouldRelease(trusted: Bool, now: TimeInterval) -> Bool {
        guard trusted, amigaHasInput else { return false }
        guard lockTimes.filter({ now - $0 <= Self.lockWindow }).count >= Self.lockThreshold else { return false }
        if let lastRelease, now - lastRelease < Self.releaseInterval { return false }
        lastRelease = now
        lockTimes = []
        return true
    }
}

/// Follows a growing file: new complete lines only, from the end at start; reopens on
/// truncation or rotation.
public final class FileTail {
    private let path: String
    private var offset: UInt64
    private var inode: UInt64?
    private var partial = ""

    public init(path: String) {
        self.path = path
        let a = try? FileManager.default.attributesOfItem(atPath: path)
        offset = (a?[.size] as? UInt64) ?? 0
        inode = (a?[.systemFileNumber] as? UInt64)
    }

    public func readNewLines() -> [String] {
        guard let a = try? FileManager.default.attributesOfItem(atPath: path),
              let size = a[.size] as? UInt64 else { return [] }
        let node = a[.systemFileNumber] as? UInt64
        if node != inode || size < offset { offset = 0; partial = ""; inode = node }
        guard size > offset, let h = FileHandle(forReadingAtPath: path) else { return [] }
        defer { try? h.close() }
        try? h.seek(toOffset: offset)
        let data = h.readDataToEndOfFile()
        offset += UInt64(data.count)
        var lines = (partial + String(decoding: data, as: UTF8.self)).components(separatedBy: "\n")
        partial = lines.removeLast()
        return lines
    }
}
