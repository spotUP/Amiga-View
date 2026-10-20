import XCTest
@testable import AmigaViewCore

final class SynergySwitchTests: XCTestCase {
    func testHotkeyIsControlOptionCommandF12() {
        XCTAssertEqual(SynergySwitch.keyCode, 0x6F)
        XCTAssertEqual(SynergySwitch.flags, [.maskControl, .maskAlternate, .maskCommand])
    }

    func testEnabledByDefaultAndStored() {
        let store = UserDefaults(suiteName: "SynergySwitchTests-\(UUID().uuidString)")!
        XCTAssertTrue(SynergySwitch.isEnabled(in: store))
        SynergySwitch.setEnabled(false, in: store)
        XCTAssertFalse(SynergySwitch.isEnabled(in: store))
        SynergySwitch.setEnabled(true, in: store)
        XCTAssertTrue(SynergySwitch.isEnabled(in: store))
    }

    func testShouldSendRules() {
        XCTAssertTrue(SynergySwitch.shouldSend(enabled: true, trusted: true, lastSent: nil, now: 10))
        XCTAssertFalse(SynergySwitch.shouldSend(enabled: false, trusted: true, lastSent: nil, now: 10))
        XCTAssertFalse(SynergySwitch.shouldSend(enabled: true, trusted: false, lastSent: nil, now: 10))
    }

    func testDebounce() {
        XCTAssertFalse(SynergySwitch.shouldSend(enabled: true, trusted: true, lastSent: 10, now: 10.4))
        XCTAssertTrue(SynergySwitch.shouldSend(enabled: true, trusted: true, lastSent: 10, now: 10.5))
    }
}
