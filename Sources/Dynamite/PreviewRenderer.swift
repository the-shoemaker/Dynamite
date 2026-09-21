import AppKit
import SwiftUI
import IslandCore
import Darwin

/// Opt-in rendering check for padding, outline continuity, and hardware clearance.
/// This path never starts providers or reads the screen behind the app.
@MainActor
enum PreviewRenderer {
    /// Same real overlay sequence in both modes, with providers disabled.
    /// CPU accounting uses getrusage's seconds/microseconds, not Mach ticks.
    static func benchmarkMotion(legacy: Bool, external: Bool, completion: @escaping () -> Void) {
        let controller = IslandController()
        controller.legacyRenderingForBenchmark = legacy
        func cpuTime() -> Double {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) +
                Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }
        // Warm the renderer before counting CPU time.
        controller.show(.preview(.volume), duration: 0.5, placement: .main, previewNotch: !external)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let start = ProcessInfo.processInfo.systemUptime
            let cpuStart = cpuTime()
            for cycle in 0..<8 {
                for step in 0..<3 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(cycle) * 1.7 + Double(step) * 0.12) {
                        controller.show(Activity(cycle.isMultiple(of: 2) ? .volume : .brightness, value: 60 + step * 10),
                                        duration: 0.65, placement: .main, previewNotch: !external)
                    }
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 13.6) {
                let elapsed = ProcessInfo.processInfo.systemUptime - start
                let cpu = cpuTime() - cpuStart
                print("mode=\(legacy ? "legacy" : "optimized") style=\(external ? "external" : "notch") cycles=8 wall_seconds=\(elapsed) cpu_seconds=\(cpu) average_cpu_percent=\(100 * cpu / elapsed)")
                controller.hide(immediately: true)
                completion()
            }
        }
    }
    static func verifyCardMotion(completion: @escaping (Bool) -> Void) {
        let presentation = IslandPresentation()
        let geometry = IslandGeometry(safeTop: 32, notchWidth: 180)
        let target = geometry.shellHeight + ClockAlertView.extraHeight
        let panel = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 500, height: 200),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.animationBehavior = .none
        panel.contentView = NSHostingView(rootView: ExpandedActionsMotionPreview(presentation: presentation, geometry: geometry))
        IslandMotionTrace.enabled = true
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { presentation.expanded = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let values = IslandMotionTrace.take()
            let peak = values.max() ?? 0
            let intermediate = values.filter { $0 > geometry.shellHeight && $0 < target }.count
            let actions = IslandMotionTrace.takeActions()
            let actionPeak = actions.max() ?? 0
            let actionIntermediate = actions.filter { $0 > 0 && $0 < 1 }.count
            let passed = peak > target + 1 && intermediate > 2 && actionPeak > 1.01 && actionIntermediate > 2
            print("Actions: peak \(actionPeak), intermediate samples \(actionIntermediate)")
            print("\(passed ? "PASS" : "FAIL"): expanded height target \(target), peak \(peak), intermediate samples \(intermediate)")
            panel.orderOut(nil); panel.contentView = nil
            completion(passed)
        }
    }
    static func verifyPromotion(completion: @escaping (Bool) -> Void) {
        guard let display = IslandController.persistentScreen(for: .clockTimer) else { completion(false); return }
        let controller = IslandController()
        controller.targetScreen = display
        controller.floatingTopGap = 170
        controller.allowsExpandedCards = false
        controller.show(.preview(.volume), duration: nil, placement: .main)
        var original = CGRect.zero
        var intermediate = CGRect.zero
        let target = display.safeAreaInsets.top + 6
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            original = controller.panelFrames.first ?? .zero
            controller.moveFloatingPill(to: target)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) {
            intermediate = controller.panelFrames.first ?? .zero
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            let final = controller.panelFrames.first ?? .zero
            let distance = final.minY - original.minY
            let passed = abs(distance - (170 - target)) < 1 &&
                intermediate.minY > original.minY && intermediate.minY < final.minY
            print("Intermediate movement: \(intermediate.minY - original.minY) pt")
            print("\(passed ? "PASS" : "FAIL"): floating window moved upward by \(final.minY - original.minY) pt; expected \(170 - target) pt")
            controller.hide(immediately: true)
            completion(passed)
        }
    }
    static func verifyRouting(completion: @escaping (Bool) -> Void) {
        let controller = IslandCoordinator()
        var passed = true
        func check(_ value: Bool, _ label: String) {
            print("\(value ? "PASS" : "FAIL"): \(label)")
            passed = passed && value
        }
        controller.setPersistent(.preview(.capsLock))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            check(controller.visiblePanelCount == 1, "One persistent display")
            controller.show(.preview(.volume), duration: 0.6, placement: .all)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            check(controller.visiblePanelCount == NSScreen.screens.count, "One temporary panel per target display, without duplicate primary panels")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.65) {
            check(controller.visiblePanelCount == 1 && controller.currentFeature == .capsLock, "Expiry retires extra panels and restores persistent activity")
            controller.setPersistent(nil)
            controller.show(.preview(.brightness), duration: 2, placement: .all)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.85) {
            controller.show(.preview(.volume), duration: 2, placement: .main, previewNotch: false)
            check(controller.visiblePanelCount == NSScreen.screens.count, "Previous displays remain visible during their exit")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.75) {
            check(controller.visiblePanelCount == 1, "Previous display panels finish retiring")
            controller.hide(immediately: true)
            check(controller.visiblePanelCount == 0, "Stop removes all panels and deadlines")
            completion(passed)
        }
    }
    static func verifyPersistence(completion: @escaping (Bool) -> Void) {
        let controller = IslandController()
        var schedule = ActivitySchedule()
        var passed = true
        func check(_ condition: Bool, _ label: String) {
            print("\(condition ? "PASS" : "FAIL"): \(label)")
            passed = passed && condition
        }
        schedule.setPersistent(.preview(.capsLock))
        controller.onTemporaryExpired = {
            schedule.expire(at: ProcessInfo.processInfo.systemUptime)
            if let activity = schedule.persistent {
                let panels = controller.visiblePanelCount
                let relocating = controller.persistentTargetChanged(for: .capsLock)
                controller.transition(to: activity, placement: .main)
                check((controller.presentation.expanded || relocating) && !controller.presentation.closing && controller.visiblePanelCount == panels,
                      "Return morph preserves its shell, or moves to the persistent display")
            }
            else { controller.hide() }
        }
        controller.show(.preview(.capsLock), duration: nil, placement: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            check(controller.presentation.expanded && controller.currentFeature == .capsLock, "Caps Lock remains expanded")
            schedule.present(.preview(.volume), duration: 0.4, now: ProcessInfo.processInfo.systemUptime)
            controller.show(.preview(.volume), duration: 0.4, placement: .main)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            check(controller.currentFeature == .volume, "Temporary volume replaces Caps Lock")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) {
            check(controller.currentFeature == .capsLock && controller.presentation.expanded, "Caps Lock returns after expiry")
            controller.transition(to: .preview(.capsLock), placement: .main)
            schedule.setPersistent(nil)
            controller.hide()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            check(controller.currentFeature == nil && controller.visiblePanelCount == 0, "Turning off cancels an in-flight return")
            controller.transition(to: .preview(.capsLock), placement: .main)
            controller.show(.preview(.brightness), duration: nil, placement: .main)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.3) {
            check(controller.currentFeature == .brightness && controller.presentation.expanded, "New activity cancels an in-flight return")
            controller.hide(immediately: true)
            completion(passed)
        }
    }
    static func verifyMotion(completion: @escaping () -> Void) {
        let controller = IslandController()
        IslandMotionTrace.enabled = true
        controller.show(Activity(.volume, value: 100), duration: 0.9, placement: .main, previewNotch: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            let values = IslandMotionTrace.take()
            print("Expansion samples: \(values.count); min: \(values.min() ?? -1); max: \(values.max() ?? -1); intermediate: \(values.filter { $0 > 0 && $0 < 1 }.count)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            let values = IslandMotionTrace.take()
            print("Collapse samples: \(values.count); min: \(values.min() ?? -1); max: \(values.max() ?? -1); intermediate: \(values.filter { $0 > 0 && $0 < 1 }.count)")
            controller.hide(immediately: true)
            IslandMotionTrace.enabled = false
            completion()
        }
    }
    static func render(to directory: String) throws {
        let destination = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for notched in [true, false] {
            for dark in [true, false] {
                let geometry = IslandGeometry(safeTop: notched ? 38 : 0, notchWidth: notched ? 220 : 0, referenceHeight: 38)
                let content = VStack(spacing: 20) {
                    ForEach([Feature.volume, .brightness, .charging, .powerDisconnected, .chargeTarget, .lowPowerMode, .capsLock, .hotspot, .wifi, .bluetooth], id: \.self) { feature in
                        IslandSurface(activity: Activity(feature, value: 100, label: feature == .chargeTarget ? "Fully charged" : Activity.preview(feature).label, isBoosted: feature == .brightness),
                                      geometry: geometry)
                            .frame(width: 540, height: 50, alignment: .top)
                    }
                }
                .padding(20)
                .background(dark ? Color.black : Color(white: 0.95))
                let renderer = ImageRenderer(content: content)
                renderer.scale = 2
                guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let name = "\(notched ? "notch" : "pill")-\(dark ? "dark" : "light").png"
                try png.write(to: destination.appendingPathComponent(name))
                let stage = DisplayPreviewScene(activity: Activity(.brightness, value: 100, isBoosted: true),
                                                notched: notched, blackBackground: dark, animate: false)
                    .frame(width: 520).padding(14).background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, .dark)
                    .transaction { $0.animation = nil; $0.disablesAnimations = true }
                let stageRenderer = ImageRenderer(content: stage)
                stageRenderer.scale = 2
                guard let stageImage = stageRenderer.nsImage, let stageTiff = stageImage.tiffRepresentation,
                      let stageBitmap = NSBitmapImageRep(data: stageTiff),
                      let stagePNG = stageBitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
                try stagePNG.write(to: destination.appendingPathComponent("display-preview-\(name)"))
            }
        }
    }
}

/// Uses the same row transform and shell clip as Clock and AirDrop without providers.
private struct ExpandedActionsMotionPreview: View {
    @ObservedObject var presentation: IslandPresentation
    let geometry: IslandGeometry
    var body: some View {
        VStack(spacing: 8) {
            Color.clear.frame(height: geometry.height)
            HStack(spacing: 10) {
                Capsule().fill(.gray)
                Capsule().fill(.orange)
            }
            .frame(height: 48).padding(.horizontal, 20)
            .modifier(ExpandedActionsEntrance(open: presentation.expanded && !presentation.closing))
        }
        .modifier(ExpandedIslandShell(presentation: presentation, geometry: geometry,
            width: 348, height: geometry.shellHeight + ClockAlertView.extraHeight, tint: .orange))
    }
}
