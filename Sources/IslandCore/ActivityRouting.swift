import Foundation

/// Each screen has a primary island and, only below an expanded card, a pill.
public enum ActivityRouting {
    public enum Source: Equatable { case persistent, temporary }
    public struct Slot: Hashable {
        public let screen: UInt32
        public let belowCard: Bool
        public init(screen: UInt32, belowCard: Bool = false) {
            self.screen = screen; self.belowCard = belowCard
        }
    }
    public static func slots(persistentScreen: UInt32?, expanded: Bool,
                             temporaryScreens: [UInt32]) -> [Slot: Source] {
        var result: [Slot: Source] = [:]
        if let screen = persistentScreen { result[Slot(screen: screen)] = .persistent }
        for screen in temporaryScreens {
            result[Slot(screen: screen, belowCard: expanded && screen == persistentScreen)] = .temporary
        }
        return result
    }
}
