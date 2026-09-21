import Foundation
import IslandCore

/// Watches only Clock's timer preferences. Directory events cover atomic file
/// replacement; a file watch covers in-place writes. Unrelated changes cost only
/// a stat of this exact path, never a directory scan or preference read.
final class ClockTimerStore {
    private let queue: DispatchQueue
    private let url: URL
    private let usesLivePreferences: Bool
    private var source: DispatchSourceFileSystemObject?
    private var directorySource: DispatchSourceFileSystemObject?
    private(set) var records: [ClockTimerRecord]?
    var onChange: (() -> Void)?
    private var running = false
    private var refreshWork: DispatchWorkItem?
    private var signature: Signature?
    private struct Signature: Equatable {
        let inode: UInt64
        let size: Int64
        let seconds: Int
        let nanoseconds: Int
    }
    init(queue: DispatchQueue, url: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/com.apple.mobiletimerd.plist")) {
        self.queue = queue; self.url = url
        usesLivePreferences = url.lastPathComponent == "com.apple.mobiletimerd.plist" && url.deletingLastPathComponent() == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences")
    }
    func start() {
        guard !running else { return }
        running = true
        let fd = open(url.deletingLastPathComponent().path, O_EVTONLY)
        if fd >= 0 {
            let next = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: queue)
            next.setCancelHandler { close(fd) }
            next.setEventHandler { [weak self] in self?.scheduleRefresh() }
            directorySource = next; next.resume()
        }
        reload()
    }
    func stop() {
        running = false
        refreshWork?.cancel(); refreshWork = nil
        source?.cancel(); source = nil
        directorySource?.cancel(); directorySource = nil
        records = nil; signature = nil
    }
    private func currentSignature() -> Signature? {
        var value = stat()
        guard stat(url.path, &value) == 0 else { return nil }
        return Signature(inode: value.st_ino, size: value.st_size,
            seconds: value.st_mtimespec.tv_sec, nanoseconds: value.st_mtimespec.tv_nsec)
    }
    private func scheduleRefresh() {
        guard running, refreshWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.running else { return }
            self.refreshWork = nil
            guard self.currentSignature() != self.signature else { return }
            self.reload(); self.onChange?()
        }
        refreshWork = work
        queue.asyncAfter(deadline: .now() + 0.025, execute: work)
    }
    func reload() {
        guard running else { return }
        let next = currentSignature()
        if source == nil || next?.inode != signature?.inode { watchFile() }
        signature = next
        // cfprefsd can delay writing the plist by several seconds. This client
        // never sets values; synchronize refreshes its view of Clock's domain.
        if usesLivePreferences {
            let domain = "com.apple.mobiletimerd" as CFString
            CFPreferencesAppSynchronize(domain)
            if let value = CFPreferencesCopyAppValue("MTTimers" as CFString, domain),
               let data = try? PropertyListSerialization.data(fromPropertyList: ["MTTimers": value], format: .binary, options: 0),
               let values = try? ClockTimerRecord.decode(data) {
                records = values
                return
            }
        }
        if let next, next.size < 2_000_000,
           let data = try? Data(contentsOf: url), let values = try? ClockTimerRecord.decode(data) {
            records = values
        } else { records = nil }
    }
    private func watchFile() {
        source?.cancel(); source = nil
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let next = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
        next.setCancelHandler { close(fd) }
        next.setEventHandler { [weak self] in self?.scheduleRefresh() }
        source = next; next.resume()
    }
}
