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
    private let audio: any OutputAudioAccess
    private var activation = UUID()
    private var deviceGeneration = UUID()
    private var routeListener: AudioObjectPropertyListenerBlock?
    private var routePending: DispatchWorkItem?
    private var outputPending: DispatchWorkItem?
    private var monitoringProperties: [AudioObjectPropertyAddress] = []
    private var outputReadDelay = 0.05
    private var hasAttached = false
    init(audio: any OutputAudioAccess = SystemOutputAudioAccess()) { self.audio = audio }
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
        let property = address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
        guard read(AudioObjectID(kAudioObjectSystemObject), property, into: &id),
              id != 0 else { return nil }
        return id
    }
    private func writable(_ device: AudioDeviceID, _ property: AudioObjectPropertyAddress) -> Bool { audio.writable(device, property) }
    private func read<T: Numeric>(_ device: AudioDeviceID, _ property: AudioObjectPropertyAddress, into value: inout T) -> Bool { audio.read(device, property, into: &value) }
    private func write<T: Numeric>(_ device: AudioDeviceID, _ property: AudioObjectPropertyAddress, _ value: T) -> Bool { audio.write(device, property, value) }
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
    private var routeAddress: AudioObjectPropertyAddress {
        address(kAudioHardwarePropertyDefaultOutputDevice, scope: kAudioObjectPropertyScopeGlobal)
    }
    func startMonitoring(on queue: DispatchQueue) {
        guard monitorQueue == nil else { return }
        monitorQueue = queue
        activation = UUID()
        let token = activation
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.monitorQueue != nil, self.activation == token, self.routePending == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.activation == token, self.monitorQueue != nil else { return }
                self.routePending = nil
                self.attachOutput()
            }
            self.routePending = work
            queue.asyncAfter(deadline: .now() + 0.05, execute: work)
        }
        if audio.add(AudioObjectID(kAudioObjectSystemObject), routeAddress, queue: queue, block: block) { routeListener = block }
        attachOutput()
    }
    func stopMonitoring() {
        guard let queue = monitorQueue else { return }
        activation = UUID()
        routePending?.cancel(); routePending = nil
        if let block = routeListener { audio.remove(AudioObjectID(kAudioObjectSystemObject), routeAddress, queue: queue, block: block) }
        routeListener = nil
        detachOutput(); hasAttached = false
        monitorQueue = nil
        onAvailability?(false)
    }
    private func detachOutput() {
        guard let queue = monitorQueue else { return }
        outputReadDelay = 0.05
        deviceGeneration = UUID()
        outputPending?.cancel(); outputPending = nil
        for (object, property, listener) in listeners { audio.remove(object, property, queue: queue, block: listener) }
        listeners.removeAll(); monitoringProperties.removeAll()
        lastObserved = nil; observedDevice = 0
    }
    private func listen(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress) {
        guard let queue = monitorQueue else { return }
        let token = activation, generation = deviceGeneration
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.monitorQueue != nil, self.activation == token,
                  self.deviceGeneration == generation, self.observedDevice == object,
                  self.outputPending == nil else { return }
            // Coalesce a burst without cancelling/reallocating work per callback.
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.monitorQueue != nil, self.activation == token,
                      self.deviceGeneration == generation else { return }
                self.outputPending = nil
                self.outputChanged()
            }
            self.outputPending = work
            queue.asyncAfter(deadline: .now() + self.outputReadDelay, execute: work)
        }
        if audio.add(object, property, queue: queue, block: listener) { listeners.append((object, property, listener)) }
    }
    private func attachOutput() {
        let nextDevice = device() ?? 0
        guard !hasAttached || nextDevice != observedDevice else { return }
        detachOutput(); hasAttached = true; observedDevice = nextDevice
        guard let control = control() else { onAvailability?(false); return }
        // Read actual scalar controls for observation. Querying virtual volume
        // can itself notify listeners on some devices. Keep virtual writes for keys.
        let master = address(kAudioDevicePropertyVolumeScalar)
        var value: Float32 = 0
        if read(control.device, master, into: &value), value.isFinite {
            monitoringProperties = [master]
        } else {
            let channels = [UInt32(1), 2].map { address(kAudioDevicePropertyVolumeScalar, element: $0) }
            if channels.allSatisfy({ read(control.device, $0, into: &value) && value.isFinite }) {
                monitoringProperties = channels
            } else { monitoringProperties = control.properties }
        }
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
        guard observedDevice != 0, !monitoringProperties.isEmpty else { return }
        var values: [Float32] = []
        for property in monitoringProperties {
            var value: Float32 = 0
            guard read(observedDevice, property, into: &value), value.isFinite else { return }
            values.append(value)
        }
        let activity = snapshot(Control(device: observedDevice, properties: monitoringProperties, values: values))
        let previous = lastObserved
        lastObserved = activity
        guard let previous, previous.value != activity.value || previous.label != activity.label else {
            // Virtual-only devices can report a notification for every read.
            // Back off that unchanged feedback instead of sustaining a hot loop.
            if monitoringProperties.contains(where: { $0.mSelector == kAudioHardwareServiceDeviceProperty_VirtualMainVolume }) {
                outputReadDelay = min(1, outputReadDelay * 2)
            }
            return
        }
        outputReadDelay = 0.05
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
        if observedDevice == device { lastObserved = activity; outputReadDelay = 0.05 }
        return activity
    }
}
