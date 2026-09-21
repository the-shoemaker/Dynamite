import Testing
import Foundation
@testable import IslandCore

struct ActivityDurationTests {
    @Test func scaleRoundTripsAndStartsAtHalfSecond() {
        #expect(ActivityDuration.steps.first == 0.5)
        #expect(ActivityDuration.steps.last == 3600)
        for (index, seconds) in ActivityDuration.steps.enumerated() {
            #expect(ActivityDuration.seconds(at: Double(index)) == seconds)
            #expect(ActivityDuration.index(for: seconds) == Double(index))
        }
        #expect(ActivityDuration.seconds(at: -.infinity) == 2)
        #expect(ActivityDuration.seconds(at: -1) == 0.5)
        #expect(ActivityDuration.seconds(at: 999) == 3600)
    }
    @Test func readableUnitsAndSafeBounds() {
        #expect(ActivityDuration.label(0.5) == "0.5 seconds")
        #expect(ActivityDuration.label(1) == "1 second")
        #expect(ActivityDuration.label(50) == "50 seconds")
        #expect(ActivityDuration.label(120) == "2 minutes")
        #expect(ActivityDuration.label(3600, compact: true) == "1 h")
        #expect(ActivityDuration.validated(.nan) == 2)
        #expect(ActivityDuration.validated(-3) == 0.5)
        #expect(ActivityDuration.validated(9999) == 3600)
    }
    @Test func existingAndLongDurationsSurviveSaving() throws {
        var original = Preferences()
        original.features[.lowBattery] = FeaturePreference(duration: 3600)
        original.features[.volume] = FeaturePreference(duration: 6)
        original.features[.charging] = FeaturePreference(duration: 0.5)
        var decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(original))
        decoded.normalize()
        #expect(decoded.preference(for: .lowBattery).duration == 3600)
        #expect(decoded.preference(for: .volume).duration == 6)
        #expect(decoded.preference(for: .charging).duration == 0.5)
        var schedule = ActivitySchedule()
        schedule.present(.preview(.lowBattery), duration: 3600, now: 0)
        schedule.present(.preview(.lowBattery), duration: 0.5, now: 10)
        #expect(schedule.expiresAt == 10.5)
    }
}
