import Foundation

/// Providers submit state here; rendering never decides which source wins.
/// Persistent state returns only after the latest temporary activity expires.
public struct ActivitySchedule {
    public private(set) var persistent: Activity?
    public private(set) var temporary: Activity?
    public private(set) var expiresAt: TimeInterval?
    public init() {}
    public var current: Activity? { temporary ?? persistent }
    public mutating func setPersistent(_ activity: Activity?) { persistent = activity }
    public mutating func present(_ activity: Activity, duration: TimeInterval, now: TimeInterval) {
        temporary = activity
        expiresAt = now + max(0, duration)
    }
    public mutating func expire(at now: TimeInterval) {
        guard let expiresAt, now >= expiresAt else { return }
        temporary = nil
        self.expiresAt = nil
    }
    public mutating func remove(_ feature: Feature) {
        if persistent?.feature == feature { persistent = nil }
        if temporary?.feature == feature { temporary = nil; expiresAt = nil }
    }
    public mutating func reset() { self = ActivitySchedule() }
}
