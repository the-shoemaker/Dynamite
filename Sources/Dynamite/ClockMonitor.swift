import AppKit
import ApplicationServices
import Combine
import IslandCore

/// Reads only Clock's timer UI on a serial utility queue. No log streaming,
/// privileged daemon connection, or main-thread Accessibility requests.
final class ClockMonitor: ObservableObject {
    @Published private(set) var status = "Off"
    @Published private(set) var reading: ClockReading?
    @Published private(set) var finishedDuration: Int?
    var onChange: ((ClockReading?) -> Void)?
    private let queue = DispatchQueue(label: "com.dan.dynomite.clock", qos: .utility)
    private lazy var store = ClockTimerStore(queue: queue)
    private var running = false
    private var processID: pid_t?
    private var timer: DispatchSourceTimer?
    private var observer: AXObserver?
    private var last: ClockReading?
    private var continuity = ClockContinuity()
    private var pollInterval: TimeInterval?
    private var pollDeadline: Date?
    private var observedWindows: [AXUIElement] = []
    private var generation = UUID()
    private var originalDurations: [String: Int] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var readPending = false
    private var preferencesRefreshPending = false
    private struct TimerNodes {
        let identifier: String
        let selected: AXUIElement
        let time: AXUIElement
        let pause: AXUIElement
        let cancel: AXUIElement?
    }
    private var cachedNodes: TimerNodes?
    private var cachedStart: AXUIElement?
    private var clockForeground = false

