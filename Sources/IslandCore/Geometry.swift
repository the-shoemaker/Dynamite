import Foundation
import CoreGraphics

public struct IslandGeometry: Equatable, Sendable {
    public let height: Double
    public let notchWidth: Double
    public let topGap: Double
    public var isNotched: Bool { notchWidth > 0 }
    public init(safeTop: Double, notchWidth: Double, referenceHeight: Double = 32, externalPreview: Bool = false, floatingTopGap: Double? = nil) {
        self.notchWidth = !externalPreview && floatingTopGap == nil && safeTop > 0 ? max(0, notchWidth) : 0
        self.height = safeTop > 0 && notchWidth > 0 ? safeTop : max(24, min(40, referenceHeight))
        self.topGap = floatingTopGap ?? (externalPreview ? safeTop + 6 : safeTop > 0 && notchWidth > 0 ? 0 : 6)
    }
    /// A one-point lip hides the seam at the bottom of the physical camera housing.
    public var shellHeight: Double { height + (isNotched ? 1 : 0) }
    public func widths(for feature: Feature) -> (left: Double, right: Double) {
        // Equal wings keep the icon and percentage balanced around the camera.
        [.hotspot, .wifi, .bluetooth, .clockTimer, .microphoneMute, .airDrop].contains(feature) ? (84, 84) : (68, 68)
    }
    public func expandedWidth(for feature: Feature) -> Double {
        let sides = widths(for: feature)
        return notchWidth + sides.left + sides.right
    }
    /// Include the screen's upper boundary and the gap above a floating pill.
    /// Transparent overshoot space below the activity is intentionally excluded.
    public func containsHover(_ point: CGPoint, screen: CGRect, width: Double, height: Double) -> Bool {
        point.x >= screen.midX - width / 2 && point.x <= screen.midX + width / 2 &&
            point.y >= screen.maxY - topGap - height && point.y <= screen.maxY
    }
    public func menuRegion(in frame: CGRect) -> CGRect? {
        guard isNotched else { return nil }
        let x = frame.midX - CGFloat(notchWidth / 2 + 4)
        let y = frame.maxY - CGFloat(shellHeight + 12)
        return CGRect(x: x, y: y, width: CGFloat(notchWidth + 8), height: CGFloat(shellHeight + 13))
    }
}

public enum VolumeAdjustment {
    /// Preserve relative stereo balance when there is no virtual main control.
    public static func channelValues(_ current: [Float], target: Float) -> [Float] {
        let peak = current.max() ?? 0
        let bounded = min(1, max(0, target))
        guard peak > 0 else { return current.map { _ in bounded } }
        return current.map { min(1, max(0, $0 / peak * bounded)) }
    }
}
