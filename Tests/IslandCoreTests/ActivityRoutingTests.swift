import Foundation
import Testing
@testable import IslandCore

struct ActivityRoutingTests {
    @Test func briefActionsReplaceTheTopStatusOnTheirTargetDisplays() {
        let rows = ActivityRouting.stacks([
            .init(.internetOffline, screens: [1]), .init(.clockTimer, screens: [1]),
            .init(.brightness, screens: [1, 2], source: .temporary)
        ])
        #expect(rows.filter { $0.slot.screen == 1 }.map(\.feature) == [.brightness, .clockTimer])
        #expect(rows.filter { $0.slot.screen == 1 }.map(\.index) == [0, 1])
        #expect(rows.filter { $0.slot.screen == 2 }.map(\.feature) == [.brightness])
        #expect(rows[0].source == .temporary)
        #expect(rows[1].source == .persistent)
    }
    @Test func replacementsAndRestorationShareThePrimarySlot() {
        let status = ActivityRouting.Request(.internetOffline, screens: [1])
        let timer = ActivityRouting.Request(.clockTimer, screens: [1])
        let original = ActivityRouting.stacks([status, timer])
        let volume = ActivityRouting.stacks([status, timer, .init(.volume, screens: [1], source: .temporary)])
        let brightness = ActivityRouting.stacks([status, timer, .init(.brightness, screens: [1], source: .temporary)])
        #expect(original[0].slot == volume[0].slot)
        #expect(volume[0].slot == brightness[0].slot)
        #expect(original[1] == volume[1] && volume[1] == brightness[1])
        #expect(ActivityRouting.stacks([timer])[0].slot.position == .primary)
    }
    @Test func aTimerAloneYieldsAndUntargetedDisplaysStayUnchanged() {
        let rows = ActivityRouting.stacks([
            .init(.clockTimer, screens: [1]),
            .init(.volume, screens: [2], source: .temporary)
        ])
        #expect(rows.map(\.feature) == [.clockTimer, .volume])
        #expect(rows.allSatisfy { $0.index == 0 })
        let sameDisplay = ActivityRouting.stacks([
            .init(.clockTimer, screens: [1]), .init(.volume, screens: [1], source: .temporary)
        ])
        #expect(sameDisplay.map(\.feature) == [.volume])
    }
    @Test func expandedActionableCardsRetainTheirExistingBelowCardAlert() {
        let rows = ActivityRouting.stacks([
            .init(.clockTimer, screens: [1], expanded: true),
            .init(.volume, screens: [1], source: .temporary)
        ])
        #expect(rows.map(\.feature) == [.clockTimer, .volume])
        #expect(rows.map(\.index) == [0, 1])
    }
    @Test func sameFeaturePreviewCannotReplaceAnActionableCard() {
        for feature in [Feature.clockTimer, .airDrop] {
            let card = ActivityRouting.Request(feature, screens: [1], expanded: true)
            let preview = ActivityRouting.Request(feature, screens: [1, 2], source: .temporary)
            let top = ActivityRouting.stacks([card, preview])
            #expect(top.first?.source == .persistent)
            #expect(top.first?.feature == feature)
            #expect(top.last?.slot.screen == 2 && top.last?.source == .temporary)
            let lower = ActivityRouting.stacks([.init(.internetOffline, screens: [1]), card, preview])
            #expect(lower.filter { $0.slot.screen == 1 }.map(\.feature) == [.internetOffline, feature])
            #expect(lower.filter { $0.slot.screen == 1 }.allSatisfy { $0.source == .persistent })
        }
    }
    @Test func repeatedFeaturesCannotDuplicatePanels() {
        let rows = ActivityRouting.stacks([.init(.capsLock, screens: [1]), .init(.capsLock, screens: [1, 2])])
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.index == 0 })
    }
    @Test func stackedPillClearsCameraAndOtherHoverRegions() {
        let geometry = IslandGeometry(safeTop: 38, notchWidth: 220, floatingTopGap: 130)
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        #expect(!geometry.isNotched)
        #expect(geometry.topGap == 130)
        #expect(geometry.height == 38)
        #expect(!geometry.containsHover(.init(x: 960, y: 1080), screen: screen, width: 200, height: 38))
        #expect(geometry.containsHover(.init(x: 960, y: 940), screen: screen, width: 200, height: 38))
    }
}
