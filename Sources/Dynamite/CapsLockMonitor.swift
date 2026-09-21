import AppKit

/// Modifier-state notifications only. No key contents, event filtering, or polling.
final class CapsLockMonitor {
    var onChange: ((Bool) -> Void)?
    var onUserToggle: ((Bool) -> Void)?
    private var global: Any?
    private var local: Any?
    private var state: Bool?
    func start() {
        if global == nil {
            global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.receive(event.modifierFlags.contains(.capsLock), userEvent: true)
            }
        }
        if local == nil {
            local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.receive(event.modifierFlags.contains(.capsLock), userEvent: true)
                return event
            }
        }
        refresh()
    }
    func refresh() { receive(CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)) }
    private func receive(_ active: Bool, userEvent: Bool = false) {
        guard state != active else { return }
        state = active
        onChange?(active)
        if userEvent { onUserToggle?(active) }
    }
    func stop() {
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        global = nil; local = nil; state = nil
    }
    deinit { stop() }
}
