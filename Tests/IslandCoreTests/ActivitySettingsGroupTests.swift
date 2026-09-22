import Testing
@testable import IslandCore

struct ActivitySettingsGroupTests {
    @Test func laptopGroupsCoverEveryFeatureExactlyOnce() {
        let features = ActivitySettingsGroup.available(hasInternalBattery: true).flatMap(\.features)
        #expect(Set(features) == Set(Feature.allCases))
        #expect(features.count == Feature.allCases.count)
    }
    @Test func desktopHidesOnlyInternalBatteryFeatures() {
        let groups = ActivitySettingsGroup.available(hasInternalBattery: false)
        let features = Set(groups.flatMap(\.features))
        #expect(!groups.contains { $0.id == "battery" })
        #expect(features == Set(Feature.allCases).subtracting([.charging, .powerDisconnected, .chargeTarget, .lowBattery, .lowPowerMode]))
        #expect(features.contains(.airPods))
    }
}
