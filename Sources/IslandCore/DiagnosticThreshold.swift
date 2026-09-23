import Foundation

/// Sustained-load detection only. A single animation spike never captures a stack.
public struct DiagnosticThreshold {
    private var consecutive = 0
    private var captures = 0
    private var lastCapture: TimeInterval?
    public init() {}
    public mutating func observe(cpuPercent: Double, footprint: UInt64, baseline: UInt64, elapsed: TimeInterval) -> Bool {
        let high = cpuPercent >= 20 || footprint >= 300 * 1_048_576 ||
            (footprint > baseline && footprint - baseline >= 150 * 1_048_576)
        consecutive = high ? consecutive + 1 : 0
        guard consecutive >= 3, captures < 3,
              lastCapture.map({ elapsed - $0 >= 1800 }) ?? true else { return false }
        captures += 1; lastCapture = elapsed; consecutive = 0
        return true
    }
}
