import SwiftUI
import MacAppUpdates

struct AboutView: View {
    @ObservedObject var updater: NativeUpdater
    @ObservedObject var diagnostic: PerformanceDiagnostic
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
            Section("Performance diagnostic") {
                Text(diagnostic.status)
                Text("Records CPU and memory once a minute for 12 hours. Sustained high usage captures up to three short stack samples. Files stay on this Mac; nothing is uploaded. Stack samples may include executable and library paths. Keeps the latest three tests.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    if diagnostic.active { Button("Stop test") { diagnostic.stop() } }
                    else { Button("Start 12-hour test") { diagnostic.start() } }
                    Button("Show diagnostic files") { diagnostic.showFiles() }.disabled(diagnostic.folder == nil)
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
