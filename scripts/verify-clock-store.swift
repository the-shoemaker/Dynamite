import Foundation
import IslandCore

@main struct VerifyClockStore {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("timers.plist")
        func fixture(_ seconds: Int) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: ["MTTimers": ["MTTimers": [["$MTTimer": [
                "MTTimerID": "8A196148-DE4A-4B0A-BB5F-46740FA8177C", "MTTimerState": 2,
                "MTTimerDuration": 120.0, "MTTimerFireTime": ["$MTTimerTimeInterval": ["MTTimerTimeInterval": Double(seconds)]]
            ]]]]], format: .binary, options: 0)
        }
        try fixture(100).write(to: file, options: .atomic)
        let queue = DispatchQueue(label: "verify.clock.store")
        let changed = DispatchSemaphore(value: 0)
        let store = ClockTimerStore(queue: queue, url: file)
        queue.sync { store.onChange = { changed.signal() }; store.start() }
        defer { queue.sync { store.stop() } }
        func check(_ seconds: Int) {
            precondition(queue.sync { store.records?.first?.reading(at: Date()).remaining } == seconds)
        }
        check(100)
        for value in 80..<90 {
            try fixture(value).write(to: file, options: .atomic)
            precondition(changed.wait(timeout: .now() + 2) == .success, "Missed atomic replacement")
            check(value)
        }
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: fixture(50))
        try handle.close()
        precondition(changed.wait(timeout: .now() + 2) == .success, "Missed in-place write")
        check(50)
        try Data("unrelated".utf8).write(to: directory.appendingPathComponent("other.plist"), options: .atomic)
        precondition(changed.wait(timeout: .now() + 0.2) == .timedOut, "Unrelated file triggered a timer update")
        print("PASS: initial read, 10 atomic replacements, in-place write, unrelated file ignored")
    }
}
