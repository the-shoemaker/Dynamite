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
    private let audio: any MicrophoneAudioAccess
    private var routeListener: AudioObjectPropertyListenerBlock?
    private var hasAttachedDevice = false
    private var routePending: DispatchWorkItem?
    private var channels = 0
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var state = MicrophoneMuteState()
    private var pending: DispatchWorkItem?

    init(audio: any MicrophoneAudioAccess = SystemMicrophoneAudioAccess()) { self.audio = audio }

    func start() {
        guard !enabled else { return }
        enabled = true
        let token = UUID(); activation = token
        queue.async { [weak self] in
            guard let self else { return }
            self.queueToken = token
            // Keep the system listener for the entire activation. Re-registering
            // it from its callback can generate another initial route callback.
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleRouteRead(token) }
            if self.audio.add(AudioObjectID(kAudioObjectSystemObject), self.routeAddress, queue: self.queue, block: block) {
                self.routeListener = block
            }
            self.attach(token)
        }
    }
    func stop() {
        enabled = false; activation = UUID(); status = "Off"
        queue.async { [weak self] in
            guard let self else { return }
            self.queueToken = nil
            self.routePending?.cancel(); self.routePending = nil
            if let block = self.routeListener {
                self.audio.remove(AudioObjectID(kAudioObjectSystemObject), self.routeAddress, queue: self.queue, block: block)
            }
            self.routeListener = nil
            self.detach(); self.hasAttachedDevice = false
            self.state = MicrophoneMuteState()
        }
    }
    private func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeInput, element: UInt32 = 0) -> AudioObjectPropertyAddress {
        .init(mSelector: selector, mScope: scope, mElement: element)
    }
    private var routeAddress: AudioObjectPropertyAddress {
        address(kAudioHardwarePropertyDefaultInputDevice, scope: kAudioObjectPropertyScopeGlobal)
    }
    private func listen(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress, token: UUID) {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self, self.device == object else { return }
            self.scheduleRead(token)
        }
        if audio.add(object, property, queue: queue, block: block) { listeners.append((object, property, block)) }
    }
    private func scheduleRouteRead(_ token: UUID) {
        guard queueToken == token, routePending == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.queueToken == token else { return }
            self.routePending = nil
            self.attach(token)
        }
        routePending = work
        queue.asyncAfter(deadline: .now() + 0.025, execute: work)
    }
    private func detach() {
        pending?.cancel(); pending = nil
        for (object, property, block) in listeners {
            audio.remove(object, property, queue: queue, block: block)
        }
        listeners.removeAll(); device = 0
    }
    private func attach(_ token: UUID) {
        guard queueToken == token else { return }
        let nextDevice = audio.defaultInput()
        guard !hasAttachedDevice || nextDevice != device else { return }
        detach()
        state = MicrophoneMuteState()
        device = nextDevice; hasAttachedDevice = true
        channels = audio.channelCount(device)
        if device != 0 {
            for element in 0...UInt32(channels) {
                for selector in [kAudioDevicePropertyMute, kAudioDevicePropertyVolumeScalar] {
                    listen(device, address(selector, element: element), token: token)
                }
            }
            listen(device, address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume), token: token)
        }
        sample(token)
    }
    private func scheduleRead(_ token: UUID) {
        guard queueToken == token, pending == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.queueToken == token else { return }
            self.pending = nil
            self.sample(token)
        }
        pending = work
        queue.asyncAfter(deadline: .now() + 0.025, execute: work)
    }
    private func sample(_ token: UUID) {
        guard queueToken == token else { return }
        let master = audio.uint(device, address(kAudioDevicePropertyMute)).map { $0 != 0 }
        let mainLevel = audio.float(device, address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)) ?? audio.float(device, address(kAudioDevicePropertyVolumeScalar))
        let elements = channels > 0 ? Array(1...UInt32(channels)) : []
        let channelLevels = elements.compactMap { audio.float(device, address(kAudioDevicePropertyVolumeScalar, element: $0)) }
        let channelMutes = elements.compactMap { audio.uint(device, address(kAudioDevicePropertyMute, element: $0)).map { $0 != 0 } }
        let muted = device == 0 ? nil : MicrophoneMuteState.resolve(masterMute: master,
            levels: mainLevel.map { [$0] } ?? (channelLevels.count == channels ? channelLevels : nil),
            channelMutes: channelMutes.count == channels ? channelMutes : nil)
        let activity = state.consume(device: device, muted: muted)
        let description = muted.map { $0 ? "Default input muted" : "Default input unmuted" } ?? "Default input has no readable mute or level control"
        DispatchQueue.main.async { [weak self] in
            guard let self, self.enabled, self.activation == token else { return }
            if self.status != description { self.status = description }
            if let activity { self.onChange?(activity) }
        }
    }
}
