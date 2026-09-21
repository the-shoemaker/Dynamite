import SwiftUI

struct PermissionRow: View {
    let title: String
    let symbol: String
    let detail: String
    let status: String
    let granted: Bool
    var actionTitle: String = "Settings…"
    let action: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(.secondary).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 5) {
                Label(status, systemImage: granted ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.caption).foregroundStyle(granted ? Color.green : .secondary)
                Button(actionTitle, action: action).controlSize(.small)
                    .accessibilityLabel("\(title) settings")
            }.fixedSize()
        }.padding(.vertical, 5)
    }
}

struct IntegrationStatusRow: View {
    let title: String
    let symbol: String
    let tint: Color
    let value: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(tint).frame(width: 24)
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
        }.padding(.vertical, 3)
    }
}

struct MicrophoneIntegrationRow: View {
    @ObservedObject var monitor: MicrophoneMonitor
    var body: some View {
        IntegrationStatusRow(title: "Microphone", symbol: "mic", tint: .secondary, value: monitor.status)
    }
}

struct ConnectedDeviceRow: View {
    let device: BluetoothMonitor.ConnectedDevice
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.symbol).font(.system(size: 24)).foregroundStyle(.primary).frame(width: 34)
            VStack(alignment: .leading, spacing: 5) {
                Text(device.name).lineLimit(1)
                if let battery = device.battery, battery.left != nil || battery.right != nil || battery.caseLevel != nil {
                    HStack(spacing: 12) {
                        batteryPart("L", level: battery.left)
                        batteryPart("R", level: battery.right)
                        batteryPart("Case", level: battery.caseLevel)
                    }.font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Connected").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let percent = device.battery?.percentage {
                HStack(spacing: 5) {
                    Image(systemName: percent <= 20 ? "battery.25percent" : percent <= 50 ? "battery.50percent" : percent <= 75 ? "battery.75percent" : "battery.100percent")
                    Text("\(percent)%").monospacedDigit()
                }.foregroundStyle(percent <= 20 ? Color.orange : .green)
            }
        }.padding(.vertical, 7)
    }
    @ViewBuilder private func batteryPart(_ label: String, level: Int?) -> some View {
        if let level { Text("\(label) \(level)%").monospacedDigit() }
    }
}
