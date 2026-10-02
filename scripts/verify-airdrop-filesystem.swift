import Foundation
import Darwin

// Drive the production FSEvents -> metadata -> card pipeline in a temporary
// Downloads directory. No real received files or Downloads permissions needed.
@main struct VerifyAirDropFilesystem {
    static func pump(_ seconds: Double) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { RunLoop.current.run(until: min(end, Date().addingTimeInterval(0.02))) }
    }
    static func wait(_ message: String, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(6)
        while !condition() && Date() < deadline { pump(0.02) }
        precondition(condition(), message)
    }
    static func run(_ executable: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        try! process.run(); process.waitUntilExit()
        precondition(process.terminationStatus == 0, "Fixture process failed")
    }
    static func quarantine(_ url: URL, id: UUID = UUID(), agent: String = "sharingd", stamp: TimeInterval = Date().timeIntervalSince1970, count: Int = 1) {
        let value = "0081;\(String(UInt64(stamp), radix: 16));\(agent);\(id.uuidString)"
        // Production ignores events from its own process. Emit metadata changes
        // in a child, as sharingd would, keeping that production flag enabled.
        run(CommandLine.arguments[0], ["--quarantine", url.path, value, String(count)])
    }
    static func main() throws {
        if CommandLine.arguments.count == 5 && CommandLine.arguments[1] == "--quarantine" {
            let value = CommandLine.arguments[3]
            for _ in 0..<Int(CommandLine.arguments[4])! {
                let result = value.withCString { setxattr(CommandLine.arguments[2], "com.apple.quarantine", $0, value.utf8.count, 0, XATTR_NOFOLLOW) }
                precondition(result == 0, "Could not write fixture quarantine metadata")
            }
            return
        }
        let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("dynamite-airdrop-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let monitor = AirDropMonitor(receipts: AirDropReceiptMonitor(directory: directory))
        var receipts: [[URL]] = []
        monitor.onChange = { if let transfer = $0 { receipts.append(transfer.urls) } }
        monitor.start()
        wait("Observer did not start") { monitor.status == "Watching AirDrop receipts" }
        let first = directory.appendingPathComponent("first.txt")
        let id = UUID()
        try Data("fixture".utf8).write(to: first)
        quarantine(first, id: id)
        wait("Fresh AirDrop was lost") { receipts.count == 1 }
        monitor.dismiss()

        let renamed = directory.appendingPathComponent("renamed.txt")
        run("/bin/mv", [first.path, renamed.path])
        pump(2)
        precondition(receipts.count == 1 && monitor.transfer == nil, "Renaming replayed a dismissed receipt")
        let copied = directory.appendingPathComponent("copied.txt")
        try FileManager.default.copyItem(at: renamed, to: copied)
        quarantine(copied, id: id)
        quarantine(renamed, id: id, count: 100)
        pump(2)
        precondition(receipts.count == 1 && monitor.transfer == nil, "Copy or metadata burst replayed an old receipt")

        monitor.stop(); monitor.start()
        wait("Restart did not start") { monitor.status == "Watching AirDrop receipts" }
        quarantine(renamed, id: id)
        pump(2)
        precondition(receipts.count == 1 && monitor.transfer == nil, "Restart replayed an old receipt")

        let fresh = directory.appendingPathComponent("next.txt")
        try Data("next".utf8).write(to: fresh)
        quarantine(fresh)
        wait("Next genuine receipt was lost") { receipts.count == 2 }
        precondition(monitor.transfer?.urls == [fresh])
        monitor.dismiss()

        let sharedID = UUID()
        let files = (0..<3).map { directory.appendingPathComponent("batch-\($0).txt") }
        for file in files { try Data("batch".utf8).write(to: file); quarantine(file, id: sharedID) }
        wait("Multi-file receipt was lost") { receipts.count == 3 }
        precondition(Set(receipts.last!) == Set(files), "Shared receipt UUID lost files in the batch")
        let transferID = monitor.transfer!.id
        let late = directory.appendingPathComponent("late-batch-file.txt")
        try Data().write(to: late); quarantine(late, id: sharedID)
        wait("Late file was lost") { receipts.count == 4 }
        precondition(monitor.transfer?.id == transferID && Set(monitor.transfer!.urls) == Set(files + [late]),
                     "Late file must update the same open card")
        monitor.dismiss()
        let continuation = directory.appendingPathComponent("dismissed-batch-file.txt")
        try Data().write(to: continuation); quarantine(continuation, id: sharedID)
        let safari = directory.appendingPathComponent("browser.txt")
        try Data().write(to: safari); quarantine(safari, agent: "Safari")
        let old = directory.appendingPathComponent("old.txt")
        try Data().write(to: old); quarantine(old, stamp: Date().timeIntervalSince1970 - 120)
        let hidden = directory.appendingPathComponent(".hidden.txt")
        try Data().write(to: hidden); quarantine(hidden)
        let nested = directory.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let child = nested.appendingPathComponent("child.txt")
        try Data().write(to: child); quarantine(child)
        pump(2)
        precondition(receipts.count == 4 && monitor.transfer == nil, "Unrelated activity or late files reopened AirDrop")

        // Metadata can arrive after file creation, during a retry chain.
        let delayed = directory.appendingPathComponent("delayed.txt")
        try Data().write(to: delayed)
        pump(0.4); quarantine(delayed)
        wait("Delayed quarantine was lost") { receipts.count == 5 }
        monitor.dismiss()
        let deleted = directory.appendingPathComponent("deleted-before-publication.txt")
        try Data().write(to: deleted); quarantine(deleted)
        pump(0.3)
        run("/bin/rm", [deleted.path])
        pump(2)
        precondition(receipts.count == 5 && monitor.transfer == nil, "Deleted file was offered as a receipt")

        let pending = directory.appendingPathComponent("renamed-before-publication.txt")
        let destination = directory.appendingPathComponent("final-name.txt")
        try Data().write(to: pending); quarantine(pending)
        pump(0.3)
        run("/bin/mv", [pending.path, destination.path])
        wait("Pending rename lost the receipt") { receipts.count == 6 }
        precondition(monitor.transfer?.urls == [destination], "Pending rename kept a stale URL")
        monitor.stop()
        pump(2)
        precondition(receipts.count == 6 && monitor.transfer == nil, "Stopped observer published a receipt")
        print("AirDrop filesystem: rename, copy, xattr bursts, restart, fresh/grouped/late receipts, dismissal, unrelated files, delayed metadata, pending delete/rename, stop passed")
    }
}
