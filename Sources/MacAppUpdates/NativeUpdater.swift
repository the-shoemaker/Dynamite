import AppKit
import Combine
import Sparkle

/// Reusable by any unsandboxed macOS app. Configuration and trust belong to the
/// host bundle; the app never accepts a feed URL from an incoming notification.
public final class NativeUpdater: NSObject, ObservableObject {
    @Published public private(set) var isConfigured = false
    @Published public private(set) var canCheck = false
    @Published public private(set) var status = "Updates aren’t published yet."
    @Published public private(set) var lastChecked: Date?
    @Published public var automaticallyChecks = false {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticallyChecks }
    }
    private var controller: SPUStandardUpdaterController?
    private var observations: [NSKeyValueObservation] = []

    public override init() { super.init() }
    public func start() {
        guard controller == nil else { return }
        let bundle = Bundle.main
        guard let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil, url.fragment == nil,
              let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        do {
            try controller.updater.start()
            isConfigured = true
            status = "Checks this app’s feed for signed releases."
            automaticallyChecks = controller.updater.automaticallyChecksForUpdates
            observations = [
                controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                    DispatchQueue.main.async { self?.canCheck = updater.canCheckForUpdates }
                },
                controller.updater.observe(\.lastUpdateCheckDate, options: [.initial, .new]) { [weak self] updater, _ in
                    DispatchQueue.main.async { self?.lastChecked = updater.lastUpdateCheckDate }
                }
            ]
        } catch {
            status = "Updates could not start: \(error.localizedDescription)"
        }
    }
    public func checkForUpdates() {
        guard let controller, isConfigured else {
            let alert = NSAlert()
            alert.messageText = "Updates aren’t published yet"
            alert.informativeText = "This build doesn’t have a release feed. Update checking will be available when signed releases are published."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }
        controller.checkForUpdates(nil)
    }
}
