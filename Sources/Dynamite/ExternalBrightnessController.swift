import AppKit
import IOKit
import Darwin
import IslandCore

/// DDC backlight plus the configured MonitorControl software range. No gamma writes or idle polling.
/// Protocol reference: MonitorControl's MIT-licensed Arm64DDC.swift.
final class ExternalBrightnessController {
    private typealias Create = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias Transfer = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> Int32
    private typealias DisplayInfo = @convention(c) (UInt32) -> Unmanaged<CFDictionary>?
    private let io = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL)
    private let core = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY | RTLD_LOCAL)
    private var services: [UInt32: CFTypeRef] = [:]
    private var maxima: [UInt32: UInt16] = [:]
    private var preferenceIDs: [UInt32: String] = [:]
    var onSoftwareBrightness: ((UInt32, Float) -> Void)?
    private var scales: [UInt32: ExternalBrightnessScale] = [:]
    private var lastHardware: [UInt32: UInt16] = [:]
    private var lastValues: [UInt32: (Float, TimeInterval)] = [:]
    private let domain = "app.monitorcontrol.MonitorControl" as CFString
    private var lastDiscovery: TimeInterval = -.infinity
    private lazy var create = io.flatMap { dlsym($0, "IOAVServiceCreateWithService") }.map { unsafeBitCast($0, to: Create.self) }
    private lazy var readI2C = io.flatMap { dlsym($0, "IOAVServiceReadI2C") }.map { unsafeBitCast($0, to: Transfer.self) }
    private lazy var writeI2C = io.flatMap { dlsym($0, "IOAVServiceWriteI2C") }.map { unsafeBitCast($0, to: Transfer.self) }
    private lazy var displayInfo = core.flatMap { dlsym($0, "CoreDisplay_DisplayCreateInfoDictionary") }.map { unsafeBitCast($0, to: DisplayInfo.self) }
    deinit { if let io { dlclose(io) }; if let core { dlclose(core) } }

    func invalidate() { services.removeAll(); maxima.removeAll(); preferenceIDs.removeAll(); lastValues.removeAll(); scales.removeAll(); lastHardware.removeAll(); lastDiscovery = -.infinity }
    func read(_ id: UInt32) -> Float? {
        guard CGDisplayIsBuiltin(id) == 0, let service = service(for: id), let readI2C else { return nil }
        if let value = lastValues[id], ProcessInfo.processInfo.systemUptime - value.1 < 2 { return value.0 }
        if let value = monitorControlBaseline(id) { return value }
        if let profile = preferenceIDs[id], CFPreferencesCopyAppValue(("value16" + profile) as CFString, domain) != nil {
            return nil // Preserve custom MonitorControl curves/remaps rather than overriding them.
        }
        guard send([0x82, 0x01, 0x10], to: service, readRequest: true) else { return nil }
        usleep(50_000)
        var reply = [UInt8](repeating: 0, count: 11)
        guard readI2C(service, 0x37, 0, &reply, 11) == 0,
              reply[2] == 0x02, reply[3] == 0, reply[4] == 0x10,
              reply.dropLast().reduce(UInt8(0x50), ^) == reply.last else { return monitorControlBaseline(id) }
        let maximum = UInt16(reply[6]) << 8 | UInt16(reply[7])
        let current = UInt16(reply[8]) << 8 | UInt16(reply[9])
        guard maximum > 0, current <= maximum else { return nil }
        maxima[id] = maximum
        return Float(current) / Float(maximum)
    }
    func set(_ id: UInt32, value: Float) -> Bool {
        guard value.isFinite, let maximum = maxima[id], let service = services[id] else { return false }
        let scale = scales[id]
        let raw = UInt16(((scale?.hardware(value) ?? min(1, max(0, value))) * Float(maximum)).rounded())
        if lastHardware[id] != raw {
            guard send([0x84, 0x03, 0x10, UInt8(raw >> 8), UInt8(raw & 255)], to: service) else { return false }
            lastHardware[id] = raw
        }
        onSoftwareBrightness?(id, scale?.software(value) ?? 1)
        lastValues[id] = (min(1, max(0, value)), ProcessInfo.processInfo.systemUptime)
        return true
    }
    private func send(_ data: [UInt8], to service: CFTypeRef, readRequest: Bool = false) -> Bool {
        guard let writeI2C else { return false }
        var packet = data + [data.reduce(UInt8(readRequest ? 0x6E : 0x6E ^ 0x51), ^)]
        usleep(10_000)
        _ = writeI2C(service, 0x37, 0x51, &packet, UInt32(packet.count))
        usleep(10_000)
        return writeI2C(service, 0x37, 0x51, &packet, UInt32(packet.count)) == 0
    }

    // Some DDC monitors support writes but return an empty read reply. MonitorControl
    // uses its saved target too. Accept only its exact display profile and plain scale.
    private func monitorControlBaseline(_ id: UInt32) -> Float? {
        guard let profile = preferenceIDs[id] else { return nil }
        CFPreferencesAppSynchronize(domain)
        func number(_ key: String) -> NSNumber? { CFPreferencesCopyAppValue(key as CFString, domain) as? NSNumber }
        guard let value = number("value16" + profile)?.floatValue,
              let maximum = number("maxDDC16" + profile)?.intValue, maximum > 0, maximum <= 65535,
              value.isFinite, (0...1).contains(value),
              !(number("forceSw" + profile)?.boolValue ?? false),
              !(number("unavailableDDC16" + profile)?.boolValue ?? false),
              !(number("invertDDC16" + profile)?.boolValue ?? false),
              (number("minDDCOverride16" + profile)?.intValue ?? 0) == 0,
              [0, 5].contains(number("curveDDC16" + profile)?.intValue ?? 0),
              (CFPreferencesCopyAppValue(("remapDDC16" + profile) as CFString, domain) as? String ?? "").isEmpty else { return nil }
        let combined = !(number("disableCombinedBrightness")?.boolValue ?? false)
        let split = Float((number("combinedBrightnessSwitchingPoint" + profile)?.intValue ?? 0) + 8) / 16
        guard let scale = ExternalBrightnessScale(split: combined ? split : 0,
            allowBlackout: number("allowZeroSwBrightness")?.boolValue ?? false) else { return nil }
        scales[id] = scale
        maxima[id] = UInt16(maximum)
        return value
    }
    func didSettle(_ id: UInt32) {
        guard let profile = preferenceIDs[id], let value = lastValues[id]?.0,
              CFPreferencesCopyAppValue(("value16" + profile) as CFString, domain) != nil else { return }
        CFPreferencesSetAppValue(("value16" + profile) as CFString, value as CFPropertyList, domain)
        CFPreferencesAppSynchronize(domain)
    }
    private func service(for id: UInt32) -> CFTypeRef? {
        if let found = services[id] { return found }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastDiscovery > 2, let displayInfo, let create else { return nil }
        lastDiscovery = now
        var ids = [UInt32](repeating: 0, count: 16), count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return nil }
        let displays = ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }.compactMap { number -> (UInt32, NSDictionary)? in
            guard let info = displayInfo(number)?.takeRetainedValue() else { return nil }
            return (number, info as NSDictionary)
        }
        var iterator: io_iterator_t = 0
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root); if iterator != 0 { IOObjectRelease(iterator) } }
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else { return nil }
        var location = ""
        while true {
            let entry = IOIteratorNext(iterator)
            if entry == 0 { break }
            defer { IOObjectRelease(entry) }
            var name = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(entry, &name) == KERN_SUCCESS else { continue }
            let kind = String(cString: name)
            if kind.contains("AppleCLCD2") || kind.contains("IOMobileFramebufferShim") {
                var path = [CChar](repeating: 0, count: 512)
                location = IORegistryEntryGetPath(entry, kIOServicePlane, &path) == KERN_SUCCESS ? String(cString: path) : ""
            } else if kind == "DCPAVServiceProxy",
                      IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String == "External",
                      !location.isEmpty {
                let matches = displays.filter { $0.1["IODisplayLocation"] as? String == location }
                guard matches.count == 1, let match = matches.first,
                      let service = create(kCFAllocatorDefault, entry)?.takeRetainedValue() else { continue }
                services[match.0] = service
                if let names = match.1["DisplayProductName"] as? [String: String],
                   let name = names["en_US"] ?? names.values.first {
                    let vendor = CGDisplayVendorNumber(match.0), model = CGDisplayModelNumber(match.0)
                    preferenceIDs[match.0] = "(\(name.filter { !$0.isWhitespace })\(vendor)\(model)@\(match.0))"
                }
            }
        }
        return services[id]
    }
}
