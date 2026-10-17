import AppKit
import IslandCore

@main
struct VerifyClockMenu {
    static func main() throws {
        let expected = ClockReading(identifier: "8A196148-DE4A-4B0A-BB5F-46740FA8177C", remaining: 90, paused: true)
        let resumed = ClockReading(identifier: expected.identifier, remaining: 89, paused: false)
        let otherTimer = ClockReading(identifier: "7E353E12-4067-4C26-B3E4-258E288FA743", remaining: 90, paused: true)
        precondition(ClockMonitor.acceptsMenuAction(expected, current: expected, cancel: false))
        precondition(!ClockMonitor.acceptsMenuAction(expected, current: resumed, cancel: false),
                     "An old Resume menu item must not pause a timer that has since resumed")
        precondition(ClockMonitor.acceptsMenuAction(expected, current: resumed, cancel: true),
                     "Cancel still addresses the same timer after its pause state changes")
        for cancel in [false, true] {
            precondition(!ClockMonitor.acceptsMenuAction(expected, current: otherTimer, cancel: cancel),
                         "A menu action must never affect a different timer")
        }
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
        var backgroundOpenRequests = 0
        let monitor = ClockMonitor(timerStoreURL: file, backgroundControlOpener: {
            precondition(Thread.isMainThread)
            backgroundOpenRequests += 1
        })
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
        monitor.togglePauseFromMenu(expected)
        monitor.cancelFromMenu(expected)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        precondition(backgroundOpenRequests == 0, "Menu actions must never request opening Clock")
        precondition(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.clock").isEmpty,
                     "Menu-only actions must never launch Clock")
        let unchanged = try Data(contentsOf: file)
        precondition(unchanged == data, "Menu checks must not modify the mirrored timer")
        monitor.togglePause()
        RunLoop.current.run(until: Date().addingTimeInterval(1.1))
        precondition(backgroundOpenRequests == 1,
                     "A compact control must request Clock once when only the mirrored timer exists")
        precondition(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.clock").isEmpty,
                     "The injected background opener must not launch the user's Clock")
        let afterCompact = try Data(contentsOf: file)
        precondition(afterCompact == data, "Compact retries must not edit the mirror")
        monitor.stop()
        print("PASS: menu actions reject stale timer identities/states, mirrored-only menus stay unavailable, compact controls request a bounded background open, and timers remain untouched")
    }
}
