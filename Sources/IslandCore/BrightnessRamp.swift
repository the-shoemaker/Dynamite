import Foundation

public enum BrightnessRange {
    /// Estimate output relative to the display's normal maximum from its linear
    /// backlight fraction and measured transfer gain. The slider is perceptual,
    /// so neither slider==100 nor gamma>1 alone describes the extra range.
    public static func isBoosted(linearBrightness: Float?, gammaPeak: Float?) -> Bool {
        guard let linearBrightness, linearBrightness.isFinite, linearBrightness >= 0,
              let gammaPeak, gammaPeak.isFinite, gammaPeak > 1.01 else { return false }
        return linearBrightness * gammaPeak > 1.01
    }
}

/// A short, monotonic hardware transition. New presses accumulate against the
/// pending target while starting from the actual current brightness.
public struct BrightnessRamp {
    public let start: Float
    public let target: Float
    public let startedAt: TimeInterval
    public static let duration: TimeInterval = 0.18

    public init(current: Float, pendingTarget: Float?, direction: Float, fine: Bool, now: TimeInterval) {
        start = min(1, max(0, current))
        target = min(1, max(0, (pendingTarget ?? start) + direction / (fine ? 64 : 16)))
        startedAt = now
    }
    public func value(at time: TimeInterval) -> Float {
        let progress = Float(min(1, max(0, (time - startedAt) / Self.duration)))
        let eased = progress * progress * (3 - 2 * progress)
        return start + (target - start) * eased
    }
    public func isComplete(at time: TimeInterval) -> Bool { time - startedAt >= Self.duration }
}
