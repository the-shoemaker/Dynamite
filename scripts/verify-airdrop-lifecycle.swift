import Foundation

// Controlled receipt source: exercise the production monitor without requesting
// Downloads permission or touching real received files.
final class AirDropReceiptMonitor {
    static var latest: AirDropReceiptMonitor!
    struct Delivery { let urls: [URL]; let receiptIDs: Set<String>; let isNew: Bool }
    var onReceipt: ((Delivery) -> Void)?
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
        oldReceipt(.init(urls: [sample], receiptIDs: ["first"], isNew: true))
        precondition(monitor.transfer?.title == "SamplePhoto.heic" && events == 1)
        monitor.dismiss()
        precondition(monitor.transfer == nil && events == 2)
        monitor.dismiss()
        precondition(events == 2, "Repeated dismissal emitted state changes")
        monitor.stop()
        oldReceipt(.init(urls: [sample], receiptIDs: ["first"], isNew: true))
        precondition(monitor.transfer == nil && events == 2)
        monitor.start()
        oldReceipt(.init(urls: [sample], receiptIDs: ["first"], isNew: true)); oldStatus("stale")
        precondition(monitor.transfer == nil && monitor.status != "stale" && events == 2)
        AirDropReceiptMonitor.latest.onReceipt?(.init(urls: [], receiptIDs: [], isNew: true))
        precondition(events == 2)
        AirDropReceiptMonitor.latest.onReceipt?(.init(urls: [sample, sample.appendingPathExtension("copy")], receiptIDs: ["second"], isNew: true))
        precondition(monitor.transfer?.title == "2 files received" && events == 3)
        let transferID = monitor.transfer!.id
        let late = sample.appendingPathExtension("late")
        AirDropReceiptMonitor.latest.onReceipt?(.init(urls: [late], receiptIDs: ["second"], isNew: false))
        precondition(monitor.transfer?.urls.count == 3 && monitor.transfer?.id == transferID && events == 4, "Continuation must update the same card")
        AirDropReceiptMonitor.latest.onReceipt?(.init(urls: [late], receiptIDs: ["first"], isNew: false))
        precondition(events == 4, "Old continuation changed an unrelated card")
        monitor.dismiss()
        AirDropReceiptMonitor.latest.onReceipt?(.init(urls: [late], receiptIDs: ["second"], isNew: false))
        precondition(monitor.transfer == nil && events == 5, "Continuation reopened a dismissed card")
        AirDropReceiptMonitor.latest.onReceipt?(.init(urls: [sample], receiptIDs: ["third"], isNew: true))
        monitor.stop()
        precondition(monitor.transfer == nil && events == 7, "Stop did not clear downstream receipt state")
        print("AirDrop lifecycle: receipt, dismiss, stop, stale callback after restart, empty receipt, multi-file receipt, late files, dismissed and unrelated continuations passed")
    }
}
