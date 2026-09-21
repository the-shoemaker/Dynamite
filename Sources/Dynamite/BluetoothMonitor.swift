import Foundation
import Combine
import IOBluetooth
import CoreAudio
import IslandCore

/// Observes paired connections and reads AirPods battery only on connection. Never scans or pairs.
final class BluetoothMonitor: NSObject, ObservableObject {
    @Published private(set) var status = "Off"
    struct ConnectedDevice: Identifiable {
        let id: String
        let name: String
        let symbol: String
        let battery: AirPodsBattery.Reading?
    }
    @Published private(set) var devices: [ConnectedDevice] = []
    private var refreshingDevices = false
    private var devicesRefreshPending = false
    var onConnect: ((Activity) -> Void)?
    var onAirPodsReady: (() -> Void)?
    var airPodsEnabled = false
    private var notification: IOBluetoothUserNotification?
    private var disconnects: [String: IOBluetoothUserNotification] = [:]
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var lastAnnouncement: (String, TimeInterval)?
    private var running = false
    private var generation = UUID()
    private let reads = DispatchQueue(label: "com.dan.dynomite.bluetooth", qos: .utility)

    func start() {
        guard !running else { return }
        running = true
        generation = UUID()
        startOutputListener()
        let token = generation
        reads.async { [weak self] in
            let initial = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
                .filter { $0.isConnected() }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running, self.generation == token else { return }
                // Initial devices need disconnect listeners immediately. Waiting for
                // their first connect callback would suppress the first real reconnect.
                for device in initial {
                    guard let id = device.addressString else { continue }
                    self.disconnects[id] = device.register(forDisconnectNotification: self,
                        selector: #selector(self.disconnected(_:device:)))
                }
                self.notification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(self.connected(_:device:)))
                if self.notification == nil { self.running = false; self.status = "Bluetooth monitoring unavailable" }
                else { self.status = "Watching paired devices" }
                self.refreshDevices()
            }
        }
    }
    func stop() {
        running = false
        if let outputListener {
            var property = Self.outputProperty
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &property, reads, outputListener)
        }
        outputListener = nil
        lastAnnouncement = nil
        generation = UUID()
        notification?.unregister()
        notification = nil
        disconnects.values.forEach { $0.unregister() }
        disconnects.removeAll()
        status = "Off"
        devices = []
        refreshingDevices = false
        devicesRefreshPending = false
    }
    /// On-demand details for Settings, plus existing connection events. No scan
    /// or polling timer is added, and this never announces an activity.
    func refreshDevices() {
        guard running else { return }
        guard !refreshingDevices else { devicesRefreshPending = true; return }
        refreshingDevices = true
        let token = generation
        reads.async { [weak self] in
            let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? [])
                .filter { $0.isConnected() }.compactMap { device -> ConnectedDevice? in
                    guard let id = device.addressString else { return nil }
                    let battery = AirPodsBattery.read(device)
                    let name = (device.name ?? "Bluetooth device").split(whereSeparator: { $0.isNewline }).joined(separator: " ")
                    let symbol = battery?.symbol ?? (device.deviceClassMajor == 4 ? "headphones" : device.deviceClassMajor == 5 ? "keyboard" : "antenna.radiowaves.left.and.right")
                    return ConnectedDevice(id: id, name: name, symbol: symbol, battery: battery)
                }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.refreshingDevices = false
                guard self.running else { return }
                self.devices = devices.filter { self.disconnects[$0.id] != nil }
                if self.devicesRefreshPending {
                    self.devicesRefreshPending = false
                    self.refreshDevices()
                }
            }
        }
    }
    @objc private func connected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.notification === notification else { return }
            let token = self.generation
            self.reads.async { [weak self] in
                guard device.isPaired(), device.isConnected(), let identifier = device.addressString else { return }
                let rawName = device.name ?? "Bluetooth"
                let name = rawName.split(whereSeparator: { $0.isNewline }).joined(separator: " ")
                let label = name.count > 18 ? String(name.prefix(17)) + "…" : name
                let major = device.deviceClassMajor
                let isAirPods = AirPodsBattery.symbol(for: device) != nil
                let symbol = major == 4 ? "headphones" : major == 5 ? "keyboard" : "antenna.radiowaves.left.and.right"
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.running, self.generation == token, self.disconnects[identifier] == nil else { return }
                    // Remove the identity on disconnection so a later reconnection can announce once.
                    guard let observer = device.register(forDisconnectNotification: self, selector: #selector(self.disconnected(_:device:))) else {
                        self.status = "Connection tracking unavailable"
                        return
                    }
                    self.disconnects[identifier] = observer
                    self.refreshDevices()
                    if self.airPodsEnabled {
                        if isAirPods { self.onAirPodsReady?() }
                        self.readBattery(device, identifier: identifier, label: label, fallbackSymbol: symbol,
                                         token: token, attempt: 0, deviceName: rawName)
                    } else {
                        self.onConnect?(Activity(.bluetooth, value: 0, label: label, symbol: symbol))
                    }
                }
            }
        }
    }
    private func readBattery(_ device: IOBluetoothDevice, identifier: String, label: String,
                             fallbackSymbol: String, token: UUID, attempt: Int, deviceName: String) {
        let observer = disconnects[identifier]
        reads.asyncAfter(deadline: .now() + (attempt == 0 ? 0.25 : 0.8)) { [weak self] in
            guard device.isConnected() else { return }
            let reading = AirPodsBattery.read(device)
            let audioDevice = device.deviceClassMajor == 4
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running, self.generation == token else { return }
                if let observer, self.disconnects[identifier] !== observer { return }
                if self.airPodsEnabled, let reading, let percent = reading.percentage {
                    self.announceAirPods(identifier: identifier, name: deviceName, reading: reading, percent: percent)
                } else if self.airPodsEnabled && (reading != nil || audioDevice) && attempt < 3 {
                    self.readBattery(device, identifier: identifier, label: label, fallbackSymbol: fallbackSymbol,
                                     token: token, attempt: attempt + 1, deviceName: deviceName)
                } else {
                    self.onConnect?(Activity(.bluetooth, value: 0, label: label, symbol: fallbackSymbol))
                }
            }
        }
    }
    private static var outputProperty: AudioObjectPropertyAddress {
        .init(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal,
              mElement: kAudioObjectPropertyElementMain)
    }
    private func startOutputListener() {
        guard outputListener == nil else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.outputChanged() }
        var property = Self.outputProperty
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &property, reads, listener) == noErr {
            outputListener = listener
        }
    }
    // Smart Routing can activate an already-connected AirPods link. CoreAudio's
    // event covers that case without polling or changing the selected output.
    private func outputChanged() {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var property = Self.outputProperty
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &deviceID) == noErr else { return }
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        property = .init(mSelector: kAudioDevicePropertyDeviceUID, mScope: kAudioObjectPropertyScopeGlobal,
                         mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(deviceID, &property, 0, nil, &size, &uid) == noErr, let uid else { return }
        let output = (uid.takeRetainedValue() as String).filter { $0.isLetter || $0.isNumber }.lowercased()
        let connected = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter { $0.isConnected() }
        guard let device = connected.first(where: {
            guard let address = $0.addressString else { return false }
            return output.contains(address.filter { $0.isLetter || $0.isNumber }.lowercased())
        }), let identifier = device.addressString else { return }
        let name = device.name ?? "AirPods"
        let isAirPods = AirPodsBattery.symbol(for: device) != nil
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running, self.airPodsEnabled else { return }
            if isAirPods { self.onAirPodsReady?() }
            self.readBattery(device, identifier: identifier, label: "AirPods", fallbackSymbol: "headphones",
                token: self.generation, attempt: 0, deviceName: name)
        }
    }
    private func announceAirPods(identifier: String, name: String, reading: AirPodsBattery.Reading, percent: Int) {
        if let index = devices.firstIndex(where: { $0.id == identifier }) {
            devices[index] = ConnectedDevice(id: identifier, name: name, symbol: reading.symbol, battery: reading)
        } else {
            devices.append(ConnectedDevice(id: identifier, name: name, symbol: reading.symbol, battery: reading))
        }
        let now = ProcessInfo.processInfo.systemUptime
        if let previous = lastAnnouncement, previous.0 == identifier, now - previous.1 < 4 { return }
        lastAnnouncement = (identifier, now)
        status = "AirPods connected · \(percent)%"
        onConnect?(Activity(.airPods, value: percent, label: "AirPods", symbol: reading.symbol))
        onAirPodsReady?()
    }
    @objc private func disconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { [weak self] in
            guard let identifier = device.addressString, self?.disconnects[identifier] === notification else { return }
            self?.disconnects.removeValue(forKey: identifier)?.unregister()
            self?.devices.removeAll { $0.id == identifier }
            if self?.lastAnnouncement?.0 == identifier { self?.lastAnnouncement = nil }
        }
    }
}
