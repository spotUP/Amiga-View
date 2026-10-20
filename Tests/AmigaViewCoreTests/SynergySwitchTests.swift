import XCTest
@testable import AmigaViewCore

final class SynergySwitchTests: XCTestCase {
    /// Deskflow ignores a posted hotkey, so the switch walks the pointer across the right
    /// edge of the desktop ("replay" is right of the Mac), keeping the pointer's height.
    func testEdgePathCrossesTheRightEdge() {
        let desktop = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        let path = SynergySwitch.edgePath(from: CGPoint(x: 1022, y: 390), desktop: desktop)
        XCTAssertEqual(path.map(\.x), [1780, 1785, 1790, 1795, 1800])
        XCTAssertEqual(Set(path.map(\.y)), [390])
    }

    func testEdgePathKeepsTheHeightOnTheDesktop() {
        let desktop = CGRect(x: -1440, y: 0, width: 3240, height: 1169)
        let path = SynergySwitch.edgePath(from: CGPoint(x: 10, y: 1500), desktop: desktop)
        XCTAssertEqual(path.last?.x, 1800)
        XCTAssertEqual(Set(path.map(\.y)), [1168])
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
