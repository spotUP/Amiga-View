import AppKit
import XCTest
@testable import AmigaView
@testable import AmigaViewCore

/// Amiga > Reset Amiga... end to end: the menu item runs the bundled wasabi client against the
/// mock wasabid from wasabi's own test suite, which logs the REBOOT it receives.
@MainActor
final class ResetMenuTests: XCTestCase {
    private var app: AppDelegate!
    private var suite = ""
    private var dir: URL!
    private var mock: Process?
    private var mockLog: URL { dir.appendingPathComponent("mock.log") }

    override func setUp() {
        _ = NSApplication.shared
        suite = "reset-tests-" + UUID().uuidString
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        try! FileManager.default.createDirectory(at: dir.appendingPathComponent("root"), withIntermediateDirectories: true)
        app = AppDelegate()
        app.defaults = UserDefaults(suiteName: suite)!
        app.frameAutosaveName = nil
        app.buildWindow()
        app.buildMenu()
    }

    override func tearDown() {
        mock?.terminate(); mock?.waitUntilExit()
        UserDefaults(suiteName: suite)!.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: dir)
    }

    private func invoke(_ title: String) throws {
        let i = try XCTUnwrap(NSApp.mainMenu?.items.compactMap(\.submenu).flatMap(\.items).first { $0.title == title }, title)
        XCTAssertTrue(NSApp.sendAction(try XCTUnwrap(i.action), to: i.target, from: i))
    }

    private func log() -> String { (try? String(contentsOf: mockLog, encoding: .utf8)) ?? "" }

    private var keyFile: URL { dir.appendingPathComponent("replay-wasabi.key") }

    /// Starts the mock on a free port with key "testkey" and points the app at it and at a key
    /// file holding that key, with wasabi's config and cache in the temp directory so the user's
    /// own are never read or written.
    private func startMock() throws {
        let port = try freePort()
        FileManager.default.createFile(atPath: mockLog.path, contents: nil)
        let out = try FileHandle(forWritingTo: mockLog)
        let p = Process()
        p.executableURL = AmigaReset.python
        p.arguments = ["-I", "-u", URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                        .appendingPathComponent("Fixtures/mock_wasabid.py").path,
                       "--root", dir.appendingPathComponent("root").path, "--port", String(port), "--key", "testkey"]
        p.standardOutput = out; p.standardError = out
        try p.run()
        mock = p
        let deadline = Date().addingTimeInterval(10)
        while !log().contains("mock-wasabid on"), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        XCTAssertTrue(log().contains("mock-wasabid on"), log())
        app.defaults.set("127.0.0.1", forKey: "amigaHost")
        app.defaults.set(port, forKey: "amigaPort")
        try "testkey\n".write(to: keyFile, atomically: true, encoding: .utf8)
        app.defaults.set(keyFile.path, forKey: "amigaKeyFile")
        app.resetEnvironment = ["PATH": "/usr/bin:/bin", "HOME": dir.path,
                                "XDG_CONFIG_HOME": dir.appendingPathComponent("config").path,
                                "XDG_CACHE_HOME": dir.appendingPathComponent("cache").path]
    }

    private func freePort() throws -> Int {
        let p = Process()
        p.executableURL = AmigaReset.python
        p.arguments = ["-I", "-c", "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1])"]
        let pipe = Pipe(); p.standardOutput = pipe
        try p.run(); p.waitUntilExit()
        return try XCTUnwrap(Int(String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    func testResetSendsRebootAfterConfirm() throws {
        try startMock()
        var asked = 0
        app.confirmReset = { asked += 1; return true }
        let finished = expectation(description: "finished")
        var result = ""
        app.resetFinished = { result = $0; finished.fulfill() }
        try invoke("Reset Amiga...")
        XCTAssertEqual(asked, 1)
        XCTAssertEqual(app.video.status, AmigaReset.startedStatus)
        wait(for: [finished], timeout: 20)
        XCTAssertEqual(result, "Amiga is rebooting")
        XCTAssertEqual(app.video.status, "Amiga is rebooting")
        XCTAssertTrue(log().contains("REBOOT requested"), log())
    }

    func testCancelSendsNothing() throws {
        try startMock()
        app.confirmReset = { false }
        app.resetFinished = { _ in XCTFail("reset ran after cancel") }
        try invoke("Reset Amiga...")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertFalse(log().contains("REBOOT"), log())
        XCTAssertNotEqual(app.video.status, AmigaReset.startedStatus)
    }

    func testWrongKeyShowsWhy() throws {
        try startMock()
        try "wrong\n".write(to: keyFile, atomically: true, encoding: .utf8)
        app.confirmReset = { true }
        let finished = expectation(description: "finished")
        var result = ""
        app.resetFinished = { result = $0; finished.fulfill() }
        try invoke("Reset Amiga...")
        wait(for: [finished], timeout: 20)
        XCTAssertTrue(result.hasPrefix("Reset failed: "), result)
        XCTAssertTrue(result.contains("bad key"), result)
        XCTAssertFalse(log().contains("REBOOT requested"), log())
    }

    func testMissingKeyFileSaysWhere() throws {
        try startMock()
        try FileManager.default.removeItem(at: keyFile)
        app.confirmReset = { true }
        let finished = expectation(description: "finished")
        var result = ""
        app.resetFinished = { result = $0; finished.fulfill() }
        try invoke("Reset Amiga...")
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(result, "Reset failed: no key in \(keyFile.path)")
    }
}
