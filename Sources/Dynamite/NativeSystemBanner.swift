import AppKit
import ApplicationServices

/// Observes one exact MenuBarAgent banner identifier after a real system change.
/// App menus and other system-banner types are never eligible.
final class NativeSystemBanner {
    var onStatus: ((String) -> Void)?
    private let queue = DispatchQueue(label: "com.dan.dynomite.system-banner", qos: .userInteractive)
    private var app: AXUIElement?
    private var observer: AXObserver?
    private var workspaceObserver: NSObjectProtocol?
    private var enabled = false
    private var until: TimeInterval = 0
    private var generation = UUID()
    private var pending = false
    private var parked: [CFHashCode: (element: AXUIElement, point: CGPoint)] = [:]
    private static let bundle = "com.apple.MenuBarAgent"
    private let identifier: String
    private let requiresPassiveContent: Bool
    private let watchCreation: Bool
    init(identifier: String, requiresPassiveContent: Bool = true, watchCreation: Bool = false) {
        self.identifier = identifier
        self.requiresPassiveContent = requiresPassiveContent
        self.watchCreation = watchCreation
    }

    func configure(enabled: Bool) {
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundle).first?.processIdentifier
        if workspaceObserver == nil {
            workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      app.bundleIdentifier == Self.bundle else { return }
                self.queue.async { if self.enabled { self.attach(app.processIdentifier) } }
            }
        }
        queue.async { [weak self] in
            guard let self else { return }
            self.enabled = enabled
            if !enabled { self.detach(); self.publish("Off") }
            else if self.app == nil, let pid { self.attach(pid); self.publish("Watching native popup") }
        }
    }
    func connected() {
        queue.async { [weak self] in
            guard let self, self.enabled else { return }
            // Bluetooth, audio routing and settled battery data can describe
            // the same connection. Don't multiply the short retry burst.
            if self.until - ProcessInfo.processInfo.systemUptime > 19 {
                self.requestRead()
                return
            }
            self.until = ProcessInfo.processInfo.systemUptime + 20
            self.publish("Checking native popup")
            let token = self.generation
            self.requestRead()
            // A bounded post-connection burst catches a delayed native banner.
            // There is no timer, AX traversal, or window scan while idle.
            for delay in [0.06, 0.2, 0.6, 1.2, 2.5, 4.5, 20.1] {
                self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.generation == token, self.enabled else { return }
                    self.requestRead()
                }
            }
        }
    }
    private func attach(_ pid: pid_t) {
        detach()
        guard enabled, AXIsProcessTrusted() else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.02)
        var observer: AXObserver?
        guard AXObserverCreate(pid, { _, element, notification, context in
            guard let context else { return }
            let owner = Unmanaged<NativeSystemBanner>.fromOpaque(context).takeUnretainedValue()
            let created = notification as String == kAXWindowCreatedNotification
            let destroyed = notification as String == kAXUIElementDestroyedNotification
            owner.queue.async {
                guard owner.enabled else { return }
                if destroyed { owner.forget(CFHash(element)) }
                else if owner.parked[CFHash(element)] != nil {
                    // Movement can arrive before the application's window list
                    // catches up, especially when changing displays.
                    owner.refreshParked(element, deadline: ProcessInfo.processInfo.systemUptime + 0.12)
                }
                if created && owner.watchCreation { owner.created(element) }
                guard ProcessInfo.processInfo.systemUptime < owner.until || !owner.parked.isEmpty else { return }
                owner.requestRead()
            }
        }, &observer) == .success, let observer else { return }
        self.app = app; self.observer = observer
        for name in [kAXWindowCreatedNotification, kAXLayoutChangedNotification, kAXUIElementDestroyedNotification] {
            AXObserverAddNotification(observer, app, name as CFString, Unmanaged.passUnretained(self).toOpaque())
        }
        CFRunLoopAddSource(NativeBannerEventLoop.shared.runLoop, AXObserverGetRunLoopSource(observer), .commonModes)
    }
    private func created(_ window: AXUIElement) {
        guard let identifier: String = attribute(window, kAXIdentifierAttribute), identifier == self.identifier else { return }
        until = ProcessInfo.processInfo.systemUptime + 20
        guard !requiresPassiveContent || passiveContent(window, deadline: ProcessInfo.processInfo.systemUptime + 0.12) == .passive else { return }
        if park(window) { publish("Native popup hidden") }
    }
    private func detach() {
        for key in Array(parked.keys) { restore(key) }
        if let observer { CFRunLoopRemoveSource(NativeBannerEventLoop.shared.runLoop, AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; app = nil; until = 0; pending = false; generation = UUID()
    }
    func stop() {
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        workspaceObserver = nil
        queue.sync { enabled = false; detach() }
    }
    private func requestRead() {
        guard app != nil, !pending else { return }
        pending = true
        let token = generation
        queue.async { [weak self] in
            guard let self, self.generation == token else { return }
            self.pending = false
            self.read()
        }
    }
    private func attribute<T>(_ node: AXUIElement, _ key: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(node, key as CFString, &value) == .success else { return nil }
        return value as? T
    }
    private func read() {
        guard let app else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // The connection window can arrive late, and Apple can refresh its
        // timeout. Eligibility expiry must not resurrect an already hidden card.
        guard now < until || !parked.isEmpty else { return }
        let deadline = now + 0.12
        // Keep known windows hidden before scanning unrelated menu-bar windows.
        // An empty/late AXWindows reply is not proof that a banner was closed.
        for entry in Array(parked.values) where ProcessInfo.processInfo.systemUptime < deadline {
            refreshParked(entry.element, deadline: deadline)
        }
        guard let windows: [AXUIElement] = attribute(app, kAXWindowsAttribute) else { return }
        for window in windows.prefix(20) where ProcessInfo.processInfo.systemUptime < deadline {
            guard let identifier: String = attribute(window, kAXIdentifierAttribute), identifier == self.identifier else { continue }
            let key = CFHash(window)
            guard parked[key] == nil else { continue }
            guard now < until || parked[key] != nil else { continue }
            // Don't hide an actionable Smart Routing suggestion or error. The
            // verified Connected card contains only static text and an image.
            guard !requiresPassiveContent || passiveContent(window, deadline: deadline) == .passive else { continue }
            if park(window) { publish("Native popup hidden") }
            else { publish("Popup found · macOS refused positioning") }
        }
    }
    private func refreshParked(_ window: AXUIElement, deadline: TimeInterval) {
        let key = CFHash(window)
        var raw: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXIdentifierAttribute as CFString, &raw)
        if result == .invalidUIElement { forget(key); return }
        // Timeouts and unfinished AX updates must not undo a successful hide.
        guard result == .success, let current = raw as? String else { return }
        guard current == identifier else { restore(key); return }
        if requiresPassiveContent {
            switch passiveContent(window, deadline: deadline) {
            case .actionable: restore(key); return
            case .unavailable: return
            case .passive: break
            }
        }
        if park(window) { publish("Native popup hidden") }
    }
    private enum Content { case passive, actionable, unavailable }
    private func passiveContent(_ window: AXUIElement, deadline: TimeInterval) -> Content {
        var nodes = [window]
        var count = 0
        var hasText = false
        while let node = nodes.popLast() {
            guard count < 30, ProcessInfo.processInfo.systemUptime < deadline else { return .unavailable }
            count += 1
            var raw: CFArray?
            let keys = [kAXRoleAttribute, kAXChildrenAttribute, kAXValueAttribute]
            guard AXUIElementCopyMultipleAttributeValues(node, keys as CFArray, [], &raw) == .success,
                  let values = raw as? [Any], values.count == 3 else { return .unavailable }
            let role = values[0] as? String ?? ""
            if [kAXButtonRole, kAXCheckBoxRole, kAXRadioButtonRole, kAXTextFieldRole, kAXMenuRole].contains(role) { return .actionable }
            if role == kAXStaticTextRole, let text = values[2] as? String, !text.isEmpty { hasText = true }
            nodes.append(contentsOf: values[1] as? [AXUIElement] ?? [])
        }
        return hasText ? .passive : .unavailable
    }
    private func position(_ node: AXUIElement) -> CGPoint? {
        guard let value: AXValue = attribute(node, kAXPositionAttribute), AXValueGetType(value) == .cgPoint else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }
    private func park(_ node: AXUIElement) -> Bool {
        let key = CFHash(node)
        guard let old = position(node) else { return false }
        if parked[key] != nil, old.x < -90000, old.y < -90000 { return true }
        var point = CGPoint(x: -100000, y: -100000)
        guard let value = AXValueCreate(.cgPoint, &point),
              AXUIElementSetAttributeValue(node, kAXPositionAttribute as CFString, value) == .success else { return false }
        if parked[key] == nil {
            parked[key] = (node, old)
            if let observer {
                for name in [kAXMovedNotification, kAXResizedNotification, kAXLayoutChangedNotification, kAXUIElementDestroyedNotification] {
                    AXObserverAddNotification(observer, node, name as CFString, Unmanaged.passUnretained(self).toOpaque())
                }
            }
        }
        // A readback timeout doesn't mean the write failed. Retain ownership so
        // the next event can verify/reapply it without bringing the card back.
        guard let result = position(node), result.x < -90000, result.y < -90000 else { return false }
        return true
    }
    private func forget(_ key: CFHashCode) {
        guard let entry = parked.removeValue(forKey: key) else { return }
        removeNotifications(entry.element)
    }
    private func removeNotifications(_ element: AXUIElement) {
        guard let observer else { return }
        for name in [kAXMovedNotification, kAXResizedNotification, kAXLayoutChangedNotification, kAXUIElementDestroyedNotification] {
            AXObserverRemoveNotification(observer, element, name as CFString)
        }
    }
    private func restore(_ key: CFHashCode) {
        guard let entry = parked.removeValue(forKey: key) else { return }
        removeNotifications(entry.element)
        var point = entry.point
        if let value = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(entry.element, kAXPositionAttribute as CFString, value)
        }
    }
    private var lastStatus = ""
    private func publish(_ status: String) {
        guard lastStatus != status else { return }
        lastStatus = status
        DispatchQueue.main.async { [weak self] in self?.onStatus?(status) }
    }
}
