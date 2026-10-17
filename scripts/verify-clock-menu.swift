import AppKit
import IslandCore

@main
struct VerifyClockMenu {
    static func main() throws {
        // An isolated paused mirror reproduces the stale menu case without
        // starting, pausing, cancelling, or editing any of the user's timers.
        guard NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.clock").isEmpty else {
            print("SKIP: Close Clock to verify the mirrored-only timer scenario")
            return
        }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("timers.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: ["MTTimers": ["MTTimers": [["$MTTimer": [
            "MTTimerID": "8A196148-DE4A-4B0A-BB5F-46740FA8177C", "MTTimerState": 2,
            "MTTimerDuration": 120.0,
            "MTTimerFireTime": ["$MTTimerTimeInterval": ["MTTimerTimeInterval": 90.0]]
        ]]]]], format: .binary, options: 0)
        try data.write(to: file)
        let monitor = ClockMonitor(timerStoreURL: file)
        monitor.start()
        let deadline = Date().addingTimeInterval(3)
        while monitor.reading == nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        precondition(monitor.reading?.paused == true, "Fixture must produce a real mirrored paused reading")
        var completed = false
        monitor.menuReading { value in
            precondition(Thread.isMainThread, "Menu callback must run on the UI thread")
            precondition(value == nil, "A mirror without open Clock controls must not produce timer menu actions")
            completed = true
        }
        let checkDeadline = Date().addingTimeInterval(3)
        while !completed && Date() < checkDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        precondition(completed)
        monitor.togglePauseFromMenu()
        monitor.cancelFromMenu()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        precondition(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.clock").isEmpty,
                     "Menu-only actions must never launch Clock")
        let unchanged = try Data(contentsOf: file)
        precondition(unchanged == data, "Menu checks must not modify the mirrored timer")
        monitor.stop()
        print("PASS: mirrored paused timer has no menu controls, checks run asynchronously, menu actions do not open Clock or modify timers")
    }
}
