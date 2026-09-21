import Foundation

public enum Feature: String, Codable, CaseIterable, Identifiable, Sendable {
    case volume, microphoneMute, brightness, charging, powerDisconnected, chargeTarget, lowBattery, lowPowerMode, capsLock, hotspot, wifi, bluetooth, airPods, focus, clockTimer, airDrop
    public var id: String { rawValue }
    public var defaultDuration: Double { self == .lowBattery ? 5 : 2 }
    public var title: String {
        switch self {
        case .volume: return "Volume"
        case .microphoneMute: return "Microphone mute"
        case .brightness: return "Brightness"
        case .charging: return "Charging"
        case .powerDisconnected: return "Power disconnected"
        case .chargeTarget: return "Charge target"
        case .lowBattery: return "Low battery"
        case .lowPowerMode: return "Low Power Mode"
        case .capsLock: return "Caps Lock"
        case .hotspot: return "Hotspot connected"
        case .wifi: return "Wi-Fi connected"
        case .bluetooth: return "Bluetooth connected"
        case .airPods: return "AirPods battery"
        case .focus: return "Focus"
        case .clockTimer: return "Clock timers"
        case .airDrop: return "AirDrop"
        }
    }
    public var symbol: String {
        switch self {
        case .volume: return "speaker.wave.2.fill"
        case .microphoneMute: return "mic.slash.fill"
        case .brightness: return "sun.max.fill"
        case .charging: return "battery.100percent.bolt"
        case .powerDisconnected: return "battery.75percent"
        case .chargeTarget: return "battery.100percent"
        case .lowBattery: return "battery.25percent"
        case .lowPowerMode: return "battery.75percent"
        case .capsLock: return "capslock.fill"
        case .hotspot: return "personalhotspot"
        case .wifi: return "wifi"
        case .bluetooth: return "antenna.radiowaves.left.and.right"
        case .airPods: return "airpodspro"
        case .focus: return "moon.fill"
        case .clockTimer: return "timer"
        case .airDrop: return "airdrop"
        }
    }
}

public struct FeaturePreference: Codable, Equatable {
    public var enabled: Bool
    public var duration: Double
    public init(enabled: Bool = true, duration: Double = 2) {
        self.enabled = enabled
        self.duration = duration
    }
}

public enum DisplayPlacement: String, Codable, CaseIterable {
    case pointer, main, all
    public var title: String {
        switch self {
        case .pointer: return "Display with pointer"
        case .main: return "Main display"
        case .all: return "All displays"
        }
    }
}

public struct Preferences: Codable, Equatable {
    public var features: [Feature: FeaturePreference] = [:]
    public var chargeTarget = 80
    public var lowThreshold = 20
    public var placement: DisplayPlacement = .pointer
    public var paused = false
    public var showMenuBarIcon = true
    public var keepSettingsOnTop = true
    public var vividCompatibility = true
    public var smoothBrightness = true
    public init() {}
    private enum CodingKeys: String, CodingKey {
        case features, chargeTarget, lowThreshold, placement, paused, showMenuBarIcon, keepSettingsOnTop, vividCompatibility, smoothBrightness
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        features = try values.decodeIfPresent([Feature: FeaturePreference].self, forKey: .features) ?? [:]
        chargeTarget = try values.decodeIfPresent(Int.self, forKey: .chargeTarget) ?? 80
        lowThreshold = try values.decodeIfPresent(Int.self, forKey: .lowThreshold) ?? 20
        placement = try values.decodeIfPresent(DisplayPlacement.self, forKey: .placement) ?? .pointer
        paused = try values.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        showMenuBarIcon = try values.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        keepSettingsOnTop = try values.decodeIfPresent(Bool.self, forKey: .keepSettingsOnTop) ?? true
        vividCompatibility = try values.decodeIfPresent(Bool.self, forKey: .vividCompatibility) ?? true
        smoothBrightness = try values.decodeIfPresent(Bool.self, forKey: .smoothBrightness) ?? true
    }
    public func preference(for feature: Feature) -> FeaturePreference {
        features[feature] ?? FeaturePreference(enabled: feature != .lowBattery && feature != .focus, duration: feature.defaultDuration)
    }
    public mutating func normalize() {
        chargeTarget = min(100, max(50, chargeTarget))
        lowThreshold = min(40, max(5, lowThreshold))
        for feature in Feature.allCases {
            var pref = preference(for: feature)
            pref.duration = ActivityDuration.validated(pref.duration)
            features[feature] = pref
        }
    }
}

