import AppKit
import SwiftUI
import QuartzCore
import IslandCore

final class IslandController {
    let presentation = IslandPresentation()
    // A coordinator pins each renderer to one display for its entire lifetime.
    var targetScreen: NSScreen?
    var floatingTopGap: Double?
    var allowsExpandedCards = true
    private(set) var previewStyle: Bool?
    var containsRelatedActivity: ((NSPoint) -> Bool)?
    // Opt-in A/B benchmark only; production always uses the cheaper path.
    var legacyRenderingForBenchmark = false
    var airDrop: AirDropMonitor?
    var clock: ClockMonitor?
    var nativeNotifications: NativeActivityNotifications?
    var onClockHoverChanged: (() -> Void)?
    private(set) var clockHovered = false
    private var expandedTransfer = false
    private var expandedClock = false
    func needsExpandedClock(_ value: Bool) -> Bool { expandedClock != value }
    private var outsideGlobal: Any?
    private var outsideLocal: Any?
    private var escapeGlobal: Any?
    private var escapeLocal: Any?
    private var hoverGlobal: Any?
    private var hoverLocal: Any?
    private var compactWork: DispatchWorkItem?
    private var pendingCompact: (() -> Void)?
    private var panels: [NSPanel] = []
    private var screenIDs: [UInt32] = []
    private struct DisplayLayout: Equatable {
        let id: UInt32
        let frame: NSRect
        let scale: CGFloat
        let geometry: IslandGeometry
    }
    private var displayLayouts: [DisplayLayout] = []
    private var externalPreview = false
    private var dismissTimer: Timer?
    private var closeTimer: Timer?
    private var revealWork: DispatchWorkItem?
    private var transitionWork: DispatchWorkItem?
    var onTemporaryExpired: (() -> Void)?
    private(set) var currentFeature: Feature?
    private(set) var currentDuration: Double?
    var panelFrames: [NSRect] { panels.map(\.frame) }
    var visiblePanelCount: Int { panels.filter(\.isVisible).count }

