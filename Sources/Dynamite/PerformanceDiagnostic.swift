import AppKit
import Combine
import Darwin
import IslandCore

/// Opt-in local recorder. One utility-queue wake per minute; no work when stopped.
final class PerformanceDiagnostic: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var status = "Not running"
    @Published private(set) var folder: URL?
    private let queue = DispatchQueue(label: "com.dan.dynomite.diagnostic", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var file: FileHandle?
    private var session: URL?
    private var started = Date()
    private var previous: (time: TimeInterval, cpu: Double)?
    private var baseline: UInt64 = 0
    private var threshold = DiagnosticThreshold()
    private var sampleProcess: Process?
    private var sampleTimeout: DispatchWorkItem?
    private var sequence = 0
    private let root: URL
    private let interval: TimeInterval
    private let duration: TimeInterval
    init(root: URL? = nil, interval: TimeInterval = 60, duration: TimeInterval = 12 * 3600) {
        self.interval = interval; self.duration = duration
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dynamite/Diagnostics", isDirectory: true)
        if let data = try? Data(contentsOf: self.root.appendingPathComponent("last-session.json")),
           let saved = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let name = saved["folder"], name == URL(fileURLWithPath: name).lastPathComponent {
            folder = self.root.appendingPathComponent(name)
            status = saved["state"] == "Recording" ? "Previous test was interrupted before completion" : saved["state"] ?? "Not running"
        }
    }
    func start() {
        guard !active else { return }
        active = true; status = "Starting 12-hour test…"
        queue.async { [weak self] in self?.begin() }
    }
    func stop() {
        queue.async { [weak self] in self?.finish("Stopped") }
    }
    func shutdown() { queue.sync { finish("Stopped when Dynamite quit") } }
    func showFiles() { if let folder { NSWorkspace.shared.open(folder) } }
    private func begin() {
        guard timer == nil else { return }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let url = root.appendingPathComponent("run-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            session = url
            // Keep the current run and two previous runs. Only our run directories qualify.
            let old = (try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey]))
                .filter { UUID(uuidString: String($0.lastPathComponent.dropFirst(4))) != nil && $0.lastPathComponent.hasPrefix("run-") && $0.lastPathComponent != url.lastPathComponent }
                .sorted { ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) }
            for stale in old.dropFirst(2) { try? FileManager.default.removeItem(at: stale) }
            let log = url.appendingPathComponent("metrics.jsonl")
            guard FileManager.default.createFile(atPath: log.path, contents: nil, attributes: [.posixPermissions: 0o600]) else { throw CocoaError(.fileWriteUnknown) }
            file = try FileHandle(forWritingTo: log)
            started = Date(); previous = nil; baseline = 0; sequence = 0; threshold = DiagnosticThreshold()
            try record(["event": "started", "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "local", "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "local", "interval_seconds": interval, "duration_hours": duration / 3600])
            saveState("Recording")
            DispatchQueue.main.async { [weak self] in self?.folder = url; self?.status = "Recording · up to 12 hours" }
            let ticker = DispatchSource.makeTimerSource(queue: queue)
            ticker.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(Int(min(5, interval / 10) * 1000)))
            ticker.setEventHandler { [weak self] in self?.tick() }
            timer = ticker; ticker.resume()
        } catch { finish("Could not start diagnostic: \(error.localizedDescription)") }
    }
    private func tick() {
        guard file != nil else { return }
        let elapsed = Date().timeIntervalSince(started)
        guard elapsed < duration else { finish("Completed 12-hour test"); return }
        var usage = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V2, $0) }
        }
        guard result == 0 else { finish("Could not read process counters"); return }
        let now = ProcessInfo.processInfo.systemUptime
        // getrusage exposes seconds/microseconds consistently across CPU architectures.
        var times = rusage()
        guard getrusage(RUSAGE_SELF, &times) == 0 else { finish("Could not read CPU counters"); return }
        let cpu = Double(times.ru_utime.tv_sec + times.ru_stime.tv_sec) + Double(times.ru_utime.tv_usec + times.ru_stime.tv_usec) / 1_000_000
        var percent: Double = 0
        if let old = previous, now > old.time, cpu >= old.cpu { percent = (cpu - old.cpu) / (now - old.time) * 100 }
        else { baseline = usage.ri_phys_footprint }
        previous = (now, cpu)
        do {
            try record(["event": "sample", "elapsed_seconds": elapsed, "cpu_percent_one_core": percent,
                        "physical_footprint_bytes": usage.ri_phys_footprint, "resident_bytes": usage.ri_resident_size])
            if threshold.observe(cpuPercent: percent, footprint: usage.ri_phys_footprint, baseline: baseline, elapsed: elapsed) { capture() }
        } catch { finish("Diagnostic stopped: log write failed") }
    }
    private func record(_ values: [String: Any]) throws {
        var values = values
        values["timestamp"] = ISO8601DateFormatter().string(from: Date())
        var data = try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]); data.append(10)
        try file?.write(contentsOf: data)
    }
    private func capture() {
        guard sampleProcess == nil, let session else { return }
        sequence += 1
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        process.arguments = [String(getpid()), "3", "-file", session.appendingPathComponent("stack-\(sequence).txt").path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] completed in
            self?.queue.async { [weak self] in
                guard let self, self.sampleProcess === completed else { return }
                self.sampleTimeout?.cancel(); self.sampleTimeout = nil; self.sampleProcess = nil
                try? self.record(["event": "stack_capture_finished", "exit_status": completed.terminationStatus])
                if completed.terminationStatus != 0 {
                    DispatchQueue.main.async { [weak self] in self?.status = "Recording · stack capture unavailable; counters saved" }
                }
            }
        }
        do {
            try process.run(); sampleProcess = process
            try? record(["event": "sustained_load", "capture": sequence])
            let timeout = DispatchWorkItem { [weak process] in
                if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
            sampleTimeout = timeout
            queue.asyncAfter(deadline: .now() + 20, execute: timeout)
            DispatchQueue.main.async { [weak self] in self?.status = "Recording · sustained load captured" }
        } catch { try? record(["event": "stack_capture_unavailable"]) }
    }
    private func saveState(_ state: String) {
        guard let session, let data = try? JSONSerialization.data(withJSONObject: ["folder": session.lastPathComponent, "state": state]) else { return }
        try? data.write(to: root.appendingPathComponent("last-session.json"), options: .atomic)
    }
    private func finish(_ reason: String) {
        guard file != nil || timer != nil || session != nil else {
            DispatchQueue.main.async { [weak self] in self?.active = false; self?.status = reason }; return
        }
        timer?.cancel(); timer = nil
        if let process = sampleProcess, process.isRunning { kill(process.processIdentifier, SIGKILL) }
        sampleTimeout?.cancel(); sampleTimeout = nil; sampleProcess = nil
        try? record(["event": "ended", "reason": reason]); try? file?.close(); file = nil
        saveState(reason); session = nil
        DispatchQueue.main.async { [weak self] in self?.active = false; self?.status = reason }
    }
}
