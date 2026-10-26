import Foundation

/// Reads the grabber's live audio (/audio.pcm, raw s16le 48000 Hz stereo) into a PCMJitterBuffer,
/// reconnecting with StreamClient's backoff when the stream ends or is not served.
public final class AudioStreamClient: NSObject, URLSessionDataDelegate {
    public static let sampleRate = 48000.0
    public static let defaultsKey = "sound"

    /// On by default; only an explicit false in the store turns the sound off.
    public static func isEnabled(in store: UserDefaults = .standard) -> Bool {
        store.object(forKey: defaultsKey) == nil ? true : store.bool(forKey: defaultsKey)
    }

    public static func setEnabled(_ on: Bool, in store: UserDefaults = .standard) {
        store.set(on, forKey: defaultsKey)
    }

    public let buffer: PCMJitterBuffer
    public private(set) var bytesReceived = 0
    public var onEvent: ((String) -> Void)?
    private let tapLock = NSLock()
    private var tap: ((Data) -> Void)?
    /// Called with every chunk of PCM as it arrives, on the network queue (the recorder's tap).
    public var onPCM: ((Data) -> Void)? {
        get { tapLock.lock(); defer { tapLock.unlock() }; return tap }
        set { tapLock.lock(); tap = newValue; tapLock.unlock() }
    }

    private let url: URL
    private var session: URLSession!
    private var task: URLSessionDataTask?
    private var failures = 0
    private var running = false
    private let queue = OperationQueue()

    /// 60 ms target: about one and a half video fields, so sound and picture stay together;
    /// 150 ms at most before the backlog is dropped.
    public init(settings: Settings,
                buffer: PCMJitterBuffer = PCMJitterBuffer(target: Int(sampleRate * 0.06), maximum: Int(sampleRate * 0.15))) {
        self.url = settings.audioURL
        self.buffer = buffer
        super.init()
        queue.maxConcurrentOperationCount = 1
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 24 * 3600
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: queue)
    }

    public func start() { running = true; connect() }

    public func stop() {
        running = false
        task?.cancel()
        session.invalidateAndCancel()
    }

    private func connect() {
        guard running else { return }
        buffer.reset()
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        let t = session.dataTask(with: req)
        task = t
        t.resume()
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard dataTask === task, (response as? HTTPURLResponse)?.statusCode == 200 else {
            completionHandler(.cancel); return
        }
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard dataTask === task else { return }
        failures = 0
        bytesReceived += data.count
        buffer.write(data)
        onPCM?(data)
    }

    public func urlSession(_ session: URLSession, task t: URLSessionTask, didCompleteWithError error: Error?) {
        guard t === task, running else { return }
        failures += 1
        onEvent?("Audio dropped")
        DispatchQueue.global().asyncAfter(deadline: .now() + StreamClient.backoff(afterFailures: failures)) { [weak self] in
            self?.queue.addOperation { self?.connect() }
        }
    }
}
