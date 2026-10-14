import Foundation

public enum WirelessConnection { case offline, wifi, hotspot }

/// Silence launch/wake baselines and duplicate network notifications.
public struct HotspotTransitions {
    private var previous: WirelessConnection?
    private var lastAnnouncement: TimeInterval?
    public init() {}
    public mutating func reset() { previous = nil; lastAnnouncement = nil }
    public mutating func consume(connected: Bool?) -> Activity? {
        consume(connection: connected.map { $0 ? .hotspot : .offline })
    }
    public mutating func consume(connection: WirelessConnection?, now: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Activity? {
        guard let connection else { return nil }
        defer { previous = connection }
        guard let previous, previous != connection else { return nil }
        guard connection != .offline else { return nil }
        // Association, hotspot recognition, and route setup can briefly bounce
        // through different states. They still describe one connection.
        if let lastAnnouncement, now - lastAnnouncement < 4 { return nil }
        lastAnnouncement = now
        switch connection {
        case .offline: return nil
        case .wifi: return .preview(.wifi)
        case .hotspot: return .preview(.hotspot)
        }
    }
}
