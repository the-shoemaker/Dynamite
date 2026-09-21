import Foundation

public enum WirelessConnection { case offline, wifi, hotspot }

/// Silence launch/wake baselines and duplicate network notifications.
public struct HotspotTransitions {
    private var previous: WirelessConnection?
    public init() {}
    public mutating func reset() { previous = nil }
    public mutating func consume(connected: Bool?) -> Activity? {
        consume(connection: connected.map { $0 ? .hotspot : .offline })
    }
    public mutating func consume(connection: WirelessConnection?) -> Activity? {
        guard let connection else { return nil }
        defer { previous = connection }
        guard let previous, previous != connection else { return nil }
        switch connection {
        case .offline: return nil
        case .wifi: return .preview(.wifi)
        case .hotspot: return .preview(.hotspot)
        }
    }
}
