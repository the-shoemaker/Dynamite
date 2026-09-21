import AppKit
import ApplicationServices
import IslandCore

/// The HID callback only decodes and enqueues. It never calls hardware or SwiftUI.
final class MediaKeyMonitor: ObservableObject {
    @Published private(set) var active = false
    var handle: ((MediaKey, Bool, @escaping (Bool) -> Void) -> Void)?
    private var tap: CFMachPort?
    private var eventThread: Thread?
    private let lock = NSLock()
    private var runLoop: CFRunLoop?
    private var generation = 0
    private var volumeEnabled = true
    private var brightnessEnabled = true
    private var pending = 0
    private var consumed = Set<Int>()
    private struct DeferredPress {
        let event: CGEvent
        let press: MediaKeyPress
        let fine: Bool
    }
    private var deferred: [Int: DeferredPress] = [:]
    private static let replayTag: Int64 = 0x44594E4F4D495445

    func configure(volume: Bool, brightness: Bool) {
        lock.lock()
        volumeEnabled = volume
        brightnessEnabled = brightness
        lock.unlock()
    }
    func start() {
        guard AXIsProcessTrusted() else { stop(); return }
        if let tap, CGEvent.tapIsEnabled(tap: tap) { active = true; return }
        guard MediaKeyEventDecoder.validate() else { stop(); return }
        stop()
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<MediaKeyMonitor>.fromOpaque(context).takeUnretainedValue().receive(type, event)
        }
        guard let newTap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: CGEventMask(1 << NSEvent.EventType.systemDefined.rawValue),
            callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        tap = newTap
        lock.lock()
        let token = generation
        lock.unlock()
        let thread = Thread { [self] in
            let loop = CFRunLoopGetCurrent()!
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0)!
            lock.lock()
            guard token == generation else { lock.unlock(); return }
            runLoop = loop
            lock.unlock()
            CFRunLoopAddSource(loop, source, .commonModes)
            CGEvent.tapEnable(tap: newTap, enable: true)
            CFRunLoopRun()
            CFRunLoopRemoveSource(loop, source, .commonModes)
        }
        thread.name = "Dynamite media keys"
        thread.qualityOfService = .userInteractive
        eventThread = thread
        thread.start()
        active = true
    }
    private func receive(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // Fail open. Do not repeatedly re-enable a hook the OS found unresponsive.
            lock.lock(); consumed.removeAll(); lock.unlock()
            DispatchQueue.main.async { [weak self] in self?.stop() }
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUserData) != Self.replayTag,
              let press = MediaKeyEventDecoder.decode(type: type, event: event) else { return Unmanaged.passUnretained(event) }
        lock.lock()
        if !press.isDown {
            let handled = consumed.remove(press.key.rawValue) != nil
            lock.unlock()
            return handled ? nil : Unmanaged.passUnretained(event)
        }
        let enabled = press.key.feature == .volume ? volumeEnabled : brightnessEnabled
        // Coalesce bursts without letting handled keys leak into the native HUD.
        // At most two hardware requests and one latest press per media key exist.
        guard enabled, let original = event.copy() else {
            consumed.remove(press.key.rawValue)
            lock.unlock()
            return Unmanaged.passUnretained(event)
        }
        let fine = event.flags.contains([.maskAlternate, .maskShift])
        consumed.insert(press.key.rawValue)
        if pending >= 2 {
            deferred[press.key.rawValue] = DeferredPress(event: original, press: press, fine: fine)
            lock.unlock()
            return nil
        }
        pending += 1
        consumed.insert(press.key.rawValue)
        let token = generation
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let valid = token == self.generation
            self.lock.unlock()
            guard valid else { Self.replay(original); return }
            guard let handle = self.handle else { self.finish(token, original, success: false); return }
            handle(press.key, fine) { [weak self] success in self?.finish(token, original, success: success) }
        }
        return nil
    }
    private func finish(_ token: Int, _ event: CGEvent, success: Bool) {
        lock.lock()
        var next: DeferredPress?
        if token == generation {
            pending = max(0, pending - 1)
            if let key = deferred.keys.sorted().first {
                next = deferred.removeValue(forKey: key)
                pending += 1
            }
        }
        lock.unlock()
        if !success { Self.replay(event) }
        if let next {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.lock.lock()
                let valid = token == self.generation
                self.lock.unlock()
                guard valid else { return }
                guard let handle = self.handle else { self.finish(token, next.event, success: false); return }
                handle(next.press.key, next.fine) { [weak self] success in self?.finish(token, next.event, success: success) }
            }
        }
    }
    private static func replay(_ event: CGEvent) {
        // Failed writes retain normal system handling. Mark the event to avoid a loop.
        event.setIntegerValueField(.eventSourceUserData, value: replayTag)
        event.post(tap: .cghidEventTap)
        if let release = MediaKeyEventDecoder.releaseCopy(event) {
            release.setIntegerValueField(.eventSourceUserData, value: replayTag)
            release.post(tap: .cghidEventTap)
        }
    }
    func stop() {
        lock.lock()
        generation += 1
        pending = 0
        deferred.removeAll()
        consumed.removeAll()
        let loop = runLoop
        runLoop = nil
        lock.unlock()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let loop { CFRunLoopStop(loop) }
        tap = nil
        eventThread = nil
        active = false
    }
    /// Exercise the real admission callback without posting any events to macOS.
    func verifyResponsiveness(completion: @escaping () -> Void) {
        guard MediaKeyEventDecoder.validate() else { print("FAIL: unsupported media-event fields"); exit(1) }
        var completions: [(Bool) -> Void] = []
        handle = { _, _, done in completions.append(done) }
        let sample = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [],
            timestamp: 0, windowNumber: 0, context: nil, subtype: 8,
            data1: (MediaKey.volumeUp.rawValue << 16) | (0xA << 8), data2: -1)!.cgEvent!
        let other = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: .capsLock,
            timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0)!.cgEvent!
        DispatchQueue.global(qos: .userInitiated).async {
            let start = ProcessInfo.processInfo.systemUptime
            var admitted = 0
            var unrelatedPassed = 0
            for _ in 0..<1000 {
                if self.receive(MediaKeyEventDecoder.eventType, sample) == nil { admitted += 1 }
                if self.receive(MediaKeyEventDecoder.eventType, other) != nil { unrelatedPassed += 1 }
            }
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            print("Input check on background thread: \(admitted) admitted, \(1000 - admitted) passed through, \(unrelatedPassed) unrelated Caps Lock events passed, \(elapsed * 1000) ms")
            DispatchQueue.main.async {
                let release = MediaKeyEventDecoder.releaseCopy(sample)!
                let releaseDecoded = MediaKeyEventDecoder.decode(type: release.type, event: release)
                guard admitted == 1000, completions.count == 2, self.deferred.count == 1,
                      unrelatedPassed == 1000, releaseDecoded?.isDown == false else {
                    print("FAIL: input regression"); exit(1)
                }
                completions.forEach { $0(true) }
                self.stop()
                completion()
            }
        }
    }
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        start()
        if !active, let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    /// Opt-in, one-minute diagnostic. Records only media-key fields and function-key
    /// codes, never typed text. This passive tap does not consume or post events.
    static func traceBrightness(completion: @escaping () -> Void) {
        let mask = CGEventMask((1 << NSEvent.EventType.systemDefined.rawValue) |
            (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue))
        guard let tap = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, _ in
                if let ns = NSEvent(cgEvent: event) {
                    if ns.type == .systemDefined {
                        print("media subtype=\(ns.subtype.rawValue) data1=\(ns.data1) data2=\(ns.data2)")
                        fflush(stdout)
                    } else if (120...145).contains(Int(ns.keyCode)) {
                        print("function type=\(type.rawValue) code=\(ns.keyCode) flags=\(ns.modifierFlags.rawValue)")
                        fflush(stdout)
                    }
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: nil),
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            print("Brightness trace unavailable"); completion(); return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("Brightness trace ready for 60 seconds"); fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            CFMachPortInvalidate(tap)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            completion()
        }
    }
    deinit { stop() }
}
