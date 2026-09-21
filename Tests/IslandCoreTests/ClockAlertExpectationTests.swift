import Testing
@testable import IslandCore

struct ClockAlertExpectationTests {
    @Test func repeatRearmsTheSameTimerAfterItsFirstFinish() {
        var state = ClockAlertExpectation()
        state.expect(identifier: "timer", now: 10)
        #expect(state.isUrgent(at: 11))
        #expect(!state.isUrgent(at: 15))
        state.expect(identifier: "timer", now: 20)
        #expect(state.isUrgent(at: 21))
        #expect(state.expiresAt == 23)
    }

    @Test func duplicateUpdatesKeepPriorityWindowBounded() {
        var state = ClockAlertExpectation()
        state.expect(identifier: "timer", now: 10)
        state.expect(identifier: "timer", now: 11)
        #expect(state.expiresAt == 13)
        #expect(!state.isUrgent(at: 13))
    }

    @Test func anotherTimerGetsItsOwnFinishWindow() {
        var state = ClockAlertExpectation()
        state.expect(identifier: "first", now: 10)
        state.expect(identifier: "second", now: 12)
        #expect(state.expiresAt == 15)
    }
}
