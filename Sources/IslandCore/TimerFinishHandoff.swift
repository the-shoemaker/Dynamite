import Foundation

/// One bounded handoff during the last displayed second, never an idle poll.
public struct TimerFinishHandoff {
    public private(set) var identifier: String?
    public private(set) var deadline: TimeInterval?
    public init() {}
    public mutating func update(identifier: String?, remaining: Int?, running: Bool, now: TimeInterval) {
        guard running, let identifier, let remaining, remaining <= 1 else {
            self.identifier = identifier
            deadline = nil
            return
        }
        if self.identifier != identifier { deadline = nil }
        self.identifier = identifier
        if remaining == 0 { deadline = min(deadline ?? now, now) }
        else if deadline == nil { deadline = now + 0.45 }
    }
    public func isImminent(at now: TimeInterval) -> Bool { deadline.map { now >= $0 } ?? false }
}
