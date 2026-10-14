import Foundation
import Testing
@testable import IslandCore

struct PreferencesUpgradeTests {
    @Test func unknownFeatureCannotResetExistingDurations() throws {
        let data = Data("""
        {"features":["powerDisconnected",{"enabled":true,"duration":4},"futureActivity",{"enabled":false,"duration":15},"volume",{"enabled":false,"duration":7}],"placement":"all","showMenuBarIcon":false}
        """.utf8)
        var saved = try JSONDecoder().decode(Preferences.self, from: data)
        saved.normalize()
        #expect(saved.preference(for: .powerDisconnected).duration == 4)
        #expect(saved.preference(for: .volume).duration == 7)
        #expect(!saved.preference(for: .volume).enabled)
        #expect(saved.placement == .all)
        #expect(!saved.showMenuBarIcon)
    }
    @Test func staleSnapshotsMergeOnlyUserEditsIncludingWithinAFeature() {
        var baseline = Preferences()
        baseline.normalize()
        var current = baseline
        current.features[.volume]?.enabled = false
        var saved = baseline
        saved.features[.powerDisconnected]?.duration = 4
        saved.features[.volume]?.duration = 10
        saved.internetProbeAddress = "8.8.8.8"
        let merged = Preferences.mergingChanges(from: baseline, current: current, saved: saved)
        #expect(merged.preference(for: .powerDisconnected).duration == 4)
        #expect(merged.preference(for: .volume).duration == 10)
        #expect(!merged.preference(for: .volume).enabled)
        #expect(merged.internetProbeAddress == "8.8.8.8")
    }
}
