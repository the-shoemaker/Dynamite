import Foundation
import Testing
@testable import IslandCore

struct ClockTimerRecordTests {
    let id = "8A196148-DE4A-4B0A-BB5F-46740FA8177C"
    func encoded(state: Int, fire: [String: Any], duration: Double = 120) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["MTTimers": ["MTTimers": [["$MTTimer": [
            "MTTimerID": id, "MTTimerState": state, "MTTimerDuration": duration, "MTTimerFireTime": fire
        ]]]]], format: .binary, options: 0)
    }
    @Test func runningUsesRealDeadlineWithoutClockWindow() throws {
        let date = Date(timeIntervalSinceReferenceDate: 1000)
        let records = try ClockTimerRecord.decode(encoded(state: 3, fire: ["$MTTimerDate": ["MTTimerTimeDate": date]]))
        let timer = try #require(records.first)
        #expect(timer.duration == 120)
        #expect(timer.reading(at: date.addingTimeInterval(-54.5)).remaining == 55)
        #expect(timer.reading(at: date.addingTimeInterval(-30)).remaining == 30)
        #expect(timer.reading(at: date.addingTimeInterval(2)).remaining == 0)
        #expect(!timer.reading(at: date).paused)
    }
    @Test func pausedKeepsExactRemainingDuration() throws {
        let records = try ClockTimerRecord.decode(encoded(state: 2, fire: ["$MTTimerTimeInterval": ["MTTimerTimeInterval": 54.504978]]))
        let timer = try #require(records.first)
        #expect(timer.reading(at: Date()).paused)
        #expect(timer.reading(at: Date()).remaining == 55)
        #expect(timer.reading(at: Date().addingTimeInterval(500)).remaining == 55)
    }
    @Test func stoppedAndFinishedRecordsDoNotProduceRunningActivities() throws {
        for state in [1, 4] { #expect(try ClockTimerRecord.decode(encoded(state: state, fire: [:])).isEmpty) }
    }
    @Test func unsupportedOrIncompleteActiveRecordsFallBackInsteadOfInventingIdle() throws {
        for (state, fire) in [(3, [String: Any]()), (2, [:]), (99, [:])] {
            let data = try encoded(state: state, fire: fire)
            #expect(throws: (any Error).self) { try ClockTimerRecord.decode(data) }
        }
        #expect(throws: (any Error).self) { try ClockTimerRecord.decode(Data()) }
    }
}
