import Foundation

/// Connection settings, stored in UserDefaults (keys: host, port, via).
public struct Settings: Equatable {
    public var host: String
    public var port: Int
    public var via: String

    public static let defaults = Settings(host: "localhost", port: 8090, via: "amigrabber")

    public init(host: String, port: Int, via: String) {
        self.host = host; self.port = port; self.via = via
    }

    public static func load(from store: UserDefaults = .standard) -> Settings {
        let d = Settings.defaults
        let port = store.integer(forKey: "port")
        return Settings(host: store.string(forKey: "host") ?? d.host,
                        port: port > 0 ? port : d.port,
                        via: store.string(forKey: "via") ?? d.via)
    }

    public var streamURL: URL { URL(string: "http://\(host):\(port)/stream.mjpg")! }
    public var snapshotURL: URL { URL(string: "http://\(host):\(port)/snapshot.png")! }
    public var audioURL: URL { URL(string: "http://\(host):\(port)/audio.pcm")! }
    /// A tunnel only makes sense when the stream host is this machine.
    public var isLocalHost: Bool { host == "localhost" || host == "127.0.0.1" }
}
