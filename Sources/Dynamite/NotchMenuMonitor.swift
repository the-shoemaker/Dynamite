import AppKit

/// Passive button listener. No pointer polling or idle window.
final class NotchMenuMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var trackingMenu = false
    private var activeMenu: NSMenu?
    private var suppressNextRelease = false
    private var generation = UUID()
    var activityContains: ((NSPoint) -> Bool)?
    var makeMenu: ((@escaping (NSMenu) -> Void) -> Void)?

    func start() {
        guard tap == nil, globalMonitor == nil, localMonitor == nil else { return }
        let mask = CGEventMask((1 << CGEventType.rightMouseUp.rawValue) | (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.leftMouseDown.rawValue))
        if let newTap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
                guard [.rightMouseUp, .rightMouseDown, .leftMouseDown].contains(type), let context else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<NotchMenuMonitor>.fromOpaque(context).takeUnretainedValue()
                let location = event.location
                let wasTracking = monitor.trackingMenu
                RunLoop.main.perform(inModes: [.common]) { [weak monitor] in
                    let top = NSScreen.screens.first?.frame.maxY ?? 0
                    monitor?.handleMouse(type, at: NSPoint(x: location.x, y: top - location.y), wasTracking: wasTracking)
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
           let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) {
            tap = newTap
            source = newSource
            CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
            CGEvent.tapEnable(tap: newTap, enable: true)
        } else {
            // Mouse monitoring can still work before Accessibility is granted.
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.rightMouseUp, .rightMouseDown, .leftMouseDown]) { [weak self] event in
                let point = NSEvent.mouseLocation
                let wasTracking = self?.trackingMenu == true
                RunLoop.main.perform(inModes: [.common]) { self?.handleMouse(event.type == .rightMouseUp ? .rightMouseUp : event.type == .rightMouseDown ? .rightMouseDown : .leftMouseDown, at: point, wasTracking: wasTracking) }
            }
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseUp, .rightMouseDown, .leftMouseDown]) { [weak self] event in
                let point = NSEvent.mouseLocation
                let wasTracking = self?.trackingMenu == true
                RunLoop.main.perform(inModes: [.common]) { self?.handleMouse(event.type == .rightMouseUp ? .rightMouseUp : event.type == .rightMouseDown ? .rightMouseDown : .leftMouseDown, at: point, wasTracking: wasTracking) }
                return event
            }
        }
    }
    private func handleMouse(_ type: CGEventType, at point: NSPoint, wasTracking: Bool) {
        if type == .rightMouseUp {
            if suppressNextRelease { suppressNextRelease = false; return }
            handleClick(at: point)
            return
        }
        guard trackingMenu || wasTracking else { return }
        if trackingMenu && activeMenu == nil {
            // A click elsewhere cancels a menu whose control check is pending.
            generation = UUID()
            trackingMenu = false
            if type == .rightMouseDown { suppressNextRelease = true }
            return
        }
        // Preserve normal left-click selection inside AppKit's menu windows.
        let insideMenu = NSApp.windows.contains {
            $0.isVisible && $0.level == .popUpMenu && $0.frame.contains(point)
        }
        if type == .rightMouseDown || !insideMenu {
            if type == .rightMouseDown { suppressNextRelease = true }
            activeMenu?.cancelTracking()
        }
    }
    private func handleClick(at point: NSPoint) {
        guard !trackingMenu else { return }
        // CG mouse coordinates can lie exactly on the upper screen boundary.
        // CGRect.contains excludes maxY, which made the very top unclickable.
        let screen = NSScreen.screens.first { $0.frame.insetBy(dx: 0, dy: -1).contains(point) }
        let atCamera = screen.map { screen in
            let geometry = IslandController.geometry(for: screen)
            return geometry.menuRegion(in: screen.frame)?.contains(point) == true
        } ?? false
        guard atCamera || activityContains?(point) == true, let makeMenu else { return }
        let ceiling = screen.map { $0.frame.maxY - $0.safeAreaInsets.top - 3 } ?? point.y
        trackingMenu = true
        let token = generation
        makeMenu { [weak self] menu in
            guard let self, self.generation == token, self.trackingMenu else { return }
            self.activeMenu = menu
            menu.popUp(positioning: nil, at: NSPoint(x: point.x, y: min(point.y, ceiling)), in: nil)
            self.trackingMenu = false
            self.activeMenu = nil
        }
    }
    func stop() {
        generation = UUID()
        trackingMenu = false
        activeMenu?.cancelTracking()
        activeMenu = nil
        if let tap { CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil; localMonitor = nil
    }
    deinit { stop() }
}
