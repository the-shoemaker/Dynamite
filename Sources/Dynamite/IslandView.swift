import SwiftUI
import IslandCore

extension Feature {
    var tint: Color {
        switch self {
        case .volume, .brightness, .powerDisconnected: return .white
        case .microphoneMute: return Color(red: 1, green: 0.34, blue: 0.35)
        case .charging, .chargeTarget, .airPods: return Color(red: 0.29, green: 0.91, blue: 0.48)
        case .lowPowerMode, .clockTimer: return IslandStyle.orange
        case .focus: return .purple
        case .lowBattery: return Color(red: 1, green: 0.28, blue: 0.29)
        case .capsLock: return Color(red: 0.25, green: 0.62, blue: 1)
        case .hotspot, .wifi, .bluetooth, .airDrop: return Color(red: 0.22, green: 0.72, blue: 1)
        }
    }
}

extension Activity {
    var tint: Color {
        if feature == .microphoneMute && isActive { return Color(red: 0.29, green: 0.91, blue: 0.48) }
        if feature == .lowPowerMode && !isActive { return .white }
        if feature == .focus && !isActive { return feature.tint.opacity(0.5) }
        return feature.tint
    }
}

enum IslandStyle {
    static let motion = Animation.spring(response: 0.48, dampingFraction: 0.50)
    static let dismissal = Animation.spring(response: 0.40, dampingFraction: 0.56)
    static let notchDismissal = Animation.timingCurve(0.22, 0.82, 0.24, 1, duration: 0.44)
    static let orange = Color(red: 1, green: 0.62, blue: 0.04)
}

final class IslandPresentation: ObservableObject {
    @Published var activity: Activity?
    @Published var expanded = false
    @Published var replaysContentEntrance = false
    @Published var closing = false
    @Published var opensFromCompact = false
    @Published var compactDestination: Feature?
    @Published var compactReturn: Activity?
    @Published var hoveredScreens: Set<UInt32> = []
}

private typealias SurfaceViewState<Value> = SwiftUI.State<Value>

