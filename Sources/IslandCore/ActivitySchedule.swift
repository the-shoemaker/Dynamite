import Foundation

/// One temporary slot replaces the primary status until its own deadline.
/// Persistent state is retained underneath and restores without a new event.
public struct ActivitySchedule {
    public struct Temporary: Equatable {
        public var activity: Activity
        public var duration: TimeInterval
        public var expiresAt: TimeInterval
    }
    public private(set) var persistents: [Activity] = []
    public private(set) var temporaries: [Temporary] = []
    public init() {}
    public var persistent: Activity? { persistents.first }
    public var temporary: Activity? { temporaries.last?.activity }
    public var expiresAt: TimeInterval? { temporaries.map(\.expiresAt).min() }
    public var current: Activity? { temporary ?? persistent }
    public mutating func setPersistent(_ activity: Activity?) { setPersistents(activity.map { [$0] } ?? []) }
    public mutating func setPersistents(_ activities: [Activity]) {
        var seen = Set<Feature>()
        persistents = activities.filter { seen.insert($0.feature).inserted }
    }
    public mutating func present(_ activity: Activity, duration: TimeInterval, now: TimeInterval) {
        let entry = Temporary(activity: activity, duration: duration, expiresAt: now + max(0, duration))
        temporaries = [entry]
    }
    public mutating func update(_ activity: Activity) {
        if let index = temporaries.firstIndex(where: { $0.activity.feature == activity.feature && $0.activity.sourceDisplayID == activity.sourceDisplayID }) { temporaries[index].activity = activity }
    }
    public mutating func expire(at now: TimeInterval) { temporaries.removeAll { now >= $0.expiresAt } }
    public mutating func remove(_ feature: Feature) {
        persistents.removeAll { $0.feature == feature }
        temporaries.removeAll { $0.activity.feature == feature }
    }
    public mutating func endTemporary() { temporaries.removeAll() }
    public mutating func reset() { self = ActivitySchedule() }
}
