import Foundation

/// Running timers persist. Pausing starts a short grace period, held open by hover.
/// Repeated source readings do not extend the deadline.
public struct TimerVisibility {
    private var identifier: String?
    private var running = false
    private var hovered = false
    private var duration: Double = 2
    public private(set) var deadline: TimeInterval?

    public init() {}

    public mutating func update(identifier nextID: String?, running nextRunning: Bool,
                                hovered nextHovered: Bool, duration nextDuration: Double, now: TimeInterval) {
        let wasVisible = isVisible(at: now)
        let sameTimer = identifier != nil && identifier == nextID
        let justPaused = sameTimer && running && !nextRunning
        let leftHover = sameTimer && hovered && !nextHovered
        let durationChanged = duration != nextDuration
        if nextID == nil || nextRunning || !sameTimer { deadline = nil }
        if nextID != nil && !nextRunning {
            if nextHovered { deadline = nil }
            else if justPaused || leftHover || (durationChanged && wasVisible) {
                deadline = now + max(1, nextDuration)
            }
        }
        identifier = nextID
        running = nextRunning
        hovered = nextID != nil && nextHovered
        duration = nextDuration
    }

    public func isVisible(at now: TimeInterval) -> Bool {
        identifier != nil && (running || hovered || deadline.map { $0 > now } == true)
    }
}
