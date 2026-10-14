import Foundation
import Combine
import Network
import IslandCore

protocol InternetProbing: AnyObject {
    func start(address: String, completion: @escaping (Bool) -> Void)
    func cancel()
}

/// One numeric-address ICMP packet, bounded to two seconds. No name lookup,
/// shell, captured output, or waiting on the UI thread.
final class InternetPing: InternetProbing {
    private let queue = DispatchQueue(label: "com.dan.dynomite.internet.ping", qos: .utility)
    private var process: Process?
    func start(address: String, completion: @escaping (Bool) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/ping")
            process.arguments = ["-n", "-c", "1", "-t", "2", "-W", "1000", address]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { process in
                DispatchQueue.main.async { completion(process.terminationStatus == 0) }
            }
            self.process = process
            do { try process.run() }
            catch { DispatchQueue.main.async { completion(false) } }
        }
    }
    func cancel() {
        // Retain the probe until queued teardown finishes, including deinit.
        queue.async {
            if self.process?.isRunning == true { self.process?.terminate() }
            self.process = nil
        }
    }
}

/// Network changes trigger immediate checks. A single leeway-enabled deadline
/// checks every 30 seconds online or 5 seconds offline, only with a usable route.
final class InternetMonitor: ObservableObject {
    @Published private(set) var state: InternetState = .checking
    @Published private(set) var status = "Off"
    var onChange: ((InternetState, Bool) -> Void)?
    private let pathQueue = DispatchQueue(label: "com.dan.dynomite.internet.path", qos: .utility)
    private let probe: InternetProbing
    private var monitor: NWPathMonitor?
    private var deadline: DispatchSourceTimer?
    private var connectivity = InternetConnectivity()
    private(set) var running = false
    private(set) var probing = false
    private var generation = UUID()
    private var probeGeneration = UUID()
    private var hasPath = false
    private var address = InternetProbeSettings.defaultAddress

    init(probe: InternetProbing = InternetPing()) { self.probe = probe }

    @discardableResult
    func start(address: String, observePath: Bool = true) -> Bool {
        guard let normalized = InternetProbeSettings.normalizedAddress(address) else { return false }
        if running && self.address == normalized { return false }
        stop()
        self.address = normalized
        running = true
        generation = UUID()
        connectivity.reset()
        state = .checking
        status = "Checking internet…"
        guard observePath else { return true } // Injected path events for lifecycle verification.
        let token = generation
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            DispatchQueue.main.async {
                guard let self, self.running, self.generation == token else { return }
                self.pathChanged(available: available)
            }
        }
        monitor.start(queue: pathQueue)
        return true
    }
    func stop() {
        guard running || probing || monitor != nil || deadline != nil else { return }
        running = false
        generation = UUID()
        cancelProbe()
        monitor?.pathUpdateHandler = nil
        monitor?.cancel(); monitor = nil
        hasPath = false
        connectivity.reset()
        state = .checking
        status = "Off"
    }
    func pathChanged(available: Bool) {
        guard running else { return }
        let recovered = !hasPath && available
        hasPath = available
        cancelProbe()
        if recovered { check() }
        else if available { scheduleCheck(after: 0.35) }
        else { publish(connectivity.pathUnavailable()) }
    }
    func refresh() {
        guard running, hasPath, !probing else { return }
        deadline?.cancel(); deadline = nil
        check()
    }
    private func cancelProbe() {
        deadline?.cancel(); deadline = nil
        probeGeneration = UUID()
        let wasProbing = probing
        probing = false
        if wasProbing { probe.cancel() }
    }
    private func check() {
        guard running, hasPath, !probing else { return }
        probing = true
        let session = generation
        let token = UUID()
        probeGeneration = token
        probe.start(address: address) { [weak self] reachable in
            guard let self, self.running, self.probing, self.generation == session, self.probeGeneration == token else { return }
            self.probing = false
            self.publish(self.connectivity.consumeProbe(reachable: reachable))
            self.scheduleCheck(after: self.connectivity.nextProbeInterval)
        }
    }
    private func publish(_ announcement: InternetState?) {
        let changed = state != connectivity.state
        if changed { state = connectivity.state }
        let nextStatus = state == .online ? "Online" : state == .offline ? "Offline" : "Checking internet…"
        if status != nextStatus { status = nextStatus }
        if changed { onChange?(state, announcement != nil) }
    }
    private func scheduleCheck(after interval: TimeInterval) {
        guard running, hasPath else { return }
        deadline?.cancel()
        let session = generation
        let token = probeGeneration
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, leeway: .milliseconds(300))
        timer.setEventHandler { [weak self] in
            guard let self, self.running, self.hasPath, self.generation == session, self.probeGeneration == token else { return }
            self.deadline?.cancel(); self.deadline = nil
            self.check()
        }
        deadline = timer
        timer.resume()
    }
    deinit { deadline?.cancel(); monitor?.cancel(); probe.cancel() }
}