struct IslandSurface: View {
    @SurfaceViewState<Bool> private var clockControlHovered = false
    let activity: Activity
    let geometry: IslandGeometry
    var expanded = true
    var replaysContentEntrance = false
    var drawsShell = true
    @SurfaceViewState<Bool> private var returnContentReady = false
    private var contentVisible: Bool { expanded && (!replaysContentEntrance || returnContentReady) }
    var closing = false
    var onClockToggle: (() -> Void)?
    var onClockOpen: (() -> Void)?
    var screenHovered: Bool? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var sides: (left: Double, right: Double) { IslandLayout.widths(activity, geometry: geometry) }
    private var width: Double { geometry.notchWidth + sides.left + sides.right }
    private var contentKey: String { "\(activity.feature.rawValue)-\(activity.isActive)" }
    private func replacement(from offset: CGFloat) -> AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.78)).combined(with: .offset(x: offset, y: 2))
    }
    private var expansion: Double { reduceMotion ? 1 : expanded ? (closing && !geometry.isNotched ? 1.035 : 1) : 0 }
    private var shellAnimation: Animation? {
        reduceMotion ? nil : expanded ? IslandStyle.motion : geometry.isNotched ? IslandStyle.notchDismissal : IslandStyle.dismissal
    }
    var body: some View {
        ZStack {
            if drawsShell {
            IslandMorph(geometry: geometry, activity: activity, amount: expansion)
                .fill(.black)
                .animation(shellAnimation, value: expanded)
                .animation(reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.6), value: closing)
                .animation(reduceMotion ? nil : IslandStyle.motion, value: activity.feature)
                .animation(reduceMotion ? .easeOut(duration: 0.15) : IslandStyle.motion, value: activity.isActive)
                // On wallpaper the black lip is visible after the rim has faded.
                // Dissolve the fill during the same middle phase, while the
                // wings are still outside the camera; never shrink its height.
                .opacity(expanded ? 1 : 0)
                .animation(geometry.isNotched ?
                    .easeOut(duration: expanded ? 0.10 : 0.14).delay(expanded ? 0 : 0.12) :
                    .easeOut(duration: expanded ? 0.10 : 0.22), value: expanded)
            IslandMorph(geometry: geometry, activity: activity, amount: expansion, outline: true)
                .stroke(activity.tint.opacity(0.20), style: StrokeStyle(lineWidth: 0.75, lineCap: .round, lineJoin: .round))
                .shadow(color: activity.tint.opacity(0.08), radius: 0.8)
                .modifier(NotchOutlineMask(notched: geometry.isNotched))
                .animation(shellAnimation, value: expanded)
                .animation(reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.6), value: closing)
                .animation(reduceMotion ? nil : IslandStyle.motion, value: activity.feature)
                .animation(reduceMotion ? .easeOut(duration: 0.15) : IslandStyle.motion, value: activity.isActive)
                // The notch rim moves horizontally first, then fades mid-collapse
                // before reaching the camera. External pills keep their own fade.
                .opacity(expanded ? 1 : 0)
                .animation(expanded ? .easeInOut(duration: 0.18) : geometry.isNotched ?
                    .easeInOut(duration: 0.16).delay(0.12) : .easeInOut(duration: 0.32), value: expanded)
            }
            HStack(spacing: 0) {
                ZStack(alignment: .leading) {
                HStack(spacing: 6) {
                    Group {
                        if activity.feature == .clockTimer, let onClockToggle {
                            Button(action: onClockToggle) { activityIcon.frame(height: geometry.height).contentShape(Rectangle()) }
                                .buttonStyle(.plain)
                                .help(activity.isActive ? "Pause timer" : "Resume timer")
                                .accessibilityLabel(activity.isActive ? "Pause timer" : "Resume timer")
                        } else { activityIcon }
                    }

                    if IslandLayout.showsLabel(activity, geometry: geometry) {
                        Text(activity.label).contentTransition(.opacity).font(.system(size: 11, weight: .medium))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .id(contentKey)
                .transition(replacement(from: -6))
                }
                .padding(.leading, geometry.isNotched ? 26 : 18)
                .padding(.trailing, geometry.isNotched ? 5 : 8)
                .scaleEffect(contentVisible || reduceMotion ? 1 : 0.60, anchor: .trailing)
                .offset(x: contentVisible || reduceMotion ? 0 : 7)
                .animation(reduceMotion ? nil : .spring(response: replaysContentEntrance ? 0.30 : 0.46, dampingFraction: replaysContentEntrance ? 0.60 : 0.48)
                    .delay(contentVisible && !replaysContentEntrance ? 0.055 : 0), value: contentVisible)
                .frame(width: sides.left, height: geometry.height, alignment: .leading)
                .clipped()
                .animation(reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.42, dampingFraction: 0.62), value: contentKey)
                if geometry.isNotched {
                    Color.clear.frame(width: geometry.notchWidth).contentShape(Rectangle())
                        .onTapGesture { if activity.feature == .clockTimer { onClockOpen?() } }
                }
                ZStack(alignment: .trailing) {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    if let seconds = activity.remainingSeconds {
                        Text(ClockReading.formatted(seconds)).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit().fixedSize()
                            .contentTransition(.numericText())
                    } else if activity.feature == .airDrop {
                        Text("Received").font(.system(size: 11, weight: .medium)).fixedSize()
                    } else if activity.feature == .focus {
                        Text(activity.isActive ? "On" : "Off").font(.system(size: 12, weight: .semibold)).contentTransition(.opacity)
                    } else if activity.feature == .capsLock {
                        Text("Active").font(.system(size: 12, weight: .semibold)).fixedSize()
                    } else if activity.feature == .microphoneMute {
                        Text(activity.isActive ? "Unmuted" : "Muted").font(.system(size: 11, weight: .semibold)).fixedSize()
                    } else if [.hotspot, .wifi, .bluetooth].contains(activity.feature) {
                        Text("Connected").font(.system(size: 11, weight: .medium)).fixedSize()
                    } else {
                    Text("\(activity.value)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText(value: Double(activity.value)))
                        .frame(width: 30, alignment: .trailing)
                    Text("%").font(.system(size: 9, weight: .medium)).opacity(0.7)
                    }
                }
                .id(contentKey)
                .transition(replacement(from: 6))
                }
                .padding(.leading, geometry.isNotched ? 0 : 6)
                .padding(.trailing, geometry.isNotched ? 26 : 18)
                .scaleEffect(contentVisible || reduceMotion ? 1 : 0.60, anchor: .leading)
                .offset(x: contentVisible || reduceMotion ? 0 : -7)
                .animation(reduceMotion ? nil : .spring(response: replaysContentEntrance ? 0.30 : 0.46, dampingFraction: replaysContentEntrance ? 0.60 : 0.48)
                    .delay(contentVisible && !replaysContentEntrance ? 0.055 : 0), value: contentVisible)
                .frame(width: sides.right, height: geometry.height, alignment: .trailing)
                .clipped()
                .animation(reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.42, dampingFraction: 0.62), value: contentKey)
                .contentShape(Rectangle())
                .onTapGesture { if activity.feature == .clockTimer { onClockOpen?() } }
                .accessibilityAddTraits(activity.feature == .clockTimer ? .isButton : [])
                .accessibilityAction { if activity.feature == .clockTimer { onClockOpen?() } }
            }
            .onHover { clockControlHovered = $0 }
            .onChange(of: activity.feature) { previous, next in
                if previous == .clockTimer && next != .clockTimer { clockControlHovered = false }
            }
            .foregroundStyle(activity.tint)
            .animation(.easeInOut(duration: 0.22), value: activity.isActive)
            .frame(height: geometry.height)
            .offset(x: geometry.isNotched ? (sides.right - sides.left) / 2 : 0)
            .opacity(contentVisible && !(activity.feature == .clockTimer && closing) ? 1 : 0)
            .animation(.easeOut(duration: 0.20), value: closing)
            // The wings stay anchored outside the camera. Only the shell grows from
            // the center; content fades after it opens and before it folds away.
            .animation(.easeOut(duration: contentVisible ? 0.16 : 0.08)
                .delay(contentVisible && !reduceMotion && !replaysContentEntrance ? 0.10 : 0), value: contentVisible)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: activity.value)
        }
        .frame(width: geometry.isNotched ? geometry.notchWidth + 360 : max(360, width * 1.4 + 24),
               height: geometry.shellHeight + (geometry.isNotched ? 0 : 12))
        .task {
            guard replaysContentEntrance else { return }
            // Only a newly mounted compact view returning from a card needs
            // this entrance. Ordinary shell/content transitions stay coupled.
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            returnContentReady = true
        }
        .accessibilityElement(children: activity.feature == .clockTimer ? .contain : .ignore)
        .accessibilityLabel(activity.remainingSeconds.map { "Timer, \(ClockReading.formatted($0)), \(activity.isActive ? "running" : "paused")" } ?? (activity.feature == .microphoneMute ? "Microphone \(activity.isActive ? "unmuted" : "muted")" : activity.feature == .focus ? "\(activity.label) \(activity.isActive ? "on" : "off")" : activity.feature == .capsLock ? "Caps Lock active" : activity.feature == .airDrop ? "AirDrop received" : [.hotspot, .wifi, .bluetooth].contains(activity.feature) ? "\(activity.label) connected" : "\(activity.label), \(activity.value) percent\(activity.isBoosted ? ", Vivid extra brightness" : "")"))
    }
    private var activityIcon: some View {
        Group {
            if activity.feature == .airDrop { AirDropGlyph().frame(width: 18, height: 18) }
            else { Image(systemName: activity.feature == .clockTimer ? (activity.isActive ? ((screenHovered ?? clockControlHovered) ? "pause.fill" : "timer") : "play.fill") : activity.symbol) }
        }
                        .font(.system(size: 14, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 22)
                        .overlay(alignment: .topTrailing) {
                            if activity.isBoosted {
                                Image(systemName: "plus").font(.system(size: 7, weight: .heavy))
                                    .foregroundStyle(IslandStyle.orange).offset(x: 5, y: -3)
                                    .transition(.scale(scale: 0.35, anchor: .bottomLeading).combined(with: .opacity))
                            }
                        }
                        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.28, dampingFraction: 0.66),
                                   value: activity.isBoosted)

            .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.65), value: activity.isActive)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.3, dampingFraction: 0.65), value: screenHovered ?? clockControlHovered)
    }
}

