import Foundation
import IslandCore

final class Probe: InternetProbing {
    var requests: [(String, (Bool) -> Void)] = []
    var cancellations = 0
    func start(address: String, completion: @escaping (Bool) -> Void) { requests.append((address, completion)) }
    func cancel() { cancellations += 1 }
    func reply(_ reachable: Bool) { requests.last!.1(reachable) }
}
@main
struct VerifyInternetLifecycle {
    static func main() {
        let probe = Probe()
        let monitor = InternetMonitor(probe: probe)
        var events: [(InternetState, Bool)] = []
        monitor.onChange = { events.append(($0, $1)) }
        monitor.refresh()
        monitor.pathChanged(available: true)
        precondition(probe.requests.isEmpty, "Disabled monitoring started a probe")
        monitor.start(address: "9.9.9.9", observePath: false)
        precondition(probe.requests.isEmpty, "No probes before a usable route")
        monitor.pathChanged(available: true)
        precondition(probe.requests.count == 1)
        monitor.refresh()
        precondition(probe.requests.count == 1, "Overlapping probe")
        probe.reply(true)
        precondition(monitor.state == .online && events.last!.1 == false, "Launch online must be quiet")
        let settledCount = probe.requests.count
        let cancelledCount = probe.cancellations
        for _ in 0..<100 { monitor.pathChanged(available: true) }
        precondition(probe.requests.count == settledCount, "Path burst launched extra probes")
        precondition(probe.cancellations == cancelledCount, "Path burst queued unnecessary cancellation")
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        precondition(probe.requests.count == settledCount + 1, "Settled path burst must launch exactly one probe")
        probe.reply(true)
        monitor.refresh()
        let oldReply = probe.requests.last!.1
        monitor.pathChanged(available: false)
        precondition(monitor.state == .offline && !monitor.probing)
        let count = probe.requests.count
        monitor.refresh()
        precondition(probe.requests.count == count, "No ping without a route")
        oldReply(true)
        precondition(monitor.state == .offline, "Cancelled probe resurrected online")
        monitor.pathChanged(available: true)
        probe.reply(true)
        precondition(monitor.state == .online && events.last!.1, "Recovery needs a transition")
        probe.reply(false) // Duplicate completion from the previous packet.
        monitor.refresh(); probe.reply(false)
        precondition(monitor.state == .online, "One lost packet cannot announce offline")
        monitor.refresh(); probe.reply(false)
        precondition(monitor.state == .offline)
        monitor.refresh()
        let staleConfigurationReply = probe.requests.last!.1
        monitor.start(address: "8.8.8.8", observePath: false)
        staleConfigurationReply(true)
        precondition(monitor.state == .checking, "Old target callback was accepted")
        monitor.pathChanged(available: true)
        precondition(probe.requests.last!.0 == "8.8.8.8")
        let before = probe.requests.count
        monitor.start(address: "8.8.8.8", observePath: false)
        precondition(probe.requests.count == before, "Same configuration restarted monitoring")
        let stoppedReply = probe.requests.last!.1
        probe.reply(false) // Arm the short two-second confirmation deadline.
        monitor.stop()
        monitor.refresh(); monitor.pathChanged(available: true); stoppedReply(true)
        precondition(!monitor.running && !monitor.probing && probe.requests.count == before && monitor.status == "Off")
        RunLoop.current.run(until: Date().addingTimeInterval(2.4))
        precondition(probe.requests.count == before, "Stopped confirmation deadline sent another ping")
        // Check the actual ping invocation without sending traffic outside this Mac.
        let live = InternetPing()
        var result: Bool?
        live.start(address: "127.0.0.1") { result = $0 }
        let deadline = Date().addingTimeInterval(4)
        while result == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
        live.cancel()
        precondition(result == true, "Loopback ICMP probe failed")
        print("Internet lifecycle: quiet baseline, coalesced path bursts, no-route silence, no overlapping probes, packet loss confirmation, immediate recovery, stale callbacks, target changes, stop/restart and real loopback ping passed")
    }
}
