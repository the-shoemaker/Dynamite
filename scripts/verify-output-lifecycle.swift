import Foundation
import CoreAudio
import AudioToolbox
import IslandCore

final class FakeOutput: OutputAudioAccess {
    struct Listener { let object: UInt32; let property: AudioObjectPropertyAddress; let queue: DispatchQueue; let block: AudioObjectPropertyListenerBlock }
    var route: UInt32 = 42
    var volume: Float32 = 0.5
    var mute: UInt32 = 0
    var entries: [Listener] = []
    var adds = 0, removes = 0, reads = 0, virtualReads = 0
    var feedback = true
    var virtualOnly = false
    var stereo = false
    var failSecondWrite = false
    func writable(_ device: UInt32, _ property: AudioObjectPropertyAddress) -> Bool {
        if property.mSelector == kAudioDevicePropertyMute { return true }
        if virtualOnly { return property.mSelector == kAudioHardwareServiceDeviceProperty_VirtualMainVolume }
        return !stereo || (property.mSelector == kAudioDevicePropertyVolumeScalar && property.mElement > 0)
    }
    func read<T: Numeric>(_ device: UInt32, _ property: AudioObjectPropertyAddress, into value: inout T) -> Bool {
        reads += 1
        if device == UInt32(kAudioObjectSystemObject) { value = route as! T; return true }
        guard device != 0 else { return false }
        if property.mSelector == kAudioDevicePropertyMute { value = mute as! T; return true }
        guard writable(device, property) else { return false }
        if property.mSelector == kAudioHardwareServiceDeviceProperty_VirtualMainVolume {
            virtualReads += 1
            if feedback { notify(routeOnly: false) }
        }
        value = volume as! T; return true
    }
    func write<T: Numeric>(_ device: UInt32, _ property: AudioObjectPropertyAddress, _ value: T) -> Bool {
        if property.mSelector == kAudioDevicePropertyMute { mute = value as! UInt32 }
        else {
            if failSecondWrite && property.mElement == 2 { return false }
            volume = value as! Float32
        }
        notify(routeOnly: false); return true
    }
    func add(_ object: UInt32, _ property: AudioObjectPropertyAddress, queue: DispatchQueue, block: @escaping AudioObjectPropertyListenerBlock) -> Bool {
        adds += 1
        let entry = Listener(object: object, property: property, queue: queue, block: block)
        entries.append(entry)
        if object == UInt32(kAudioObjectSystemObject) { fire(entry) }
        return true
    }
    func remove(_ object: UInt32, _ property: AudioObjectPropertyAddress, queue: DispatchQueue, block: @escaping AudioObjectPropertyListenerBlock) {
        removes += 1
        if let index = entries.firstIndex(where: { $0.object == object && $0.property.mSelector == property.mSelector && $0.property.mElement == property.mElement }) { entries.remove(at: index) }
    }
    func fire(_ entry: Listener) { entry.queue.async { var p = entry.property; entry.block(1, &p) } }
    func notify(routeOnly: Bool, count: Int = 1) {
        let matches = entries.filter { ($0.object == UInt32(kAudioObjectSystemObject)) == routeOnly }
        for _ in 0..<count { for entry in matches { fire(entry) } }
    }
}
@main struct VerifyOutput {
    static func settle() { Thread.sleep(forTimeInterval: 0.15) }
    static func require(_ condition: Bool, _ message: String) { precondition(condition, message) }
    static func main() {
        let queue = DispatchQueue(label: "output-test")
        let audio = FakeOutput()
        let monitor = AudioController(audio: audio)
        var events: [Activity] = []
        queue.sync { monitor.onChange = { events.append($0) }; monitor.startMonitoring(on: queue) }
        settle()
        queue.sync {
            require(audio.adds == 6 && audio.removes == 0, "Initial route callback rebuilt listeners")
            require(audio.virtualReads == 1, "Observation read virtual volume and caused feedback")
            audio.notify(routeOnly: true, count: 2000)
            audio.notify(routeOnly: false, count: 2000)
        }
        settle()
        queue.sync {
            require(audio.adds == 6 && audio.removes == 0, "Duplicate route rebuilt listeners")
            require(audio.virtualReads == 1 && audio.reads < 30, "Callback flood caused unbounded reads")
            require(events.isEmpty, "Unchanged volume emitted events")
            audio.volume = 0.7; audio.notify(routeOnly: false)
        }
        settle()
        queue.sync { require(events.count == 1 && events.last?.value == 70, "External volume change lost"); audio.mute = 1; audio.notify(routeOnly: false) }
        settle()
        queue.sync {
            require(events.last?.label == "Muted", "Mute callback lost")
            require(monitor.adjust(.mute, fine: false) != nil, "Mute key failed")
        }
        settle()
        queue.sync {
            require(events.count == 2, "Key callback duplicated presentation")
            let old = audio.entries
            audio.route = 43; audio.stereo = true; audio.notify(routeOnly: true)
            for entry in old { audio.fire(entry) }
        }
        settle()
        queue.sync {
            require(audio.entries.count == 6 && audio.adds == 11 && audio.removes == 5, "Route lifecycle incorrect")
            let before = audio.volume
            audio.failSecondWrite = true
            require(monitor.adjust(.volumeUp, fine: false) == nil, "Partial stereo failure accepted")
            require(audio.volume == before, "Partial write was not rolled back")
            audio.failSecondWrite = false
            let stale = audio.entries
            monitor.stopMonitoring(); monitor.startMonitoring(on: queue)
            for entry in stale { audio.fire(entry) }
        }
        settle()
        queue.sync { require(audio.entries.count == 6, "Restart leaked listeners"); audio.route = 0; audio.notify(routeOnly: true) }
        settle()
        queue.sync { require(audio.entries.count == 1, "No-output state retained device listeners"); audio.route = 44; audio.notify(routeOnly: true) }
        settle()
        queue.sync {
            require(audio.entries.count == 6, "Route recovery failed")
            monitor.stopMonitoring()
            require(audio.entries.isEmpty, "Stop leaked listeners")
        }
        queue.sync { audio.stereo = false; audio.virtualOnly = true; monitor.startMonitoring(on: queue) }
        Thread.sleep(forTimeInterval: 2)
        queue.sync {
            require(audio.virtualReads < 20, "Virtual-only read feedback was not bounded")
            monitor.stopMonitoring()
            require(audio.entries.isEmpty, "Feedback stop leaked listeners")
        }
        if CommandLine.arguments.contains("--stress") {
            queue.sync { audio.virtualOnly = false; monitor.startMonitoring(on: queue) }
            for cycle in 0..<200 {
                queue.sync {
                    audio.route = UInt32(100 + cycle)
                    audio.notify(routeOnly: true, count: 500)
                    audio.notify(routeOnly: false, count: 500)
                    if cycle % 20 == 0 { monitor.stopMonitoring(); monitor.startMonitoring(on: queue) }
                }
                Thread.sleep(forTimeInterval: 0.08)
                queue.sync { require(audio.entries.count == 6, "Stress leaked output listeners") }
            }
            queue.sync { monitor.stopMonitoring(); require(audio.entries.isEmpty, "Stress cleanup failed") }
            print("Output stress: 200 routes, 100000 route events, 100000 output event bursts, 10 restarts passed")
        }
        print("Output lifecycle: read-triggered feedback, burst coalescing, route stability, mute/volume, key deduplication, stereo rollback, restart, zero output, recovery passed")
    }
}
