import AppKit
import Combine
import IslandCore
import MacAppUpdates

final class AppModel: ObservableObject {
    let settings = SettingsStore()
    let mediaKeys = MediaKeyMonitor()
    let island = IslandCoordinator()
    let loginItem = LoginItemController()
    let updater = NativeUpdater()
    let wireless = WirelessMonitor()
    let bluetooth = BluetoothMonitor()
    let microphone = MicrophoneMonitor()
    let clock = ClockMonitor()
    let nativeNotifications = NativeActivityNotifications()
    let focus = FocusMonitor()
    let airDrop = AirDropMonitor()
    private var airDropActivity: Activity?
    private var clockActivity: Activity?
    private var timerVisibility = TimerVisibility()
    private var finishHandoff = TimerFinishHandoff()
    private var finishHandoffWork: DispatchWorkItem?
    private var finishHandoffDeadline: TimeInterval?
    private var hadClockAlert = false
    private var pausedTimerWork: DispatchWorkItem?
    private var pausedTimerDeadline: TimeInterval?
    private let hardwareQueue = DispatchQueue(label: "com.dan.dynomite.hardware", qos: .userInitiated)
    private let audio = AudioController()
    private let brightness = BrightnessController()
    private let shades = DisplayShadeController()
    private let battery = BatteryMonitor()
    private let capsLock = CapsLockMonitor()
    private var schedule = ActivitySchedule()
    private var capsLockActive = false
    private var capsLockRunning = false
    private var transitions = BatteryTransitions()
    private var subscriptions = Set<AnyCancellable>()
    private var observations: [NSObjectProtocol] = []
    private var batteryRunning = false
    private var sleeping = false
    private var acceptsShadeUpdates = false
    private var displayIDs: [UInt32] = []
    private var previousPlacement: DisplayPlacement?
    @Published private(set) var hasInternalBattery = BatteryMonitor.hasInternalBattery() ?? true
    @Published private(set) var batteryPercent: Int?

