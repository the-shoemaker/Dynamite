import AppKit
import IslandCore

/// Compact alerts share the primary panel on each target display. Additional
/// persistent activities retain lower panels while the primary content changes.
final class IslandCoordinator {
    var airDrop: AirDropMonitor?
    var clock: ClockMonitor?
    var nativeNotifications: NativeActivityNotifications?
    var onClockHoverChanged: (() -> Void)?
    var onTemporaryExpired: (() -> Void)?
    private var schedule = ActivitySchedule()
    private var temporaryScreens: [Feature: [UInt32]] = [:]
    private var previewStyles: [Feature: Bool] = [:]
    private var expiry: Timer?
    private var entries: [ActivityRouting.Slot: IslandController] = [:]
    private var removals: [ActivityRouting.Slot: DispatchWorkItem] = [:]
    var currentFeature: Feature? { schedule.current?.feature }
    var currentActivity: Activity? { schedule.current }
    var currentDuration: Double? { schedule.temporaries.last?.duration }
    var clockHovered: Bool { entries.values.contains { $0.clockHovered } }
    var visiblePanelCount: Int { entries.values.reduce(0) { $0 + $1.visiblePanelCount } }
    private var visibleEntries: [(Feature, IslandController)] {
        entries.compactMap { slot, controller in
            guard removals[slot] == nil, let feature = controller.currentFeature else { return nil }
            return (feature, controller)
        }
    }
    var panelFrames: [Feature: [NSRect]] {
        Dictionary(grouping: visibleEntries, by: { $0.0 }).mapValues { $0.flatMap { $0.1.panelFrames } }
    }
    var panelNumbers: [Feature: [Int]] {
        Dictionary(grouping: visibleEntries, by: { $0.0 }).mapValues { $0.flatMap { $0.1.panelNumbers } }
    }
    private func id(_ screen: NSScreen) -> UInt32 {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0
    }
    private func isExpanded(_ activity: Activity) -> Bool {
        activity.feature == .airDrop && airDrop?.transfer != nil ||
        activity.feature == .clockTimer && nativeNotifications?.clockActions.isEmpty == false
    }
    func setPersistent(_ activity: Activity?) { setPersistents(activity.map { [$0] } ?? []) }
    func setPersistents(_ activities: [Activity]) {
        schedule.setPersistents(activities)
        reconcile()
    }
    func show(_ activity: Activity, duration: Double?, placement: DisplayPlacement, previewNotch: Bool? = nil) {
        guard let duration else { setPersistent(activity); return }
        schedule.present(activity, duration: duration, now: ProcessInfo.processInfo.systemUptime)
        previewStyles[activity.feature] = previewNotch
        let screens: [NSScreen]
        if previewNotch != nil {
            screens = (NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first).map { [$0] } ?? []
        } else { screens = IslandController.targetScreens(placement) }
        temporaryScreens[activity.feature] = screens.map(id)
        reconcile()
        scheduleExpiry()
    }
    private func scheduleExpiry() {
        expiry?.invalidate(); expiry = nil
        guard let deadline = schedule.expiresAt else { return }
        let timer = Timer(timeInterval: max(0.001, deadline - ProcessInfo.processInfo.systemUptime), repeats: false) { [weak self] _ in
            guard let self else { return }
            self.expireTemporary()
            self.onTemporaryExpired?()
        }
        expiry = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    func expireTemporary() {
        schedule.expire(at: ProcessInfo.processInfo.systemUptime)
        reconcile()
        scheduleExpiry()
    }
    func endTemporary() {
        schedule.endTemporary()
        temporaryScreens.removeAll(); previewStyles.removeAll()
        reconcile(); scheduleExpiry()
    }
    func remove(_ feature: Feature) {
        schedule.remove(feature)
        temporaryScreens.removeValue(forKey: feature); previewStyles.removeValue(forKey: feature)
        reconcile(); scheduleExpiry()
    }
    func restart(duration: Double) {
        guard let activity = schedule.temporary else { return }
        restart(activity.feature, duration: duration)
    }
    func restart(_ feature: Feature, duration: Double) {
        guard let activity = schedule.temporaries.first(where: { $0.activity.feature == feature })?.activity else { return }
        schedule.present(activity, duration: duration, now: ProcessInfo.processInfo.systemUptime)
        // Duration changes extend only this deadline, without replaying other rows.
        scheduleExpiry()
    }
    func updateVisibleActivity(_ activity: Activity) {
        schedule.update(activity)
        reconcile()
    }
    private func reconcile() {
        let available = Dictionary(uniqueKeysWithValues: NSScreen.screens.map { (id($0), $0) })
        var requests = schedule.persistents.map { activity -> ActivityRouting.Request in
            let screens = IslandController.persistentScreen(for: activity.feature).map { [id($0)] } ?? []
            return .init(activity.feature, screens: screens, expanded: isExpanded(activity))
        }
        if let activity = schedule.temporary {
            requests.append(.init(activity.feature,
                screens: (temporaryScreens[activity.feature] ?? []).filter { available[$0] != nil }, source: .temporary))
        }
        let rows = ActivityRouting.stacks(requests)
        let desired = Set(rows.map(\.slot))
        // Keep an existing long-running panel when it becomes a lower pill.
        for row in rows where row.index > 0 && entries[row.slot] == nil {
            let primary = ActivityRouting.Slot(screen: row.slot.screen, position: .primary)
            if let controller = entries[primary], controller.currentFeature == row.feature {
                removals.removeValue(forKey: primary)?.cancel()
                entries[row.slot] = entries.removeValue(forKey: primary)
            }
        }
        // Reuse a lower panel when its persistent activity returns to the notch.
        for row in rows where row.index == 0 {
            let lower = ActivityRouting.Slot(screen: row.slot.screen, position: .secondary(row.feature))
            guard !desired.contains(lower), let controller = entries.removeValue(forKey: lower) else { continue }
            removals.removeValue(forKey: lower)?.cancel()
            removals.removeValue(forKey: row.slot)?.cancel()
            if let old = entries.removeValue(forKey: row.slot) { retireDetached(old) }
            entries[row.slot] = controller
        }
        let activeFeatures = Set(schedule.temporaries.map { $0.activity.feature })
        temporaryScreens = temporaryScreens.filter { activeFeatures.contains($0.key) }
        previewStyles = previewStyles.filter { activeFeatures.contains($0.key) }
        for (slot, controller) in entries where !desired.contains(slot) && removals[slot] == nil {
            controller.hide()
            let removal = DispatchWorkItem { [weak self, weak controller] in
                guard let self, self.entries[slot] === controller else { return }
                self.entries.removeValue(forKey: slot)
                self.removals.removeValue(forKey: slot)
            }
            removals[slot] = removal
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75, execute: removal)
        }
        var nextTop: [UInt32: Double] = [:]
        for row in rows {
            let slot = row.slot
            guard let display = available[slot.screen],
                  let activity = row.source == .persistent ? schedule.persistents.first(where: { $0.feature == row.feature }) : schedule.temporary else { continue }
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
            }
            let preview = row.source == .temporary ? previewStyles[activity.feature] : nil
            let floating = nextTop[slot.screen]
            let wasFloating = controller.floatingTopGap != nil
            let modeChanged = wasFloating != (floating != nil)
            if let floating, wasFloating { controller.moveFloatingPill(to: floating) }
            else { controller.floatingTopGap = floating }
            controller.targetScreen = display
            let card = row.source == .persistent && isExpanded(activity)
            let configurationChanged = controller.allowsExpandedCards != card || modeChanged
            controller.allowsExpandedCards = card
            if controller.currentFeature != activity.feature || configurationChanged || controller.presentation.closing || controller.previewStyle != preview {
                controller.show(activity, duration: nil, placement: .main, previewNotch: preview)
            } else { controller.updateVisibleActivity(activity) }
            let geometry = IslandController.geometry(for: display, externalPreview: preview == false, floatingTopGap: floating)
            let height = card && activity.feature == .airDrop ? AirDropExpandedView.height(for: geometry) :
                card ? geometry.shellHeight + ClockAlertView.extraHeight : geometry.shellHeight
            nextTop[slot.screen] = geometry.topGap + height + 10
        }
    }
    private func retireDetached(_ controller: IslandController) {
        controller.hide()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { controller.hide(immediately: true) }
    }
    func containsActivity(at point: NSPoint) -> Bool {
        entries.contains { removals[$0.key] == nil && $0.value.containsActivity(at: point) }
    }
    func screenParametersChanged() {
        entries.values.forEach { $0.screenParametersChanged() }
        reconcile()
    }
    func hide(immediately: Bool = false) {
        expiry?.invalidate(); expiry = nil
        schedule.reset(); temporaryScreens.removeAll(); previewStyles.removeAll()
        if immediately {
            removals.values.forEach { $0.cancel() }; removals.removeAll()
            entries.values.forEach { $0.hide(immediately: true) }; entries.removeAll()
        } else { reconcile() }
    }
    deinit { expiry?.invalidate(); removals.values.forEach { $0.cancel() } }
}
