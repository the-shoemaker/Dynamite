import Foundation

/// MonitorControl's combined slider uses its lower segment for software dimming.
public struct ExternalBrightnessScale: Equatable {
    public let split: Float
    public let minimumSoftware: Float
    public init?(split: Float, allowBlackout: Bool) {
        guard split.isFinite, split >= 0, split < 1 else { return nil }
        self.split = split
        minimumSoftware = allowBlackout ? 0 : 0.15
    }
    public func hardware(_ value: Float) -> Float {
        min(1, max(0, (value - split) / (1 - split)))
    }
    public func software(_ value: Float) -> Float {
        guard split > 0 else { return 1 }
        return min(1, max(0, value / split)) * (1 - minimumSoftware) + minimumSoftware
    }
}
