import Foundation
import IOBluetooth
import ObjectiveC

/// Read only the connected device's own battery fields. No scans, cached defaults,
/// device-name matching, or fabricated percentages.
enum AirPodsBattery {
    struct Reading {
        let symbol: String
        let percentage: Int?
        let left: Int?
        let right: Int?
        let caseLevel: Int?
    }
    static func read(_ device: IOBluetoothDevice) -> Reading? {
        guard let symbol = symbol(for: device) else { return nil }
        let left = valid(byte(device, "batteryPercentLeft"))
        let right = valid(byte(device, "batteryPercentRight"))
        let combined = valid(byte(device, "batteryPercentCombined"))
        let single = valid(byte(device, "batteryPercentSingle"))
        return Reading(symbol: symbol, percentage: [left, right].compactMap { $0 }.min() ?? combined ?? single,
                       left: left, right: right, caseLevel: valid(byte(device, "batteryPercentCase")))
    }
    /// Product identity is ready before battery fields settle after connection.
    static func symbol(for device: IOBluetoothDevice) -> String? {
        guard device.isConnected(), let product = unsignedShort(device, "productID") else { return nil }
        switch product {
        case 0x2002, 0x200F, 0x2013, 0x2019, 0x201B: return "airpods"
        case 0x200E, 0x2014, 0x2024, 0x2027: return "airpodspro"
        case 0x200A, 0x201F: return "airpodsmax"
        default: return nil
        }
    }
    private static func valid(_ value: Int?) -> Int? {
        // Zero is also used for unavailable components; do not invent a flat
        // battery from an unavailable field. Use the lowest reported earbud.
        guard let value, (1...100).contains(value) else { return nil }
        return value
    }
    static func diagnostics() -> [[String: Any]] {
        (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).compactMap { device in
            guard let reading = read(device) else { return nil }
            return ["symbol": reading.symbol, "percentage": reading.percentage ?? -1]
        }
    }
    private static func byte(_ device: IOBluetoothDevice, _ name: String) -> Int? {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(type(of: device), selector),
              let encoding = method_getTypeEncoding(method),
              String(cString: encoding) == "C16@0:8" else { return nil }
        typealias Read = @convention(c) (AnyObject, Selector) -> UInt8
        return Int(unsafeBitCast(method_getImplementation(method), to: Read.self)(device, selector))
    }
    private static func unsignedShort(_ device: IOBluetoothDevice, _ name: String) -> Int? {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(type(of: device), selector),
              let encoding = method_getTypeEncoding(method),
              String(cString: encoding) == "S16@0:8" else { return nil }
        typealias Read = @convention(c) (AnyObject, Selector) -> UInt16
        return Int(unsafeBitCast(method_getImplementation(method), to: Read.self)(device, selector))
    }
}
