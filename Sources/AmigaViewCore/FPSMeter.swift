import Foundation

/// Frames-per-second over a sliding window; the clock is injected by the caller.
public struct FPSMeter {
    private var stamps: [TimeInterval] = []
    public let window: TimeInterval
    public init(window: TimeInterval = 1) { self.window = window }

    public mutating func tick(at now: TimeInterval) { stamps.append(now); trim(now) }

    public mutating func fps(at now: TimeInterval) -> Double {
        trim(now)
        return Double(stamps.count) / window
    }

    public mutating func reset() { stamps.removeAll() }

    private mutating func trim(_ now: TimeInterval) {
        stamps.removeAll { now - $0 > window }
    }
}
