import AppKit
import ApplicationServices
import Combine
import IslandCore

/// Only the three requested integrations are eligible. Notification text is
/// neither logged nor saved. AX work is bounded and stays off the main thread.
final class NativeActivityNotifications: ObservableObject {
    struct Action: Identifiable, Equatable { let id: String; let title: String }
    @Published private(set) var clockActions: [Action] = []
    @Published private(set) var clockOriginalDuration: Int?
    @Published private(set) var status = "Off"
    @Published private(set) var airPodsStatus = "Waiting for a connection"
    @Published private(set) var focusStatus = "Waiting for a Focus change"
    @Published private(set) var volumeStatus = "Waiting for a volume change"
    @Published private(set) var airDropStatus = "Waiting for a transfer"
    var onClockChange: (() -> Void)?
    private let queue = DispatchQueue(label: "com.dan.dynomite.native-activities", qos: .utility)
    private var observer: AXObserver?
    private var app: AXUIElement?
    private var enabled = Set<Feature>()
    private var pending = false
    private var pendingUrgent = false
    private var pendingRead: DispatchWorkItem?
    private var clockExpectation = ClockAlertExpectation()
    private var generation = UUID()
    private var actions: [String: (AXUIElement, String)] = [:]
    private var receipts = Set<String>()
    private var receiptGeneration = UUID()
    private var receiptsUntil: TimeInterval = 0
    private let airPodsBanner = NativeSystemBanner(identifier: "smart-routing-system-banner")
    private let focusBanner = NativeSystemBanner(identifier: "focus-system-banner", watchCreation: true)
    private let volumeBanner = NativeSystemBanner(identifier: "volume-system-banner", requiresPassiveContent: false, watchCreation: true)
    private var menuFeatures = Set<Feature>() // Main-thread readiness/configuration.
    private var focusReadable = false
    private var volumeReadable = false
    private var parked: [CFHashCode: (AXUIElement, CGPoint)] = [:]
    private var parkedHosts = Set<CFHashCode>()
    private var workspaceObserver: NSObjectProtocol?
    private var deadline: TimeInterval = 0
    private var exhausted = false
    private static let bannerRoles = Set(["AXNotificationCenterBanner", "AXNotificationCenterBannerStack", "AXNotificationCenterAlert", "AXNotificationCenterAlertStack"])