public struct Activity: Equatable {
    public let feature: Feature
    public let value: Int
    public let label: String
    public let symbol: String
    public let isBoosted: Bool
    public let isActive: Bool
    public let remainingSeconds: Int?
    public let sourceDisplayID: UInt32?
    public init(_ feature: Feature, value: Int, label: String? = nil, symbol: String? = nil, isBoosted: Bool = false, isActive: Bool = true, sourceDisplayID: UInt32? = nil, remainingSeconds: Int? = nil) {
        self.feature = feature
        self.value = max(0, min(100, value))
        self.label = label ?? feature.title
        self.symbol = symbol ?? ([.powerDisconnected, .lowPowerMode].contains(feature) ? "battery.\(min(100, max(0, ((value + 12) / 25) * 25)))percent" : feature.symbol)
        self.isBoosted = feature == .brightness && isBoosted
        self.isActive = isActive
        self.sourceDisplayID = sourceDisplayID
        self.remainingSeconds = remainingSeconds.map { max(0, $0) }
    }
    public static func preview(_ feature: Feature, preferences: Preferences? = nil) -> Activity {
        switch feature {
        case .volume: return Activity(feature, value: 64)
        case .microphoneMute: return Activity(feature, value: 0, label: "Microphone", isActive: false)
        case .brightness: return Activity(feature, value: 72)
        case .charging: return Activity(feature, value: 68)
        case .powerDisconnected: return Activity(feature, value: 68, label: "On battery")
        case .chargeTarget:
            let target = preferences?.chargeTarget ?? 80
            return Activity(feature, value: target, label: target == 100 ? "Fully charged" : "Target reached")
        case .lowBattery: return Activity(feature, value: preferences?.lowThreshold ?? 20, label: "Battery low")
        case .lowPowerMode: return Activity(feature, value: 68, label: "Low Power Mode")
        case .capsLock: return Activity(feature, value: 0, label: "Caps Lock")
        case .hotspot: return Activity(feature, value: 0, label: "Hotspot")
        case .wifi: return Activity(feature, value: 0, label: "Wi-Fi")
        case .bluetooth: return Activity(feature, value: 0, label: "Bluetooth")
        case .airPods: return Activity(feature, value: 75, label: "AirPods")
        case .focus: return Activity(feature, value: 0, label: "Focus")
        case .clockTimer: return Activity(feature, value: 0, label: "Timer", remainingSeconds: 119)
        case .airDrop: return Activity(feature, value: 100, label: "Received")
        }
    }
}

public struct BatterySnapshot: Equatable {
    public let percent: Int
    public let pluggedIn: Bool
    public let charging: Bool
    public let lowPowerMode: Bool
    public init(percent: Int, pluggedIn: Bool, charging: Bool, lowPowerMode: Bool = false) {
        self.percent = max(0, min(100, percent))
        self.pluggedIn = pluggedIn
        self.charging = charging
        self.lowPowerMode = lowPowerMode
    }
}

/// Edges only. The initial reading and unchanged notifications never announce.
public struct BatteryTransitions {
    private var previous: BatterySnapshot?
    public init() {}
    public mutating func reset(to snapshot: BatterySnapshot?) { previous = snapshot }
    public mutating func consume(_ next: BatterySnapshot, preferences: Preferences) -> [Activity] {
        defer { previous = next }
        guard let old = previous, !preferences.paused else { return [] }
        var result: [Activity] = []
        if old.lowPowerMode != next.lowPowerMode {
            result.append(Activity(.lowPowerMode, value: next.percent,
                label: next.lowPowerMode ? "Low Power Mode" : "Low Power Mode off", isActive: next.lowPowerMode))
        }
        if next.pluggedIn && !old.pluggedIn {
            result.append(Activity(.charging, value: next.percent,
                label: next.charging ? "Charging" : "Power connected"))
        }
        if old.pluggedIn && !next.pluggedIn {
            result.append(Activity(.powerDisconnected, value: next.percent, label: "On battery"))
        }
        if next.pluggedIn && old.percent < preferences.chargeTarget && next.percent >= preferences.chargeTarget {
            result.append(Activity(.chargeTarget, value: next.percent,
                label: next.percent == 100 ? "Fully charged" : "Target reached"))
        }
        if !next.pluggedIn && next.percent <= preferences.lowThreshold &&
            (old.percent > preferences.lowThreshold || old.pluggedIn) {
            result.append(Activity(.lowBattery, value: next.percent, label: "Battery low"))
        }
        return result.filter { preferences.preference(for: $0.feature).enabled }
    }
}

public enum MediaKey: Int {
    case volumeUp = 0, volumeDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
    public var feature: Feature {
        self == .brightnessUp || self == .brightnessDown ? .brightness : .volume
    }
    public var direction: Float {
        self == .volumeUp || self == .brightnessUp ? 1 : -1
    }
}

public struct MediaKeyPress {
    public let key: MediaKey
    public let isDown: Bool
    public init?(data: Int) {
        guard let key = MediaKey(rawValue: (data >> 16) & 0xFFFF) else { return nil }
        let state = (data >> 8) & 0xFF
        guard state == 0xA || state == 0xB else { return nil }
        self.key = key
        self.isDown = state == 0xA
    }
}
