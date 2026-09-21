import AppKit
import SwiftUI
import IslandCore

private let ink = Color(red: 0.055, green: 0.065, blue: 0.10)
private let muted = Color(red: 0.63, green: 0.67, blue: 0.76)

struct Backdrop: View {
    var body: some View {
        ZStack {
            ink
            RadialGradient(colors: [Color(red: 0.20, green: 0.15, blue: 0.35).opacity(0.7), .clear], center: .topTrailing, startRadius: 10, endRadius: 750)
            RadialGradient(colors: [Color(red: 0.08, green: 0.23, blue: 0.31).opacity(0.45), .clear], center: .bottomLeading, startRadius: 0, endRadius: 600)
        }
    }
}
struct LabelLine: View {
    let text: String
    var body: some View {
        HStack(spacing: 9) {
            Capsule().fill(Color.cyan).frame(width: 18, height: 5)
            Text(text.uppercased()).font(.system(size: 12, weight: .semibold)).tracking(2.6).foregroundStyle(muted)
        }
    }
}
struct Hero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LabelLine(text: "Dynamite / macOS")
            Text("A little less popup.\nA lot more polish.")
                .font(.system(size: 61, weight: .semibold)).tracking(-2.8).lineSpacing(-3)
                .foregroundStyle(.white).padding(.top, 25)
            Text("Everyday status, beautifully tucked into your notch.")
                .font(.system(size: 20)).foregroundStyle(muted).padding(.top, 16)
            DisplayPreviewScene(activity: Activity(.volume, value: 64), notched: true, blackBackground: false, animate: false)
                .frame(width: 570).scaleEffect(1.5).frame(width: 855, height: 189)
                .shadow(color: .black.opacity(0.35), radius: 30, y: 20)
                .padding(.top, 46)
            HStack {
                Text("Native Swift. Focused on status.")
                Spacer()
                Text("NOTCH + EXTERNAL DISPLAYS").tracking(1.2)
            }.font(.system(size: 11, weight: .medium)).foregroundStyle(muted).padding(.top, 35)
        }.padding(60).frame(width: 1000, height: 640, alignment: .topLeading).background(Backdrop())
    }
}
struct StatusCard: View {
    let title: String
    let subtitle: String
    let activity: Activity
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            Text(subtitle).font(.system(size: 12)).foregroundStyle(muted).padding(.top, 6)
            IslandSurface(activity: activity, geometry: IslandGeometry(safeTop: 0, notchWidth: 0))
                .scaleEffect(1.65).frame(maxWidth: .infinity).frame(height: 90).padding(.top, 9)
        }.padding(24).frame(maxWidth: .infinity).frame(height: 185)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.07), lineWidth: 1))
    }
}
struct StatusSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LabelLine(text: "The everyday essentials")
            Text("Small updates. Clear at a glance.")
                .font(.system(size: 42, weight: .semibold)).tracking(-1.6).foregroundStyle(.white).padding(.top, 19)
            Text("The status you need, for as long as you choose.")
                .font(.system(size: 17)).foregroundStyle(muted).padding(.top, 10)
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    StatusCard(title: "Microphone", subtitle: "Know when your Mac input is muted.", activity: Activity(.microphoneMute, value: 0, label: "Muted", isActive: false))
                    StatusCard(title: "Focus", subtitle: "A quieter way to show Do Not Disturb.", activity: Activity(.focus, value: 100, label: "Do Not Disturb"))
                }
                HStack(spacing: 16) {
                    StatusCard(title: "AirPods", subtitle: "Battery at connection, when available.", activity: Activity(.airPods, value: 82))
                    StatusCard(title: "Low Power Mode", subtitle: "A small reminder of your power state.", activity: Activity(.lowPowerMode, value: 46))
                }
            }.padding(.top, 32)
        }.padding(55).frame(width: 1000, height: 650, alignment: .topLeading).background(Backdrop())
    }
}
struct ActionStage<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.29, green: 0.20, blue: 0.51), Color(red: 0.14, green: 0.35, blue: 0.45)], startPoint: .topLeading, endPoint: .bottomTrailing)
            content
        }.frame(width: 420, height: 225)
            .clipShape(RoundedRectangle(cornerRadius: 23))
            .padding(6).background(Color(white: 0.035), in: RoundedRectangle(cornerRadius: 29))
            .overlay(RoundedRectangle(cornerRadius: 29).strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }
}
struct ActionsSheet: View {
    let timerPresentation: IslandPresentation
    let dropPresentation: IslandPresentation
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LabelLine(text: "Room for the next step")
            Text("Compact until you need more.")
                .font(.system(size: 44, weight: .semibold)).tracking(-1.7).foregroundStyle(.white).padding(.top, 20)
            Text("Useful actions, right where the update appears.")
                .font(.system(size: 18)).foregroundStyle(muted).padding(.top, 12)
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 20) {
                    ActionStage {
                        ClockAlertView(monitor: NativeActivityNotifications(), clock: ClockMonitor(), presentation: timerPresentation,
                            geometry: IslandGeometry(safeTop: 32, notchWidth: 150), screenID: 1)
                            .frame(width: 360, height: 150).scaleEffect(1.15, anchor: .top)
                    }
                    Text("Time's up.").font(.system(size: 23, weight: .semibold)).foregroundStyle(.white)
                    Text("Repeat the timer or stop the alert.")
                        .font(.system(size: 14)).foregroundStyle(muted)
                }
                VStack(alignment: .leading, spacing: 20) {
                    ActionStage {
                        AirDropExpandedView(monitor: AirDropMonitor(), presentation: dropPresentation,
                            geometry: IslandGeometry(safeTop: 32, notchWidth: 180), screenID: 2)
                            .frame(width: 360, height: 170).scaleEffect(1.15, anchor: .top)
                    }
                    Text("File received.").font(.system(size: 23, weight: .semibold)).foregroundStyle(.white)
                    Text("Open it or find it in Downloads.")
                        .font(.system(size: 14)).foregroundStyle(muted)
                }
            }.padding(.top, 40)
            Text("Clock controls and completed AirDrop receipts shown with sample data.")
                .font(.system(size: 11)).foregroundStyle(muted).padding(.top, 33)
        }.padding(55).frame(width: 1000, height: 630, alignment: .topLeading).background(Backdrop())
    }
}
@main struct Showcase {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let timer = IslandPresentation(); timer.activity = Activity(.clockTimer, value: 0, remainingSeconds: 0); timer.expanded = true
        let drop = IslandPresentation(); drop.activity = Activity(.airDrop, value: 100, label: "Received"); drop.expanded = true
        try save(Hero(), name: "showcase-hero", to: output)
        try save(StatusSheet(), name: "showcase-status", to: output)
        try save(ActionsSheet(timerPresentation: timer, dropPresentation: drop), name: "showcase-actions", to: output)
    }
    @MainActor static func save<V: View>(_ view: V, name: String, to directory: URL) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark).transaction { $0.animation = nil; $0.disablesAnimations = true })
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: directory.appendingPathComponent(name+".png"))
        print("Rendered \(name)")
    }
}
