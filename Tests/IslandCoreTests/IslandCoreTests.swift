import Foundation
import Testing
@testable import IslandCore

struct BatteryTransitionsTests {
    private func snapshot(_ percent: Int, plugged: Bool = false, charging: Bool = false) -> BatterySnapshot {
        BatterySnapshot(percent: percent, pluggedIn: plugged, charging: charging)
    }
    @Test func testInitialAndUnchangedReadingsAreSilent() {
        var monitor = BatteryTransitions()
        let preferences = Preferences()
        #expect(monitor.consume(snapshot(50, plugged: true, charging: true), preferences: preferences).isEmpty)
        #expect(monitor.consume(snapshot(50, plugged: true, charging: true), preferences: preferences).isEmpty)
    }
    @Test func testConnectionReportsActualChargingState() {
        var monitor = BatteryTransitions()
        let preferences = Preferences()
        _ = monitor.consume(snapshot(80), preferences: preferences)
        let events = monitor.consume(snapshot(80, plugged: true), preferences: preferences)
        #expect(events.map(\.feature) == [.charging])
        #expect(events.first?.label == "Power connected")
    }
    @Test func testTargetCrossingSkipsAndDoesNotRepeat() {
        var monitor = BatteryTransitions()
        let preferences = Preferences()
        _ = monitor.consume(snapshot(78, plugged: true, charging: true), preferences: preferences)
        #expect(monitor.consume(snapshot(81, plugged: true, charging: true), preferences: preferences).map(\.feature) == [.chargeTarget])
        #expect(monitor.consume(snapshot(82, plugged: true, charging: true), preferences: preferences).isEmpty)
    }
    @Test func testTargetDoesNotClaimFullChargeAtEighty() {
        var monitor = BatteryTransitions()
        let preferences = Preferences()
        _ = monitor.consume(snapshot(79, plugged: true), preferences: preferences)
        #expect(monitor.consume(snapshot(80, plugged: true), preferences: preferences).first?.label == "Target reached")
    }
    @Test func testFullChargeTarget() {
        var monitor = BatteryTransitions()
        var preferences = Preferences()
        preferences.chargeTarget = 100
        _ = monitor.consume(snapshot(99, plugged: true), preferences: preferences)
        #expect(monitor.consume(snapshot(100, plugged: true), preferences: preferences).first?.label == "Fully charged")
    }
    @Test func testLowBatteryIsOptInAndCrossesOnce() {
        var monitor = BatteryTransitions()
        var preferences = Preferences()
        preferences.features[.lowBattery] = FeaturePreference(enabled: true, duration: 7)
        _ = monitor.consume(snapshot(21), preferences: preferences)
        #expect(monitor.consume(snapshot(19), preferences: preferences).map(\.feature) == [.lowBattery])
        #expect(monitor.consume(snapshot(18), preferences: preferences).isEmpty)
        _ = monitor.consume(snapshot(23), preferences: preferences)
        #expect(monitor.consume(snapshot(20), preferences: preferences).map(\.feature) == [.lowBattery])
    }
    @Test func testUnpluggingBelowThresholdRemindsOnce() {
        var monitor = BatteryTransitions()
        var preferences = Preferences()
        preferences.features[.lowBattery] = FeaturePreference()
        _ = monitor.consume(snapshot(15, plugged: true), preferences: preferences)
        #expect(monitor.consume(snapshot(15), preferences: preferences).map(\.feature) == [.powerDisconnected, .lowBattery])
        #expect(monitor.consume(snapshot(15), preferences: preferences).isEmpty)
    }
    @Test func testDisabledFeatureStillUpdatesBaseline() {
        var monitor = BatteryTransitions()
        var preferences = Preferences()
        preferences.features[.charging] = FeaturePreference(enabled: false)
        _ = monitor.consume(snapshot(50), preferences: preferences)
        #expect(monitor.consume(snapshot(50, plugged: true, charging: true), preferences: preferences).isEmpty)
        preferences.features[.charging]?.enabled = true
        #expect(monitor.consume(snapshot(51, plugged: true, charging: true), preferences: preferences).isEmpty)
    }
    @Test func testPauseDoesNotReplayEvents() {
        var monitor = BatteryTransitions()
        var preferences = Preferences()
        _ = monitor.consume(snapshot(60), preferences: preferences)
        preferences.paused = true
        #expect(monitor.consume(snapshot(60, plugged: true, charging: true), preferences: preferences).isEmpty)
        preferences.paused = false
        #expect(monitor.consume(snapshot(61, plugged: true, charging: true), preferences: preferences).isEmpty)
    }
    @Test func testResetAfterWakeDoesNotInventAnEvent() {
        var monitor = BatteryTransitions()
        let preferences = Preferences()
        _ = monitor.consume(snapshot(60), preferences: preferences)
        monitor.reset(to: nil)
        #expect(monitor.consume(snapshot(90, plugged: true), preferences: preferences).isEmpty)
    }
}

