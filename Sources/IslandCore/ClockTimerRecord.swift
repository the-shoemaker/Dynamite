import Foundation

/// Read-only mirror written by Clock's timer service. Unknown active formats fail
/// closed so a future macOS schema change can fall back to the UI adapter.
public struct ClockTimerRecord {
    public let identifier: String
    public let duration: Int
    public let deadline: Date?
    public let pausedRemaining: Double?

    public func reading(at now: Date) -> ClockReading {
        ClockReading(identifier: identifier,
            remaining: Int(ceil(min(604800, max(0, pausedRemaining ?? deadline?.timeIntervalSince(now) ?? 0)))),
            paused: pausedRemaining != nil)
    }
    public static func decode(_ data: Data) throws -> [ClockTimerRecord] {
        enum Invalid: Error { case schema }
        guard let root = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let store = root["MTTimers"] as? [String: Any],
              let timers = store["MTTimers"] as? [[String: Any]] else { throw Invalid.schema }
        return try timers.compactMap { wrapper in
            guard let timer = wrapper["$MTTimer"] as? [String: Any], let state = timer["MTTimerState"] as? Int else { throw Invalid.schema }
            guard state == 2 || state == 3 else {
                guard state == 1 || state == 4 else { throw Invalid.schema }
                return nil
            }
            guard let id = timer["MTTimerID"] as? String, UUID(uuidString: id) != nil,
                  let duration = timer["MTTimerDuration"] as? Double, duration.isFinite, duration > 0, duration < 604800,
                  let fire = timer["MTTimerFireTime"] as? [String: Any] else { throw Invalid.schema }
            if state == 3 {
                guard let value = fire["$MTTimerDate"] as? [String: Any], let date = value["MTTimerTimeDate"] as? Date else { throw Invalid.schema }
                return ClockTimerRecord(identifier: id, duration: Int(duration.rounded()), deadline: date, pausedRemaining: nil)
            }
            guard let value = fire["$MTTimerTimeInterval"] as? [String: Any],
                  let seconds = value["MTTimerTimeInterval"] as? Double, seconds.isFinite, seconds >= 0, seconds <= duration else { throw Invalid.schema }
            return ClockTimerRecord(identifier: id, duration: Int(duration.rounded()), deadline: nil, pausedRemaining: seconds)
        }
    }
}