/// Only the camera-connected outline needs a mask. A rectangular mask on the
/// external pill clips the spring and its glow to the unexpanded layout bounds.
struct NotchOutlineMask: ViewModifier {
    let notched: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if notched {
            content.mask {
                LinearGradient(stops: [.init(color: .clear, location: 0),
                                       .init(color: .clear, location: 0.12),
                                       .init(color: .white, location: 0.40),
                                       .init(color: .white, location: 1)], startPoint: .top, endPoint: .bottom)
            }
        } else {
            content
        }
    }
}

enum IslandLayout {
    static func showsLabel(_ activity: Activity, geometry: IslandGeometry) -> Bool {
        !geometry.isNotched && activity.feature != .volume && activity.feature != .brightness && activity.feature != .capsLock && activity.feature != .clockTimer && activity.feature != .microphoneMute && activity.feature != .airDrop
    }
    static func widths(_ activity: Activity, geometry: IslandGeometry) -> (left: Double, right: Double) {
        guard !geometry.isNotched else { return geometry.widths(for: activity.feature) }
        let labelWidth = showsLabel(activity, geometry: geometry) ?
            ceil((activity.label as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium)]).width) + 6 : 0
        return (18 + 22 + labelWidth + 8, [.hotspot, .wifi, .bluetooth, .clockTimer, .microphoneMute, .airDrop].contains(activity.feature) ? 84 : 68)
    }
}

