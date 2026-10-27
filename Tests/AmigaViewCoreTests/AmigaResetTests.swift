import XCTest
@testable import AmigaViewCore

final class AmigaResetTests: XCTestCase {
    func testLoadUsesDefaultsThenStore() {
        let suite = "amiga-reset-" + UUID().uuidString
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        XCTAssertEqual(AmigaReset.load(from: store), AmigaReset(host: "192.168.0.74", port: 1234,
                                                                   keyFile: "~/.config/up-term/replay-wasabi.key"))
        store.set("10.0.0.5", forKey: "amigaHost")
        store.set(4321, forKey: "amigaPort")
        store.set("/k", forKey: "amigaKeyFile")
        XCTAssertEqual(AmigaReset.load(from: store), AmigaReset(host: "10.0.0.5", port: 4321, keyFile: "/k"))
    }

    func testArgumentsAlwaysNameTheHost() {
        let args = AmigaReset(host: "10.0.0.5", port: 1234, keyFile: "/k").arguments(script: URL(fileURLWithPath: "/x/wasabi.py"))
        XCTAssertEqual(args, ["-I", "/x/wasabi.py", "--host", "10.0.0.5", "--port", "1234", "reboot", "--yes"])
    }

    func testKeyIsTheFirstLineOfTheKeyFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("key-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let reset = AmigaReset(host: "h", port: 1, keyFile: file.path)
        XCTAssertNil(reset.key())
        try "  secret \nignored\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(reset.key(), "secret")
        try "\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertNil(reset.key())
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
