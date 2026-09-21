import CoreAudio
import AudioToolbox
import IslandCore
import Foundation

/// Prefer macOS's virtual main control, which also handles channel-only devices.
final class AudioController {
    // Monitoring and adjust() share AppModel's serial hardware queue.
    var onChange: ((Activity) -> Void)?
    var onAvailability: ((Bool) -> Void)?
    private var monitorQueue: DispatchQueue?
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var lastObserved: Activity?
    private var observedDevice: AudioDeviceID = 0
    struct Control {
        let device: AudioDeviceID
        let properties: [AudioObjectPropertyAddress]
        let values: [Float32]
        var volume: Float32 { values.max() ?? 0 }
    }
    private func address(_ selector: AudioObjectPropertySelector,
                         scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeOutput,
                         element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: scope, mElement: element)
    }
    private func device() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var property = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        return id
    }
    private func writable(_ device: AudioDeviceID, _ property: AudioObjectPropertyAddress) -> Bool {
        var property = property
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &property) &&
            AudioObjectIsPropertySettable(device, &property, &settable) == noErr && settable.boolValue
    }
    private func read<T: Numeric>(_ device: AudioDeviceID, _ property: AudioObjectPropertyAddress, into value: inout T) -> Bool {
        var property = property
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(device, &property, 0, nil, &size, pointer) == noErr
        }
    }
    private func write<T: Numeric>(_ device: AudioDeviceID, _ property: AudioObjectPropertyAddress, _ value: T) -> Bool {
        var property = property
        var value = value
        return withUnsafePointer(to: &value) { pointer in
            AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<T>.size), pointer) == noErr
        }
    }
    private func control() -> Control? {
        guard let device = device() else { return nil }
        for selector in [kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyVolumeScalar] {
            let property = address(selector)
            var value: Float32 = 0
            if writable(device, property), read(device, property, into: &value), value.isFinite {
                return Control(device: device, properties: [property], values: [value])
            }
        }
        // Devices without a virtual control may expose only their stereo channels.
        let properties = [UInt32(1), 2].map { address(kAudioDevicePropertyVolumeScalar, element: $0) }
        var values: [Float32] = []
        for property in properties {
            var value: Float32 = 0
            guard writable(device, property), read(device, property, into: &value), value.isFinite else { return nil }
            values.append(value)
        }
        return Control(device: device, properties: properties, values: values)
    }
    func diagnostics() -> [String: Any] {
        guard let control = control() else { return ["available": false, "reason": "No writable volume control on the current output"] }
        return ["available": true, "device": control.device, "volume": control.volume,
                "selector": String(control.properties[0].mSelector), "channels": control.properties.count]
    }
    func startMonitoring(on queue: DispatchQueue) {
        guard monitorQueue == nil else { return }
        monitorQueue = queue
        attachOutput()
    }
    func stopMonitoring() {
        guard monitorQueue != nil else { return }
        detachOutput()
        monitorQueue = nil
        onAvailability?(false)
    }
    private func detachOutput() {
        guard let queue = monitorQueue else { return }
        for (object, property, listener) in listeners {
            var property = property
            AudioObjectRemovePropertyListenerBlock(object, &property, queue, listener)
        }
        listeners.removeAll(); lastObserved = nil; observedDevice = 0
    }
    private func listen(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress, route: Bool = false) {
        guard let queue = monitorQueue else { return }
        var property = property
        guard AudioObjectHasProperty(object, &property) else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.monitorQueue != nil else { return }
            if route { self.attachOutput() } else { self.outputChanged() }
        }
        if AudioObjectAddPropertyListenerBlock(object, &property, queue, listener) == noErr {
            listeners.append((object, property, listener))
        }
    }
    private func attachOutput() {
        detachOutput()
        listen(AudioObjectID(kAudioObjectSystemObject), address(kAudioHardwarePropertyDefaultOutputDevice,
               scope: kAudioObjectPropertyScopeGlobal), route: true)
        guard let control = control() else { onAvailability?(false); return }
        observedDevice = control.device
        // Bluetooth devices may notify scalar channels even when reads/writes
        // use the virtual main control. Listen to each available representation.
        listen(control.device, address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume))
        for element in UInt32(0)...2 { listen(control.device, address(kAudioDevicePropertyVolumeScalar, element: element)) }
        listen(control.device, address(kAudioDevicePropertyMute))
        lastObserved = snapshot(control)
        onAvailability?(true)
    }
    private func snapshot(_ control: Control) -> Activity {
        var muted: UInt32 = 0
        _ = read(control.device, address(kAudioDevicePropertyMute), into: &muted)
        return Self.activity(volume: control.volume, muted: muted != 0)
    }
    private static func activity(volume: Float32, muted: Bool) -> Activity {
        let value = muted ? 0 : Int((min(1, max(0, volume)) * 100).rounded())
        return Activity(.volume, value: value, label: muted ? "Muted" : "Volume",
                        symbol: value == 0 ? "speaker.slash.fill" : value < 35 ? "speaker.wave.1.fill" : "speaker.wave.2.fill")
    }
    private func outputChanged() {
        guard let control = control(), control.device == observedDevice else { return }
        let activity = snapshot(control)
        let previous = lastObserved
        lastObserved = activity
        guard let previous, previous.value != activity.value || previous.label != activity.label else { return }
        onChange?(activity)
    }
    func adjust(_ key: MediaKey, fine: Bool) -> Activity? {
        guard let control = control() else { return nil }
        let device = control.device
        let muteAddress = address(kAudioDevicePropertyMute)
        var volume = control.volume
        var muted: UInt32 = 0
        let hasMute = read(device, muteAddress, into: &muted)
        if key == .mute {
            guard hasMute, writable(device, muteAddress), write(device, muteAddress, UInt32(muted == 0 ? 1 : 0)) else { return nil }
            muted = muted == 0 ? 1 : 0
        } else {
            if muted != 0 {
                guard writable(device, muteAddress), write(device, muteAddress, UInt32(0)) else { return nil }
            }
            let target = min(1, max(0, volume + key.direction / (fine ? 64 : 16)))
            let values = VolumeAdjustment.channelValues(control.values, target: target)
            for index in control.properties.indices {
                guard write(device, control.properties[index], values[index]) else {
                    // Restore previous values if only part of a stereo update succeeds.
                    for restore in 0..<index { _ = write(device, control.properties[restore], control.values[restore]) }
                    if muted != 0 { _ = write(device, muteAddress, muted) }
                    return nil
                }
            }
            muted = 0
            volume = target
            var readback: Float32 = target
            if read(device, control.properties[0], into: &readback), control.properties.count == 1 { volume = readback }
        }
        let activity = Self.activity(volume: volume, muted: muted != 0)
        // The key handler already presents this change. Its CoreAudio callback
        // must not announce it a second time or extend the activity's duration.
        if observedDevice == device { lastObserved = activity }
        return activity
    }
}
