import AppKit
import IslandCore

/// Core Graphics-only decoding for the input thread. NSEvent(cgEvent:) can invoke
/// HIToolbox's main-queue-only Caps Lock processing, even for a system event.
/// These optional fields are validated against AppKit-created samples on main
/// before installing a filtering tap. If macOS changes them, keep native handling.
enum MediaKeyEventDecoder {
    static let eventType = CGEventType(rawValue: 14)!
    private static let subtype = CGEventField(rawValue: 99)!
    private static let data1 = CGEventField(rawValue: 149)!
    private static let data2 = CGEventField(rawValue: 150)!

    static func validate() -> Bool {
        precondition(Thread.isMainThread)
        for (kind, payload, extra) in [(8, 0x10A00, -1), (7, 0x20B00, 17)] {
            guard let sample = NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: 0, context: nil, subtype: Int16(kind), data1: payload, data2: extra)?.cgEvent,
                sample.type == eventType,
                sample.getIntegerValueField(subtype) == kind,
                sample.getIntegerValueField(data1) == payload,
                sample.getIntegerValueField(data2) == extra else { return false }
        }
        return true
    }
    static func decode(type: CGEventType, event: CGEvent) -> MediaKeyPress? {
        guard type == eventType, event.getIntegerValueField(subtype) == 8 else { return nil }
        return MediaKeyPress(data: Int(event.getIntegerValueField(data1)))
    }
    static func releaseCopy(_ event: CGEvent) -> CGEvent? {
        guard let release = event.copy() else { return nil }
        let payload = event.getIntegerValueField(data1)
        release.setIntegerValueField(data1, value: (payload & ~0xFF01) | (0xB << 8))
        return release
    }
}
