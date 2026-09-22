import Foundation

public struct ActivitySettingsGroup: Identifiable {
    public let id: String
    public let title: String
    public let features: [Feature]

    public static func available(hasInternalBattery: Bool) -> [Self] {
        var groups = [
            Self(id: "audio", title: "Audio", features: [.volume, .microphoneMute]),
            Self(id: "display", title: "Display & keyboard", features: [.brightness, .capsLock])
        ]
        if hasInternalBattery {
            groups.append(Self(id: "battery", title: "Battery", features: [.charging, .powerDisconnected, .chargeTarget, .lowBattery, .lowPowerMode]))
        }
        groups.append(Self(id: "activities", title: "Focus & timers", features: [.focus, .clockTimer]))
        groups.append(Self(id: "connections", title: "Connections", features: [.wifi, .hotspot, .bluetooth, .airPods, .airDrop]))
        return groups
    }
}
