import Foundation

/// A missing Clock window is not evidence that its timer was cancelled.
public struct ClockContinuity {
    private var confirmed: ClockReading?
    private var confirmedAt: TimeInterval = 0
    public init() {}

    public mutating func resolve(_ reading: ClockReading?, idle: Bool, now: TimeInterval) -> ClockReading? {
        if let reading {
            confirmed = reading
            confirmedAt = now
            return reading
        }
        if idle { confirmed = nil; return nil }
        guard let confirmed else { return nil }
        let elapsed = max(0, now - confirmedAt)
        // Keep a short handoff at zero for the real finished alert, then stop.
        // Never manufacture a ringing alert or repeat controls from an estimate.
        guard confirmed.paused || elapsed < Double(confirmed.remaining) + 3 else {
            self.confirmed = nil
            return nil
        }
        return ClockReading(identifier: confirmed.identifier,
            remaining: confirmed.paused ? confirmed.remaining : max(0, confirmed.remaining - Int(elapsed)),
            paused: confirmed.paused)
    }
}
