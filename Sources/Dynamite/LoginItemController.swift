import ServiceManagement
import Combine

final class LoginItemController: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var message: String?
    init() { refresh() }
    func refresh() {
        enabled = SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval
        if SMAppService.mainApp.status == .requiresApproval { message = "Approve Dynamite in System Settings → General → Login Items." }
        else { message = nil }
    }
    func setEnabled(_ desired: Bool) {
        do {
            if desired { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refresh()
        } catch {
            refresh()
            message = "Couldn't change login settings: \(error.localizedDescription)"
        }
    }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
