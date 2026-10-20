import XCTest
import ImageIO
import UniformTypeIdentifiers
import Darwin
@testable import AmigaViewCore

/// Minimal blocking HTTP server on 127.0.0.1 serving a multipart MJPEG stream.
final class TestMJPEGServer {
    let port: Int
    private let listenFD: Int32
    private var stopped = false

    convenience init(jpegs: [Data]) {
        self.init { send in
            send(Data("HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=frame\r\nConnection: close\r\n\r\n".utf8))
            for _ in 0..<100 {
                for j in jpegs {
                    send(Data("--frame\r\nContent-Type: image/jpeg\r\nContent-Length: \(j.count)\r\n\r\n".utf8) + j + Data("\r\n".utf8))
                    Thread.sleep(forTimeInterval: 0.02)
                }
            }
        }
    }

    /// `body` writes the whole response, status line included, then the connection closes.
    init(body: @escaping (_ send: (Data) -> Void) -> Void) {
        signal(SIGPIPE, SIG_IGN)
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, 4)
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        _ = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        listen(fd, 4)
        var bound = sockaddr_in(); var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &bound) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) } }
        port = Int(UInt16(bigEndian: bound.sin_port))
        listenFD = fd
        Thread.detachNewThread { [weak self] in
            while let self, !self.stopped {
                let c = accept(fd, nil, nil)
                if c < 0 { break }
                self.serve(c, body)
            }
        }
    }

    private func serve(_ c: Int32, _ body: (_ send: (Data) -> Void) -> Void) {
        defer { close(c) }
        var req = [UInt8](repeating: 0, count: 4096)
        _ = read(c, &req, req.count)
        func send(_ d: Data) { d.withUnsafeBytes { _ = write(c, $0.baseAddress, d.count) } }
        body(send)
    }

    func stop() { stopped = true; close(listenFD) }
}

final class StreamClientTests: XCTestCase {
    static func jpeg(gray: UInt8, width: Int = 8, height: Int = 4) -> Data {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(gray: CGFloat(gray) / 255, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    func testClientDeliversDecodedFramesFromMultipartStream() {
        let server = TestMJPEGServer(jpegs: [Self.jpeg(gray: 30), Self.jpeg(gray: 120), Self.jpeg(gray: 220)])
        defer { server.stop() }
        let client = StreamClient(settings: Settings(host: "127.0.0.1", port: server.port, via: ""))
        var sizes: [CGSize] = []
        var fallbackAtThirdFrame = true
        let got = expectation(description: "three decoded frames")
        client.onFrame = { image in
            sizes.append(CGSize(width: image.width, height: image.height))
            if sizes.count == 3 { fallbackAtThirdFrame = client.usingSnapshotFallback; got.fulfill() }
        }
        client.start()
        wait(for: [got], timeout: 10)
        client.stop()
        XCTAssertGreaterThanOrEqual(client.framesDelivered, 3)
        XCTAssertEqual(sizes.first, CGSize(width: 8, height: 4))
        XCTAssertFalse(fallbackAtThirdFrame)
    }

    func testFramesDecodeFromSnapshotPNGData() {
        XCTAssertNotNil(FrameDecoder.decode(Self.jpeg(gray: 10)))
        XCTAssertNil(FrameDecoder.decode(Data([1, 2, 3])))
    }

    func testLatestSlotKeepsOnlyTheNewestAndWakesOncePerDrain() {
        let slot = LatestSlot<Int>()
        XCTAssertTrue(slot.put(1), "an empty slot must wake the consumer")
        XCTAssertFalse(slot.put(2), "a waiting wake-up must not be scheduled twice")
        XCTAssertFalse(slot.put(3))
        XCTAssertEqual(slot.take(), 3, "the consumer gets the newest frame, not the first")
        XCTAssertNil(slot.take())
        XCTAssertTrue(slot.put(4), "after a drain the next frame wakes the consumer again")
    }
}
