import SwiftUI
import MacAppUpdates

struct AboutView: View {
    @ObservedObject var updater: NativeUpdater
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }
    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Dynamite").font(.title2.weight(.semibold))
                        Text("Version \(version) (\(build))").foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
            }
            Section("Updates") {
                LabeledContent("Release", value: updater.isConfigured ? "Signed updates" : "Local development build")
                Text(updater.status).font(.caption).foregroundStyle(.secondary)
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(updater.isConfigured && !updater.canCheck)
                Toggle("Automatically check for updates", isOn: $updater.automaticallyChecks)
                    .disabled(!updater.isConfigured)
                if let checked = updater.lastChecked {
                    LabeledContent("Last checked") { Text(checked, format: .dateTime.day().month().hour().minute()) }
                }
            }
            Section("Acknowledgements") {
                Link("Sparkle · Native macOS updates", destination: URL(string: "https://sparkle-project.org")!)
                Text("Sparkle is open-source software, distributed under the MIT license.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                HStack(spacing: 16) {
                    Text("Quit to stop all activities.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Quit Dynamite", systemImage: "power") { NSApp.terminate(nil) }
                        .controlSize(.regular)
                }.padding(.vertical, 4)
            }
        }.formStyle(.grouped)
    }
}
