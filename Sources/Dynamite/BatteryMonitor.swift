import Foundation
import IOKit.ps
import IslandCore

final class BatteryMonitor {
    var onChange: ((BatterySnapshot) -> Void)?
    private var source: CFRunLoopSource?
    private var powerStateObservation: NSObjectProtocol?
    func start() {
        guard source == nil else { return }
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            Unmanaged<BatteryMonitor>.fromOpaque(context).takeUnretainedValue().read()
        }
        source = IOPSNotificationCreateRunLoopSource(callback, Unmanaged.passUnretained(self).toOpaque())?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
        powerStateObservation = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange,
            object: nil, queue: .main) { [weak self] _ in self?.read() }
        read()
    }
    func read() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for item in sources {
            guard let description = IOPSGetPowerSourceDescription(info, item)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
            onChange?(BatterySnapshot(percent: Int((Double(current) / Double(maximum) * 100).rounded()),
                pluggedIn: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                charging: description[kIOPSIsChargingKey] as? Bool ?? false,
                lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled))
        }
    }
    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        if let powerStateObservation { NotificationCenter.default.removeObserver(powerStateObservation) }
        powerStateObservation = nil
    }
    deinit { stop() }
}