struct PreferenceTests {
    @Test func testDefaultsAndIndividualDurations() {
        var preferences = Preferences()
        #expect(preferences.preference(for: .volume).duration == 2)
        #expect(!(preferences.preference(for: .lowBattery).enabled))
        #expect(preferences.preference(for: .lowBattery).duration == 5)
        preferences.features[.charging] = FeaturePreference(enabled: false, duration: 4)
        #expect(preferences.preference(for: .volume).duration == 2)
        #expect(preferences.preference(for: .charging).duration == 4)
    }
    @Test func testPersistenceRoundTrip() throws {
        var preferences = Preferences()
        preferences.features[.charging] = FeaturePreference(enabled: false, duration: 4)
        preferences.lowThreshold = 15
        preferences.placement = .all
        #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences)) == preferences)
    }
    @Test func testInvalidSavedValuesAreClamped() {
        var preferences = Preferences()
        preferences.chargeTarget = 200
        preferences.lowThreshold = -10
        preferences.features[.volume] = FeaturePreference(duration: -.infinity)
        preferences.features[.brightness] = FeaturePreference(duration: 200)
        preferences.normalize()
        #expect(preferences.chargeTarget == 100)
        #expect(preferences.lowThreshold == 5)
        #expect(preferences.preference(for: .volume).duration == 2)
        #expect(preferences.preference(for: .brightness).duration == 200)
    }
}

struct MediaKeyTests {
    @Test func testKeyDownRepeatAndReleaseDecoding() {
        #expect(MediaKeyPress(data: (1 << 16) | (0xA << 8))?.key == .volumeDown)
        #expect(MediaKeyPress(data: (1 << 16) | (0xA << 8) | 1)?.isDown == true)
        #expect(MediaKeyPress(data: (1 << 16) | (0xB << 8))?.isDown == false)
    }
    @Test func testUnrelatedAndInvalidEventsAreIgnored() {
        #expect(MediaKeyPress(data: (16 << 16) | (0xA << 8)) == nil)
        #expect(MediaKeyPress(data: (0 << 16) | (0xF << 8)) == nil)
        #expect(MediaKeyPress(data: (7 << 16) | (0xA << 8))?.key == .mute)
    }
}

