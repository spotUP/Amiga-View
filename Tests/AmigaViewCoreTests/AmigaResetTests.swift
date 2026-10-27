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
        let reset = AmigaReset(host: "h", port: 1, keyFile: file.path, keychain: Self.emptyKeychain)
        XCTAssertNil(reset.key())
        try "  secret \nignored\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(reset.key(), "secret")
        try "\n".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertNil(reset.key())
    }

    /// A Keychain item no test writes, so the user's stored key never leaks into a test.
    static let emptyKeychain = Keychain(service: "com.spotup.amiga-view.test-empty", account: "none")

    func testStoredKeyWinsOverTheKeyFile() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("key-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try "fromfile\n".write(to: file, atomically: true, encoding: .utf8)
        let keychain = Keychain(service: "com.spotup.amiga-view.test-" + UUID().uuidString, account: "wasabid")
        defer { keychain.delete() }
        let reset = AmigaReset(host: "h", port: 1, keyFile: file.path, keychain: keychain)
        XCTAssertEqual(reset.key(), "fromfile")
        XCTAssertNil(keychain.write("stored"))
        XCTAssertEqual(keychain.read(), "stored")
        XCTAssertEqual(reset.key(), "stored")
        XCTAssertNil(keychain.write("again"))
        XCTAssertEqual(reset.key(), "again")
        keychain.delete()
        XCTAssertEqual(reset.key(), "fromfile")
    }

    func testParseChecksTheFieldsAndSaveStoresThem() {
        XCTAssertEqual(AmigaReset.parse(host: " ", port: "1234", keyFile: ""), .failure(.init("Enter the Amiga's address")))
        XCTAssertEqual(AmigaReset.parse(host: "a b", port: "1234", keyFile: ""), .failure(.init("Enter the Amiga's address")))
        for bad in ["0", "65536", "x", ""] {
            XCTAssertEqual(AmigaReset.parse(host: "h", port: bad, keyFile: ""),
                           .failure(.init("Port must be a number from 1 to 65535")), bad)
        }
        let parsed = AmigaReset.parse(host: " 10.0.0.9 ", port: " 99 ", keyFile: "")
        XCTAssertEqual(parsed, .success(AmigaReset(host: "10.0.0.9", port: 99, keyFile: AmigaReset.defaults.keyFile)))
        let suite = "amiga-reset-" + UUID().uuidString
        let store = UserDefaults(suiteName: suite)!
        defer { store.removePersistentDomain(forName: suite) }
        AmigaReset(host: "10.0.0.9", port: 99, keyFile: "/k").save(to: store)
        XCTAssertEqual(AmigaReset.load(from: store), AmigaReset(host: "10.0.0.9", port: 99, keyFile: "/k"))
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
