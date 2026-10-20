import XCTest
@testable import AmigaViewCore

final class PCMJitterBufferTests: XCTestCase {
    /// s16le stereo frames: left = i, right = -i.
    static func pcm(_ range: Range<Int>) -> Data {
        var d = Data()
        for i in range {
            for v in [Int16(i), Int16(-i)] { d.append(UInt8(UInt16(bitPattern: v) & 0xFF)); d.append(UInt8(UInt16(bitPattern: v) >> 8)) }
        }
        return d
    }

    func read(_ b: PCMJitterBuffer, _ n: Int) -> ([Float], [Float]) {
        var l = [Float](repeating: 9, count: n), r = [Float](repeating: 9, count: n)
        l.withUnsafeMutableBufferPointer { lp in r.withUnsafeMutableBufferPointer { rp in
            b.read(left: lp.baseAddress!, right: rp.baseAddress!, frames: n) } }
        return (l, r)
    }

    func testSilenceUntilTargetIsBufferedThenSamplesInOrder() {
        let b = PCMJitterBuffer(target: 4, maximum: 100)
        b.write(Self.pcm(1..<3))
        XCTAssertEqual(read(b, 2).0, [0, 0], "still priming below the target")
        b.write(Self.pcm(3..<6))
        let (l, r) = read(b, 4)
        XCTAssertEqual(l.map { Int(($0 * 32768).rounded()) }, [1, 2, 3, 4])
        XCTAssertEqual(r.map { Int(($0 * 32768).rounded()) }, [-1, -2, -3, -4])
    }

    func testChunkSplitInsideASampleFrameKeepsTheStreamAligned() {
        let b = PCMJitterBuffer(target: 2, maximum: 100)
        let d = Self.pcm(1..<4)
        b.write(d.prefix(5)); b.write(d.dropFirst(5).prefix(4)); b.write(d.dropFirst(9))
        XCTAssertEqual(read(b, 3).1.map { Int(($0 * 32768).rounded()) }, [-1, -2, -3])
    }

    func testUnderrunPlaysSilenceAndPrimesAgain() {
        let b = PCMJitterBuffer(target: 2, maximum: 100)
        b.write(Self.pcm(1..<3))
        let (l, _) = read(b, 4)
        XCTAssertEqual(l.map { Int(($0 * 32768).rounded()) }, [1, 2, 0, 0])
        XCTAssertEqual(b.underruns, 1)
        b.write(Self.pcm(5..<6))
        XCTAssertEqual(read(b, 1).0, [0], "one frame is below the target again")
    }

    func testBacklogAboveMaximumIsCutBackToTargetKeepingTheNewest() {
        let b = PCMJitterBuffer(target: 4, maximum: 10)
        b.write(Self.pcm(0..<11))
        XCTAssertEqual(b.bufferedFrames, 4)
        XCTAssertEqual(b.droppedFrames, 7)
        XCTAssertEqual(read(b, 4).0.map { Int(($0 * 32768).rounded()) }, [7, 8, 9, 10])
    }
}