    func start() {
        displayIDs = NSScreen.screens.compactMap { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 }
        brightness.onSoftwareBrightness = { [weak self] id, value in
            DispatchQueue.main.async {
                guard let self, self.acceptsShadeUpdates else { return }
                self.shades.set(value, displayID: id)
            }
        }
        bluetooth.onConnect = { [weak self] activity in
            self?.show(activity)

        }
        bluetooth.onAirPodsReady = { [weak self] in self?.nativeNotifications.airPodsConnected() }
        wireless.onConnect = { [weak self] activity in self?.show(activity) }
        microphone.onChange = { [weak self] activity in self?.show(activity) }
        brightness.onSettled = { [weak self] activity in
            DispatchQueue.main.async { self?.island.updateVisibleActivity(activity) }
        }
        island.airDrop = airDrop
        island.clock = clock
        island.nativeNotifications = nativeNotifications
        nativeNotifications.onClockChange = { [weak self] in self?.updateCapsLock() }
        island.onClockHoverChanged = { [weak self] in self?.updateCapsLock() }
        airDrop.onChange = { [weak self] transfer in
            guard let self else { return }
            self.nativeNotifications.receivedFiles(transfer?.urls ?? [])
            self.airDropActivity = transfer.map { _ in Activity(.airDrop, value: 100, label: "Received") }
            self.updateCapsLock()
        }
        focus.onChange = { [weak self] activity in
            self?.nativeNotifications.focusChanged()
            self?.show(activity)
        }
        focus.onAvailability = { [weak self] in self?.nativeNotifications.focusAvailability($0) }
        audio.onAvailability = { [weak self] available in
            DispatchQueue.main.async { [weak self] in self?.nativeNotifications.volumeAvailability(available) }
        }
        audio.onChange = { [weak self] activity in
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.settings.preferences.paused,
                      self.settings.preferences.preference(for: .volume).enabled else { return }
                self.nativeNotifications.volumeChanged()
                self.show(activity)
            }
        }
        clock.onChange = { [weak self] reading in
            guard let self else { return }
            self.clockActivity = reading.map { Activity(.clockTimer, value: 0, label: "Timer",
                symbol: $0.paused ? "play.fill" : "pause.fill", isActive: !$0.paused, remainingSeconds: $0.remaining) }
            self.updateCapsLock()
        }
        updater.start()
        island.onTemporaryExpired = { [weak self] in self?.temporaryExpired() }
        capsLock.onChange = { [weak self] active in
            guard let self else { return }
            self.capsLockActive = active
            if !active, self.schedule.temporary?.feature == .capsLock { self.schedule.remove(.capsLock) }
            self.updateCapsLock()
        }
        capsLock.onUserToggle = { [weak self] active in
            guard let self, active, self.schedule.persistent?.feature == .clockTimer else { return }
            self.show(.preview(.capsLock))
        }
        mediaKeys.handle = { [weak self] key, fine, completion in
            guard let self else { completion(false); return }
            let preferences = self.settings.preferences
            guard !preferences.paused, preferences.preference(for: key.feature).enabled else { completion(false); return }
            let screen = IslandController.pointerScreen()
            let displayID = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
            let showVividBoost = key.feature == .brightness && preferences.vividCompatibility &&
                screen.map(VividBridge.supports) == true
            self.hardwareQueue.async { [weak self] in
                guard let self else { completion(false); return }
                let activity = key.feature == .volume ? self.audio.adjust(key, fine: fine) :
                    self.brightness.adjust(key, fine: fine, displayID: displayID, vivid: showVividBoost,
                                           smooth: preferences.smoothBrightness, queue: self.hardwareQueue)
                completion(activity != nil)
                if let activity {
                    DispatchQueue.main.async { [weak self] in self?.show(activity) }
                }
            }
        }
        battery.onChange = { [weak self] snapshot in
            guard let self else { return }
            self.batteryPercent = snapshot.percent
            let activities = self.transitions.consume(snapshot, preferences: self.settings.preferences)
            // A target/low warning takes precedence over a simultaneous connection message.
            if let activity = activities.last { self.show(activity) }
        }
        settings.$preferences.removeDuplicates(by: { old, new in
            old.paused == new.paused && old.placement == new.placement &&
            Feature.allCases.allSatisfy { old.preference(for: $0).enabled == new.preference(for: $0).enabled }
        }).dropFirst().sink { [weak self] preferences in
            // @Published emits before assignment. Reconcile after the store has changed.
            DispatchQueue.main.async { self?.reconcile(preferences) }
        }.store(in: &subscriptions)
        settings.$preferences.map { preferences in
            Feature.allCases.map { preferences.preference(for: $0).duration }
        }.removeDuplicates().dropFirst().debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.restartChangedDuration() }.store(in: &subscriptions)
        observations.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in self?.reconcile(self?.settings.preferences ?? Preferences()) })
        observations.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                let ids = NSScreen.screens.compactMap { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 }
                if self?.displayIDs != ids {
                    self?.displayIDs = ids
                    self?.shades.clear()
                    self?.hardwareQueue.async { [weak self] in self?.brightness.displaysChanged() }
                }
                self?.island.screenParametersChanged()
                self?.updateCapsLock()
            })
        observations.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.sleeping = true
                self?.acceptsShadeUpdates = false
                self?.shades.clear()
                self?.schedule.reset()
                self?.island.hide(immediately: true)
                self?.wireless.stop()
                self?.bluetooth.stop()
                self?.microphone.stop()
                self?.clock.stop()
                self?.nativeNotifications.configure([])
                self?.focus.stop()
                self?.airDrop.stop()
                self?.airDropActivity = nil
                self?.hardwareQueue.async { [weak self] in self?.brightness.cancelRamps() }
            })
        observations.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.sleeping = false
                self?.transitions.reset(to: nil)
                self?.battery.read()
                self?.capsLock.refresh()
                self?.wireless.resetBaseline()
                self?.reconcile(self?.settings.preferences ?? Preferences())
            })
        reconcile(settings.preferences)
    }
    func refreshConnections() {
        reconcile(settings.preferences)
        wireless.refresh()
        loginItem.refresh()
        clock.refresh()
        if settings.preferences.preference(for: .focus).enabled && !settings.preferences.paused { focus.refresh() }
    }
    private func reconcile(_ preferences: Preferences) {
        if !sleeping && !preferences.paused && preferences.preference(for: .microphoneMute).enabled { microphone.start() }
        else { microphone.stop() }
        nativeNotifications.configure(Set([Feature.clockTimer, .airDrop, .airPods, .focus, .volume].filter {
            !sleeping && !preferences.paused && preferences.preference(for: $0).enabled
        }))
        let watchVolume = !sleeping && !preferences.paused && preferences.preference(for: .volume).enabled
        hardwareQueue.async { [weak self] in
            guard let self else { return }
            if watchVolume { self.audio.startMonitoring(on: self.hardwareQueue) }
            else { self.audio.stopMonitoring() }
        }
        if !sleeping && !preferences.paused && preferences.preference(for: .airDrop).enabled { airDrop.start() }
        else { airDrop.stop(); airDropActivity = nil }
        if !sleeping && !preferences.paused && preferences.preference(for: .clockTimer).enabled { clock.start() }
        else { clock.stop(); clockActivity = nil }
        if !sleeping && !preferences.paused && preferences.preference(for: .focus).enabled { focus.start() }
        else { focus.stop() }
        acceptsShadeUpdates = !sleeping && !preferences.paused && preferences.preference(for: .brightness).enabled
        if !preferences.paused && (preferences.preference(for: .hotspot).enabled || preferences.preference(for: .wifi).enabled) { wireless.start() }
        else { wireless.stop() }
        bluetooth.airPodsEnabled = preferences.preference(for: .airPods).enabled
        if !preferences.paused && (preferences.preference(for: .bluetooth).enabled || bluetooth.airPodsEnabled) { bluetooth.start() }
        else { bluetooth.stop() }
        if preferences.paused || !preferences.preference(for: .brightness).enabled {
            shades.clear()
            hardwareQueue.async { [weak self] in self?.brightness.cancelRamps() }
        }
        mediaKeys.configure(volume: !preferences.paused && preferences.preference(for: .volume).enabled,
                            brightness: !preferences.paused && preferences.preference(for: .brightness).enabled)
        if preferences.paused || (!preferences.preference(for: .volume).enabled && !preferences.preference(for: .brightness).enabled) {
            mediaKeys.stop()
        } else { mediaKeys.start() }
        let needsBattery = !preferences.paused && [Feature.charging, .powerDisconnected, .chargeTarget, .lowBattery, .lowPowerMode].contains {
            preferences.preference(for: $0).enabled
        }
        if needsBattery && !batteryRunning {
            transitions.reset(to: nil)
            batteryRunning = true
            battery.start()
        } else if !needsBattery && batteryRunning {
            battery.stop()
            batteryRunning = false
            transitions.reset(to: nil)
        }
        let disabledCurrent = island.currentFeature.map { !preferences.preference(for: $0).enabled } ?? false
        for feature in Feature.allCases where !preferences.preference(for: feature).enabled { schedule.remove(feature) }
        if preferences.paused || disabledCurrent || (previousPlacement != nil && previousPlacement != preferences.placement) {
            island.hide(immediately: true)
            schedule.reset()
        }
        previousPlacement = preferences.placement
        let needsCapsLock = !preferences.paused && preferences.preference(for: .capsLock).enabled
        if needsCapsLock {
            capsLockRunning = true
            capsLock.start()
        } else if capsLockRunning {
            capsLock.stop()
            capsLockRunning = false
        }
        updateCapsLock()
    }
    func show(_ activity: Activity) {
        let preferences = settings.preferences
        guard !preferences.paused, preferences.preference(for: activity.feature).enabled else { return }
        guard !finishHandoff.isImminent(at: ProcessInfo.processInfo.systemUptime) else { return }
        let duration = preferences.preference(for: activity.feature).duration
        schedule.present(activity, duration: duration, now: ProcessInfo.processInfo.systemUptime)
        island.show(activity, duration: duration, placement: preferences.placement)
    }
    private func restartChangedDuration() {
        updateCapsLock()
        guard let activity = island.currentActivity, schedule.temporary?.feature == activity.feature,
              let duration = island.currentDuration,
              settings.preferences.preference(for: activity.feature).duration != duration else { return }
        let newDuration = settings.preferences.preference(for: activity.feature).duration
        schedule.present(activity, duration: newDuration, now: ProcessInfo.processInfo.systemUptime)
        island.restart(duration: newDuration)
    }
    private func updateCapsLock() {
        let preferences = settings.preferences
        let active = capsLockActive && !preferences.paused && preferences.preference(for: .capsLock).enabled
        let now = ProcessInfo.processInfo.systemUptime
        let clockEnabled = !sleeping && !preferences.paused && preferences.preference(for: .clockTimer).enabled
        timerVisibility.update(identifier: clockEnabled ? clock.reading?.identifier : nil,
            running: clockActivity?.isActive == true, hovered: island.clockHovered,
            duration: preferences.preference(for: .clockTimer).duration, now: now)
        let deadline = timerVisibility.deadline.flatMap { $0 > now ? $0 : nil }
        if pausedTimerDeadline != deadline {
            pausedTimerWork?.cancel()
            pausedTimerWork = nil
            pausedTimerDeadline = deadline
            if let deadline {
                let work = DispatchWorkItem { [weak self] in self?.updateCapsLock() }
                pausedTimerWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - now), execute: work)
            }
        }
        let timerVisible = timerVisibility.isVisible(at: now)
        let hasAlert = clockEnabled && !nativeNotifications.clockActions.isEmpty
        if clockEnabled, let reading = clock.reading, !reading.paused, reading.remaining <= 1 {
            nativeNotifications.expectClockAlert(identifier: reading.identifier)
        }
        finishHandoff.update(identifier: clockEnabled ? clock.reading?.identifier : nil,
            remaining: clock.reading?.remaining, running: clockEnabled && clockActivity?.isActive == true && !hasAlert, now: now)
        if finishHandoff.deadline != finishHandoffDeadline {
            finishHandoffWork?.cancel(); finishHandoffWork = nil
            finishHandoffDeadline = finishHandoff.deadline
            if let deadline = finishHandoffDeadline {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.finishHandoff.isImminent(at: ProcessInfo.processInfo.systemUptime) else { return }
                    self.finishHandoffWork = nil
                    self.temporaryExpired()
                }
                finishHandoffWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline - now), execute: work)
            }
        }
        // A delayed/native finish notification still wins over an older alert.
        // Later alerts are allowed alongside the already-expanded card.
        if hasAlert && !hadClockAlert { temporaryExpired() }
        hadClockAlert = hasAlert
        let timer = hasAlert ? Activity(.clockTimer, value: 0, label: "Timer finished", remainingSeconds: 0) :
            (clockEnabled && timerVisible ? clockActivity : nil)
        let transfer = !preferences.paused && preferences.preference(for: .airDrop).enabled ? airDropActivity : nil
        schedule.setPersistent(transfer ?? timer ?? (active ? .preview(.capsLock) : nil))
        island.setPersistent(schedule.persistent)
        if schedule.temporary == nil { island.endTemporary() }
    }
    private func temporaryExpired() {
        schedule.expire(at: max(ProcessInfo.processInfo.systemUptime, schedule.expiresAt ?? 0))
        island.endTemporary()
    }

    func preview(_ feature: Feature, notch: Bool? = nil) {
        let activity = Activity.preview(feature, preferences: settings.preferences)
        schedule.present(activity, duration: settings.preferences.preference(for: feature).duration,
                         now: ProcessInfo.processInfo.systemUptime)
        island.show(activity, duration: settings.preferences.preference(for: feature).duration,
                    placement: settings.preferences.placement, previewNotch: notch)
    }
    func stop() {
        finishHandoffWork?.cancel(); finishHandoffWork = nil
        finishHandoffDeadline = nil; finishHandoff = TimerFinishHandoff(); hadClockAlert = false
        pausedTimerWork?.cancel()
        pausedTimerWork = nil
        pausedTimerDeadline = nil
        timerVisibility = TimerVisibility()
        acceptsShadeUpdates = false
        settings.flush()
        shades.clear()
        wireless.stop()
        bluetooth.stop()
        hardwareQueue.async { [weak self] in self?.audio.stopMonitoring() }
        microphone.stop()
        clock.stop()
        nativeNotifications.stop()
        focus.stop()
        airDrop.stop()
        capsLock.stop()
        schedule.reset()
        hardwareQueue.async { [weak self] in self?.brightness.cancelRamps() }
        mediaKeys.stop()
        battery.stop()
        island.hide(immediately: true)
        subscriptions.removeAll()
        for observer in observations {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observations.removeAll()
    }
}