    func configure(_ features: Set<Feature>) {
        menuFeatures = features
        airPodsBanner.onStatus = { [weak self] in self?.airPodsStatus = $0 }
        airPodsBanner.configure(enabled: features.contains(.airPods))
        focusBanner.onStatus = { [weak self] in self?.focusStatus = $0 }
        focusBanner.configure(enabled: features.contains(.focus) && focusReadable)
        volumeBanner.onStatus = { [weak self] in self?.volumeStatus = $0 }
        volumeBanner.configure(enabled: features.contains(.volume) && volumeReadable)
        let features = features.subtracting([.airPods, .focus, .volume])
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.notificationcenterui").first?.processIdentifier
        if workspaceObserver == nil {
            workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                object: nil, queue: .main) { [weak self] note in
                guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == "com.apple.notificationcenterui" else { return }
                self.queue.async { self.attach(app.processIdentifier) }
            }
        }
        queue.async { [weak self] in
            guard let self else { return }
            if self.enabled != features { self.restoreParked(); self.enabled = features }
            if features.isEmpty { self.detach(); self.publish([], status: "Off"); return }
            if let pid, self.app == nil { self.attach(pid) }
            self.requestRead()
        }
    }
    func receivedFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.receipts = Set(urls.flatMap { AirDropReceipt.notificationNames(for: $0.lastPathComponent) })
            self.receiptsUntil = ProcessInfo.processInfo.systemUptime + 15
            let token = UUID()
            self.receiptGeneration = token
            self.requestRead()
            // Only a short burst after a verified receipt, never idle polling.
            for delay in [0.25, 0.6, 1.2, 2.5, 5.0] {
                self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.receiptGeneration == token else { return }
                    self.requestRead()
                }
            }
        }
    }
    func airPodsConnected() { airPodsBanner.connected() }
    func focusChanged() { focusBanner.connected() }
    func volumeChanged() { volumeBanner.connected() }
    func focusAvailability(_ available: Bool) {
        focusReadable = available
        focusBanner.configure(enabled: available && menuFeatures.contains(.focus))
    }
    func volumeAvailability(_ available: Bool) {
        volumeReadable = available
        volumeBanner.configure(enabled: available && menuFeatures.contains(.volume))
    }
    private func attach(_ pid: pid_t) {
        guard !enabled.isEmpty, AXIsProcessTrusted() else { return }
        detach()
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.025)
        var observer: AXObserver?
        guard AXObserverCreate(pid, { _, _, notification, context in
            guard let context else { return }
            let owner = Unmanaged<NativeActivityNotifications>.fromOpaque(context).takeUnretainedValue()
            let created = notification as String == kAXWindowCreatedNotification
            owner.queue.async {
                owner.requestRead(urgent: created || !owner.actions.isEmpty ||
                    owner.clockExpectation.isUrgent(at: ProcessInfo.processInfo.systemUptime))
            }
        }, &observer) == .success, let observer else { publish([], status: "Native alert connection unavailable"); return }
        self.app = app; self.observer = observer
        for name in [kAXWindowCreatedNotification, kAXLayoutChangedNotification, kAXUIElementDestroyedNotification] {
            AXObserverAddNotification(observer, app, name as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        requestRead()
    }
    private func detach() {
        generation = UUID(); pending = false; pendingUrgent = false
        pendingRead?.cancel(); pendingRead = nil
        clockExpectation = ClockAlertExpectation()
        restoreParked()
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; app = nil; actions.removeAll()
    }
    func stop() {
        menuFeatures.removeAll()
        airPodsBanner.stop()
        focusBanner.stop()
        volumeBanner.stop()
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        workspaceObserver = nil
        // Termination must restore native windows before the process exits.
        queue.sync { enabled.removeAll(); detach() }
        clockActions = []; status = "Off"
    }
    /// Final-second state only changes event priority; it adds no polling.
    func expectClockAlert(identifier: String) {
        queue.async { [weak self] in
            guard let self, self.enabled.contains(.clockTimer) else { return }
            self.clockExpectation.expect(identifier: identifier, now: ProcessInfo.processInfo.systemUptime)
        }
    }
    private func requestRead(urgent: Bool = false) {
        guard app != nil, !enabled.isEmpty else { return }
        guard !pending || (urgent && !pendingUrgent) else { return }
        pendingRead?.cancel()
        pending = true; pendingUrgent = urgent
        let token = generation
        let work = DispatchWorkItem(qos: urgent ? .userInitiated : .utility,
                                    flags: urgent ? .enforceQoS : []) { [weak self] in
            guard let self, self.generation == token else { return }
            self.pending = false; self.pendingUrgent = false; self.pendingRead = nil
            self.read()
        }
        pendingRead = work
        queue.asyncAfter(deadline: .now() + (urgent ? 0 : 0.08), execute: work)
    }
    private func attribute<T>(_ node: AXUIElement, _ key: String) -> T? {
        guard ProcessInfo.processInfo.systemUptime < deadline else { exhausted = true; return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(node, key as CFString, &value) == .success else { return nil }
        return value as? T
    }
    /// One IPC round trip for related attributes keeps the first Clock scan short.
    private func attributes(_ node: AXUIElement, _ keys: [String]) -> [String: Any] {
        guard ProcessInfo.processInfo.systemUptime < deadline else { exhausted = true; return [:] }
        var values: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(node, keys as CFArray, [], &values) == .success,
              let values = values as? [Any] else { return [:] }
        return Dictionary(uniqueKeysWithValues: zip(keys, values))
    }
    private func read() {
        guard let app else { return }
        deadline = ProcessInfo.processInfo.systemUptime + 0.35; exhausted = false
        let windows: [AXUIElement] = attribute(app, kAXWindowsAttribute) ?? []
        var found: [(AXUIElement, AXUIElement)] = []
        var visited = 0
        var otherContent = Set<CFHashCode>()
        func find(_ node: AXUIElement, window: AXUIElement, depth: Int) {
            guard !exhausted else { return }
            guard depth < 9, visited < 100 else { exhausted = true; return }
            visited += 1
            let values = attributes(node, [kAXSubroleAttribute, kAXRoleAttribute, kAXChildrenAttribute])
            let role = values[kAXSubroleAttribute] as? String ?? ""
            if Self.bannerRoles.contains(role) { found.append((node, window)); return }
            let elementRole = values[kAXRoleAttribute] as? String ?? ""
            if [kAXButtonRole, kAXStaticTextRole, kAXImageRole, kAXTextFieldRole].contains(elementRole) {
                otherContent.insert(CFHash(window))
            }
            let children = values[kAXChildrenAttribute] as? [AXUIElement] ?? []
            for child in children { find(child, window: window, depth: depth + 1) }
        }
        for window in windows { find(window, window: window, depth: 0) }
        // macOS can share one host between banners. Restore that host before
        // leaving an unrelated notification or desktop control offscreen.
        for key in Array(parkedHosts) {
            let count = found.filter { CFHash($0.1) == key }.count
            if count != 1 || otherContent.contains(key) || exhausted {
                if let (node, original) = parked.removeValue(forKey: key) {
                    var point = original
                    if let value = AXValueCreate(.cgPoint, &point) { AXUIElementSetAttributeValue(node, kAXPositionAttribute as CFString, value) }
                }
                parkedHosts.remove(key)
            }
        }
        var nextActions: [Action] = []
        var nextTargets: [String: (AXUIElement, String)] = [:]
        var matchedClock = false
        var originalClockDuration: Int?
        var hiddenClock = false
        var airDropResult: String?
        var eligibleParkedNodes = Set<CFHashCode>()
        for (banner, window) in found where !exhausted {
            let attributed: NSAttributedString? = attribute(banner, "AXAttributedDescription")
            let text = attributed?.string ?? (attribute(banner, kAXDescriptionAttribute) as String? ?? "")
            let source = text.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
            // Some system alerts expose their app name and filename as child
            // text values instead of a comma-separated attributed summary.
            let inspectAirDrop = enabled.contains(.airDrop) && ProcessInfo.processInfo.systemUptime < receiptsUntil && source != "clock"
            let details = inspectAirDrop ? bannerLabels(in: banner) : []
            let isAirDrop = source == "airdrop" || details.contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "airdrop" }
            if enabled.contains(.clockTimer), source == "clock" {
                // Source and host isolation are already verified. Hide before
                // traversing controls, which can take several accessibility IPCs.
                // Failed/incomplete control discovery is restored below, so a
                // native alert is never stranded without working replacement actions.
                let hidden = park(banner) || parkDedicatedWindow(window, banners: found, otherContent: otherContent)
                let controls = controls(in: banner, required: ["Stop", "Repeat"])
                let permitted = controls.filter { ["Stop", "Repeat"].contains($0.0) }
                guard permitted.count == 2, Set(permitted.map { $0.0 }) == Set(["Stop", "Repeat"]) else { continue }
                matchedClock = true
                originalClockDuration = text.components(separatedBy: ",").compactMap { ClockReading.durationLabel($0) }.first
                for (title, element, action) in permitted {
                    let id = "\(CFHash(banner))-\(title)"
                    nextActions.append(Action(id: id, title: title)); nextTargets[id] = (element, action)
                }
                eligibleParkedNodes.insert(CFHash(banner))
                eligibleParkedNodes.insert(CFHash(window))
                hiddenClock = hiddenClock || hidden
            } else if enabled.contains(.airDrop), isAirDrop {
                let receiptText = ([text] + details).joined(separator: "\n")
                if ProcessInfo.processInfo.systemUptime < receiptsUntil,
                   receipts.contains(where: { receiptText.localizedCaseInsensitiveContains($0) }) {
                    airDropResult = dismiss(banner) ? "Dismiss action sent to AirDrop" : "AirDrop matched · no working dismiss action"
                } else { airDropResult = "AirDrop found · filename did not match the recent receipt" }
            }
        }
        // A single unrelated banner can replace Clock in the same native host.
        // Restore it too, even though its banner count has not changed.
        for key in Array(parked.keys) where exhausted || !eligibleParkedNodes.contains(key) {
            restoreParked(key)
        }
        if !exhausted {
            actions = nextTargets
            publish(nextActions, status: matchedClock ? (hiddenClock ? "Clock alert replaced" : "Clock controls ready · native banner remains") : airDropResult ?? "Watching matching native alerts", clockDuration: originalClockDuration)
        }
        if ProcessInfo.processInfo.systemUptime < receiptsUntil {
            let result = airDropResult ?? (exhausted ? "Native alert read reached its time limit" : "No accessible AirDrop alert · \(found.count) native banners")
            DispatchQueue.main.async { [weak self] in self?.airDropStatus = result }
        }
    }
    private func bannerLabels(in root: AXUIElement) -> [String] {
        var labels: [String] = []
        var nodes = [root]
        var count = 0
        while let node = nodes.popLast(), count < 35, !exhausted {
            count += 1
            for key in [kAXTitleAttribute, kAXDescriptionAttribute] {
                if let label: String = attribute(node, key), !label.isEmpty { labels.append(label) }
            }
            let role: String = attribute(node, kAXRoleAttribute) ?? ""
            if role == kAXStaticTextRole, let value: String = attribute(node, kAXValueAttribute), !value.isEmpty { labels.append(value) }
            let children: [AXUIElement] = attribute(node, kAXChildrenAttribute) ?? []
            nodes.append(contentsOf: children)
        }
        return labels
    }
    private func controls(in root: AXUIElement, required: Set<String>? = nil) -> [(String, AXUIElement, String)] {
        var result: [(String, AXUIElement, String)] = []
        var nodes = [root]; var count = 0
        while let node = nodes.popLast(), count < 55, !exhausted {
            count += 1
            let values = attributes(node, [kAXRoleAttribute, kAXTitleAttribute, kAXDescriptionAttribute, kAXChildrenAttribute])
            let role = values[kAXRoleAttribute] as? String ?? ""
            let title = values[kAXTitleAttribute] as? String ?? ""
            let description = values[kAXDescriptionAttribute] as? String ?? ""
            if role == kAXButtonRole {
                let label = title.isEmpty ? description : title
                if !label.isEmpty { result.append((label, node, kAXPressAction)) }
            }
            var names: CFArray?
            if ProcessInfo.processInfo.systemUptime < deadline,
               AXUIElementCopyActionNames(node, &names) == .success, let values = names as? [String] {
                for action in values where action != kAXPressAction {
                    var description: CFString?
                    if AXUIElementCopyActionDescription(node, action as CFString, &description) == .success, let description {
                        result.append((description as String, node, action))
                    }
                }
            }
            if let required, required.isSubset(of: Set(result.map { $0.0 })) { break }
            let children = values[kAXChildrenAttribute] as? [AXUIElement] ?? []
            nodes.append(contentsOf: children)
        }
        return result
    }
    @discardableResult private func dismiss(_ banner: AXUIElement) -> Bool {
        let controls = controls(in: banner)
        for control in controls where ["close", "dismiss", "clear"].contains(where: { control.0.lowercased().hasPrefix($0) }) || control.2 == kAXCancelAction {
            if AXUIElementPerformAction(control.1, control.2 as CFString) == .success { return true }
        }
        return false
    }
    private func parkDedicatedWindow(_ window: AXUIElement, banners: [(AXUIElement, AXUIElement)], otherContent: Set<CFHashCode>) -> Bool {
        let key = CFHash(window)
        guard !exhausted, !otherContent.contains(key), banners.filter({ CFEqual($0.1, window) }).count == 1 else { return false }
        // Even a fullscreen NC host is eligible only while its entire accessible
        // content is the one matched Clock alert. A new banner restores it above.
        if park(window) { parkedHosts.insert(key); return true }
        return false
    }
    private func park(_ node: AXUIElement) -> Bool {
        let key = CFHash(node)
        guard let value: AXValue = attribute(node, kAXPositionAttribute), AXValueGetType(value) == .cgPoint else { return false }
        var old = CGPoint.zero; AXValueGetValue(value, .cgPoint, &old)
        if parked[key] != nil, old.x < -90000, old.y < -90000 { return true }
        var point = CGPoint(x: -100000, y: -100000)
        guard let new = AXValueCreate(.cgPoint, &point), AXUIElementSetAttributeValue(node, kAXPositionAttribute as CFString, new) == .success else { return false }
        if parked[key] == nil { parked[key] = (node, old) }
        guard let result: AXValue = attribute(node, kAXPositionAttribute), AXValueGetType(result) == .cgPoint else {
            restoreParked(key); return false
        }
        var actual = CGPoint.zero; AXValueGetValue(result, .cgPoint, &actual)
        guard actual.x < -90000, actual.y < -90000 else { restoreParked(key); return false }
        return true
    }
    private func restoreParked(_ key: CFHashCode) {
        if let (element, old) = parked.removeValue(forKey: key) {
            var point = old
            if let value = AXValueCreate(.cgPoint, &point) { AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) }
        }
        parkedHosts.remove(key)
    }
    private func restoreParked() {
        for (_, (element, old)) in parked {
            var point = old
            if let value = AXValueCreate(.cgPoint, &point) { AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) }
        }
        parked.removeAll(); parkedHosts.removeAll()
    }
    func stopClockAlert() {
        if let action = clockActions.first(where: { $0.title == "Stop" }) { perform(action) }
    }
    func perform(_ action: Action) {
        queue.async { [weak self] in
            guard let self, self.enabled.contains(.clockTimer), let target = self.actions[action.id] else { return }
            AXUIElementPerformAction(target.0, target.1 as CFString)
            self.requestRead()
        }
    }
    private func publish(_ values: [Action], status: String, clockDuration: Int? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.status = status
            self.clockOriginalDuration = clockDuration
            guard self.clockActions != values else { return }
            self.clockActions = values
            self.onClockChange?()
        }
    }
}