    static func pointerScreen() -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.screens.first
    }
    static func persistentScreen(for feature: Feature) -> NSScreen? {
        if [.capsLock, .clockTimer, .airDrop].contains(feature), let builtIn = NSScreen.screens.first(where: { CGDisplayIsBuiltin(id($0)) != 0 }) { return builtIn }
        let external = NSScreen.screens.filter { CGDisplayIsBuiltin(id($0)) == 0 }
        return external.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
            ?? NSScreen.screens.first
    }
    func persistentTargetChanged(for feature: Feature) -> Bool { screenIDs != Self.persistentScreen(for: feature).map { [Self.id($0)] } ?? [] }
    static func targetScreens(_ placement: DisplayPlacement) -> [NSScreen] {
        switch placement {
        case .pointer: return pointerScreen().map { [$0] } ?? []
        case .main: return NSScreen.screens.first.map { [$0] } ?? []
        case .all: return NSScreen.screens
        }
    }
    static func geometry(for screen: NSScreen, externalPreview: Bool = false, floatingTopGap: Double? = nil) -> IslandGeometry {
        let reference = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 })?.safeAreaInsets.top ?? 32
        let notchWidth: CGFloat
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = max(0, right.minX - left.maxX)
        } else { notchWidth = 0 }
        return IslandGeometry(safeTop: screen.safeAreaInsets.top, notchWidth: notchWidth,
                              referenceHeight: reference, externalPreview: externalPreview, floatingTopGap: floatingTopGap)
    }
    private static func id(_ screen: NSScreen) -> UInt32 {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0
    }
    private func layout(for screen: NSScreen) -> DisplayLayout {
        DisplayLayout(id: Self.id(screen), frame: screen.frame, scale: screen.backingScaleFactor,
                      geometry: Self.geometry(for: screen, externalPreview: externalPreview, floatingTopGap: floatingTopGap))
    }
    func screenParametersChanged() {
        // Vivid and macOS also announce brightness/HDR changes here. Those do not
        // move our panel and must not dismiss a just-presented brightness activity.
        guard !panels.isEmpty else { return }
        let screens = NSScreen.screens
        let layouts = screenIDs.compactMap { id in screens.first { Self.id($0) == id } }.map(layout)
        let changed = layouts != displayLayouts
        if changed { hide(immediately: true) }
    }
    func show(_ activity: Activity, duration: Double?, placement: DisplayPlacement, previewNotch: Bool? = nil) {
        previewStyle = previewNotch
        let nextIsCard = allowsExpandedCards && ((activity.feature == .clockTimer && nativeNotifications?.clockActions.isEmpty == false) ||
            (activity.feature == .airDrop && airDrop?.transfer != nil))
        if !panels.isEmpty && (expandedClock || expandedTransfer) && !nextIsCard {
            // Keep the existing window and shell through the flattening phase.
            // Clock can publish several samples while Repeat takes effect.
            pendingCompact = { [weak self] in
                self?.present(activity, duration: duration, placement: placement, previewNotch: previewNotch, fromCard: true)
            }
            presentation.compactDestination = activity.feature
            presentation.compactReturn = activity
            guard compactWork == nil else { return }
            dismissTimer?.invalidate(); closeTimer?.invalidate()
            transitionWork?.cancel(); revealWork?.cancel()
            presentation.closing = true
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.compactWork = nil
                let next = self.pendingCompact
                self.pendingCompact = nil
                next?()
            }
            compactWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.40, execute: work)
            return
        }
        compactWork?.cancel(); compactWork = nil; pendingCompact = nil
        present(activity, duration: duration, placement: placement, previewNotch: previewNotch)
    }
    private func present(_ activity: Activity, duration: Double?, placement: DisplayPlacement, previewNotch: Bool?, fromCard: Bool = false) {
        transitionWork?.cancel()
        presentation.closing = false
        dismissTimer?.invalidate()
        closeTimer?.invalidate()
        revealWork?.cancel()
        let screens: [NSScreen]
        if let targetScreen { screens = [targetScreen] }
        else if previewNotch != nil {
            // Both preview styles use the laptop when available, regardless of placement.
            screens = (NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first)
                .map { [$0] } ?? []
        } else if duration == nil || activity.feature == .capsLock { screens = Self.persistentScreen(for: activity.feature).map { [$0] } ?? [] }
        else { screens = Self.targetScreens(placement) }
        let newExternalPreview = previewNotch == false
        let newExpandedClock = allowsExpandedCards && activity.feature == .clockTimer && nativeNotifications?.clockActions.isEmpty == false
        let newExpandedTransfer = allowsExpandedCards && activity.feature == .airDrop && airDrop?.transfer != nil
        let opensFromCompact = !panels.isEmpty && !expandedTransfer && !expandedClock && (newExpandedTransfer || newExpandedClock)
        let reusablePanels = Dictionary(uniqueKeysWithValues: zip(screenIDs, panels))
        var retiringPanels: [NSPanel] = []
        if screenIDs != screens.map(Self.id) || externalPreview != newExternalPreview || expandedTransfer != newExpandedTransfer || expandedClock != newExpandedClock {
            retiringPanels = closePanels(retainingWindows: true)
        }
        externalPreview = newExternalPreview
        expandedTransfer = newExpandedTransfer
        expandedClock = newExpandedClock
        presentation.opensFromCompact = opensFromCompact
        presentation.compactDestination = nil
        presentation.compactReturn = nil
        if fromCard {
            // The card already animated these contents during flattening.
            // Preserve their final pose when replacing the hosting view.
            presentation.expanded = true
            presentation.replaysContentEntrance = false
        }
        currentFeature = activity.feature
        currentDuration = duration
        if panels.isEmpty { makePanels(on: screens, reusing: reusablePanels) }
        presentation.activity = activity
        for panel in panels {
            panel.ignoresMouseEvents = !(expandedTransfer || activity.feature == .clockTimer)
            // SwiftUI coalesces ordinary value updates into the next display
            // pass. Force the first frame only when bringing a window onscreen.
            if !panel.isVisible || legacyRenderingForBenchmark {
                panel.contentView?.layoutSubtreeIfNeeded()
                panel.orderFrontRegardless()
                panel.displayIfNeeded()
            }
        }
        // Order the replacement before retiring the old backing store.
        retiringPanels.filter { retired in !panels.contains { $0 === retired } }.forEach { $0.orderOut(nil); $0.contentView = nil; $0.close() }
        if !presentation.expanded {
            let reveal = DispatchWorkItem { [weak self] in
                self?.presentation.expanded = true
            }
            revealWork = reveal
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: reveal)
        }
        configureHoverMonitoring()
        updateHover()
        if let duration {
            dismissTimer = oneShot(after: duration) { [weak self] in
                guard let self else { return }
                if let onTemporaryExpired { onTemporaryExpired() } else { hide() }
            }
        }
    }
    func moveFloatingPill(to topGap: Double) {
        guard let previous = floatingTopGap else { return }
        floatingTopGap = topGap
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.32
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            for panel in panels {
                var destination = panel.frame
                destination.origin.y += previous - topGap
                panel.animator().setFrame(destination, display: true)
            }
        }
        if let targetScreen { displayLayouts = [layout(for: targetScreen)] }
    }
    func restart(duration: Double) {
        guard currentFeature != nil else { return }
        currentDuration = duration
        dismissTimer?.invalidate()
        closeTimer?.invalidate()
        transitionWork?.cancel()
        revealWork?.cancel()
        restartAnimation()
        dismissTimer = oneShot(after: duration) { [weak self] in
            guard let self else { return }
            if let onTemporaryExpired { onTemporaryExpired() } else { hide() }
        }
    }
    func restartAnimation() {
        transitionWork?.cancel(); revealWork?.cancel(); closeTimer?.invalidate()
        presentation.closing = false
        presentation.expanded = false
        let reveal = DispatchWorkItem { [weak self] in
                self?.presentation.expanded = true
            }
        revealWork = reveal
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: reveal)
    }
    func transition(to activity: Activity, placement: DisplayPlacement) {
        // Use the same in-place morph as Caps Lock -> volume. Keep the shell open.
        show(activity, duration: nil, placement: placement)
    }
    func updateVisibleActivity(_ activity: Activity) {
        guard currentFeature == activity.feature, presentation.expanded,
              presentation.activity?.sourceDisplayID == activity.sourceDisplayID else { return }
        presentation.activity = activity
    }
    func hide(immediately: Bool = false) {
        compactWork?.cancel(); compactWork = nil; pendingCompact = nil
        presentation.compactDestination = nil
        presentation.compactReturn = nil
        transitionWork?.cancel()
        dismissTimer?.invalidate()
        closeTimer?.invalidate()
        revealWork?.cancel()
        currentFeature = nil
        currentDuration = nil
        if immediately {
            presentation.expanded = false
            presentation.closing = false
            closePanels()
            return
        }
        // A small outward release makes the retraction feel elastic. The outline
        // fades from this moment, before the shell approaches the physical notch.
        presentation.closing = true
        let retract = DispatchWorkItem { [weak self] in
            self?.presentation.expanded = false
        }
        transitionWork = retract
        let expandedCard = expandedTransfer || expandedClock
        DispatchQueue.main.asyncAfter(deadline: .now() + (expandedCard ? 0.24 : (displayLayouts.contains { $0.geometry.isNotched } ? 0 : 0.06)), execute: retract)
        closeTimer = oneShot(after: expandedCard ? 0.70 : 0.58) { [weak self] in self?.closePanels() }
    }
    private func oneShot(after delay: Double, action: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in action() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
    @discardableResult
    private func closePanels(retainingWindows: Bool = false) -> [NSPanel] {
        if clockHovered {
            clockHovered = false
            DispatchQueue.main.async { [weak self] in self?.onClockHoverChanged?() }
        }
        presentation.hoveredScreens = []
        if let hoverGlobal { NSEvent.removeMonitor(hoverGlobal) }; hoverGlobal = nil
        if let hoverLocal { NSEvent.removeMonitor(hoverLocal) }; hoverLocal = nil
        if let escapeGlobal { NSEvent.removeMonitor(escapeGlobal) }; escapeGlobal = nil
        if let escapeLocal { NSEvent.removeMonitor(escapeLocal) }; escapeLocal = nil
        if let outsideGlobal { NSEvent.removeMonitor(outsideGlobal) }; outsideGlobal = nil
        if let outsideLocal { NSEvent.removeMonitor(outsideLocal) }; outsideLocal = nil
        let retired = panels
        if !retainingWindows { retired.forEach { $0.orderOut(nil); $0.contentView = nil; $0.close() } }
        panels.removeAll()
        screenIDs.removeAll()
        displayLayouts.removeAll()
        presentation.activity = nil
        presentation.expanded = false
        presentation.closing = false
        presentation.opensFromCompact = false
        presentation.replaysContentEntrance = false
        presentation.compactDestination = nil
        presentation.compactReturn = nil
        expandedTransfer = false
        expandedClock = false
        return retainingWindows ? retired : []
    }
    func containsActivity(at point: NSPoint) -> Bool {
        guard let activity = presentation.activity, presentation.expanded else { return false }
        return displayLayouts.contains { hoverContains(point, layout: $0, activity: activity) }
    }
    private func hoverContains(_ point: NSPoint, layout: DisplayLayout, activity: Activity) -> Bool {
        let geometry = layout.geometry
        let sides = IslandLayout.widths(activity, geometry: geometry)
        let card = expandedTransfer || expandedClock
        let width = card ? max(288, geometry.notchWidth + 168) : geometry.notchWidth + sides.left + sides.right
        let height = expandedTransfer ? AirDropExpandedView.height(for: geometry) :
            expandedClock ? geometry.shellHeight + ClockAlertView.extraHeight : geometry.shellHeight
        return geometry.containsHover(point, screen: layout.frame, width: width, height: height)
    }
    private func configureHoverMonitoring() {
        guard expandedTransfer || expandedClock || presentation.activity?.feature == .clockTimer else {
            if let hoverGlobal { NSEvent.removeMonitor(hoverGlobal) }; hoverGlobal = nil
            if let hoverLocal { NSEvent.removeMonitor(hoverLocal) }; hoverLocal = nil
            return
        }
        guard hoverGlobal == nil, hoverLocal == nil else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        hoverGlobal = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in self?.updateHover() }
        hoverLocal = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.updateHover(); return event
        }
    }
    private func updateHover() {
        guard let activity = presentation.activity else { return }
        let point = NSEvent.mouseLocation
        let hovered = Set(displayLayouts.filter { hoverContains(point, layout: $0, activity: activity) }.map(\.id))
        if presentation.hoveredScreens != hovered { presentation.hoveredScreens = hovered }
        let clockIsHovered = activity.feature == .clockTimer && !hovered.isEmpty
        if clockHovered != clockIsHovered {
            clockHovered = clockIsHovered
            DispatchQueue.main.async { [weak self] in self?.onClockHoverChanged?() }
        }
    }
    private func makePanels(on screens: [NSScreen], reusing reusablePanels: [UInt32: NSPanel] = [:]) {
        for screen in screens {
            let geometry = Self.geometry(for: screen, externalPreview: externalPreview, floatingTopGap: floatingTopGap)
            let width = max(geometry.notchWidth + 440, 560)
            let overshootInset: CGFloat = geometry.isNotched ? 0 : 6
            // Keep transparent space below the expanded spring's overshoot.
            let extraHeight: CGFloat = expandedTransfer ? AirDropExpandedView.height(for: geometry) - geometry.shellHeight + 24 : (expandedClock ? ClockAlertView.extraHeight + 24 : 0)
            let frame = NSRect(x: screen.frame.midX - width / 2,
                               y: screen.frame.maxY - geometry.topGap - geometry.shellHeight - overshootInset - 1 - extraHeight,
                               width: width, height: geometry.shellHeight + overshootInset * 2 + 1 + extraHeight)
            // Reuse the same WindowServer surface across compact/card changes.
            // Ordering a newly-created panel can expose a frame of wallpaper.
            let panel = reusablePanels[Self.id(screen)] ?? NSPanel(contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
            if panel.frame != frame { panel.setFrame(frame, display: false, animate: false) }
            panel.level = geometry.isNotched ? .statusBar : NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.animationBehavior = legacyRenderingForBenchmark ? .default : .none
            panel.acceptsMouseMovedEvents = true
            panel.ignoresMouseEvents = !expandedTransfer
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            if expandedTransfer, let airDrop {
                panel.contentView = NSHostingView(rootView: AirDropExpandedView(monitor: airDrop, presentation: presentation, geometry: geometry, screenID: Self.id(screen)))
            } else if expandedClock, let nativeNotifications, let clock {
                panel.contentView = NSHostingView(rootView: ClockAlertView(monitor: nativeNotifications, clock: clock, presentation: presentation, geometry: geometry, screenID: Self.id(screen)))
            } else {
                panel.contentView = NSHostingView(rootView: IslandOverlay(clock: clock, screenID: Self.id(screen), presentation: presentation, geometry: geometry))
            }
            panels.append(panel)
        }
        if expandedTransfer {
            let outside: () -> Void = { [weak self] in
                guard let self, self.expandedTransfer else { return }
                let point = NSEvent.mouseLocation
                if self.containsRelatedActivity?(point) == true { return }
                if !self.panels.contains(where: { panel in
                    guard let screen = panel.screen else { return false }
                    let geometry = Self.geometry(for: screen, externalPreview: self.externalPreview)
                    let width = max(288, geometry.notchWidth + 168)
                    let top = panel.frame.maxY - (geometry.isNotched ? 0 : 6)
                    let height = AirDropExpandedView.height(for: geometry)
                    return NSRect(x: panel.frame.midX - width / 2, y: top - height,
                                  width: width, height: height).contains(point)
                }) { self.airDrop?.dismiss() }
            }
            outsideGlobal = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { _ in outside() }
            outsideLocal = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { event in outside(); return event }
        }
        if expandedTransfer || expandedClock {
            let dismiss: () -> Void = { [weak self] in
                guard let self else { return }
                if self.expandedTransfer { self.airDrop?.dismiss() }
                else if self.expandedClock { self.nativeNotifications?.stopClockAlert() }
            }
            escapeGlobal = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { dismiss() }
            }
            escapeLocal = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53 { dismiss(); return nil }; return event
            }
        }
        screenIDs = screens.map(Self.id)
        displayLayouts = screens.map(layout)
    }
    deinit { compactWork?.cancel(); dismissTimer?.invalidate(); closeTimer?.invalidate(); revealWork?.cancel(); transitionWork?.cancel() }
}
