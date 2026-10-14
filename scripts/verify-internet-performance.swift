import Foundation
import Darwin
import IslandCore

private final class StressProbe: InternetProbing {
    var completion: ((Bool) -> Void)?
    var starts = 0
    var cancellations = 0
    func start(address: String, completion: @escaping (Bool) -> Void) {
        precondition(self.completion == nil, "Overlapping probe")
        starts += 1
        self.completion = completion
    }
    func cancel() { cancellations += 1; completion = nil }
}

@main
struct VerifyInternetPerformance {
    static func footprint() -> UInt64 {
        var usage = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &usage) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(getpid(), RUSAGE_INFO_V2, $0) }
        }
        precondition(result == 0, "Cannot read process memory")
        return usage.ri_phys_footprint
    }
    static func cpuTime() -> Double {
        var usage = rusage()
        precondition(getrusage(RUSAGE_SELF, &usage) == 0)
        return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
    }
    static func main() {
        let probe = StressProbe()
        let monitor = InternetMonitor(probe: probe)
        func cycle(_ count: Int) {
            for index in 0..<count {
                monitor.start(address: "9.9.9.9", observePath: false)
                monitor.pathChanged(available: true)
                let stale = probe.completion!
                for _ in 0..<10 { monitor.pathChanged(available: true) }
                stale(true)
                precondition(monitor.probing == false, "Stale path reply accepted")
                monitor.pathChanged(available: false)
                monitor.stop()
                stale(true)
                precondition(!monitor.running && monitor.status == "Off")
                if index.isMultiple(of: 100) { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        cycle(1_000)
        let baseline = footprint()
        for batch in 1...3 {
            cycle(5_000)
            let bytes = footprint()
            print("stress_batch=\(batch) sessions=\(batch * 5_000) footprint_mib=\(Double(bytes) / 1_048_576)")
            precondition(bytes <= baseline + 16 * 1_048_576, "Repeated sessions accumulate memory")
        }
        precondition(probe.starts == 16_000 && probe.cancellations == 16_000, "Path storms bypass coalescing")
        let count = probe.starts
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        precondition(probe.starts == count, "Stopped stress sessions left a deadline running")

        // Exercise the real packet process at production cadence without leaving this Mac.
        let live = InternetMonitor()
        live.start(address: "127.0.0.1", observePath: false)
        live.pathChanged(available: true)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        precondition(live.state == .online)
        let liveCPU = cpuTime()
        let liveMemory = footprint()
        let started = ProcessInfo.processInfo.systemUptime
        for sample in 1...3 {
            RunLoop.current.run(until: Date().addingTimeInterval(31))
            precondition(live.state == .online && live.running)
            let elapsed = ProcessInfo.processInfo.systemUptime - started
            print("live_sample=\(sample) elapsed_s=\(elapsed) cpu_percent=\((cpuTime() - liveCPU) / elapsed * 100) footprint_mib=\(Double(footprint()) / 1_048_576)")
            precondition(footprint() <= liveMemory + 8 * 1_048_576, "Real probe sessions accumulate memory")
        }
        live.stop()
        print("Internet performance: 16,000 sessions, 160,000 repeated path events, bounded memory, no leftover deadlines and real loopback probes at 30-second cadence passed")
    }
}
