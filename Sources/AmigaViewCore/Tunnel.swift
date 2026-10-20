import Foundation
import Darwin

/// Decides whether the SSH tunnel must be started.
public enum TunnelPlanner {
    public typealias Probe = (Int) -> Bool

    public static func needsTunnel(settings: Settings, probe: Probe = portAnswers) -> Bool {
        settings.isLocalHost && !settings.via.isEmpty && !probe(settings.port)
    }

    /// True when something accepts TCP connections on 127.0.0.1:port.
    public static func portAnswers(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var tv = timeval(tv_sec: 0, tv_usec: 500_000)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return rc == 0
    }

    public static func sshArguments(_ s: Settings) -> [String] {
        ["-N", "-o", "ExitOnForwardFailure=yes", "-o", "ConnectTimeout=8", "-o", "BatchMode=yes",
         "-o", "StrictHostKeyChecking=accept-new", "-L", "\(s.port):localhost:\(s.port)", s.via]
    }
}

/// Owns the ssh child process; terminates it on `stop()`.
public final class TunnelManager {
    public private(set) var process: Process?
    private let errPipe = Pipe()

    public init() {}

    /// Starts the tunnel when needed and waits for the port. Returns nil on success
    /// (including "not needed"), else the failure reason. Blocking: call off the main thread.
    public func ensure(settings: Settings, probe: @escaping TunnelPlanner.Probe = TunnelPlanner.portAnswers,
                       timeout: TimeInterval = 12) -> String? {
        guard TunnelPlanner.needsTunnel(settings: settings, probe: probe) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        p.arguments = TunnelPlanner.sshArguments(settings)
        p.standardError = errPipe
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        do { try p.run() } catch { return "cannot start ssh (\(error.localizedDescription))" }
        process = p
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if probe(settings.port) { return nil }
            if !p.isRunning {
                let data = errPipe.fileHandleForReading.availableData
                let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                process = nil
                return text.isEmpty ? "ssh exited with status \(p.terminationStatus)" : text
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        stop()
        return "timed out waiting for port \(settings.port)"
    }

    public func stop() {
        if let p = process, p.isRunning { p.terminate(); p.waitUntilExit() }
        process = nil
    }
}
