import XCTest
@testable import AmigaViewCore

final class LogicTests: XCTestCase {
    func testActualSizeAndAspect() {
        XCTAssertEqual(ViewGeometry.actualSize, CGSize(width: 720, height: 576))
        XCTAssertEqual(ViewGeometry.size(scale: 2), CGSize(width: 1440, height: 1152))
        XCTAssertEqual(ViewGeometry.aspect, 1.25, accuracy: 1e-9)
    }

    func testFitLetterboxes() {
        let wide = ViewGeometry.fit(in: CGSize(width: 2000, height: 576))
        XCTAssertEqual(wide.height, 576, accuracy: 1e-6)
        XCTAssertEqual(wide.width, 720, accuracy: 1e-6)
        XCTAssertEqual(wide.minX, 640, accuracy: 1e-6)
        let tall = ViewGeometry.fit(in: CGSize(width: 360, height: 1000))
        XCTAssertEqual(tall.width, 360, accuracy: 1e-6)
        XCTAssertEqual(tall.height, 288, accuracy: 1e-6)
        XCTAssertEqual(ViewGeometry.fit(in: .zero), .zero)
    }

    func testTunnelDecision() {
        let s = Settings.defaults
        XCTAssertFalse(TunnelPlanner.needsTunnel(settings: s, probe: { $0 == 8090 }))
        XCTAssertTrue(TunnelPlanner.needsTunnel(settings: s, probe: { _ in false }))
        var remote = s; remote.host = "pi.local"
        XCTAssertFalse(TunnelPlanner.needsTunnel(settings: remote, probe: { _ in false }))
        var noVia = s; noVia.via = ""
        XCTAssertFalse(TunnelPlanner.needsTunnel(settings: noVia, probe: { _ in false }))
    }

    func testSSHArguments() {
        let a = TunnelPlanner.sshArguments(.defaults)
        XCTAssertTrue(a.contains("8090:localhost:8090"))
        XCTAssertEqual(a.last, "spot@amigrabber.local")
        XCTAssertTrue(a.contains("BatchMode=yes"))
    }

    func testSettingsDefaultsAndOverride() {
        let d = UserDefaults(suiteName: "amigaview.test")!
        d.removePersistentDomain(forName: "amigaview.test")
        XCTAssertEqual(Settings.load(from: d), .defaults)
        d.set(9000, forKey: "port"); d.set("a@b", forKey: "via")
        XCTAssertEqual(Settings.load(from: d).port, 9000)
        XCTAssertEqual(Settings.load(from: d).via, "a@b")
    }

    func testFPSMeter() {
        var m = FPSMeter()
        for i in 0..<50 { m.tick(at: Double(i) * 0.02) }
        XCTAssertEqual(m.fps(at: 0.98), 50, accuracy: 1)
        XCTAssertEqual(m.fps(at: 10), 0)
    }

    func testBackoffGrowsAndCaps() {
        XCTAssertEqual(StreamClient.backoff(afterFailures: 1), 0.5)
        XCTAssertEqual(StreamClient.backoff(afterFailures: 3), 2)
        XCTAssertEqual(StreamClient.backoff(afterFailures: 20), 8)
    }
}
