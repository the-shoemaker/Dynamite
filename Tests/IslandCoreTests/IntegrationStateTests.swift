import Foundation
import Testing
@testable import IslandCore

struct IntegrationStateTests {
    @Test func clockReadsOriginalDurationInsteadOfRemainingTime() {
        #expect(ClockReading.durationLabel("23 sec") == 23)
        #expect(ClockReading.durationLabel("2 min 5 sec") == 125)
        #expect(ClockReading.durationLabel("1 hour, 2 minutes, 3 seconds") == 3723)
        for label in ["00:03", "Tea for 5 min", "5 min left", "-2 sec", "0 sec", "99999999999999999 hours"] {
            #expect(ClockReading.durationLabel(label) == nil)
        }
    }
    @Test func clockOnlyAcceptsCompleteTimes() {
        #expect(ClockReading.seconds("01:59") == 119)
        #expect(ClockReading.seconds("1:02:03") == 3723)
        for value in ["Timer", "01:59, 2 min", "-1:20", "1:60", "1::03", "1:2:3:4"] {
            #expect(ClockReading.seconds(value) == nil)
        }
        #expect(ClockReading.formatted(119) == "1:59")
    }
    @Test func focusIncompleteDataDoesNotInventOff() throws {
        #expect(throws: (any Error).self) { try FocusReading.decode(Data("{}".utf8)) }
        #expect(try FocusReading.decode(Data("{\"data\":[]}".utf8)) == .off)
        let active = #"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.focus.work"}}]}]}"#
        #expect(try FocusReading.decode(Data(active.utf8)) == .active("com.apple.focus.work"))
    }
    @Test func timerKeepsSecondsOutsidePercentageRange() {
        let timer = Activity(.clockTimer, value: 0, remainingSeconds: 3723)
        #expect(timer.remainingSeconds == 3723)
        #expect(Preferences().preference(for: .airPods).enabled)
        #expect(!Preferences().preference(for: .focus).enabled)
    }
}