/// Animate the path itself. Container layout and opacity transactions cannot turn
/// a width change into a crossfade or move the content through the camera.
struct IslandMorph: Shape {
    let geometry: IslandGeometry
    var left: Double
    var right: Double
    var amount: Double
    var outline: Bool
    init(geometry: IslandGeometry, activity: Activity, amount: Double, outline: Bool = false) {
        self.geometry = geometry
        let sides = IslandLayout.widths(activity, geometry: geometry)
        left = sides.left
        right = sides.right
        self.amount = amount
        self.outline = outline
    }
    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(amount, AnimatablePair(left, right)) }
        set { amount = newValue.first; left = newValue.second.first; right = newValue.second.second }
    }
    func path(in rect: CGRect) -> Path {
        IslandMotionTrace.record(amount)
        let progress = max(0, amount) // Keep spring overshoot above one.
        let width = geometry.isNotched ? geometry.notchWidth + (left + right) * progress :
            (left + right) * progress
        let height = geometry.isNotched ? geometry.shellHeight :
            geometry.height * progress
        let x = geometry.isNotched ? rect.midX - geometry.notchWidth / 2 - left * progress : rect.midX - width / 2
        let y = geometry.isNotched ? rect.minY : rect.midY - height / 2
        let bounds = CGRect(x: x, y: y, width: width, height: height)
        return outline ? IslandOutline(notched: geometry.isNotched).path(in: bounds) :
            IslandShape(notched: geometry.isNotched).path(in: bounds)
    }
}

