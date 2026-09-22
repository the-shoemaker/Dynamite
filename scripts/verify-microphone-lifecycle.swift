import Foundation
import CoreAudio
import AudioToolbox
import IslandCore

final class FakeAudio: MicrophoneAudioAccess {
    struct Listener { let object: UInt32; let property: AudioObjectPropertyAddress; let queue: DispatchQueue; let block: AudioObjectPropertyListenerBlock }
    let lock = NSRecursiveLock()
    var route: UInt32 = 42
    var muted = false
    var level: Float32 = 0.5
    var entries: [Listener] = []
    var adds = 0, removes = 0, routeReads = 0
    func access<T>(_ action: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return action() }
    func defaultInput() -> UInt32 { access { routeReads += 1; return route } }
    func channelCount(_ device: UInt32) -> Int { device == 0 ? 0 : 1 }
    func uint(_ object: UInt32, _ property: AudioObjectPropertyAddress) -> UInt32? { access { object == 0 ? nil : (muted ? 1 : 0) } }
    func float(_ object: UInt32, _ property: AudioObjectPropertyAddress) -> Float32? { access { object == 0 ? nil : level } }
    func add(_ object: UInt32, _ property: AudioObjectPropertyAddress, queue: DispatchQueue, block: @escaping AudioObjectPropertyListenerBlock) -> Bool {
        access {
            adds += 1
            let entry = Listener(object: object, property: property, queue: queue, block: block)
            entries.append(entry)
            // Model a driver that reports current routing when subscribed.
            if object == UInt32(kAudioObjectSystemObject) { fire(entry) }
            return true
        }
    }
    func remove(_ object: UInt32, _ property: AudioObjectPropertyAddress, queue: DispatchQueue, block: @escaping AudioObjectPropertyListenerBlock) {
        access {
            removes += 1
            if let index = entries.firstIndex(where: { $0.object == object && $0.property.mSelector == property.mSelector && $0.property.mElement == property.mElement }) { entries.remove(at: index) }
        }
    }
    func fire(_ entry: Listener) {
        entry.queue.async { var address = entry.property; entry.block(1, &address) }
    }
    func notify(routeOnly: Bool, count: Int = 1) {
        let matches = access { entries.filter { ($0.object == UInt32(kAudioObjectSystemObject)) == routeOnly } }
        for _ in 0..<count { for entry in matches { fire(entry) } }
    }
}
@main struct VerifyMicrophone {
    static func settle(_ seconds: Double = 0.15) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { fatalError(message) } }
    static func main() {
        let audio = FakeAudio()
        let subject = MicrophoneMonitor(audio: audio)
        var events: [Activity] = []
        subject.onChange = { events.append($0) }
        subject.start(); settle()
        let initial = audio.access { (audio.adds, audio.removes) }
        require(initial.0 == 6 && initial.1 == 0, "Initial callback must not cause re-subscription")
        audio.notify(routeOnly: true, count: 1000); settle()
        require(audio.access { audio.adds == initial.0 && audio.removes == 0 }, "Duplicate routes rebuilt listeners")
        require(events.isEmpty, "Initial route must be silent")
        audio.access { audio.muted = true }; audio.notify(routeOnly: false); settle()
        require(events.count == 1 && !events[0].isActive, "Mute edge lost")
        audio.notify(routeOnly: true, count: 1000); settle()
        audio.access { audio.muted = false }; audio.notify(routeOnly: false); settle()
        require(events.count == 2 && events[1].isActive, "Duplicate route erased mute baseline")
        let old = audio.access { audio.entries }
        audio.access { audio.route = 43; audio.muted = true }; audio.notify(routeOnly: true); settle()
        require(events.count == 2, "Switch must establish a silent baseline")
        require(audio.access { audio.adds == 11 && audio.removes == 5 }, "Device switch must keep system listener")
        for listener in old where listener.object != UInt32(kAudioObjectSystemObject) { audio.fire(listener) }; settle()
        require(events.count == 2, "Old device callback leaked")
        audio.access { audio.muted = false }; audio.notify(routeOnly: false); settle()
        require(events.count == 3 && events.last!.isActive, "New device unmute missing")
        audio.access { audio.level = 0 }; audio.notify(routeOnly: false, count: 1000); settle()
        require(events.count == 4 && !events.last!.isActive, "Input level zero missing")
        audio.access { audio.route = 0 }; audio.notify(routeOnly: true); settle()
        require(audio.access { audio.entries.count == 1 }, "No-input state lost system listener")
        subject.stop(); subject.start(); settle()
        for listener in old { audio.fire(listener) }; settle()
        require(audio.access { audio.entries.count == 1 }, "Stale restart callback changed listeners")
        audio.access { audio.route = 44; audio.level = 0.5 }; audio.notify(routeOnly: true); settle()
        require(audio.access { audio.entries.count == 6 }, "Recovery from no input failed")
        audio.notify(routeOnly: true)
        audio.notify(routeOnly: false)
        subject.stop(); subject.start(); settle()
        require(audio.access { audio.entries.count == 6 && audio.adds - audio.removes == 6 }, "Restart with pending reads leaked listeners")
        if CommandLine.arguments.contains("--stress") {
            // Accelerate route churn without touching the real audio devices.
            for index in 0..<1000 {
                audio.access { audio.route = UInt32(50 + index % 2) }
                audio.notify(routeOnly: true, count: 100)
                settle(0.04)
                require(audio.access { audio.entries.count == 6 && audio.adds - audio.removes == 6 }, "Listener count grew during route stress")
                if index % 100 == 0 {
                    subject.stop(); subject.start(); settle(0.04)
                    require(audio.access { audio.entries.count == 6 && audio.adds - audio.removes == 6 }, "Listener count grew across restart")
                }
            }
            print("Stress: 1000 route changes, 100000 route notifications, 10 restarts; exactly 6 active listeners throughout")
        }
        let stale = audio.access { audio.entries }
        subject.stop(); settle()
        let stopped = audio.access { audio.adds }
        for listener in stale { audio.fire(listener) }; settle()
        require(audio.access { audio.entries.isEmpty && audio.adds == stopped }, "Stopped callbacks reattached")
        require(subject.status == "Off", "Stopped status changed")
        print("Microphone lifecycle: initial callback, 2000 duplicate routes, mute/unmute, device switch, old callbacks, zero input, zero level, stop/restart passed")
    }
}
