import Testing
@testable import IslandCore

struct TimerVisibilityTests {
    @Test func pauseExpiresWithoutExtendingOnRead() {
        var state = TimerVisibility()
        state.update(identifier: "a", running: true, hovered: false, duration: 2, now: 0)
        state.update(identifier: "a", running: false, hovered: false, duration: 2, now: 10)
        state.update(identifier: "a", running: false, hovered: false, duration: 2, now: 11)
        #expect(state.deadline == 12)
        #expect(state.isVisible(at: 11.9))
        #expect(!state.isVisible(at: 12))
    }
    @Test func hoverHoldsAndLeavingRestartsGrace() {
        var state = TimerVisibility()
        state.update(identifier: "a", running: true, hovered: true, duration: 2, now: 0)
        state.update(identifier: "a", running: false, hovered: true, duration: 2, now: 1)
        #expect(state.deadline == nil)
        #expect(state.isVisible(at: 100))
        state.update(identifier: "a", running: false, hovered: false, duration: 2, now: 100)
        #expect(state.deadline == 102)
        state.update(identifier: "a", running: false, hovered: true, duration: 2, now: 101)
        #expect(state.deadline == nil)
        state.update(identifier: "a", running: false, hovered: false, duration: 2, now: 105)
        #expect(state.deadline == 107)
    }
    @Test func initialPausedIsQuietAndResumeCancelsExpiry() {
        var state = TimerVisibility()
        state.update(identifier: "a", running: false, hovered: false, duration: 2, now: 0)
        #expect(!state.isVisible(at: 0))
        state.update(identifier: "a", running: true, hovered: false, duration: 2, now: 1)
        state.update(identifier: "a", running: false, hovered: false, duration: 2, now: 2)
        state.update(identifier: "a", running: true, hovered: false, duration: 2, now: 3)
        #expect(state.deadline == nil)
        #expect(state.isVisible(at: 100))
        state.update(identifier: nil, running: false, hovered: false, duration: 2, now: 101)
        #expect(!state.isVisible(at: 101))
    }
    @Test func shorteningDurationRestartsVisiblePausedTimerOnly() {
        var state = TimerVisibility()
        state.update(identifier: "a", running: true, hovered: false, duration: 15, now: 0)
        state.update(identifier: "a", running: false, hovered: false, duration: 15, now: 1)
        state.update(identifier: "a", running: false, hovered: false, duration: 2, now: 3)
        #expect(state.deadline == 5)
        state.update(identifier: "a", running: false, hovered: false, duration: 10, now: 10)
        #expect(!state.isVisible(at: 10))
    }
}
