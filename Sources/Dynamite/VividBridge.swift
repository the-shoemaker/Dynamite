import AppKit
import IslandCore

/// Vivid owns the extended range. Read its display effect only in response to a key.
final class VividBridge {
    static let bundleID = "com.goodsnooze.vivid"
    static func isRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
    static func boostLevel(displayID: UInt32) -> Float? {
        var red = [Float](repeating: 0, count: 256)
        var green = red, blue = red
        var count: UInt32 = 0
        guard CGGetDisplayTransferByTable(displayID, 256, &red, &green, &blue, &count) == .success,
              count > 0 else { return nil }
        let peaks = [red, green, blue].compactMap { $0.prefix(Int(count)).filter(\.isFinite).max() }
        return peaks.count == 3 ? peaks.min() : nil
    }
    static func supports(_ screen: NSScreen) -> Bool {
        guard isRunning() else { return false }
        let domain = bundleID as CFString
        let displayType = CFPreferencesCopyAppValue("useDisplayTypes" as CFString, domain) as? String
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0
        if displayType == "Only MacBook Display" && CGDisplayIsBuiltin(id) == 0 { return false }
        if displayType == "Only External Displays" && CGDisplayIsBuiltin(id) != 0 { return false }
        return screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1
    }
    static func isBoosted(displayID: UInt32, linearBrightness: Float?) -> Bool {
        BrightnessRange.isBoosted(linearBrightness: linearBrightness, gammaPeak: boostLevel(displayID: displayID))
    }
    static func hideIndicator() -> Bool {
        CFPreferencesSetAppValue("hideVividIndicator" as CFString, true as CFPropertyList, bundleID as CFString)
        return CFPreferencesAppSynchronize(bundleID as CFString)
    }
}
