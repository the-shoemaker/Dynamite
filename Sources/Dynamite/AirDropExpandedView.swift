import SwiftUI
import IslandCore

private typealias TransferViewState<Value> = SwiftUI.State<Value>

struct AirDropExpandedView: View {
    static func height(for geometry: IslandGeometry) -> Double {
        (geometry.isNotched ? geometry.height + 8 : 14) + 28 + 10 + 48 + 8
    }
    @ObservedObject var monitor: AirDropMonitor
    @ObservedObject var presentation: IslandPresentation
    let geometry: IslandGeometry
    let screenID: UInt32
    private var activityHovered: Bool { hovered || presentation.hoveredScreens.contains(screenID) }
    @TransferViewState<Bool> private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var width: Double { max(288, geometry.notchWidth + 168) }
    var body: some View {
        VStack(spacing: 0) {
            if geometry.isNotched {
                HStack {
                AirDropGlyph().frame(width: 20, height: 20).foregroundStyle(.blue)
                Spacer(minLength: geometry.notchWidth)
                Text(presentation.activity?.label ?? "AirDrop").font(.system(size: 11, weight: .semibold)).foregroundStyle(.blue)
                }.padding(.horizontal, 26).frame(height: geometry.height)
            }
            if let transfer = monitor.transfer {
                Text(transfer.title).font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    .padding(.horizontal, 48).frame(maxWidth: .infinity).frame(height: 28)
                    .overlay(alignment: .trailing) {
                        IslandCloseButton(visible: activityHovered, title: "Dismiss AirDrop") { monitor.dismiss() }
                            .padding(.trailing, geometry.isNotched ? 20 : 12)
                    }
                    .padding(.top, geometry.isNotched ? 8 : 14).padding(.bottom, 10)
                Group {
                if !transfer.urls.isEmpty {
                    HStack(spacing: 10) {
                        IslandActionButton(title: "Open", symbol: "arrow.up.forward", tint: .blue, prominent: true) { monitor.openReceived() }
                        IslandActionButton(title: "Show in Finder", symbol: "folder") { monitor.revealReceived() }
                    }

                }
                }.padding(.horizontal, geometry.isNotched ? 20 : 12)
                .modifier(ExpandedActionsEntrance(open: presentation.expanded && !presentation.closing))
            }
            Spacer(minLength: 8)
        }
        .onHover { hovered = $0 }
        .modifier(ExpandedIslandShell(presentation: presentation, geometry: geometry,
            width: width, height: Self.height(for: geometry), tint: .blue))
    }
}
