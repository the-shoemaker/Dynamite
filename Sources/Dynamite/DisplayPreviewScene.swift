import SwiftUI
import IslandCore
private typealias PreviewState<Value> = SwiftUI.State<Value>

/// A static vector desktop with the real activity renderer. No wallpaper reads,
/// capture permission, image decoding, or continuous animation are needed.
struct DisplayPreviewScene: View {
    let activity: Activity
    let notched: Bool
    let blackBackground: Bool
    var animate = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(white: 0.055))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.16), lineWidth: 0.7))
            ZStack(alignment: .top) {
                PreviewWallpaper().opacity(blackBackground ? 0 : 1)
                    .background(.black)
                DisplayPreviewActivity(activity: activity, notched: notched, animate: animate)
                    .id(notched)
                    .padding(.top, notched ? 0 : 10)
                    .transition(.opacity)
            }
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .padding(7)
        }
        .frame(height: 126)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: blackBackground)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: notched)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(notched ? "MacBook" : "External display") preview, \(blackBackground ? "black background" : "wallpaper")")
    }
}

private struct DisplayPreviewActivity: View {
    let activity: Activity
    let notched: Bool
    let animate: Bool
    @PreviewState<Bool> private var expanded = false
    var body: some View {
        ZStack(alignment: .top) {
            IslandSurface(activity: activity,
                          geometry: IslandGeometry(safeTop: notched ? 32 : 0, notchWidth: notched ? 150 : 0),
                          expanded: !animate || expanded)
            if notched {
                UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 9,
                                       bottomTrailingRadius: 9, topTrailingRadius: 0)
                    .fill(.black).frame(width: 150, height: 32).allowsHitTesting(false)
            }
        }
        .task {
            guard animate else { return }
            do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
            expanded = true
        }
    }
}

/// Original, resolution-independent wallpaper. Curves continue beyond the crop
/// so this reads as the top of a display, not a miniature whole computer.
private struct PreviewWallpaper: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                LinearGradient(colors: [Color(red: 0.27, green: 0.25, blue: 0.64),
                                        Color(red: 0.70, green: 0.42, blue: 0.65),
                                        Color(red: 0.97, green: 0.67, blue: 0.52)],
                               startPoint: .bottomLeading, endPoint: .topTrailing)
                Path { p in
                    p.move(to: CGPoint(x: -w * 0.1, y: -h))
                    p.addCurve(to: CGPoint(x: w * 0.73, y: h * 1.3),
                               control1: CGPoint(x: w * 0.5, y: -h * 0.3), control2: CGPoint(x: w * 0.12, y: h * 1.1))
                    p.addLine(to: CGPoint(x: -w * 0.1, y: h * 1.3)); p.closeSubpath()
                }.fill(LinearGradient(colors: [Color(red: 0.57, green: 0.31, blue: 0.75), Color(red: 0.21, green: 0.20, blue: 0.55)], startPoint: .top, endPoint: .bottom))
                Path { p in
                    p.move(to: CGPoint(x: w * 0.48, y: h * 1.2))
                    p.addCurve(to: CGPoint(x: w * 1.1, y: -h * 0.6),
                               control1: CGPoint(x: w * 0.87, y: h * 1.1), control2: CGPoint(x: w * 0.7, y: -h * 0.1))
                    p.addLine(to: CGPoint(x: w * 1.1, y: h * 1.2)); p.closeSubpath()
                }.fill(LinearGradient(colors: [Color(red: 0.98, green: 0.70, blue: 0.62), Color(red: 0.65, green: 0.33, blue: 0.62)], startPoint: .topTrailing, endPoint: .bottomLeading))
            }
        }.accessibilityHidden(true)
    }
}
