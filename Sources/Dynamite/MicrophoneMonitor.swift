import CoreAudio
import AudioToolbox
import Combine
import IslandCore

/// Observes device controls only. Never starts an audio stream or records sound.
final class MicrophoneMonitor: ObservableObject {
    @Published private(set) var status = "Off"
    var onChange: ((Activity) -> Void)?
    private let queue = DispatchQueue(label: "com.dan.dynomite.microphone", qos: .utility)
    private var enabled = false // Main-thread lifecycle.
    private var activation = UUID()
    private var device: AudioDeviceID = 0 // Remaining state lives on queue.
    private var queueToken: UUID?
    private var channels = 0
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var state = MicrophoneMuteState()
    private var pending: DispatchWorkItem?

    func start() {
        guard !enabled else { return }
        enabled = true
        let token = UUID(); activation = token
        queue.async { [weak self] in self?.queueToken = token; self?.attach(token) }
    }
    func stop() {
        enabled = false; activation = UUID(); status = "Off"
        queue.async { [weak self] in self?.queueToken = nil; self?.detach(); self?.state = MicrophoneMuteState() }
    }
    private func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeInput, element: UInt32 = 0) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: scope, mElement: element)
    }
    private func read<T: Numeric>(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress, _ initial: T) -> T? {
        var property = property, value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let result = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0)
        }
        return result == noErr ? value : nil
    }
    private func listen(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress, action: @escaping () -> Void) {
        var property = property
        guard AudioObjectHasProperty(object, &property) else { return }
        let block: AudioObjectPropertyListenerBlock = { _, _ in action() }
        if AudioObjectAddPropertyListenerBlock(object, &property, queue, block) == noErr { listeners.append((object, property, block)) }
    }
    private func detach() {
        pending?.cancel(); pending = nil
        for (object, property, block) in listeners {
            var property = property
            AudioObjectRemovePropertyListenerBlock(object, &property, queue, block)
        }
        listeners.removeAll(); device = 0
    }
    private func attach(_ token: UUID) {
        guard queueToken == token else { return }
        detach()
        state = MicrophoneMuteState()
        let route = address(kAudioHardwarePropertyDefaultInputDevice, scope: kAudioObjectPropertyScopeGlobal)
        listen(AudioObjectID(kAudioObjectSystemObject), route) { [weak self] in self?.attach(token) }
        device = read(AudioObjectID(kAudioObjectSystemObject), route, UInt32(0)) ?? 0
        channels = channelCount()
        if device != 0 {
            for element in 0...UInt32(channels) {
                for selector in [kAudioDevicePropertyMute, kAudioDevicePropertyVolumeScalar] {
                    listen(device, address(selector, element: element)) { [weak self] in self?.scheduleRead(token) }
                }
            }
            listen(device, address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)) { [weak self] in self?.scheduleRead(token) }
        }
        sample(token)
    }
    private func channelCount() -> Int {
        guard device != 0 else { return 0 }
        var property = address(kAudioDevicePropertyStreamConfiguration)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size, size < 65536 else { return 0 }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, memory) == noErr else { return 0 }
        return min(64, UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + Int($1.mNumberChannels) })
    }
    private func scheduleRead(_ token: UUID) {
        guard queueToken == token else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.sample(token) }
        pending = work
        queue.asyncAfter(deadline: .now() + 0.025, execute: work)
    }
    private func sample(_ token: UUID) {
        guard queueToken == token else { return }
        let master = read(device, address(kAudioDevicePropertyMute), UInt32(0)).map { $0 != 0 }
        let mainLevel = read(device, address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume), Float32(0)) ?? read(device, address(kAudioDevicePropertyVolumeScalar), Float32(0))
        let elements = channels > 0 ? Array(1...UInt32(channels)) : []
        let channelLevels = elements.compactMap { read(device, address(kAudioDevicePropertyVolumeScalar, element: $0), Float32(0)) }
        let channelMutes = elements.compactMap { read(device, address(kAudioDevicePropertyMute, element: $0), UInt32(0)).map { $0 != 0 } }
        let muted = device == 0 ? nil : MicrophoneMuteState.resolve(masterMute: master,
            levels: mainLevel.map { [$0] } ?? (channelLevels.count == channels ? channelLevels : nil),
            channelMutes: channelMutes.count == channels ? channelMutes : nil)
        let activity = state.consume(device: device, muted: muted)
        let description = muted.map { $0 ? "Default input muted" : "Default input unmuted" } ?? "Default input has no readable mute or level control"
        DispatchQueue.main.async { [weak self] in
            guard let self, self.enabled, self.activation == token else { return }
            self.status = description
            if let activity { self.onChange?(activity) }
        }
    }
}
