import SwiftUI
import IslandCore

/// Draw animated geometry inside fixed layout bounds. Animating the hosting
/// layout itself can briefly move the card's top away from the screen edge.
private struct ExpandedShellSurface<Contents: View>: View, Animatable {
    let geometry: IslandGeometry
    let layoutWidth: Double
    let layoutHeight: Double
    let tint: Color
    let expanded: Bool
    let closing: Bool
    var width: Double
    var height: Double
    var corner: Double
    var scale: Double
    let contents: Contents

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, Double>> {
        get { .init(.init(width, height), .init(corner, scale)) }
        set {
            width = newValue.first.first; height = newValue.first.second
            corner = newValue.second.first; scale = newValue.second.second
        }
    }

    var body: some View {
        let amount = max(0, scale)
        let w = geometry.isNotched ? max(geometry.notchWidth + 16, width) : max(0, width) * amount
        // A closing spring may undershoot; never expose the camera's lower edge.
        let h = geometry.isNotched ? max(geometry.shellHeight, height) : max(0, height) * amount
        let bounds = CGRect(x: (layoutWidth - w) / 2, y: 0, width: w, height: h)
        let radius = max(0, corner) * (geometry.isNotched ? 1 : amount)
        let _ = IslandMotionTrace.record(h)
        // One interpolation owns both paths. Fades below affect only opacity,
        // never the geometry spring, and neither path starts its own animation.
        ZStack(alignment: .top) {
            IslandShape(notched: geometry.isNotched, expandedCornerRadius: radius).path(in: bounds)
                .fill(.black)
                .animation(.easeOut(duration: 0.14).delay(expanded ? 0 : 0.12)) { fill in
                    fill.opacity(!geometry.isNotched || expanded || !closing ? 1 : 0)
                }
                .allowsHitTesting(false)
            contents
                .clipShape(IslandShape(notched: geometry.isNotched, expandedCornerRadius: radius).path(in: bounds))
            IslandOutline(notched: geometry.isNotched, expandedCornerRadius: radius).path(in: bounds)
                .stroke(tint.opacity(0.22), lineWidth: 0.75)
                .modifier(ExpandedOutlineMask(notched: geometry.isNotched,
                    fadeHeight: geometry.shellHeight * 0.40, width: layoutWidth, height: layoutHeight))
                .animation(expanded ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.16).delay(0.10)) { rim in
                    rim.opacity(expanded ? 1 : 0)
                }
                .allowsHitTesting(false)
        }
        .frame(width: layoutWidth, height: layoutHeight, alignment: .top)
    }
}

/// The attachment fade belongs to the screen edge, not to the card's height.
/// Extra mask space preserves the rim during the geometry spring's overshoot.
private struct ExpandedOutlineMask: ViewModifier {
    let notched: Bool
    let fadeHeight: Double
    let width: Double
    let height: Double

    @ViewBuilder func body(content: Content) -> some View {
        if notched {
            content.mask(alignment: .top) {
                VStack(spacing: 0) {
                    LinearGradient(stops: [.init(color: .clear, location: 0),
                                           .init(color: .clear, location: 0.30),
                                           .init(color: .white, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: fadeHeight)
                    Color.white
                }
                .frame(width: width + 128, height: height + 128)
            }
        } else {
            content
        }
    }
}

/// Flatten the card first, then pull both wings into the camera together.
struct ExpandedIslandShell: ViewModifier {
    @ObservedObject var presentation: IslandPresentation
    let geometry: IslandGeometry
    let width: Double
    let height: Double
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var open: Bool { presentation.expanded && !presentation.closing }
    private var shellWidth: Double {
        if reduceMotion { return width }
        if let destination = presentation.compactDestination {
            if geometry.isNotched { return geometry.expandedWidth(for: destination) }
            let sides = IslandLayout.widths(.preview(destination), geometry: geometry)
            return sides.left + sides.right
        }
        if geometry.isNotched && !presentation.expanded {
            return presentation.opensFromCompact && !presentation.closing ? width : geometry.notchWidth + 16
        }
        return presentation.closing && presentation.expanded ? width * 1.015 : width
    }
    private var shellHeight: Double { open || reduceMotion ? height : geometry.shellHeight }
    private var scale: Double {
        geometry.isNotched || reduceMotion || presentation.expanded || presentation.compactDestination != nil ? 1 : 0
    }
    private var motion: Animation? {
        guard !reduceMotion else { return nil }
        return presentation.expanded ? .spring(response: 0.46, dampingFraction: 0.60) :
            .timingCurve(0.22, 0.82, 0.24, 1, duration: 0.40)
    }
    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            ExpandedShellSurface(geometry: geometry, layoutWidth: width, layoutHeight: height,
                tint: tint, expanded: presentation.expanded, closing: presentation.closing,
                width: shellWidth, height: shellHeight,
                corner: open ? 36 : (geometry.isNotched ? 18 : geometry.height / 2), scale: scale,
                contents: content
                    .frame(width: width, height: height, alignment: .top)
                    .animation(.easeOut(duration: open ? 0.16 : 0.10).delay(open ? 0.035 : 0)) { contents in
                        contents.opacity(open ? 1 : 0)
                    })
            if let returning = presentation.compactReturn {
                IslandSurface(activity: returning, geometry: geometry, expanded: true,
                    replaysContentEntrance: true, drawsShell: false)
                    .allowsHitTesting(false)
            }

        }
        .frame(width: width, height: height, alignment: .top)
        .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.82), value: presentation.closing)
        .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.82), value: presentation.compactDestination)
        .animation(motion, value: presentation.expanded)
        .animation(.easeOut(duration: 0.22)) { shell in
            shell.opacity(presentation.expanded || (geometry.isNotched && !reduceMotion) || presentation.compactDestination != nil ? 1 : 0)
        }
        .allowsHitTesting(open)
        .padding(.top, geometry.isNotched ? 0 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Both actions enter together from the center, without moving the header.
/// The shell clips them using its current interpolated path throughout entry.
struct ExpandedActionsEntrance: ViewModifier {
    let open: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .animation(reduceMotion ? nil : open ?
                .spring(response: 0.46, dampingFraction: 0.64).delay(0.035) : .easeOut(duration: 0.10)) { row in
                row.modifier(ExpandedActionsTransform(amount: open || reduceMotion ? 1 : 0))
            }
            .animation(.easeOut(duration: open ? 0.18 : 0.10).delay(open && !reduceMotion ? 0.055 : 0)) { row in
                row.opacity(open ? 1 : 0)
            }
    }
}

private struct ExpandedActionsTransform: GeometryEffect {
    var amount: Double
    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        IslandMotionTrace.recordActions(amount)
        let scale = 0.84 + 0.16 * amount
        return ProjectionTransform(CGAffineTransform(translationX: size.width * (1 - scale) / 2,
                                                     y: -10 * (1 - amount))
            .scaledBy(x: scale, y: scale))
    }
}
