import Testing
@testable import IslandCore

struct ClockContinuityTests {
    @Test func closingWindowKeepsCountdownBeyondFiveSeconds() {
        var state = ClockContinuity()
        _ = state.resolve(ClockReading(identifier: "a", remaining: 120, paused: false), idle: false, now: 100)
        #expect(state.resolve(nil, idle: false, now: 130)?.remaining == 90)
        #expect(state.resolve(nil, idle: false, now: 150)?.remaining == 70)
    }
    @Test func confirmedCancellationClearsFallback() {
        var state = ClockContinuity()
        _ = state.resolve(ClockReading(identifier: "a", remaining: 120, paused: false), idle: false, now: 100)
        #expect(state.resolve(nil, idle: true, now: 101) == nil)
        #expect(state.resolve(nil, idle: false, now: 102) == nil)
    }
    @Test func pausedTimerDoesNotCountDownWhileWindowIsClosed() {
        var state = ClockContinuity()
        _ = state.resolve(ClockReading(identifier: "a", remaining: 50, paused: true), idle: false, now: 100)
        #expect(state.resolve(nil, idle: false, now: 300)?.remaining == 50)
        _ = state.resolve(ClockReading(identifier: "a", remaining: 50, paused: false), idle: false, now: 301)
        #expect(state.resolve(nil, idle: false, now: 311)?.remaining == 40)
    }
    @Test func elapsedTimerDoesNotRemainForever() {
        var state = ClockContinuity()
        _ = state.resolve(ClockReading(identifier: "a", remaining: 10, paused: false), idle: false, now: 100)
        #expect(state.resolve(nil, idle: false, now: 110)?.remaining == 0)
        #expect(state.resolve(nil, idle: false, now: 113) == nil)
    }
    @Test func reopenedClockReconcilesActualState() {
        var state = ClockContinuity()
        _ = state.resolve(ClockReading(identifier: "a", remaining: 120, paused: false), idle: false, now: 100)
        let resumed = ClockReading(identifier: "b", remaining: 45, paused: true)
        #expect(state.resolve(resumed, idle: false, now: 150) == resumed)
        #expect(state.resolve(nil, idle: false, now: 160) == resumed)
    }
}
