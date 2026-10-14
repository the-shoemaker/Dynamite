import Testing
@testable import IslandCore

struct BluetoothConnectionActivityTests {
    @Test func airPodsOwnTheConnectionWhenBothFeaturesAreOn() {
        var preferences = Preferences()
        preferences.features[.bluetooth] = FeaturePreference(enabled: true)
        preferences.features[.airPods] = FeaturePreference(enabled: true)
        let activity = BluetoothConnectionActivity.make(isAirPods: true,
            airPodsEnabled: preferences.preference(for: .airPods).enabled,
            label: "Paired headphones", symbol: "airpodspro", batteryPercentage: 74)
        #expect(activity.feature == .airPods)
        #expect(activity.value == 74)
        #expect(activity.showsPercentage)
    }
    @Test func unknownBatteryDoesNotFallBackToBluetoothOrInventAPercentage() {
        let activity = BluetoothConnectionActivity.make(isAirPods: true, airPodsEnabled: true,
            label: "Paired headphones", symbol: "airpodspro", batteryPercentage: nil)
        #expect(activity.feature == .airPods)
        #expect(!activity.showsPercentage)
        #expect(activity.symbol == "airpodspro")
    }
    @Test func otherDevicesAndDisabledAirPodsKeepBluetoothFeedback() {
        let other = BluetoothConnectionActivity.make(isAirPods: false, airPodsEnabled: true,
            label: "Keyboard", symbol: "keyboard", batteryPercentage: nil)
        #expect(other.feature == .bluetooth)
        #expect(other.label == "Keyboard")
        let disabled = BluetoothConnectionActivity.make(isAirPods: true, airPodsEnabled: false,
            label: "Headphones", symbol: "headphones", batteryPercentage: 80)
        #expect(disabled.feature == .bluetooth)
        #expect(!disabled.showsPercentage)
    }
}
