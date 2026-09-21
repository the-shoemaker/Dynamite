import AppKit
import SwiftUI
import ApplicationServices
import Combine
import Darwin

/// Checks only on entry, app activation, or explicit retry. No idle polling.
final class SetupAccess: ObservableObject {
    @Published private(set) var accessibility = AXIsProcessTrusted()
    @Published private(set) var focus = "Not checked"
    @Published private(set) var downloads = "Not checked"
    @Published private(set) var checking = false
    private var checkDownloads = UserDefaults.standard.bool(forKey: "hasLaunched") ||
        UserDefaults.standard.bool(forKey: "setup.downloadsCheckRequested")
    private let queue = DispatchQueue(label: "Dynamite.setup-access", qos: .utility)
    func refresh() {
        accessibility = AXIsProcessTrusted()
        guard !checking else { return }
        checking = true
        let inspectDownloads = checkDownloads
        queue.async { [weak self] in
            let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
            let focus: String
            do { _ = try Data(contentsOf: file); focus = "Available" }
            catch let error as CocoaError where error.code == .fileReadNoPermission { focus = "Needs access" }
            catch { focus = "Unavailable" }
            var downloads: String?
            if inspectDownloads, let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
                let fd = open(folder.path, O_RDONLY | O_DIRECTORY)
                if fd >= 0 { close(fd); downloads = "Available" }
                else { downloads = "Needs access" }
            }
            DispatchQueue.main.async { [weak self] in
                self?.focus = focus
                if let downloads { self?.downloads = downloads }
                self?.checking = false
            }
        }
    }
    func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        openPrivacy("Privacy_Accessibility")
    }
    func requestDownloads() {
        if downloads == "Available" { openPrivacy("Privacy_FilesAndFolders"); return }
        checkDownloads = true
        UserDefaults.standard.set(true, forKey: "setup.downloadsCheckRequested")
        // The first actual directory access lets macOS present its own prompt.
        refresh()
        if downloads == "Needs access" { openPrivacy("Privacy_FilesAndFolders") }
    }
    func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") { NSWorkspace.shared.open(url) }
    }
}

struct SetupView: View {
    @StateObject private var access = SetupAccess()
    @ObservedObject var loginItem: LoginItemController
    let finish: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().scaledToFit().frame(width: 48, height: 48)
                    .accessibilityHidden(true)
                Text("Permission setup").font(.title2.bold())
            }
            Text("macOS asks for each permission separately. Optional access enables the features below; you can add it later in Integrations.")
                .font(.callout).foregroundStyle(.secondary)
            VStack(spacing: 16) {
                PermissionRow(title: "Accessibility", symbol: "hand.raised", detail: "Keyboard controls, Caps Lock, and timer actions.",
                    status: access.accessibility ? "Allowed" : "Needs access", granted: access.accessibility) { access.requestAccessibility() }
                Divider()
                PermissionRow(title: "Focus · optional", symbol: "moon", detail: "Full Disk Access permits reading Focus state and grants broader file access.",
                    status: access.focus, granted: access.focus == "Available") { access.openPrivacy("Privacy_AllFiles") }
                Divider()
                PermissionRow(title: "AirDrop · optional", symbol: "folder", detail: "Downloads access for received files. No file contents are read.",
                    status: access.downloads, granted: access.downloads == "Available",
                    actionTitle: access.downloads == "Not checked" ? "Check access…" : "Settings…") { access.requestDownloads() }
            }.padding(16).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
            Toggle("Open Dynamite when I log in", isOn: Binding(get: { loginItem.enabled }, set: { loginItem.setEnabled($0) }))
            if let message = loginItem.message {
                Text(message).font(.caption).foregroundStyle(.secondary)
                Button("Open Login Items settings") { loginItem.openSettings() }
            }
            Text("Keep Dynamite in Applications before enabling login startup. Bluetooth access, if needed, is requested by macOS when the integration starts.")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack {
                Button("Check again") { access.refresh(); loginItem.refresh() }.disabled(access.checking)
                Spacer()
                if !access.accessibility { Button("Set up later", action: finish) }
                Button("Start Dynamite", action: finish).buttonStyle(.borderedProminent)
                    .disabled(!access.accessibility).keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 540, height: 580)
        .onAppear { access.refresh(); loginItem.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            access.refresh(); loginItem.refresh()
        }
    }
}