    func start() {
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification, NSWorkspace.didActivateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      (app.bundleIdentifier == "com.apple.clock" || name == NSWorkspace.didActivateApplicationNotification) else { return }
                self?.connect()
            })
        }
        queue.async { [weak self] in
            guard let self else { return }
            self.running = true
            self.store.onChange = { [weak self] in self?.requestRead() }
            self.store.start()
        }
        connect()
    }
    func stop() {
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        queue.async { [weak self] in
            guard let self else { return }
            self.running = false
            self.store.stop()
            self.disconnect()
            self.publish(nil, status: "Off")
        }
    }
    func refresh() { connect() }
    private func connect() {
        let foreground = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.clock"
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.clock").first?.processIdentifier
        queue.async { [weak self] in
            guard let self, self.running else { return }
            self.clockForeground = foreground
            if self.processID != pid || (self.observer == nil && AXIsProcessTrusted()) {
                self.disconnect()
                self.processID = pid
                if let pid, AXIsProcessTrusted() {
                    var observation: AXObserver?
                    let result = AXObserverCreate(pid, { _, _, _, context in
                        guard let context else { return }
                        Unmanaged<ClockMonitor>.fromOpaque(context).takeUnretainedValue().requestRead(refreshPreferences: true)
                    }, &observation)
                    if result == .success, let observation {
                        self.observer = observation
                        let app = AXUIElementCreateApplication(pid)
                        AXUIElementSetMessagingTimeout(app, 0.05)
                        for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXFocusedUIElementChangedNotification, kAXLayoutChangedNotification, kAXValueChangedNotification] {
                            AXObserverAddNotification(observation, app, name as CFString, Unmanaged.passUnretained(self).toOpaque())
                        }
                        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observation), .commonModes)
                    }
                }
            }
            self.refreshWindowObservations()
            self.store.reload()
            self.read()
        }
    }
    private func disconnect() {
        generation = UUID(); readPending = false; preferencesRefreshPending = false
        timer?.cancel(); timer = nil; pollInterval = nil; pollDeadline = nil
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; observedWindows.removeAll(); processID = nil; last = nil; continuity = ClockContinuity(); cachedNodes = nil; cachedStart = nil
    }
    private func requestRead(refreshPreferences: Bool = false) {
        queue.async { [weak self] in
            guard let self, self.running else { return }
            self.preferencesRefreshPending = self.preferencesRefreshPending || refreshPreferences
            guard !self.readPending else { return }
            self.readPending = true
            let token = self.generation
            self.queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self, self.generation == token else { return }
                self.readPending = false
                if self.preferencesRefreshPending {
                    self.refreshWindowObservations()
                    self.store.reload()
                    self.preferencesRefreshPending = false
                }
                self.read()
            }
        }
    }
    private func read() {
        guard running else { return }
        // Preferences can trail Clock's own UI by several seconds. While Clock
        // is foreground, read cached timer controls directly. No UI polling is
        // added while another app is active or Clock's window is closed.
        if clockForeground, let pid = processID, AXIsProcessTrusted() {
            let live = sample(pid)
            if live.reading != nil || live.idle {
                publish(live.reading, status: live.idle ? "Waiting for a Clock timer" : "Mirroring Clock")
                setPolling(0.25)
                return
            }
        }
        if let records = store.records {
            let now = Date()
            let eligible = records.filter { $0.deadline.map { $0.timeIntervalSince(now) > -3 } ?? true }
            let record = eligible.first(where: { $0.identifier == last?.identifier }) ?? eligible.sorted {
                if ($0.deadline != nil) != ($1.deadline != nil) { return $0.deadline != nil }
                return ($0.deadline ?? .distantFuture) < ($1.deadline ?? .distantFuture)
            }.first
            if let record { originalDurations[record.identifier] = record.duration }
            publish(record?.reading(at: now), status: record == nil ? "Waiting for a Clock timer" : "Mirroring Clock")
            // A paused deadline needs no ticker: the file watcher reports resume.
            setPolling(record?.deadline != nil ? 1 : nil, phase: record?.deadline)
            return
        }
        guard AXIsProcessTrusted() else { publish(nil, status: "Needs Accessibility"); return }
        guard let pid = processID else { publish(nil, status: "Open Clock’s Timers page"); return }
        let result = sample(pid)
        let current = continuity.resolve(result.reading, idle: result.idle, now: Date.timeIntervalSinceReferenceDate)
        publish(current, status: current == nil ? "Open Clock’s Timers page" : result.reading == nil ? "Following timer with Clock’s window closed" : "Mirroring Clock")
        let interval: TimeInterval? = current.map { $0.paused || result.reading == nil ? 1 : 0.2 }
        setPolling(interval)
    }
    private func setPolling(_ interval: TimeInterval?, phase: Date? = nil) {
        if interval != pollInterval || phase != pollDeadline {
            timer?.cancel(); timer = nil; pollInterval = interval; pollDeadline = phase
            if let interval {
                let ticker = DispatchSource.makeTimerSource(queue: queue)
                // Align displayed seconds with Clock's actual deadline rather
                // than letting a one-second poll drift behind its digit change.
                let remaining = phase?.timeIntervalSinceNow
                let delay = remaining.map { max(0.02, $0 - floor($0) + 0.005) } ?? interval
                ticker.schedule(deadline: .now() + delay, repeating: interval, leeway: .milliseconds(20))
                ticker.setEventHandler { [weak self] in self?.read() }
                timer = ticker; ticker.resume()
            }
        }
    }

    private func publish(_ value: ClockReading?, status: String) {
        let completedDuration = (value?.remaining ?? last?.remaining).flatMap { remaining in
            remaining <= 1 ? (value?.identifier ?? last?.identifier).flatMap { originalDurations[$0] } : nil
        }
        let newTimer = value != nil && value?.identifier != last?.identifier
        last = value
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if self.status != status { self.status = status }
            if let completedDuration, self.finishedDuration != completedDuration { self.finishedDuration = completedDuration }
            else if newTimer { self.finishedDuration = nil }
            guard self.reading != value else { return }
            self.reading = value
            self.onChange?(value)
        }
    }
    func openClock() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.clock") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    func reconnectAfterRepeat() {
        queue.async { [weak self] in
            guard let self, self.running else { return }
            let token = self.generation
            // Repeat updates the service mirror, even with Clock closed.
            // Reconcile after the action in addition to the file notification.
            for delay in [0.2, 0.6, 1.2] {
                self.queue.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.store.reload()
                    self.cachedNodes = nil
                    self.cachedStart = nil
                    self.read()
                }
            }
        }
    }
    private func openControlsInBackground() {
        DispatchQueue.main.async {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.clock") else { return }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
    }
    func togglePause() {
        perform(cancel: false)
    }
    func cancel() { perform(cancel: true) }
    private func perform(cancel: Bool) {
        queue.async { [weak self] in
            guard let self, self.running, let last = self.last else { return }
            self.perform(cancel: cancel, identifier: last.identifier, attempt: 0)
        }
    }
    private func perform(cancel: Bool, identifier: String, attempt: Int) {
        guard running, let pid = processID, last?.identifier == identifier else { return }
        // Clock replaces its SwiftUI controls after start/repeat and selection.
        // Resolve a fresh button for this exact timer before every action.
        cachedNodes = nil
        let current = sample(pid)
        if current.reading?.identifier == identifier,
           let button = cancel ? current.cancel : current.pause {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
            requestRead(refreshPreferences: true)
            return
        }
        guard attempt < 4 else { return }
        if attempt == 0 {
            // Recreate Clock's controls without switching the user's active app.
            openControlsInBackground()
        }
        let token = generation
        queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.generation == token else { return }
            self.perform(cancel: cancel, identifier: identifier, attempt: attempt + 1)
        }
    }
    private func refreshWindowObservations() {
        guard let pid = processID, observer != nil else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.025)
        let windows: [AXUIElement] = attribute(app, kAXWindowsAttribute) ?? []
        observeWindows(windows)
    }
    private func observeWindows(_ windows: [AXUIElement]) {
        guard let observer else { return }
        let notifications = [kAXLayoutChangedNotification, kAXValueChangedNotification, kAXSelectedChildrenChangedNotification, kAXTitleChangedNotification]
        for old in observedWindows where !windows.contains(where: { CFEqual($0, old) }) {
            for name in notifications { AXObserverRemoveNotification(observer, old, name as CFString) }
        }
        for window in windows where !observedWindows.contains(where: { CFEqual($0, window) }) {
            for name in notifications {
                AXObserverAddNotification(observer, window, name as CFString, Unmanaged.passUnretained(self).toOpaque())
            }
        }
        observedWindows = windows
    }
    private func attribute<T>(_ node: AXUIElement, _ name: String) -> T? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(node, name as CFString, &result) == .success else { return nil }
        return result as? T
    }
    private func sample(_ pid: pid_t) -> (reading: ClockReading?, pause: AXUIElement?, cancel: AXUIElement?, idle: Bool) {
        if let cachedStart, (attribute(cachedStart, kAXDescriptionAttribute) as String?) == "Start" {
            return (nil, nil, nil, true)
        }
        cachedStart = nil
        if let cached = cachedNodes,
           (attribute(cached.selected, kAXSelectedAttribute) as Bool?) == true,
           let time: String = attribute(cached.time, kAXDescriptionAttribute),
           let remaining = ClockReading.seconds(time),
           let state: String = attribute(cached.pause, kAXDescriptionAttribute),
           ["Pause", "Resume"].contains(state) {
            return (ClockReading(identifier: cached.identifier, remaining: remaining, paused: state == "Resume"), cached.pause, cached.cancel, false)
        }
        cachedNodes = nil
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.025)
        let windows: [AXUIElement] = attribute(app, kAXWindowsAttribute) ?? []
        observeWindows(windows)
        let deadline = ProcessInfo.processInfo.systemUptime + 0.35
        var nodes = windows
        var visited = 0
        var identifier: String?
        var seconds: Int?
        var timeNode: AXUIElement?
        var selectedNode: AXUIElement?
        var paused: Bool?
        var pauseButton: AXUIElement?
        var cancelButton: AXUIElement?
        var showsStart = false
        while let node = nodes.popLast(), visited < 180, ProcessInfo.processInfo.systemUptime < deadline {
            visited += 1
            let id: String = attribute(node, kAXIdentifierAttribute) ?? ""
            let description: String = attribute(node, kAXDescriptionAttribute) ?? attribute(node, kAXTitleAttribute) ?? ""
            if id == "PauseResumeButton" {
                if description == "Start" { showsStart = true; cachedStart = node }
                if description == "Resume" { paused = true }
                if description == "Pause" { paused = false }
                pauseButton = node
            }
            if id == "CancelButton" { cancelButton = node }
            if let time = ClockReading.seconds(description) { seconds = time; timeNode = node }
            if UUID(uuidString: id) != nil, (attribute(node, kAXSelectedAttribute) as Bool?) == true {
                identifier = id; selectedNode = node
                if let comma = description.firstIndex(of: ","),
                   let duration = ClockReading.durationLabel(String(description[description.index(after: comma)...])) {
                    if originalDurations.count > 64 { originalDurations.removeAll() }
                    originalDurations[id] = duration
                }
            }
            let children: [AXUIElement] = attribute(node, kAXChildrenAttribute) ?? []
            nodes.append(contentsOf: children)
        }
        guard let seconds, let paused, let identifier else { return (nil, nil, nil, showsStart) }
        if let timeNode, let selectedNode, let pauseButton {
            cachedNodes = TimerNodes(identifier: identifier, selected: selectedNode, time: timeNode, pause: pauseButton, cancel: cancelButton)
        }
        return (ClockReading(identifier: identifier, remaining: seconds, paused: paused), pauseButton, cancelButton, false)
    }
}