struct GeometryAndVolumeTests {
    @Test func notchStaysInItsExistingVerticalSpace() {
        let geometry = IslandGeometry(safeTop: 38, notchWidth: 220)
        #expect(geometry.height == 38)
        #expect(geometry.topGap == 0)
        #expect(geometry.isNotched)
        #expect(geometry.expandedWidth(for: .volume) == 356)
    }
    @Test func externalPillUsesNotchHeightWithoutACenterGap() {
        let geometry = IslandGeometry(safeTop: 0, notchWidth: 0, referenceHeight: 38)
        #expect(geometry.height == 38)
        #expect(geometry.topGap == 6)
        #expect(!geometry.isNotched)
        #expect(geometry.expandedWidth(for: .volume) == 136)
    }
    @Test func nonNotchedMacHasCompactFallback() {
        let geometry = IslandGeometry(safeTop: 0, notchWidth: 0)
        #expect(geometry.height == 32)
        #expect(geometry.notchWidth == 0)
    }
    @Test func externalPreviewClearsThePhysicalNotch() {
        let geometry = IslandGeometry(safeTop: 38, notchWidth: 220, externalPreview: true)
        #expect(!geometry.isNotched)
        #expect(geometry.notchWidth == 0)
        #expect(geometry.topGap == 44)
        #expect(geometry.height == 38)
        #expect(geometry.shellHeight == 38)
        #expect(geometry.expandedWidth(for: .volume) == 136)
    }
    @Test func notchLipMasksTheHardwareSeamWithoutGrowingContent() {
        let geometry = IslandGeometry(safeTop: 38, notchWidth: 220)
        #expect(geometry.height == 38)
        #expect(geometry.shellHeight == 39)
    }
    @Test func stereoFallbackPreservesBalance() {
        let values = VolumeAdjustment.channelValues([0.2, 0.4], target: 0.6)
        #expect(abs(values[0] - 0.3) < 0.0001)
        #expect(abs(values[1] - 0.6) < 0.0001)
    }
    @Test func silentStereoCanBeRaisedAndTargetsAreBounded() {
        #expect(VolumeAdjustment.channelValues([0, 0], target: 0.25) == [0.25, 0.25])
        #expect(VolumeAdjustment.channelValues([0.5, 1], target: 2) == [0.5, 1])
    }
    @Test func oldPreferencesKeepSettingsWhenNewOptionsAreAdded() throws {
        let json = Data(#"{"chargeTarget":85,"paused":true,"placement":"all"}"#.utf8)
        let restored = try JSONDecoder().decode(Preferences.self, from: json)
        #expect(restored.chargeTarget == 85)
        #expect(restored.paused)
        #expect(restored.placement == .all)
        #expect(restored.showMenuBarIcon)
        #expect(restored.keepSettingsOnTop)
    }
}

struct BoostedBrightnessTests {
    @Test func boostUsesLinearOutputRatherThanRunningStateOrSliderCeiling() {
        #expect(!BrightnessRange.isBoosted(linearBrightness: 0.5, gammaPeak: 1.45))
        #expect(!BrightnessRange.isBoosted(linearBrightness: 0.65, gammaPeak: 1.45))
        // Observed at 87.5% on the perceptual system slider, below 100%.
        #expect(BrightnessRange.isBoosted(linearBrightness: 0.72742695, gammaPeak: 1.45))
        #expect(BrightnessRange.isBoosted(linearBrightness: 1, gammaPeak: 1.45))
        #expect(!BrightnessRange.isBoosted(linearBrightness: 1, gammaPeak: 1))
        #expect(!BrightnessRange.isBoosted(linearBrightness: nil, gammaPeak: 1.45))
        #expect(!BrightnessRange.isBoosted(linearBrightness: .nan, gammaPeak: 1.45))
    }
    @Test func markerIsOnlyForBrightness() {
        #expect(Activity(.brightness, value: 100, isBoosted: true).isBoosted)
        #expect(!Activity(.brightness, value: 72).isBoosted)
        #expect(!Activity(.charging, value: 100, isBoosted: true).isBoosted)
    }
}

struct BrightnessRampTests {
    @Test func rampsAreMonotonicAndReachTheExactTarget() {
        for direction: Float in [-1, 1] {
            let ramp = BrightnessRamp(current: 0.5, pendingTarget: nil, direction: direction, fine: false, now: 10)
            var previous = ramp.start
            for step in 0...30 {
                let value = ramp.value(at: 10 + Double(step) * 0.01)
                #expect((value - previous) * direction >= 0)
                #expect(value >= min(ramp.start, ramp.target) && value <= max(ramp.start, ramp.target))
                previous = value
            }
            #expect(previous == ramp.target)
            #expect(ramp.isComplete(at: 10.3))
        }
    }
    @Test func heldKeysAccumulateInsteadOfLosingPartialSteps() {
        let first = BrightnessRamp(current: 0.5, pendingTarget: nil, direction: 1, fine: false, now: 0)
        let current = first.value(at: 0.04)
        let next = BrightnessRamp(current: current, pendingTarget: first.target, direction: 1, fine: false, now: 0.04)
        #expect(next.start == current)
        #expect(next.target == 0.625)
        #expect(next.value(at: 0.04) == current)
    }
    @Test func fineStepsAndEndpointsStayBounded() {
        let fine = BrightnessRamp(current: 0.5, pendingTarget: nil, direction: -1, fine: true, now: 0)
        #expect(fine.target == 0.484375)
        #expect(BrightnessRamp(current: 1, pendingTarget: nil, direction: 1, fine: false, now: 0).target == 1)
        #expect(BrightnessRamp(current: 0, pendingTarget: nil, direction: -1, fine: false, now: 0).target == 0)
    }
}

struct BalancedLayoutTests {
    @Test func everyActivityUsesEqualWings() {
        let geometry = IslandGeometry(safeTop: 38, notchWidth: 220)
        for feature in Feature.allCases {
            let sides = geometry.widths(for: feature)
            #expect(sides.left == sides.right)
            #expect(geometry.expandedWidth(for: feature) == ([.hotspot, .wifi, .bluetooth, .clockTimer, .microphoneMute, .airDrop].contains(feature) ? 388 : 356))
        }
    }
}

struct PowerDisconnectTests {
    @Test func unpluggingReportsTheActualLevelOnce() {
        var transitions = BatteryTransitions()
        let preferences = Preferences()
        _ = transitions.consume(BatterySnapshot(percent: 68, pluggedIn: true, charging: true), preferences: preferences)
        let snapshot = BatterySnapshot(percent: 68, pluggedIn: false, charging: false)
        let events = transitions.consume(snapshot, preferences: preferences)
        #expect(events.map(\.feature) == [.powerDisconnected])
        #expect(events.first?.symbol == "battery.75percent")
        #expect(events.first?.value == 68)
        #expect(transitions.consume(snapshot, preferences: preferences).isEmpty)
    }
    @Test func disconnectCanBeDisabled() {
        var transitions = BatteryTransitions()
        var preferences = Preferences()
        preferences.features[.powerDisconnected] = FeaturePreference(enabled: false)
        _ = transitions.consume(BatterySnapshot(percent: 52, pluggedIn: true, charging: false), preferences: preferences)
        #expect(transitions.consume(BatterySnapshot(percent: 52, pluggedIn: false, charging: false), preferences: preferences).isEmpty)
        #expect(Activity(.powerDisconnected, value: 0).symbol == "battery.0percent")
        #expect(Activity(.powerDisconnected, value: 100).symbol == "battery.100percent")
    }
}

struct ActivityScheduleTests {
    @Test func capsLockReturnsAfterTheLatestTemporaryActivity() {
        var schedule = ActivitySchedule()
        schedule.setPersistent(.preview(.capsLock))
        schedule.present(.preview(.volume), duration: 2, now: 10)
        schedule.present(.preview(.brightness), duration: 2, now: 11)
        schedule.expire(at: 12)
        #expect(schedule.current?.feature == .brightness)
        schedule.expire(at: 13)
        #expect(schedule.current?.feature == .capsLock)
        #expect(schedule.expiresAt == nil)
    }
    @Test func turningCapsOffDuringAnInterruptionDoesNotBringItBack() {
        var schedule = ActivitySchedule()
        schedule.setPersistent(.preview(.capsLock))
        schedule.present(.preview(.volume), duration: 2, now: 10)
        schedule.setPersistent(nil)
        #expect(schedule.current?.feature == .volume)
        schedule.expire(at: 12)
        #expect(schedule.current == nil)
    }
    @Test func enablingCapsDuringAnActivityWaitsAndPauseClearsEverything() {
        var schedule = ActivitySchedule()
        schedule.present(.preview(.volume), duration: 2, now: 10)
        schedule.setPersistent(.preview(.capsLock))
        #expect(schedule.current?.feature == .volume)
        schedule.reset()
        schedule.expire(at: 20)
        #expect(schedule.current == nil)
    }
}

struct HotspotTransitionTests {
    @Test func baselineAndDuplicateCallbacksAreQuiet() {
        var state = HotspotTransitions()
        #expect(state.consume(connected: true) == nil)
        #expect(state.consume(connected: true) == nil)
        #expect(state.consume(connected: false) == nil)
        #expect(state.consume(connected: true)?.feature == .hotspot)
        #expect(state.consume(connected: true) == nil)
    }
    @Test func unknownAndWakeDoNotInventConnections() {
        var state = HotspotTransitions()
        #expect(state.consume(connected: false) == nil)
        #expect(state.consume(connected: nil) == nil)
        #expect(state.consume(connected: true)?.feature == .hotspot)
        state.reset()
        #expect(state.consume(connected: true) == nil)
    }
}

struct ThresholdPreviewTests {
    @Test func previewsUseTheSavedThresholds() {
        var preferences = Preferences()
        preferences.lowThreshold = 15
        preferences.chargeTarget = 90
        #expect(Activity.preview(.lowBattery, preferences: preferences).value == 15)
        #expect(Activity.preview(.chargeTarget, preferences: preferences).value == 90)
        #expect(Activity.preview(.chargeTarget, preferences: preferences).label == "Target reached")
        preferences.chargeTarget = 100
        #expect(Activity.preview(.chargeTarget, preferences: preferences).label == "Fully charged")
    }
}


struct WirelessAndHitRegionTests {
    @Test func wifiAndHotspotUseDistinctConnectionActivities() {
        var state = HotspotTransitions()
        #expect(state.consume(connection: .offline) == nil)
        #expect(state.consume(connection: .wifi)?.feature == .wifi)
        #expect(state.consume(connection: .wifi) == nil)
        #expect(state.consume(connection: .hotspot)?.feature == .hotspot)
        #expect(state.consume(connection: .wifi)?.feature == .wifi)
        #expect(state.consume(connection: .offline) == nil)
    }
    @Test func notchMenuIncludesTheExactTopScreenEdge() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let geometry = IslandGeometry(safeTop: 38, notchWidth: 220)
        let target = geometry.menuRegion(in: screen)!
        #expect(target.contains(CGPoint(x: screen.midX, y: screen.maxY)))
        #expect(target.contains(CGPoint(x: screen.midX, y: screen.maxY - 45)))
        #expect(!target.contains(CGPoint(x: 100, y: screen.maxY)))
        #expect(IslandGeometry(safeTop: 0, notchWidth: 0).menuRegion(in: screen) == nil)
    }
}

