import Foundation

/// Confirmed AirPods own their connection, including when battery fields are
/// unavailable. Turning their activity off restores generic Bluetooth feedback.
public enum BluetoothConnectionActivity {
    public static func make(isAirPods: Bool, airPodsEnabled: Bool, label: String,
                            symbol: String, batteryPercentage: Int?) -> Activity {
        if isAirPods && airPodsEnabled {
            return Activity(.airPods, value: batteryPercentage ?? 0, label: "AirPods", symbol: symbol,
                            showsPercentage: batteryPercentage != nil)
        }
        return Activity(.bluetooth, value: 0, label: label, symbol: symbol, showsPercentage: false)
    }
}
