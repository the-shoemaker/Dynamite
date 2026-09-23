import Foundation

@main struct VerifyDiagnostic {
    static func wait(_ seconds: Double) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("diagnostic-test-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let recorder = PerformanceDiagnostic(root: root, interval: 0.03, duration: 0.2)
        recorder.start(); recorder.start()
        wait(0.4)
        precondition(!recorder.active && recorder.status == "Completed 12-hour test")
        let first = recorder.folder!
        let text = try String(contentsOf: first.appendingPathComponent("metrics.jsonl"), encoding: .utf8)
        let rows = try text.split(separator: "\n").map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
        precondition(rows.first?["event"] as? String == "started")
        precondition(rows.last?["event"] as? String == "ended")
        let samples = rows.filter { $0["event"] as? String == "sample" }
        precondition(samples.count >= 2 && samples.count <= 9)
        precondition((samples[0]["physical_footprint_bytes"] as? NSNumber)?.uint64Value ?? 0 > 0)
        let before = try Data(contentsOf: first.appendingPathComponent("metrics.jsonl"))
        wait(0.15)
        let after = try Data(contentsOf: first.appendingPathComponent("metrics.jsonl"))
        precondition(after == before)
        for _ in 0..<3 { recorder.start(); wait(0.08); recorder.stop(); wait(0.1); precondition(!recorder.active) }
        let runs = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("run-") }
        precondition(runs.count == 3, "retained \(runs.count) runs; status \(recorder.status)")
        let restored = PerformanceDiagnostic(root: root)
        precondition(restored.status == "Stopped" && restored.folder != nil)
        recorder.start(); wait(0.05)
        let interrupted = PerformanceDiagnostic(root: root)
        precondition(interrupted.status.contains("interrupted"))
        recorder.shutdown(); wait(0.05)
        precondition(!recorder.active)
        if CommandLine.arguments.contains("--capture") {
        let capturing = PerformanceDiagnostic(root: root, interval: 0.05, duration: 6)
        capturing.start(); wait(0.1)
        DispatchQueue.global().async {
            let until = Date().addingTimeInterval(0.7)
            while Date() < until { _ = ProcessInfo.processInfo.systemUptime }
        }
        wait(4.5)
        let captureLog = try String(contentsOf: capturing.folder!.appendingPathComponent("metrics.jsonl"), encoding: .utf8)
        precondition(captureLog.contains("sustained_load"), "Real CPU load did not trigger capture: \(captureLog.prefix(2500))")
        precondition(captureLog.contains("stack_capture_finished"), "Stack capture did not finish")
        let stack = try Data(contentsOf: capturing.folder!.appendingPathComponent("stack-1.txt"))
        precondition(!stack.isEmpty, "Stack capture produced no evidence")
        capturing.shutdown(); wait(0.05)
        print("Diagnostic: sustained real CPU load triggered a completed stack sample")
        }
        print("Diagnostic: real CPU/memory counters, duplicate start, timed completion, stop, restart, retention, interruption marker and shutdown passed")
    }
}
