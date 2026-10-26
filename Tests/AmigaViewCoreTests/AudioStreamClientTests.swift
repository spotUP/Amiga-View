import XCTest
@testable import AmigaViewCore

final class AudioStreamClientTests: XCTestCase {
    /// End to end: /audio.pcm served in chunks that split sample frames reaches the jitter buffer
    /// aligned, through the URL the settings name.
    func testClientFillsTheJitterBufferFromTheAudioStream() {
        let pcm = PCMJitterBufferTests.pcm(1..<4001)
        var path = ""
        let server = TestMJPEGServer { send in
            send(Data("HTTP/1.1 200 OK\r\nContent-Type: audio/x-raw\r\nConnection: close\r\n\r\n".utf8))
            var i = 0
            while i < pcm.count { send(pcm.subdata(in: i..<min(i + 1001, pcm.count))); i += 1001; Thread.sleep(forTimeInterval: 0.001) }
            Thread.sleep(forTimeInterval: 2)
        }
        defer { server.stop() }
        let settings = Settings(host: "127.0.0.1", port: server.port, via: "")
        path = settings.audioURL.path
        let client = AudioStreamClient(settings: settings, buffer: PCMJitterBuffer(target: 100, maximum: 10_000))
        client.start()
        let deadline = Date().addingTimeInterval(5)
        while client.bytesReceived < pcm.count && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertEqual(path, "/audio.pcm")
        XCTAssertEqual(client.bytesReceived, pcm.count)
        XCTAssertEqual(client.buffer.bufferedFrames, 4000)
        var l = [Float](repeating: 0, count: 3), r = [Float](repeating: 0, count: 3)
        l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
            client.buffer.read(left: lp.baseAddress!, right: rp.baseAddress!, frames: 3) } }
        XCTAssertEqual(r.map { Int(($0 * 32768).rounded()) }, [-1, -2, -3])
        client.stop()
    }

    func testSoundOnByDefaultAndStored() {
        let store = UserDefaults(suiteName: "AudioStreamClientTests-\(UUID().uuidString)")!
        XCTAssertTrue(AudioStreamClient.isEnabled(in: store))
        AudioStreamClient.setEnabled(false, in: store)
        XCTAssertFalse(AudioStreamClient.isEnabled(in: store))
        AudioStreamClient.setEnabled(true, in: store)
        XCTAssertTrue(AudioStreamClient.isEnabled(in: store))
    }
}
