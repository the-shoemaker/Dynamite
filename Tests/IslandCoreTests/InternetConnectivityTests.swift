import Foundation
import Testing
@testable import IslandCore

struct InternetConnectivityTests {
    @Test func launchOnlineIsQuietAndPacketLossNeedsConfirmation() {
        var state = InternetConnectivity()
        #expect(state.consumeProbe(reachable: true) == nil)
        #expect(state.state == .online)
        #expect(state.nextProbeInterval == 30)
        #expect(state.consumeProbe(reachable: false) == nil)
        #expect(state.state == .online)
        #expect(state.nextProbeInterval == 2)
        #expect(state.consumeProbe(reachable: true) == nil)
        #expect(state.consumeProbe(reachable: false) == nil)
        #expect(state.consumeProbe(reachable: false) == .offline)
        #expect(state.nextProbeInterval == 5)
        #expect(state.consumeProbe(reachable: false) == nil)
        #expect(state.consumeProbe(reachable: true) == .online)
        #expect(state.nextProbeInterval == 30)
    }
    @Test func routeLossIsImmediateAndRecoveryCannotKeepAStaleOfflineState() {
        var state = InternetConnectivity()
        _ = state.consumeProbe(reachable: true)
        #expect(state.pathUnavailable() == .offline)
        #expect(state.pathUnavailable() == nil)
        #expect(state.consumeProbe(reachable: true) == .online)
        #expect(state.pathUnavailable() == .offline)
        state.reset()
        #expect(state.state == .checking)
        #expect(state.consumeProbe(reachable: true) == nil)
    }
    @Test func addressValidationAndOldPreferencesAreSafe() throws {
        #expect(InternetProbeSettings.normalizedAddress(" 009.009.009.009 ") == "9.9.9.9")
        for bad in ["", "9.9.9", "9.9.9.256", "example.com", "9.9.9.9; echo hi", "-c 100", "0.0.0.0", "224.0.0.1"] {
            #expect(InternetProbeSettings.normalizedAddress(bad) == nil)
        }
        var preferences = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        #expect(!preferences.preference(for: .internetOnline).enabled)
        #expect(!preferences.preference(for: .internetOffline).enabled)
        #expect(!preferences.keepOfflineVisible)
        preferences.internetProbeAddress = "invalid"
        preferences.normalize()
        #expect(preferences.internetProbeAddress == "9.9.9.9")
        preferences.keepOfflineVisible = true
        preferences.internetProbeAddress = "8.8.8.8"
        #expect(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(preferences)) == preferences)
    }
    @Test func wifiAndHotspotCoalesceWithRecoveryButLaterOutagesDoNot() {
        var events = ConnectionAnnouncements()
        #expect(events.shouldAnnounceOnline(at: 0))
        events.linked(at: 10)
        #expect(!events.shouldAnnounceOnline(at: 12))
        #expect(events.shouldAnnounceOnline(at: 18))
        events.reset()
        #expect(events.shouldAnnounceOnline(at: 12))
        var wireless = HotspotTransitions()
        #expect(wireless.consume(connection: .offline, now: 0) == nil)
        #expect(wireless.consume(connection: .wifi, now: 1)?.feature == .wifi)
        #expect(wireless.consume(connection: .hotspot, now: 2) == nil)
        #expect(wireless.consume(connection: .offline, now: 3) == nil)
        #expect(wireless.consume(connection: .hotspot, now: 3.5) == nil)
        #expect(wireless.consume(connection: .offline, now: 10) == nil)
        #expect(wireless.consume(connection: .hotspot, now: 11)?.feature == .hotspot)
    }
    @Test func repeatedKeysReplaceTheTemporarySlotAndRestorePersistentState() {
        var schedule = ActivitySchedule()
        schedule.setPersistents([.preview(.internetOffline), .preview(.clockTimer)])
        schedule.present(.preview(.volume), duration: 2, now: 0)
        schedule.present(.preview(.brightness), duration: 10, now: 0.5)
        #expect(schedule.temporaries.map(\.activity.feature) == [.brightness])
        schedule.present(Activity(.volume, value: 75), duration: 2, now: 1)
        #expect(schedule.temporaries.count == 1)
        #expect(schedule.current?.feature == .volume)
        #expect(schedule.expiresAt == 3)
        schedule.expire(at: 2)
        #expect(schedule.current?.feature == .volume)
        schedule.expire(at: 3)
        #expect(schedule.temporaries.isEmpty)
        #expect(schedule.current?.feature == .internetOffline)
        #expect(schedule.persistents.map(\.feature) == [.internetOffline, .clockTimer])
        schedule.remove(.internetOffline)
        #expect(schedule.current?.feature == .clockTimer)
        #expect(schedule.expiresAt == nil)
        schedule.reset()
        #expect(schedule.temporaries.isEmpty && schedule.persistents.isEmpty)
    }
    @Test func oppositeInternetStateClearsBeforeLongDurationExpires() {
        var schedule = ActivitySchedule()
        schedule.present(.preview(.internetOffline), duration: 3600, now: 0)
        schedule.remove(.internetOffline)
        schedule.present(.preview(.internetOnline), duration: 10, now: 1)
        #expect(schedule.temporaries.map(\.activity.feature) == [.internetOnline])
        schedule.remove(.internetOnline)
        schedule.setPersistents([.preview(.internetOffline)])
        #expect(schedule.temporaries.isEmpty)
        #expect(schedule.persistents.map(\.feature) == [.internetOffline])
    }
}
