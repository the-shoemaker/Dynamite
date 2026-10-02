import Foundation
import CoreServices
import Darwin
import IslandCore

/// Watches Downloads metadata only. No content reads, directory polling, or
/// guesses based on a file appearing. The quarantine agent must be sharingd.
final class AirDropReceiptMonitor {
    struct Delivery {
        let urls: [URL]
        let receiptIDs: Set<String>
        let isNew: Bool
    }
    var onReceipt: ((Delivery) -> Void)?
    var onStatus: ((String) -> Void)?
    private let queue = DispatchQueue(label: "com.dan.dynomite.airdrop.receipts", qos: .utility)
    private let queueKey = DispatchSpecificKey<Bool>()
    private var receiptCallback: ((Delivery) -> Void)?
    private var statusCallback: ((String) -> Void)?
    private let directory: URL
    private var stream: FSEventStreamRef?
    private var generation = UUID()
    private var startedAt: TimeInterval = 0
    // A quarantine UUID identifies a receipt, not its mutable Downloads path.
    // Keep consumed receipts across stop/start, including same-second restarts.
    private var delivered = Set<String>()
    private var deliveredFiles = Set<String>()
    private struct PendingReceipt { let receipt: AirDropReceipt; let fileID: String; let url: URL }
    private var pending: [String: PendingReceipt] = [:]
    private var retrying = Set<URL>()
    private var publishWork: DispatchWorkItem?

    init(directory: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]) {
        self.directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        queue.setSpecific(key: queueKey, value: true)
    }

    func start() {
        // Capture callbacks on the caller's thread. Queued publications must
        // retain their own session's callbacks through a rapid stop/start.
        let receiptCallback = onReceipt
        let statusCallback = onStatus
        queue.async { [weak self] in
            guard let self, self.stream == nil else { return }
            self.generation = UUID()
            self.receiptCallback = receiptCallback
            self.statusCallback = statusCallback
            self.startedAt = Date().timeIntervalSince1970
            var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
            let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagIgnoreSelf)
            guard let stream = FSEventStreamCreate(nil, { _, context, count, paths, flags, _ in
                guard let context else { return }
                let owner = Unmanaged<AirDropReceiptMonitor>.fromOpaque(context).takeUnretainedValue()
                let values = unsafeBitCast(paths, to: NSArray.self) as? [String] ?? []
                for i in 0..<min(count, values.count) {
                    let relevant = UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemXattrMod)
                    if flags[i] & relevant != 0 { owner.inspect(URL(fileURLWithPath: values[i]), attempt: 0, token: owner.generation) }
                }
            }, &context, [self.directory.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.25, flags) else {
                self.report("Downloads observer unavailable"); return
            }
            self.stream = stream
            FSEventStreamSetDispatchQueue(stream, self.queue)
            guard FSEventStreamStart(stream) else { self.report("Downloads observer unavailable"); self.stopOnQueue(); return }
            // This checks folder permission once; existing files are never announced.
            do { _ = try self.directory.resourceValues(forKeys: [.isReadableKey])
                let fd = open(self.directory.path, O_RDONLY | O_DIRECTORY)
                if fd >= 0 { close(fd); self.report("Watching AirDrop receipts") }
                else { self.report("Allow Downloads access to show received files") }
            } catch { self.report("Allow Downloads access to show received files") }
        }
    }
    func stop() { queue.async { [weak self] in self?.stopOnQueue() } }
    private func stopOnQueue() {
        generation = UUID()
        if let stream { FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream) }
        stream = nil
        publishWork?.cancel(); publishWork = nil
        pending.removeAll(); retrying.removeAll()
        receiptCallback = nil; statusCallback = nil
    }
    private func report(_ value: String) {
        let callback = statusCallback
        DispatchQueue.main.async { callback?(value) }
    }
    private func inspect(_ input: URL, attempt: Int, token: UUID) {
        guard stream != nil, generation == token else { return }
        let url = input.standardizedFileURL
        guard url.deletingLastPathComponent() == directory, !url.lastPathComponent.hasPrefix(".") else { return }
        guard attempt != 0 || !retrying.contains(url) else { return }
        var buffer = [UInt8](repeating: 0, count: 1024)
        let count = getxattr(url.path, "com.apple.quarantine", &buffer, buffer.count, 0, XATTR_NOFOLLOW)
        if count > 0, let receipt = AirDropReceipt(quarantine: String(decoding: buffer.prefix(count), as: UTF8.self),
            since: startedAt, now: Date().timeIntervalSince1970), let fileID = fileIdentity(url) {
            let key = receipt.identifier + ":" + fileID
            guard !deliveredFiles.contains(key) else { return }
            pending[key] = PendingReceipt(receipt: receipt, fileID: fileID, url: url)
            guard publishWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.stream != nil, self.generation == token else { return }
                self.publishWork = nil
                // A file can be renamed, deleted, or replaced during batching.
                // Only offer actions for the same file and receipt we inspected.
                let values = self.pending.values.filter { value in
                    guard self.fileIdentity(value.url) == value.fileID else { return false }
                    return self.receiptIdentifier(value.url) == value.receipt.identifier
                }
                let urls = values.map(\.url).sorted { $0.lastPathComponent < $1.lastPathComponent }
                let receiptIDs = Set(values.map { $0.receipt.identifier })
                let isNew = !receiptIDs.isSubset(of: self.delivered)
                self.delivered.formUnion(receiptIDs)
                for value in values { self.deliveredFiles.insert(value.receipt.identifier + ":" + value.fileID) }
                self.pending.removeAll()
                guard !urls.isEmpty else { return }
                let callback = self.receiptCallback
                let delivery = Delivery(urls: urls, receiptIDs: receiptIDs, isNew: isNew)
                DispatchQueue.main.async { callback?(delivery) }
            }
            publishWork = work
            queue.asyncAfter(deadline: .now() + 0.45, execute: work)
        } else if attempt < 3 {
            retrying.insert(url)
            queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.generation == token else { return }
                self.retrying.remove(url)
                self.inspect(url, attempt: attempt + 1, token: token)
            }
        }
    }
    private func fileIdentity(_ url: URL) -> String? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType != .typeSymbolicLink,
              let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else { return nil }
        return "\(device):\(inode)"
    }
    private func receiptIdentifier(_ url: URL) -> String? {
        var buffer = [UInt8](repeating: 0, count: 1024)
        let count = getxattr(url.path, "com.apple.quarantine", &buffer, buffer.count, 0, XATTR_NOFOLLOW)
        guard count > 0 else { return nil }
        return AirDropReceipt(quarantine: String(decoding: buffer.prefix(count), as: UTF8.self),
                              since: startedAt, now: Date().timeIntervalSince1970)?.identifier
    }
    deinit {
        if DispatchQueue.getSpecific(key: queueKey) == true { stopOnQueue() }
        else { queue.sync { stopOnQueue() } }
    }
}
