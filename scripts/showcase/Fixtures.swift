// Render-only fixtures. No providers, permissions, file reads or system actions.
import SwiftUI
import IslandCore
final class ClockMonitor: ObservableObject {
    let finishedDuration: Int? = 300
    func togglePause() {}
    func openClock() {}
    func reconnectAfterRepeat() {}
}
final class NativeActivityNotifications: ObservableObject {
    struct Action: Identifiable { let id: String; let title: String }
    let clockOriginalDuration: Int? = 300
    let clockActions = [Action(id: "repeat", title: "Repeat"), Action(id: "stop", title: "Stop")]
    func stopClockAlert() {}
    func perform(_ action: Action) {}
}
final class AirDropMonitor: ObservableObject {
    struct Transfer { let title: String; let urls: [URL] }
    let transfer: Transfer? = Transfer(title: "Weekend.jpg", urls: [URL(fileURLWithPath: "/sample/Weekend.jpg")])
    func dismiss() {}
    func openReceived() {}
    func revealReceived() {}
}
