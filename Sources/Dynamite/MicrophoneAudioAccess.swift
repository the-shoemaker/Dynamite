import CoreAudio
import AudioToolbox
import Foundation

/// The read-only Core Audio boundary, injectable for listener lifecycle tests.
protocol MicrophoneAudioAccess {
    func defaultInput() -> AudioDeviceID
    func channelCount(_ device: AudioDeviceID) -> Int
    func uint(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress) -> UInt32?
    func float(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress) -> Float32?
    func add(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress, queue: DispatchQueue,
             block: @escaping AudioObjectPropertyListenerBlock) -> Bool
    func remove(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress, queue: DispatchQueue,
                block: @escaping AudioObjectPropertyListenerBlock)
}
struct SystemMicrophoneAudioAccess: MicrophoneAudioAccess {
    func defaultInput() -> AudioDeviceID {
        uint(AudioObjectID(kAudioObjectSystemObject), .init(mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: 0)) ?? 0
    }
    func uint(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress) -> UInt32? { read(object, property, UInt32(0)) }
    func float(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress) -> Float32? { read(object, property, Float32(0)) }
    private func read<T: Numeric>(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress, _ initial: T) -> T? {
        var property = property, value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let result = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0)
        }
        return result == noErr ? value : nil
    }
    func add(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress, queue: DispatchQueue,
             block: @escaping AudioObjectPropertyListenerBlock) -> Bool {
        var property = property
        guard AudioObjectHasProperty(object, &property) else { return false }
        return AudioObjectAddPropertyListenerBlock(object, &property, queue, block) == noErr
    }
    func remove(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress, queue: DispatchQueue,
                block: @escaping AudioObjectPropertyListenerBlock) {
        var property = property
        AudioObjectRemovePropertyListenerBlock(object, &property, queue, block)
    }
    func channelCount(_ device: AudioDeviceID) -> Int {
        guard device != 0 else { return 0 }
        var property = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeInput, mElement: 0)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &property, 0, nil, &size) == noErr,
              size >= MemoryLayout<AudioBufferList>.size, size < 65536 else { return 0 }
        let memory = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { memory.deallocate() }
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, memory) == noErr else { return 0 }
        return min(64, UnsafeMutableAudioBufferListPointer(memory.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + Int($1.mNumberChannels) })
    }
}
