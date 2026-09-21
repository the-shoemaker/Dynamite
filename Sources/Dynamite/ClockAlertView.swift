import SwiftUI
import IslandCore

private typealias ClockAlertState<Value> = SwiftUI.State<Value>

struct ClockAlertView: View {
    static let extraHeight: CGFloat = 64
    @ClockAlertState<Bool> private var hovered = false
    @ObservedObject var monitor: NativeActivityNotifications
    @ObservedObject var clock: ClockMonitor
    @ObservedObject var presentation: IslandPresentation
    let geometry: IslandGeometry
    let screenID: UInt32
    private var activityHovered: Bool { hovered || presentation.hoveredScreens.contains(screenID) }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "timer").font(.system(size: 16, weight: .semibold))
                Spacer(minLength: geometry.notchWidth)
                ZStack(alignment: .trailing) {
                    Text((monitor.clockOriginalDuration ?? clock.finishedDuration).map(ClockReading.formatted) ?? "Timer")
                        .font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText())
                        .opacity(activityHovered ? 0 : 1)
                    IslandCloseButton(visible: activityHovered, title: "Stop timer") { monitor.stopClockAlert() }
                }.animation(.easeInOut(duration: 0.15), value: activityHovered)
            }.foregroundStyle(IslandStyle.orange).padding(.horizontal, 26).frame(height: geometry.height)
            HStack(spacing: 10) {
                ForEach(monitor.clockActions.sorted { $0.title == "Repeat" && $1.title != "Repeat" }) { action in
                    Button {
                        monitor.perform(action)
                        if action.title == "Repeat" { clock.reconnectAfterRepeat() }
                    } label: {
                        Group {
                            if action.title == "Stop" {
                                Text("Stop").font(.system(size: 16, weight: .semibold))
                            } else {
                                Image(systemName: "arrow.clockwise").font(.system(size: 21, weight: .medium))
                            }
                        }
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .foregroundStyle(action.title == "Stop" ? Color.black : IslandStyle.orange)
                        .background(action.title == "Stop" ? IslandStyle.orange : Color.white.opacity(0.14), in: Capsule())
                        .contentShape(Capsule())
                    }.buttonStyle(.plain).accessibilityLabel(action.title)
                }
            }.padding(.horizontal, geometry.isNotched ? 20 : 12)
                .modifier(ExpandedActionsEntrance(open: presentation.expanded && !presentation.closing))
        }
        .onHover { hovered = $0 }
        .modifier(ExpandedIslandShell(presentation: presentation, geometry: geometry,
            width: max(288, geometry.notchWidth + 168), height: geometry.shellHeight + Self.extraHeight,
            tint: IslandStyle.orange))
    }
}
