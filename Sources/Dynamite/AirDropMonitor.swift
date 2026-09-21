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
    private let receipts = AirDropReceiptMonitor()
    private var running = false
    private var generation = UUID()
    func start() {
        guard !running else { return }
        running = true
        generation = UUID()
        let token = generation
        receipts.onStatus = { [weak self] value in
            guard let self, self.running, self.generation == token else { return }
            self.status = value
        }
        receipts.onReceipt = { [weak self] urls in
            guard let self, self.running, self.generation == token, !urls.isEmpty else { return }
            let value = Transfer(id: UUID().uuidString,
                title: urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files received", urls: urls)
            self.transfer = value
            self.status = "AirDrop received"
            self.onChange?(value)
        }
        receipts.start()
        status = "Starting receipt observer"
    }
    func stop() {
        running = false
        generation = UUID()
        receipts.stop()
        transfer = nil
        status = "Off"
    }
    func dismiss() {
        transfer = nil
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
