import Testing
@testable import IslandCore

struct ActivityRoutingTests {
    @Test func compactOnlyYieldsOnItsOwnScreen() {
        let result = ActivityRouting.slots(persistentScreen: 1, expanded: false, temporaryScreens: [2])
        #expect(result[.init(screen: 1)] == .persistent)
        #expect(result[.init(screen: 2)] == .temporary)
        let same = ActivityRouting.slots(persistentScreen: 1, expanded: false, temporaryScreens: [1])
        #expect(same.count == 1)
        #expect(same[.init(screen: 1)] == .temporary)
    }
    @Test func expandedCardCannotBeInterrupted() {
        let result = ActivityRouting.slots(persistentScreen: 1, expanded: true, temporaryScreens: [1, 2])
        #expect(result[.init(screen: 1)] == .persistent)
        #expect(result[.init(screen: 1, belowCard: true)] == .temporary)
        #expect(result[.init(screen: 2)] == .temporary)
    }
    @Test func closingCardPromotesTemporaryAndExpiryRestoresPersistent() {
        #expect(ActivityRouting.slots(persistentScreen: nil, expanded: false, temporaryScreens: [1]) == [.init(screen: 1): .temporary])
        #expect(ActivityRouting.slots(persistentScreen: 1, expanded: false, temporaryScreens: []) == [.init(screen: 1): .persistent])
        #expect(ActivityRouting.slots(persistentScreen: nil, expanded: false, temporaryScreens: []).isEmpty)
    }
    @Test func stackedPillClearsCameraAndCard() {
        let geometry = IslandGeometry(safeTop: 38, notchWidth: 220, floatingTopGap: 130)
        #expect(!geometry.isNotched)
        #expect(geometry.topGap == 130)
        #expect(geometry.height == 38)
    }
}
