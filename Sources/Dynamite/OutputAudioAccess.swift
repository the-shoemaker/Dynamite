import CoreAudio
import AudioToolbox
import Foundation

protocol OutputAudioAccess {
    func writable(_ device: AudioDeviceID, _ property: AudioObjectPropertyAddress) -> Bool
    func read<T: Numeric>(_ device: AudioDeviceID, _ property: AudioObjectPropertyAddress, into value: inout T) -> Bool
    func write<T: Numeric>(_ device: AudioDeviceID, _ property: AudioObjectPropertyAddress, _ value: T) -> Bool
    func add(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress, queue: DispatchQueue, block: @escaping AudioObjectPropertyListenerBlock) -> Bool
    func remove(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress, queue: DispatchQueue, block: @escaping AudioObjectPropertyListenerBlock)
}
struct SystemOutputAudioAccess: OutputAudioAccess {
    func writable(_ device: AudioDeviceID, _ property: AudioObjectPropertyAddress) -> Bool {
        var property = property
        var settable: DarwinBoolean = false
        return AudioObjectHasProperty(device, &property) &&
            AudioObjectIsPropertySettable(device, &property, &settable) == noErr && settable.boolValue
    }
    func read<T: Numeric>(_ device: AudioDeviceID, _ property: AudioObjectPropertyAddress, into value: inout T) -> Bool {
        var property = property
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(device, &property, 0, nil, &size, pointer) == noErr
        }
    }
    func write<T: Numeric>(_ device: AudioDeviceID, _ property: AudioObjectPropertyAddress, _ value: T) -> Bool {
        var property = property
        var value = value
        return withUnsafePointer(to: &value) { pointer in
            AudioObjectSetPropertyData(device, &property, 0, nil, UInt32(MemoryLayout<T>.size), pointer) == noErr
        }
    }
    func add(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress, queue: DispatchQueue, block: @escaping AudioObjectPropertyListenerBlock) -> Bool {
        var property = property
        guard AudioObjectHasProperty(object, &property) else { return false }
        return AudioObjectAddPropertyListenerBlock(object, &property, queue, block) == noErr
    }
    func remove(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress, queue: DispatchQueue, block: @escaping AudioObjectPropertyListenerBlock) {
        var property = property
        AudioObjectRemovePropertyListenerBlock(object, &property, queue, block)
    }
}
