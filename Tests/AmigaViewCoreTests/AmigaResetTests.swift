import XCTest
@testable import AmigaViewCore

final class AmigaResetTests: XCTestCase {
    func testLoadUsesDefaultsThenStore() {
        let suite = "amiga-reset-" + UUID().uuidString
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        XCTAssertEqual(AmigaReset.load(from: store), AmigaReset(host: "192.168.0.66", port: 1234))
        store.set("10.0.0.5", forKey: "amigaHost")
        store.set(4321, forKey: "amigaPort")
        XCTAssertEqual(AmigaReset.load(from: store), AmigaReset(host: "10.0.0.5", port: 4321))
    }

    func testArgumentsAlwaysNameTheHost() {
        let args = AmigaReset(host: "10.0.0.5", port: 1234).arguments(script: URL(fileURLWithPath: "/x/wasabi.py"))
        XCTAssertEqual(args, ["-I", "/x/wasabi.py", "--host", "10.0.0.5", "--port", "1234", "reboot", "--yes"])
    }

    func testOutcomeReadsTheLastErrorLine() {
        XCTAssertEqual(AmigaReset.outcome(status: 0, stderr: "noise\n"), "Amiga is rebooting")
        XCTAssertEqual(AmigaReset.outcome(status: 1, stderr: "warning\nwasabi: cannot reach 10.0.0.5:1234 - timed out\n"),
                       "Reset failed: cannot reach 10.0.0.5:1234 - timed out")
        XCTAssertEqual(AmigaReset.outcome(status: 2, stderr: ""), "Reset failed (exit 2)")
    }

    func testScriptFallsBackToTheSourceTree() {
        let url = AmigaReset.scriptURL(bundle: Bundle(for: AmigaResetTests.self))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), url.path)
    }
}
