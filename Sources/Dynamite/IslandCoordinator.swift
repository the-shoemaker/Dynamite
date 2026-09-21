import AppKit
import IslandCore

/// Keeps display placement separate from the animation of an individual island.
/// Only visible/retiring slots own panels; there is one temporary expiry timer.
final class IslandCoordinator {
    var airDrop: AirDropMonitor?
    var clock: ClockMonitor?
    var nativeNotifications: NativeActivityNotifications?
    var onClockHoverChanged: (() -> Void)?
    var onTemporaryExpired: (() -> Void)?
    private var persistent: Activity?
    private var temporary: Activity?
    private var temporaryScreens: [NSScreen] = []
    private var previewNotch: Bool?
    private var expiry: Timer?
    private(set) var currentDuration: Double?
    private var entries: [ActivityRouting.Slot: IslandController] = [:]
    private var removals: [ActivityRouting.Slot: DispatchWorkItem] = [:]
    private var promoted = Set<ActivityRouting.Slot>()
    var currentFeature: Feature? { (temporary ?? persistent)?.feature }
    var currentActivity: Activity? { temporary ?? persistent }
    var clockHovered: Bool { entries.values.contains { $0.clockHovered } }
    var visiblePanelCount: Int { entries.values.reduce(0) { $0 + $1.visiblePanelCount } }
    private func id(_ screen: NSScreen) -> UInt32 {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0
    }
    private var expanded: Bool {
        persistent?.feature == .airDrop && airDrop?.transfer != nil ||
        persistent?.feature == .clockTimer && nativeNotifications?.clockActions.isEmpty == false
    }
    func setPersistent(_ activity: Activity?) {
        persistent = activity
        reconcile()
    }
    func show(_ activity: Activity, duration: Double?, placement: DisplayPlacement, previewNotch: Bool? = nil) {
        guard let duration else { setPersistent(activity); return }
        // A pill promoted from beneath a card belongs to that temporary event.
        // A later event uses the display's normal notch/pill geometry again.
        if temporary?.feature != activity.feature { retirePromoted() }
        temporary = activity
        self.previewNotch = previewNotch
        if previewNotch != nil {
            temporaryScreens = (NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first).map { [$0] } ?? []
        } else { temporaryScreens = IslandController.targetScreens(placement) }
        currentDuration = duration
        reconcile()
        scheduleExpiry(duration)
    }
    private func scheduleExpiry(_ duration: Double) {
        expiry?.invalidate()
        let timer = Timer(timeInterval: duration, repeats: false) { [weak self] _ in
            guard let self else { return }
            if let onTemporaryExpired = self.onTemporaryExpired { onTemporaryExpired() }
            else { self.endTemporary() }
        }
        expiry = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func endTemporary() {
        expiry?.invalidate(); expiry = nil
        retirePromoted()
        temporary = nil; temporaryScreens = []; currentDuration = nil; previewNotch = nil
        reconcile()
    }
    func restart(duration: Double) {
        guard temporary != nil else { return }
        currentDuration = duration
        for (slot, controller) in entries where removals[slot] == nil && controller.currentFeature == temporary?.feature {
            controller.restartAnimation()
        }
        scheduleExpiry(duration)
    }
    func updateVisibleActivity(_ activity: Activity) {
        guard temporary?.feature == activity.feature,
              temporary?.sourceDisplayID == activity.sourceDisplayID else { return }
        temporary = activity
        reconcile()
    }
    private func reconcile() {
        let persistentScreen = persistent.flatMap { IslandController.persistentScreen(for: $0.feature) }
        let screen = persistentScreen.map(id)
        let available = Dictionary(uniqueKeysWithValues: NSScreen.screens.map { (id($0), $0) })
        temporaryScreens = temporaryScreens.compactMap { available[id($0)] }
        let desired = ActivityRouting.slots(persistentScreen: screen, expanded: expanded,
            temporaryScreens: temporary == nil ? [] : temporaryScreens.map(id))

        for slot in promoted where desired[slot] != .temporary {
            removals.removeValue(forKey: slot)?.cancel()
            if let controller = entries.removeValue(forKey: slot) { retireDetached(controller) }
            promoted.remove(slot)
        }
        // Keep the same floating window when its card goes away. WindowServer
        // moves it; SwiftUI does not rerender the pill on each movement frame.
        for (slot, source) in desired where source == .temporary && !slot.belowCard {
            let lower = ActivityRouting.Slot(screen: slot.screen, belowCard: true)
            if let controller = entries.removeValue(forKey: lower), let display = available[slot.screen] {
                removals.removeValue(forKey: lower)?.cancel()
                if let old = entries.removeValue(forKey: slot) { retireDetached(old) }
                removals.removeValue(forKey: slot)?.cancel()
                entries[slot] = controller
                promoted.insert(slot)
                controller.moveFloatingPill(to: display.safeAreaInsets.top + 6)
            }
        }
        for (slot, controller) in entries where desired[slot] == nil && removals[slot] == nil {
            controller.hide()
            let removal = DispatchWorkItem { [weak self, weak controller] in
                guard let self, self.entries[slot] === controller else { return }
                self.entries.removeValue(forKey: slot)
                self.removals.removeValue(forKey: slot)
            }
            removals[slot] = removal
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: removal)
        }
        for (slot, source) in desired {
            guard let display = available[slot.screen], let activity = source == .persistent ? persistent : temporary else { continue }
            removals.removeValue(forKey: slot)?.cancel()
            let controller: IslandController
            if let existing = entries[slot] { controller = existing }
            else {
                controller = IslandController()
                controller.targetScreen = display
                controller.airDrop = airDrop; controller.clock = clock; controller.nativeNotifications = nativeNotifications
                controller.onClockHoverChanged = { [weak self] in self?.onClockHoverChanged?() }
                controller.containsRelatedActivity = { [weak self] point in self?.containsActivity(at: point) ?? false }
                entries[slot] = controller
                if slot.belowCard {
                    let geometry = IslandController.geometry(for: display)
                    let height = persistent?.feature == .airDrop ? AirDropExpandedView.height(for: geometry) : geometry.shellHeight + ClockAlertView.extraHeight
                    controller.floatingTopGap = geometry.topGap + height + 14
                }
            }
            controller.targetScreen = display
            let card = source == .persistent && expanded
            let configurationChanged = controller.allowsExpandedCards != card
            controller.allowsExpandedCards = card
            if controller.currentFeature != activity.feature || configurationChanged || controller.presentation.closing || controller.previewStyle != (source == .temporary ? previewNotch : nil) {
                controller.show(activity, duration: nil, placement: .main, previewNotch: source == .temporary ? previewNotch : nil)
            } else { controller.updateVisibleActivity(activity) }
        }
    }
    private func retirePromoted() {
        for slot in promoted {
            removals.removeValue(forKey: slot)?.cancel()
            if let controller = entries.removeValue(forKey: slot) { retireDetached(controller) }
        }
        promoted.removeAll()
    }
    private func retireDetached(_ controller: IslandController) {
        controller.hide()
        // A finite retention keeps its exit animation alive, without polling.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { controller.hide(immediately: true) }
    }
    func containsActivity(at point: NSPoint) -> Bool { entries.values.contains { $0.containsActivity(at: point) } }
    func screenParametersChanged() {
        entries.values.forEach { $0.screenParametersChanged() }
        reconcile()
    }
    func hide(immediately: Bool = false) {
        expiry?.invalidate(); expiry = nil
        persistent = nil; temporary = nil; temporaryScreens = []; currentDuration = nil
        if immediately {
            removals.values.forEach { $0.cancel() }; removals.removeAll()
            entries.values.forEach { $0.hide(immediately: true) }; entries.removeAll(); promoted.removeAll()
        } else { reconcile() }
    }
    deinit { expiry?.invalidate(); removals.values.forEach { $0.cancel() } }
}
