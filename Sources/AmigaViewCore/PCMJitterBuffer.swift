import Foundation

/// Live s16le stereo PCM from the network to the audio device. The writer appends whatever the
/// socket hands over (a chunk may split a sample frame); the render thread pulls float frames.
/// Latency stays bounded so the sound keeps up with the picture: on an underrun it plays silence
/// until `target` frames are buffered again, and when more than `maximum` frames pile up (network
/// burst, a stalled audio device) the oldest are dropped back down to `target`.
public final class PCMJitterBuffer {
    public static let channels = 2
    public let target: Int
    public let maximum: Int

    private let lock = NSLock()
    private var samples: [Int16] = []     // interleaved L R L R
    private var head = 0                  // index of the next sample to play
    private var carry: [UInt8] = []       // bytes of an unfinished sample frame
    private var priming = true
    public private(set) var underruns = 0
    public private(set) var droppedFrames = 0

    public init(target: Int, maximum: Int) {
        precondition(target > 0 && maximum > target)
        self.target = target; self.maximum = maximum
    }

    /// Frames waiting to be played.
    public var bufferedFrames: Int { lock.lock(); defer { lock.unlock() }; return available }
    private var available: Int { (samples.count - head) / Self.channels }

    public func write(_ data: Data) {
        let frameBytes = 2 * Self.channels
        lock.lock(); defer { lock.unlock() }
        var bytes = carry
        bytes.append(contentsOf: data)
        let whole = bytes.count / frameBytes * frameBytes
        samples.reserveCapacity(samples.count - head + whole / 2)
        var i = 0
        while i < whole {
            samples.append(Int16(bitPattern: UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8))
            i += 2
        }
        carry = Array(bytes[whole...])
        if available > maximum {
            let drop = available - target
            head += drop * Self.channels
            droppedFrames += drop
        }
        if priming, available >= target { priming = false }
        compact()
    }

    /// Fills `frames` frames of left and right with -1...1; silence where there is nothing to play.
    public func read(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        lock.lock(); defer { lock.unlock() }
        var n = 0
        if !priming {
            n = min(frames, available)
            for f in 0..<n {
                left[f] = Float(samples[head]) / 32768
                right[f] = Float(samples[head + 1]) / 32768
                head += Self.channels
            }
            if n < frames { priming = true; underruns += 1 }
        }
        for f in n..<frames { left[f] = 0; right[f] = 0 }
        compact()
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        samples.removeAll(keepingCapacity: true); head = 0; carry = []; priming = true
    }

    private func compact() {
        if head > 0 && head * 2 >= samples.count { samples.removeFirst(head); head = 0 }
    }
}
