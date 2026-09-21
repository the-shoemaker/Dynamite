import AppKit

/// Event-driven software dimming for the range below an external panel's minimum.
/// No gamma tables, capture, mouse interception, or idle refresh loop.
final class DisplayShadeController {
    private var panels: [UInt32: NSPanel] = [:]
    func set(_ brightness: Float, displayID: UInt32) {
        precondition(Thread.isMainThread)
        guard CGDisplayIsBuiltin(displayID) == 0, brightness.isFinite,
              let screen = NSScreen.screens.first(where: {
                  $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 == displayID
              }) else { return }
        let alpha = CGFloat(1 - min(1, max(0, brightness)))
        if alpha < 0.001 {
            panels.removeValue(forKey: displayID)?.close()
            return
        }
        let panel: NSPanel
        if let existing = panels[displayID] { panel = existing }
        else {
            panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.backgroundColor = .black
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.stationary, .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panels[displayID] = panel
        }
        panel.setFrame(screen.frame, display: false)
        panel.alphaValue = alpha
        panel.orderFrontRegardless()
    }
    func clear() {
        precondition(Thread.isMainThread)
        panels.values.forEach { $0.close() }
        panels.removeAll()
    }
}
