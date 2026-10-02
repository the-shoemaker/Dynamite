import AppKit
import Combine

/// Completed receipts only. Incoming requests/progress remain with macOS.
final class AirDropMonitor: ObservableObject {
    struct Transfer {
        let id: String
        let title: String
        let urls: [URL]
    }
    @Published private(set) var status = "Off"
    @Published private(set) var transfer: Transfer?
    var onChange: ((Transfer?) -> Void)?
    private let receipts: AirDropReceiptMonitor
    private var running = false
    private var generation = UUID()
    private var transferReceiptIDs = Set<String>()
    init(receipts: AirDropReceiptMonitor = AirDropReceiptMonitor()) { self.receipts = receipts }
    func start() {
        guard !running else { return }
        running = true
        generation = UUID()
        let token = generation
        receipts.onStatus = { [weak self] value in
            guard let self, self.running, self.generation == token else { return }
            self.status = value
        }
        receipts.onReceipt = { [weak self] delivery in
            guard let self, self.running, self.generation == token, !delivery.urls.isEmpty else { return }
            var urls = delivery.urls
            let id: String
            if delivery.isNew {
                id = UUID().uuidString
                self.transferReceiptIDs = delivery.receiptIDs
            } else {
                // Late files in the same receipt can update an open card, but
                // an old receipt must never reopen a dismissed/stopped card.
                guard let transfer = self.transfer,
                      !self.transferReceiptIDs.isDisjoint(with: delivery.receiptIDs) else { return }
                id = transfer.id
                urls = Array(Set(transfer.urls + urls)).sorted { $0.lastPathComponent < $1.lastPathComponent }
                self.transferReceiptIDs.formUnion(delivery.receiptIDs)
            }
            let value = Transfer(id: id,
                title: urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files received", urls: urls)
            self.transfer = value
            self.status = "AirDrop received"
            self.onChange?(value)
        }
        receipts.start()
        status = "Starting receipt observer"
    }
    func stop() {
        let hadTransfer = transfer != nil
        running = false
        generation = UUID()
        receipts.stop()
        transfer = nil
        transferReceiptIDs.removeAll()
        status = "Off"
        if hadTransfer { onChange?(nil) }
    }
    func dismiss() {
        guard transfer != nil else { return }
        transfer = nil
        transferReceiptIDs.removeAll()
        onChange?(nil)
    }
    func openReceived() {
        guard let urls = transfer?.urls, !urls.isEmpty else { return }
        if urls.count == 1 { NSWorkspace.shared.open(urls[0]) }
        else { NSWorkspace.shared.activateFileViewerSelecting(urls) }
        dismiss()
    }
    func revealReceived() {
        guard let urls = transfer?.urls, !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        dismiss()
    }
}
