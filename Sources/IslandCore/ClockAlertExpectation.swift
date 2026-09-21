import Foundation

/// Gives imminent Clock alerts a short priority window without idle polling.
/// Clock reuses a timer's identifier when Repeat starts another countdown.
public struct ClockAlertExpectation {
    private var identifier: String?
    public private(set) var expiresAt: TimeInterval = 0
    public init() {}

    public mutating func expect(identifier: String, now: TimeInterval) {
        guard self.identifier != identifier || now >= expiresAt else { return }
        self.identifier = identifier
        expiresAt = now + 3
    }

    public func isUrgent(at now: TimeInterval) -> Bool { now < expiresAt }
}
