import Foundation

/// Compact statuses share one primary slot. A brief alert replaces its contents
/// until expiry; only additional persistent activities get lower pills.
public enum ActivityRouting {
    public enum Source: Equatable { case persistent, temporary }
    public enum Position: Hashable { case primary, secondary(Feature) }
    public struct Slot: Hashable {
        public let screen: UInt32
        public let position: Position
        public init(screen: UInt32, position: Position) { self.screen = screen; self.position = position }
    }
    public struct Request {
        public let feature: Feature
        public let screens: [UInt32]
        public let source: Source
        public let expanded: Bool
        public init(_ feature: Feature, screens: [UInt32], source: Source = .persistent, expanded: Bool = false) {
            self.feature = feature; self.screens = screens; self.source = source; self.expanded = expanded
        }
    }
    public struct Row: Equatable {
        public let slot: Slot
        public let feature: Feature
        public let source: Source
        public let index: Int
    }
    public static func stacks(_ requests: [Request]) -> [Row] {
        let temporary = requests.last { $0.source == .temporary }
        var screenOrder: [UInt32] = []
        for screen in requests.flatMap(\.screens) where !screenOrder.contains(screen) { screenOrder.append(screen) }
        var result: [Row] = []
        for screen in screenOrder {
            var seen = Set<Feature>()
            var visible = requests.filter {
                $0.source == .persistent && $0.screens.contains(screen) && seen.insert($0.feature).inserted
            }
            if let temporary, temporary.screens.contains(screen),
               !visible.contains(where: { $0.feature == temporary.feature && $0.expanded }) {
                if visible.first?.expanded == true {
                    // Preserve actionable finish/receipt cards, as before.
                    visible.removeAll { $0.feature == temporary.feature }
                    visible.append(temporary)
                } else {
                    if !visible.isEmpty { visible.removeFirst() }
                    visible.removeAll { $0.feature == temporary.feature }
                    visible.insert(temporary, at: 0)
                }
            }
            for (index, request) in visible.enumerated() {
                let position: Position = index == 0 ? .primary : .secondary(request.feature)
                result.append(Row(slot: .init(screen: screen, position: position),
                                  feature: request.feature, source: request.source, index: index))
            }
        }
        return result
    }
}
