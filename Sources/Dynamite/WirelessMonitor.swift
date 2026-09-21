import Foundation
import CoreWLAN
import Combine
import IslandCore
import ObjectiveC

/// Connection events only. No scanning, battery guesses, network names, or polling.
final class WirelessMonitor: NSObject, ObservableObject, CWEventDelegate {
    @Published private(set) var status = "Off"
    var onConnect: ((Activity) -> Void)?
    private let queue = DispatchQueue(label: "com.dan.dynomite.hotspot", qos: .utility)
    private var client: CWWiFiClient? // Access only on queue; Wi-Fi IPC never blocks the main thread.
    private let events: [CWEventType] = [.ssidDidChange, .linkDidChange, .powerDidChange]
    private var running = false
    private var generation = UUID()
    private var debounce: DispatchWorkItem?
    private var reading = false
    private var refreshPending = false
    private var transitions = HotspotTransitions()

    func start() {
        guard !running else { return }
        running = true
        generation = UUID()
        let token = generation
        transitions.reset()
        status = "Connecting…"
        queue.async { [weak self] in
            guard let self else { return }
            let client = CWWiFiClient()
            self.client = client
            client.delegate = self
            do {
                for event in self.events { try client.startMonitoringEvent(with: event) }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.running, self.generation == token else { return }
                    self.refresh()
                }
            } catch {
                for event in self.events { try? client.stopMonitoringEvent(with: event) }
                client.delegate = nil
                self.client = nil
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == token else { return }
                    self.running = false
                    self.status = "Wi-Fi monitoring unavailable"
                }
            }
        }
    }
    func stop() {
        guard running else { return }
        running = false
        generation = UUID()
        debounce?.cancel()
        refreshPending = false
        transitions.reset()
        status = "Off"
        queue.async { [weak self] in
            guard let self, let client = self.client else { return }
            for event in self.events { try? client.stopMonitoringEvent(with: event) }
            client.delegate = nil
            self.client = nil
        }
    }
    func resetBaseline() {
        transitions.reset()
        refresh()
    }
    func refresh() {
        guard running else { return }
        guard !reading else { refreshPending = true; return }
        reading = true
        let token = generation
        queue.async { [weak self] in
            guard let self else { return }
            let connected = self.client.flatMap { Self.connectionState(client: $0) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.reading = false
                if self.running, self.generation == token {
                    self.status = connected == .hotspot ? "Personal Hotspot connected" : connected == .wifi ? "Wi-Fi connected" : connected == .offline ? "Not connected" : "Unavailable on this macOS version"
                    if let activity = self.transitions.consume(connection: connected) { self.onConnect?(activity) }
                }
                if self.refreshPending {
                    self.refreshPending = false
                    self.refresh()
                }
            }
        }
    }
    private func connectionChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running else { return }
            self.debounce?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.refresh() }
            self.debounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }
    func ssidDidChangeForWiFiInterface(withName interfaceName: String) { connectionChanged() }
    func linkDidChangeForWiFiInterface(withName interfaceName: String) { connectionChanged() }
    func powerStateDidChangeForWiFiInterface(withName interfaceName: String) { connectionChanged() }

    /// Isolate the optional private read. All selectors and ABI return types are
    /// checked before calling; absent support yields nil, never a guessed result.
    static func connectionState(client: CWWiFiClient) -> WirelessConnection? {
        guard let interface = client.interface() else { return .offline }
        guard interface.powerOn() else { return .offline }
        guard let core = object(interface, selector: "corewifi"),
              let method = class_getInstanceMethod(type(of: core), NSSelectorFromString("currentScanResult")),
              method_getTypeEncoding(method)?.pointee == 64 else { return nil }
        guard let scan = object(core, selector: "currentScanResult") else { return .offline }
        let selector = NSSelectorFromString("isPersonalHotspot")
        guard let method = class_getInstanceMethod(type(of: scan), selector),
              method_getNumberOfArguments(method) == 2,
              method_getTypeEncoding(method)?.pointee == 66 else { return nil }
        typealias ReadBool = @convention(c) (AnyObject, Selector) -> Bool
        return unsafeBitCast(method_getImplementation(method), to: ReadBool.self)(scan, selector) ? .hotspot : .wifi
    }
    private static func object(_ source: NSObject, selector name: String) -> NSObject? {
        let selector = NSSelectorFromString(name)
        guard let method = class_getInstanceMethod(type(of: source), selector),
              method_getNumberOfArguments(method) == 2,
              method_getTypeEncoding(method)?.pointee == 64 else { return nil }
        return source.perform(selector)?.takeUnretainedValue() as? NSObject
    }
}
