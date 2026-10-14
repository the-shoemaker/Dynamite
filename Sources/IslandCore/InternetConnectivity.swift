import Foundation

public enum InternetProbeSettings {
    public static let defaultAddress = "9.9.9.9"
    public static let onlineInterval: TimeInterval = 30
    public static let offlineInterval: TimeInterval = 5
    public static let confirmationInterval: TimeInterval = 2
    public static func normalizedAddress(_ input: String) -> String? {
        let parts = input.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0 >= "0" && $0 <= "9" } }),
              parts.allSatisfy({ Int($0).map { (0...255).contains($0) } == true }) else { return nil }
        let numbers = parts.compactMap { Int($0) }
        guard numbers[0] > 0, numbers[0] < 224, numbers != [255, 255, 255, 255] else { return nil }
        return numbers.map(String.init).joined(separator: ".")
    }
}

public enum InternetState: String, Equatable, Sendable { case checking, online, offline }

/// A missing route is decisive. Packet loss needs two failed probes; one reply
/// restores online immediately. Initial online readings establish a quiet baseline.
public struct InternetConnectivity {
    public private(set) var state: InternetState = .checking
    public private(set) var failures = 0
    public init() {}
    public mutating func reset() { self = Self() }
    public mutating func pathUnavailable() -> InternetState? {
        failures = 0
        return change(to: .offline)
    }
    public mutating func consumeProbe(reachable: Bool) -> InternetState? {
        if reachable { failures = 0; return change(to: .online) }
        failures = min(2, failures + 1)
        return failures >= 2 ? change(to: .offline) : nil
    }
    public var nextProbeInterval: TimeInterval {
        if failures == 1 { return InternetProbeSettings.confirmationInterval }
        return state == .online ? InternetProbeSettings.onlineInterval : InternetProbeSettings.offlineInterval
    }
    private mutating func change(to next: InternetState) -> InternetState? {
        let old = state
        state = next
        guard old != next else { return nil }
        return old == .checking && next == .online ? nil : next
    }
}

/// Link messages and internet recovery describe one reconnect. A link message
/// wins only during that same short settling window; later recoveries still show.
public struct ConnectionAnnouncements {
    private var linkTime: TimeInterval?
    public init() {}
    public mutating func linked(at now: TimeInterval) { linkTime = now }
    public mutating func reset() { linkTime = nil }
    public func shouldAnnounceOnline(at now: TimeInterval) -> Bool {
        guard let linkTime else { return true }
        return now - linkTime > 6
    }
}
