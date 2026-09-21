import Testing
@testable import IslandCore

struct TimerFinishHandoffTests {
    @Test func repeatedUpdatesDoNotPostponeHandoff() {
        var state = TimerFinishHandoff()
        state.update(identifier: "a", remaining: 1, running: true, now: 10)
        state.update(identifier: "a", remaining: 1, running: true, now: 10.25)
        #expect(state.deadline == 10.45)
        #expect(!state.isImminent(at: 10.4))
        #expect(state.isImminent(at: 10.5))
    }
    @Test func pauseCancelAndRestartDiscardOldDeadline() {
        var state = TimerFinishHandoff()
        state.update(identifier: "a", remaining: 1, running: true, now: 10)
        state.update(identifier: "a", remaining: 1, running: false, now: 10.1)
        #expect(state.deadline == nil)
        state.update(identifier: "a", remaining: 1, running: true, now: 11)
        #expect(state.deadline == 11.45)
        state.update(identifier: "b", remaining: 20, running: true, now: 12)
        #expect(state.deadline == nil)
        state.update(identifier: nil, remaining: nil, running: false, now: 13)
        #expect(!state.isImminent(at: 14))
    }
    @Test func missingFinalSecondReturnsImmediately() {
        var state = TimerFinishHandoff()
        state.update(identifier: "a", remaining: 0, running: true, now: 10)
        #expect(state.isImminent(at: 10))
    }
}
