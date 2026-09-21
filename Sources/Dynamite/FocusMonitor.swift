import Foundation
import Combine
import IslandCore

/// File events only. Full Disk Access is requested in settings, never bypassed.
final class FocusMonitor: ObservableObject {
    @Published private(set) var status = "Off"
    var onChange: ((Activity) -> Void)?
    var onAvailability: ((Bool) -> Void)?
    private var available = false
    private let queue = DispatchQueue(label: "com.dan.dynomite.focus", qos: .utility)
    private let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")
    private var source: DispatchSourceFileSystemObject?
    private var enabled = false
    private var previous: FocusReading?
    func start() {
        queue.async { [weak self] in
            guard let self, !self.enabled else { return }
            self.enabled = true
            self.read()
            let fd = open(self.directory.path, O_EVTONLY)
            guard fd >= 0 else { self.publish("Needs Full Disk Access"); return }
            let watcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: self.queue)
            watcher.setEventHandler { [weak self] in self?.read() }
            watcher.setCancelHandler { close(fd) }
            self.source = watcher
            watcher.resume()
        }
    }
    func refresh() {
        stop()
        start()
    }
    func stop() {
        queue.async { [weak self] in
            self?.enabled = false
            self?.source?.cancel(); self?.source = nil
            self?.previous = nil
            self?.setAvailability(false)
            self?.publish("Off")
        }
    }
    private func read() {
        guard enabled else { return }
        do {
            let data = try Data(contentsOf: directory.appendingPathComponent("Assertions.json"))
            let reading = try FocusReading.decode(data)
            setAvailability(true)
            let old = previous
            previous = reading
            publish(reading == .off ? "Focus off" : "Focus on")
            guard let old, old != reading else { return }
            let identifier: String
            let active: Bool
            switch reading {
            case .active(let id): identifier = id; active = true
            case .off:
                guard case .active(let id) = old else { return }
                identifier = id; active = false
            }
            let known: [String: (String, String)] = [
                "com.apple.donotdisturb.mode.default": ("Do Not Disturb", "moon.fill"),
                "com.apple.focus.work": ("Work", "briefcase.fill"),
                "com.apple.focus.personal": ("Personal", "person.fill"),
                "com.apple.sleep.sleep-mode": ("Sleep", "bed.double.fill")
            ]
            let appearance = known[identifier] ?? ("Focus", "moon.fill")
            let activity = Activity(.focus, value: 0, label: appearance.0, symbol: appearance.1, isActive: active)
            DispatchQueue.main.async { [weak self] in self?.onChange?(activity) }
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            setAvailability(false)
            publish("Needs Full Disk Access")
        } catch {
            setAvailability(false)
            // A partially rewritten file must not invent an off transition.
            publish("Focus data unavailable")
        }
    }
    private func setAvailability(_ value: Bool) {
        guard available != value else { return }
        available = value
        DispatchQueue.main.async { [weak self] in self?.onAvailability?(value) }
    }
    private func publish(_ value: String) { DispatchQueue.main.async { [weak self] in self?.status = value } }
}