struct LowPowerModeTests {
    @Test func onlyModeEdgesAnnounceAndUseActualBattery() {
        var transitions = BatteryTransitions()
        let preferences = Preferences()
        #expect(transitions.consume(BatterySnapshot(percent: 42, pluggedIn: false, charging: false), preferences: preferences).isEmpty)
        let enabled = transitions.consume(BatterySnapshot(percent: 41, pluggedIn: false, charging: false, lowPowerMode: true), preferences: preferences)
        #expect(enabled.count == 1)
        #expect(enabled.first?.feature == .lowPowerMode)
        #expect(enabled.first?.isActive == true)
        #expect(enabled.first?.value == 41)
        #expect(enabled.first?.symbol == "battery.50percent")
        #expect(transitions.consume(BatterySnapshot(percent: 40, pluggedIn: false, charging: false, lowPowerMode: true), preferences: preferences).isEmpty)
        let disabled = transitions.consume(BatterySnapshot(percent: 39, pluggedIn: false, charging: false), preferences: preferences)
        #expect(disabled.first?.isActive == false)
        #expect(disabled.first?.value == 39)
    }
    @Test func smoothBrightnessDefaultsAndSavedChoiceSurviveDecoding() throws {
        let old = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        #expect(old.smoothBrightness)
        var custom = Preferences()
        custom.smoothBrightness = false
        #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(custom)).smoothBrightness == false)
    }
    @Test func shorterDurationReplacesTheOldDeadlineAndReturnsPersistentActivity() {
        var schedule = ActivitySchedule()
        schedule.setPersistent(.preview(.capsLock))
        schedule.present(.preview(.brightness), duration: 15, now: 0)
        schedule.present(.preview(.brightness), duration: 2, now: 1)
        schedule.expire(at: 2.9)
        #expect(schedule.current?.feature == .brightness)
        schedule.expire(at: 3)
        #expect(schedule.current?.feature == .capsLock)
        #expect(Feature.lowBattery.defaultDuration == 5)
        #expect(Feature.brightness.defaultDuration == 2)
    }
}

struct ExternalBrightnessScaleTests {
    @Test func combinedScaleReachesBlackAndTransitionsContinuously() {
        let scale = ExternalBrightnessScale(split: 0.5, allowBlackout: true)!
        #expect(scale.hardware(1) == 1)
        #expect(scale.hardware(0.5) == 0)
        #expect(scale.software(0.5) == 1)
        #expect(scale.hardware(0.25) == 0)
        #expect(scale.software(0.25) == 0.5)
        #expect(scale.software(0) == 0)
        #expect(scale.software(0.501) == 1)
    }
    @Test func respectsTheBlackoutPreferenceAndRejectsInvalidSplits() {
        #expect(ExternalBrightnessScale(split: 0.5, allowBlackout: false)!.software(0) == 0.15)
        #expect(ExternalBrightnessScale(split: 0, allowBlackout: true)!.software(0) == 1)
        #expect(ExternalBrightnessScale(split: 1, allowBlackout: true) == nil)
        #expect(ExternalBrightnessScale(split: .nan, allowBlackout: true) == nil)
    }
}
