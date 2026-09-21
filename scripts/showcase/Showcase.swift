import AppKit
import SwiftUI
import IslandCore

private let muted = Color(white: 0.62)

struct Backdrop: View {
    var body: some View { Color(white: 0.095) }
}
struct Hero: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 13) {
                Image(nsImage: NSImage(contentsOfFile: "Resources/Dynamite.icns")!)
                    .resizable().frame(width: 62, height: 62)
                Text("Dynamite").font(.system(size: 27, weight: .semibold)).foregroundStyle(.white)
            }
            Text("Your latest activities, in the notch.")
                .font(.system(size: 43, weight: .medium)).tracking(-1.4)
                .foregroundStyle(.white).padding(.top, 28)
            DisplayPreviewScene(activity: Activity(.volume, value: 64), notched: true, blackBackground: false, animate: false)
                .frame(width: 570).scaleEffect(1.5).frame(width: 855, height: 189)
                .padding(.top, 43)
        }.padding(60).frame(width: 1000, height: 510, alignment: .topLeading).background(Backdrop())
    }
}
struct StatusCard: View {
    let title: String
    let activity: Activity
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
            IslandSurface(activity: activity, geometry: IslandGeometry(safeTop: 0, notchWidth: 0))
                .scaleEffect(1.65).frame(maxWidth: .infinity).frame(height: 90).padding(.top, 9)
        }.padding(24).frame(maxWidth: .infinity).frame(height: 155)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.07), lineWidth: 1))
    }
}
struct StatusSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    StatusCard(title: "Microphone", activity: Activity(.microphoneMute, value: 0, label: "Muted", isActive: false))
                    StatusCard(title: "Focus", activity: Activity(.focus, value: 100, label: "Do Not Disturb"))
                }
                HStack(spacing: 16) {
                    StatusCard(title: "AirPods", activity: Activity(.airPods, value: 82))
                    StatusCard(title: "Low Power Mode", activity: Activity(.lowPowerMode, value: 46))
                }
            }
        }.padding(55).frame(width: 1000, height: 436, alignment: .topLeading).background(Backdrop())
    }
}
struct ActionStage<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        ZStack(alignment: .top) {
            Color(white: 0.19)
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
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 20) {
                    ActionStage {
                        ClockAlertView(monitor: NativeActivityNotifications(), clock: ClockMonitor(), presentation: timerPresentation,
                            geometry: IslandGeometry(safeTop: 32, notchWidth: 150), screenID: 1)
                            .frame(width: 360, height: 150).scaleEffect(1.15, anchor: .top)
                    }
                    Text("Clock").font(.system(size: 23, weight: .semibold)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 20) {
                    ActionStage {
                        AirDropExpandedView(monitor: AirDropMonitor(), presentation: dropPresentation,
                            geometry: IslandGeometry(safeTop: 32, notchWidth: 180), screenID: 2)
                            .frame(width: 360, height: 170).scaleEffect(1.15, anchor: .top)
                    }
                    Text("AirDrop").font(.system(size: 23, weight: .semibold)).foregroundStyle(.white)
                }
            }
        }.padding(55).frame(width: 1000, height: 390, alignment: .topLeading).background(Backdrop())
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
