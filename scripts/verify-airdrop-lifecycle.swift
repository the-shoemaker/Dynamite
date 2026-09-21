import Foundation

// Controlled receipt source: exercise the production monitor without requesting
// Downloads permission or touching real received files.
final class AirDropReceiptMonitor {
    static var latest: AirDropReceiptMonitor!
    var onReceipt: (([URL]) -> Void)?
    var onStatus: ((String) -> Void)?
    init() { Self.latest = self }
    func start() {}
    func stop() {}
}
@main struct VerifyAirDropLifecycle {
    static func main() {
        let monitor = AirDropMonitor()
        var events = 0
        monitor.onChange = { _ in events += 1 }
        monitor.start()
        let oldReceipt = AirDropReceiptMonitor.latest.onReceipt!
        let oldStatus = AirDropReceiptMonitor.latest.onStatus!
        let sample = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SamplePhoto.heic")
        oldReceipt([sample])
        precondition(monitor.transfer?.title == "SamplePhoto.heic" && events == 1)
        monitor.dismiss()
        precondition(monitor.transfer == nil && events == 2)
        monitor.stop()
        oldReceipt([sample])
        precondition(monitor.transfer == nil && events == 2)
        monitor.start()
        oldReceipt([sample]); oldStatus("stale")
        precondition(monitor.transfer == nil && monitor.status != "stale" && events == 2)
        AirDropReceiptMonitor.latest.onReceipt?([])
        precondition(events == 2)
        AirDropReceiptMonitor.latest.onReceipt?([sample, sample.appendingPathExtension("copy")])
        precondition(monitor.transfer?.title == "2 files received" && events == 3)
        monitor.stop()
        print("AirDrop lifecycle: receipt, dismiss, stop, stale callback after restart, empty receipt, multi-file receipt passed")
    }
}
