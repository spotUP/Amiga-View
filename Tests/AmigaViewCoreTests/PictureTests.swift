import XCTest
@testable import AmigaViewCore

final class PictureTests: XCTestCase {
    private func store() -> UserDefaults {
        let name = "picture-tests-" + UUID().uuidString
        let d = UserDefaults(suiteName: name)!
        addTeardownBlock { d.removePersistentDomain(forName: name) }
        return d
    }

    func testCropDefaultsAndOverrides() {
        let d = store()
        XCTAssertEqual(ViewGeometry.cropRect(in: d), ViewGeometry.defaultCrop)
        for (k, v) in zip(ViewGeometry.cropKeys, [4.0, 2, 700, 280]) { d.set(v, forKey: k) }
        XCTAssertEqual(ViewGeometry.cropRect(in: d), CGRect(x: 4, y: 2, width: 700, height: 280))
        d.set(800.0, forKey: "cropWidth")   // outside the field
        XCTAssertEqual(ViewGeometry.cropRect(in: d), ViewGeometry.defaultCrop)
    }

    func testCropAspectAndContentsRect() {
        let crop = CGRect(x: 0, y: 0, width: 708, height: 287)
        XCTAssertEqual(ViewGeometry.displaySize(of: crop), CGSize(width: 708, height: 574))
        XCTAssertEqual(ViewGeometry.aspect(of: crop), 708.0 / 574.0, accuracy: 1e-9)
        XCTAssertEqual(ViewGeometry.aspect(of: ViewGeometry.fullField), ViewGeometry.aspect, accuracy: 1e-9)
    }

    func testFitUsesContentAspect() {
        let r = ViewGeometry.fit(in: CGSize(width: 1000, height: 574), content: CGSize(width: 708, height: 574))
        XCTAssertEqual(r.width, 708, accuracy: 1e-6); XCTAssertEqual(r.minX, 146, accuracy: 1e-6)
    }

    func testIntegerFit() {
        let c = ViewGeometry.actualSize   // 720x576
        // 2x fits (1440x1152) but not 3x; centred with black around it.
        XCTAssertEqual(ViewGeometry.integerFit(in: CGSize(width: 2000, height: 1300), content: c),
                       CGRect(x: 280, y: 74, width: 1440, height: 1152))
        // Height limits: 1x only, though the width allows 2x.
        XCTAssertEqual(ViewGeometry.integerFit(in: CGSize(width: 1500, height: 1000), content: c),
                       CGRect(x: 390, y: 212, width: 720, height: 576))
        // Exact multiple.
        XCTAssertEqual(ViewGeometry.integerFit(in: CGSize(width: 720, height: 576), content: c), CGRect(x: 0, y: 0, width: 720, height: 576))
        // Not even 1x: the normal fit.
        let small = CGSize(width: 360, height: 1000)
        XCTAssertEqual(ViewGeometry.integerFit(in: small, content: c), ViewGeometry.fit(in: small, content: c))
        // Cropped content.
        XCTAssertEqual(ViewGeometry.integerFit(in: CGSize(width: 1500, height: 1200), content: CGSize(width: 708, height: 574)),
                       CGRect(x: 42, y: 26, width: 1416, height: 1148))
    }

    /// The viewport the picture is drawn in: crop and Integer Scaling in points, scaled to pixels.
    func testPictureRect() {
        let full = ViewGeometry.fullField, cropped = ViewGeometry.defaultCrop
        // Fitted, Retina: the 720x576 picture fills a 1000x900-point view at width, centred in height.
        XCTAssertEqual(ViewGeometry.pictureRect(in: CGSize(width: 1000, height: 900), scale: 2, crop: full, integerScaling: false),
                       CGRect(x: 0, y: 100, width: 2000, height: 1600))
        // Cropped and integer: 708x574 at 2x in 1500x1200 points is the integerFit rect, doubled.
        XCTAssertEqual(ViewGeometry.pictureRect(in: CGSize(width: 1500, height: 1200), scale: 2, crop: cropped, integerScaling: true),
                       CGRect(x: 84, y: 52, width: 2832, height: 2296))
        XCTAssertEqual(ViewGeometry.pictureRect(in: .zero, scale: 2, crop: full, integerScaling: false), .zero)
    }

    /// The chain renders at the picture size up to 1080 pixels high, then at 1080 with the aspect kept.
    func testChainSizeIsCappedAndKeepsAspect() {
        XCTAssertEqual(ViewGeometry.chainSize(for: CGSize(width: 1440, height: 1080)), CGSize(width: 1440, height: 1080))
        XCTAssertEqual(ViewGeometry.chainSize(for: CGSize(width: 720, height: 576)), CGSize(width: 720, height: 576))
        XCTAssertEqual(ViewGeometry.chainSize(for: CGSize(width: 2880, height: 2160)), CGSize(width: 1440, height: 1080))
        XCTAssertEqual(ViewGeometry.chainSize(for: CGSize(width: 2832, height: 2296)).height, 1080)
        XCTAssertEqual(ViewGeometry.chainSize(for: CGSize(width: 2832, height: 2296)).width,
                       (2832.0 * 1080 / 2296).rounded())
    }

    func testCRTShaderChoiceIsStoredAndOffByDefault() {
        let d = store()
        XCTAssertNil(CRTShader.selected(in: d))
        CRTShader.select(.standard, in: d)
        XCTAssertEqual(CRTShader.selected(in: d), .standard)
        CRTShader.select(nil, in: d)
        XCTAssertNil(CRTShader.selected(in: d))
        XCTAssertEqual(CRTShader.allCases.count, 9)
        XCTAssertEqual(Set(CRTShader.allCases.map(\.title)).count, 9)
    }

    func testPictureOptionsAreStoredAndOffByDefault() {
        let d = store()
        for o in PictureOption.allCases {
            XCTAssertFalse(o.isEnabled(in: d)); o.setEnabled(true, in: d); XCTAssertTrue(o.isEnabled(in: d))
        }
        XCTAssertEqual(Set(PictureOption.allCases.map(\.defaultsKey)).count, PictureOption.allCases.count)
    }

    func testEdgeClickRule() {
        let desktop = CGRect(x: 0, y: 0, width: 1800, height: 1169)
        XCTAssertTrue(SynergySwitch.isClickClearOfEdge(at: CGPoint(x: 1783, y: 5), desktop: desktop))
        XCTAssertFalse(SynergySwitch.isClickClearOfEdge(at: CGPoint(x: 1784, y: 5), desktop: desktop))
        XCTAssertFalse(SynergySwitch.isClickClearOfEdge(at: CGPoint(x: 1799, y: 5), desktop: desktop))
        XCTAssertTrue(SynergySwitch.isClickClearOfEdge(at: CGPoint(x: 10, y: 5), desktop: desktop))
    }
}
