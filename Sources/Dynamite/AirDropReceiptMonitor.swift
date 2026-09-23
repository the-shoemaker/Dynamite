import Foundation
import CoreServices
import Darwin
import IslandCore

/// Watches Downloads metadata only. No content reads, directory polling, or
/// guesses based on a file appearing. The quarantine agent must be sharingd.
final class AirDropReceiptMonitor {
    var onReceipt: (([URL]) -> Void)?
    var onStatus: ((String) -> Void)?
    private let queue = DispatchQueue(label: "com.dan.dynomite.airdrop.receipts", qos: .utility)
    private let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].standardizedFileURL
    private var stream: FSEventStreamRef?
    private var generation = UUID()
    private var startedAt: TimeInterval = 0
    private var seen = Set<String>()
    private var pending: [String: URL] = [:]
    private var retrying = Set<URL>()
    private var publishWork: DispatchWorkItem?

    func start() {
        queue.async { [weak self] in
            guard let self, self.stream == nil else { return }
            self.generation = UUID()
            self.startedAt = Date().timeIntervalSince1970
            self.seen.removeAll()
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
            guard FSEventStreamStart(stream) else { self.stopOnQueue(); self.report("Downloads observer unavailable"); return }
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
        pending.removeAll(); seen.removeAll(); retrying.removeAll()
    }
    private func report(_ value: String) {
        let callback = onStatus
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
            since: startedAt, now: Date().timeIntervalSince1970), FileManager.default.fileExists(atPath: url.path) {
            let key = receipt.identifier + ":" + url.path
            guard seen.insert(key).inserted else { return }
            pending[key] = url
            guard publishWork == nil else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.stream != nil, self.generation == token else { return }
                self.publishWork = nil
                let urls = Array(self.pending.values).sorted { $0.lastPathComponent < $1.lastPathComponent }
                self.pending.removeAll()
                let callback = self.onReceipt
                DispatchQueue.main.async { callback?(urls) }
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
}