/// Opt-in diagnostics only; normal rendering allocates no samples.
enum IslandMotionTrace {
    private static let lock = NSLock()
    static var enabled = false
    private static var samples: [Double] = []
    private static var actionSamples: [Double] = []
    static func record(_ value: Double) {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }
        if samples.count < 2000 { samples.append(value) }
    }
    static func recordActions(_ value: Double) {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }
        if actionSamples.count < 2000 { actionSamples.append(value) }
    }
    static func takeActions() -> [Double] {
        lock.lock(); defer { lock.unlock() }
        let result = actionSamples
        actionSamples.removeAll(keepingCapacity: true)
        return result
    }
    static func take() -> [Double] {
        lock.lock(); defer { lock.unlock() }
        let result = samples
        samples.removeAll(keepingCapacity: true)
        return result
    }
}

struct IslandShape: Shape {
    var notched: Bool
    var closesTop = true
    var expandedCornerRadius: CGFloat? = nil
    func path(in rect: CGRect) -> Path {
        if notched {
            let shoulder: CGFloat = min(8, rect.height / 4)
            let bottom = min(expandedCornerRadius ?? 18, (rect.height - shoulder) * 0.6)
            let arc: CGFloat = 0.55228475
            let left = rect.minX + shoulder, right = rect.maxX - shoulder
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addCurve(to: CGPoint(x: left, y: rect.minY + shoulder),
                          control1: CGPoint(x: rect.minX + shoulder * arc, y: rect.minY),
                          control2: CGPoint(x: left, y: rect.minY + shoulder * (1 - arc)))
            path.addLine(to: CGPoint(x: left, y: rect.maxY - bottom))
            path.addCurve(to: CGPoint(x: left + bottom, y: rect.maxY),
                          control1: CGPoint(x: left, y: rect.maxY - bottom * (1 - arc)),
                          control2: CGPoint(x: left + bottom * (1 - arc), y: rect.maxY))
            path.addLine(to: CGPoint(x: right - bottom, y: rect.maxY))
            path.addCurve(to: CGPoint(x: right, y: rect.maxY - bottom),
                          control1: CGPoint(x: right - bottom * (1 - arc), y: rect.maxY),
                          control2: CGPoint(x: right, y: rect.maxY - bottom * (1 - arc)))
            path.addLine(to: CGPoint(x: right, y: rect.minY + shoulder))
            path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control1: CGPoint(x: right, y: rect.minY + shoulder * (1 - arc)),
                          control2: CGPoint(x: rect.maxX - shoulder * arc, y: rect.minY))
            if closesTop { path.closeSubpath() }
            return path
        }
        guard rect.width > 0, rect.height > 0 else { return Path() }
        // Circular ends and explicit straight sides retain the pill silhouette
        // even in the last small frames of the uniform shrink to zero.
        let radius = min(expandedCornerRadius ?? .infinity, min(rect.width, rect.height) / 2)
        return Path(roundedRect: rect, cornerRadius: radius)
    }
}

/// Inset the complete pill stroke so its upper half cannot be clipped. The notch
/// outline is an open path: shoulders and bottom only, no line across the menu bar.
struct IslandOutline: Shape {
    var notched: Bool
    var expandedCornerRadius: CGFloat? = nil
    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: 0.5, dy: 0.5)
        return IslandShape(notched: notched, closesTop: !notched, expandedCornerRadius: expandedCornerRadius).path(in: inset)
    }
}

struct IslandPill: View {
    let activity: Activity
    var body: some View {
        IslandSurface(activity: activity, geometry: IslandGeometry(safeTop: 0, notchWidth: 0))
    }
}

struct IslandOverlay: View {
    var clock: ClockMonitor?
    let screenID: UInt32
    @ObservedObject var presentation: IslandPresentation
    let geometry: IslandGeometry
    var body: some View {
        Group {
            if let activity = presentation.activity {
                IslandSurface(activity: activity, geometry: geometry, expanded: presentation.expanded, replaysContentEntrance: presentation.replaysContentEntrance,
                              closing: presentation.closing, onClockToggle: clock.map { monitor in { monitor.togglePause() } },
                              onClockOpen: clock.map { monitor in { monitor.openClock() } }, screenHovered: presentation.hoveredScreens.contains(screenID))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
