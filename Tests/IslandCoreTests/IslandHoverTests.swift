import Foundation
import Testing
@testable import IslandCore

struct IslandHoverTests {
    @Test func notchHoverIncludesCameraAndExactTopEdge() {
        let screen = CGRect(x: -1512, y: 900, width: 1512, height: 982)
        let geometry = IslandGeometry(safeTop: 32, notchWidth: 180)
        for x in [screen.midX - 100, screen.midX, screen.midX + 100] {
            #expect(geometry.containsHover(CGPoint(x: x, y: screen.maxY), screen: screen, width: 348, height: 33))
        }
        #expect(!geometry.containsHover(CGPoint(x: screen.midX, y: screen.maxY + 1), screen: screen, width: 348, height: 33))
        #expect(!geometry.containsHover(CGPoint(x: screen.midX + 175, y: screen.maxY), screen: screen, width: 348, height: 33))
    }
    @Test func floatingCardIncludesTopGapButNotTransparentPanelMargin() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let geometry = IslandGeometry(safeTop: 0, notchWidth: 0)
        #expect(geometry.containsHover(CGPoint(x: 960, y: 1080), screen: screen, width: 288, height: 104))
        #expect(geometry.containsHover(CGPoint(x: 960, y: 971), screen: screen, width: 288, height: 104))
        #expect(!geometry.containsHover(CGPoint(x: 960, y: 969), screen: screen, width: 288, height: 104))
        #expect(!geometry.containsHover(CGPoint(x: 1200, y: 1080), screen: screen, width: 288, height: 104))
    }
}
