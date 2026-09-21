import AppKit
import SwiftUI
import IslandCore
import Combine
import ApplicationServices

@main
struct DynamiteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { delegate.showSettings() }
                        .keyboardShortcut(",", modifiers: .command)
                }
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var modelStarted = false
    private let notchMenu = NotchMenuMonitor()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var preferencesSubscription: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--benchmark-motion") {
            PreviewRenderer.benchmarkMotion(legacy: CommandLine.arguments.contains("--legacy-rendering"),
                external: CommandLine.arguments.contains("--external")) { NSApp.terminate(nil) }
            return
        }
        if CommandLine.arguments.contains("--verify-card-motion") {
            PreviewRenderer.verifyCardMotion { passed in exit(passed ? 0 : 1) }
            return
        }
        if CommandLine.arguments.contains("--verify-promotion") {
            PreviewRenderer.verifyPromotion { passed in exit(passed ? 0 : 1) }
            return
        }
        if CommandLine.arguments.contains("--verify-routing") {
            PreviewRenderer.verifyRouting { passed in exit(passed ? 0 : 1) }
            return
        }
        if CommandLine.arguments.contains("--verify-persistence") {
            PreviewRenderer.verifyPersistence { passed in exit(passed ? 0 : 1) }
            return
        }
        if CommandLine.arguments.contains("--trace-brightness") {
            MediaKeyMonitor.traceBrightness { NSApp.terminate(nil) }
            return
        }
        if CommandLine.arguments.contains("--verify-input") {
            model.mediaKeys.verifyResponsiveness { NSApp.terminate(nil) }
            return
        }
        if CommandLine.arguments.contains("--verify-motion") {
            PreviewRenderer.verifyMotion { NSApp.terminate(nil) }
            return
        }
        if let output = CommandLine.arguments.first(where: { $0.hasPrefix("--render-previews=") }) {
            do { try PreviewRenderer.render(to: String(output.dropFirst("--render-previews=".count))) }
            catch { fputs("Preview rendering failed: \(error)\n", stderr) }
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--diagnostics") {
            printDiagnostics()
            NSApp.terminate(nil)
            return
        }
        updateMenuVisibility(model.settings.preferences.showMenuBarIcon)
        preferencesSubscription = model.settings.$preferences.sink { [weak self] preferences in
            self?.updateMenuVisibility(preferences.showMenuBarIcon)
            self?.settingsWindow?.level = preferences.keepSettingsOnTop ? .floating : .normal
        }
        notchMenu.makeMenu = { [weak self] in self?.makeMenu() ?? NSMenu() }
        notchMenu.activityContains = { [weak self] point in self?.model.island.containsActivity(at: point) ?? false }
        notchMenu.start()
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            showSetup()
        } else {
            startModelIfNeeded()
            if CommandLine.arguments.contains("--setup") { showSetup() }
            else if CommandLine.arguments.contains("--settings") { showSettings() }
        }
        if let argument = CommandLine.arguments.first(where: { $0.hasPrefix("--preview=") }),
           let feature = Feature(rawValue: String(argument.dropFirst("--preview=".count))) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.model.preview(feature) }
        }
    }
    private func updateMenuVisibility(_ visible: Bool) {
        if visible && statusItem == nil { setupMenu() }
        else if !visible, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }
    private func printDiagnostics() {
        let monitor = MediaKeyMonitor()
        monitor.start()
        let result: [String: Any] = [
            "accessibility": AXIsProcessTrusted(),
            "eventTap": monitor.active,
            "audio": AudioController().diagnostics(),
            "vividRunning": VividBridge.isRunning(),
            "airPods": AirPodsBattery.diagnostics(),
            "screens": NSScreen.screens.map { screen -> [String: Any] in
                let geometry = IslandController.geometry(for: screen)
                return ["name": screen.localizedName, "height": geometry.height,
                        "notchWidth": geometry.notchWidth, "topGap": geometry.topGap,
                        "vividBoost": BrightnessController().snapshot(displayID: screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0, vivid: true)?.isBoosted ?? false]
            }
        ]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print(text) }
        monitor.stop()
    }
    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "capsule.fill", accessibilityDescription: "Dynamite")
        statusItem?.button?.image?.isTemplate = true
        statusItem?.button?.target = self
        statusItem?.button?.action = #selector(statusMenuClicked(_:))
        statusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
    @objc private func statusMenuClicked(_ sender: NSStatusBarButton) {
        sender.highlight(true)
        defer { sender.highlight(false) }
        makeMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY - 2), in: sender)
    }
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Dynamite settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Check for updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Preview island", action: #selector(preview), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Pause island", action: #selector(togglePause), keyEquivalent: "").target = self
        menu.addItem(.separator())
        if let timer = model.clock.reading {
            menu.addItem(withTitle: timer.paused ? "Resume Clock timer" : "Pause Clock timer", action: #selector(toggleClockTimer), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Cancel Clock timer", action: #selector(cancelClockTimer), keyEquivalent: "").target = self
            menu.addItem(.separator())
        }
        menu.addItem(withTitle: "Quit Dynamite", action: #selector(quit), keyEquivalent: "q").target = self
        menu.delegate = self
        return menu
    }
    private func startModelIfNeeded() {
        guard !modelStarted else { return }
        modelStarted = true
        model.start()
    }
    @objc func showSetup() {
        if setupWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 580),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Permission setup"
            window.level = .floating
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: SetupView(loginItem: model.loginItem) { [weak self] in
                self?.finishSetup()
            })
            window.center()
            setupWindow = window
        }
        setupWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func finishSetup() {
        UserDefaults.standard.set(true, forKey: "hasLaunched")
        setupWindow?.orderOut(nil)
        setupWindow?.contentView = nil
        setupWindow = nil
        startModelIfNeeded()
        showSettings()
    }
    @objc func showSettings() {
        guard modelStarted else { showSetup(); return }
        if settingsWindow == nil {
            let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 740),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.delegate = self
            window.title = "Dynamite Settings"
            window.titleVisibility = .visible
            window.titlebarAppearsTransparent = false
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.toolbar = nil
            window.level = model.settings.preferences.keepSettingsOnTop ? .floating : .normal
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 820, height: 400)
            window.contentMaxSize = NSSize(width: 1640, height: CGFloat.greatestFiniteMagnitude)
            let hostingView = NSHostingView(rootView: SettingsView(model: model, settings: model.settings, mediaKeys: model.mediaKeys, loginItem: model.loginItem, wireless: model.wireless, bluetooth: model.bluetooth, clock: model.clock, focus: model.focus, airDrop: model.airDrop, onSetup: { [weak self] in self?.showSetup() }))
            hostingView.sizingOptions = [.minSize, .maxSize]
            window.contentView = hostingView
            window.center()
            settingsWindow = window
        }
        model.refreshConnections()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func toggleClockTimer() { model.clock.togglePause() }
    @objc private func cancelClockTimer() { model.clock.cancel() }
    @objc private func checkForUpdates() { model.updater.checkForUpdates() }
    @objc private func preview() { model.preview(.volume) }
    @objc private func togglePause() { model.settings.preferences.paused.toggle() }
    @objc private func quit() { NSApp.terminate(nil) }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        notchMenu.stop()
        // Read-only render/verification modes must not flush an old preference
        // snapshot over settings edited in a concurrently running app.
        if modelStarted { model.stop() }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        menu.items.first(where: { $0.action == #selector(togglePause) })?.title =
            model.settings.preferences.paused ? "Resume island" : "Pause island"
    }
}

// Release the settings view tree while the menu bar app is idle.
extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === setupWindow {
            window.contentView = nil
            setupWindow = nil
            // Closing setup leaves it available on next launch; no permissions
            // or optional login registration are silently accepted.
            startModelIfNeeded()
            return
        }
        guard window === settingsWindow else { return }
        window.contentView = nil
        settingsWindow = nil
    }
}


/// SwiftUI may rewrite NSWindow's advertised limits while rebuilding its toolbar.
/// Keep the actual window frame bounded for both live and programmatic resizing.
private final class SettingsWindow: NSWindow {
    override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        var frame = frameRect
        frame.size.width = min(1640, max(820, frame.width))
        super.setFrame(frame, display: flag)
    }
    override func setFrame(_ frameRect: NSRect, display flag: Bool, animate animateFlag: Bool) {
        var frame = frameRect
        frame.size.width = min(1640, max(820, frame.width))
        super.setFrame(frame, display: flag, animate: animateFlag)
    }
}
