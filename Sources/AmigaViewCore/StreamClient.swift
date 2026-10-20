import Foundation
import CoreGraphics

/// Streams MJPEG from /stream.mjpg, reconnecting with backoff; while the stream is down
/// it polls /snapshot.png once per second. All callbacks run on the main queue.
public final class StreamClient: NSObject, URLSessionDataDelegate {
    public var onFrame: ((CGImage) -> Void)?
    public var onEvent: ((String) -> Void)?

    public private(set) var framesDelivered = 0
    public private(set) var usingSnapshotFallback = false

    private let settings: Settings
    private var session: URLSession!
    private var streamTask: URLSessionDataTask?
    private var parser = MultipartParser()
    private var partBuffer = Data()
    private var gotStreamFrame = false
    private var failures = 0
    private var running = false
    private var pollTimer: Timer?
    private var retryWork: DispatchWorkItem?
    private let queue = OperationQueue()

    public init(settings: Settings) {
        self.settings = settings
        super.init()
        queue.maxConcurrentOperationCount = 1
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 24 * 3600
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: cfg, delegate: self, delegateQueue: queue)
    }

    public static func backoff(afterFailures n: Int) -> TimeInterval { min(0.5 * pow(2, Double(max(0, n - 1))), 8) }

    public func start() {
        running = true
        connect()
    }

    public func stop() {
        running = false
        retryWork?.cancel()
        pollTimer?.invalidate(); pollTimer = nil
        streamTask?.cancel()
        session.invalidateAndCancel()
    }

    private func connect() {
        guard running else { return }
        onEvent?("Connecting")
        gotStreamFrame = false
        var req = URLRequest(url: settings.streamURL)
        req.timeoutInterval = 8
        let task = session.dataTask(with: req)
        streamTask = task
        task.resume()
    }

    private func deliver(_ data: Data, fromStream: Bool) {
        guard let image = FrameDecoder.decode(data) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running else { return }
            if fromStream {
                if !self.gotStreamFrame { self.gotStreamFrame = true; self.failures = 0; self.stopPolling() }
            }
            self.framesDelivered += 1
            self.onFrame?(image)
        }
    }

    // MARK: URLSessionDataDelegate

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                           didReceive response: URLResponse,
                           completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard dataTask === streamTask else { completionHandler(.cancel); return }
        let http = response as? HTTPURLResponse
        if let http, http.statusCode != 200 { completionHandler(.cancel); return }
        let ct = http?.value(forHTTPHeaderField: "Content-Type") ?? ""
        // URLSession announces each unwrapped multipart part with a new response.
        partBuffer = Data()
        if dataTask.countOfBytesReceived == 0 {
            parser = MultipartParser(boundary: MultipartParser.boundary(fromContentType: ct))
        }
        completionHandler(.allow)
    }

    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard dataTask === streamTask else { return }
        if partBuffer.isEmpty, data.first == 0x2D {
            // Raw multipart framing ("--boundary"): our parser splits it.
            if let newest = parser.feedNewest(data) { deliver(newest, fromStream: true) }
        } else if !partBuffer.isEmpty || data.first == 0xFF {
            // Foundation already unwrapped the multipart part; collect chunks up to the JPEG end marker.
            partBuffer.append(data)
            if partBuffer.suffix(2) == Data([0xFF, 0xD9]) {
                deliver(partBuffer, fromStream: true)
                partBuffer = Data()
            }
        } else {
            // Mid-part raw data: keep feeding the parser (it buffers across chunks).
            if let newest = parser.feedNewest(data) { deliver(newest, fromStream: true) }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard task === streamTask else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running else { return }
            self.failures += 1
            if !self.gotStreamFrame { self.startPolling() }
            self.onEvent?("Stream dropped")
            let work = DispatchWorkItem { [weak self] in self?.connect() }
            self.retryWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.backoff(afterFailures: self.failures), execute: work)
        }
    }

    // MARK: Snapshot fallback

    private func startPolling() {
        guard pollTimer == nil else { return }
        usingSnapshotFallback = true
        pollSnapshot()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.pollSnapshot() }
    }

    private func stopPolling() {
        pollTimer?.invalidate(); pollTimer = nil
        usingSnapshotFallback = false
    }

    private func pollSnapshot() {
        guard running else { return }
        session.dataTask(with: settings.snapshotURL) { [weak self] data, response, _ in
            guard let self, let data, (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            self.deliver(data, fromStream: false)
        }.resume()
    }
}
