import SwiftUI
import IslandCore
import ApplicationServices

// Property-wrapper spelling avoids the newer SDK's optional State macro plugin.
private typealias ViewState<Value> = SwiftUI.State<Value>

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var mediaKeys: MediaKeyMonitor
    @ObservedObject var loginItem: LoginItemController
    @ObservedObject var wireless: WirelessMonitor
    @ObservedObject var bluetooth: BluetoothMonitor
    @ObservedObject var clock: ClockMonitor
    @ObservedObject var focus: FocusMonitor
    @ObservedObject var airDrop: AirDropMonitor
    var onSetup: () -> Void = {}
    @ViewState<Feature> private var previewFeature = .volume
    @ViewState<Feature?> private var expanded: Feature?
    @ViewState<Set<String>> private var collapsedGroups = []
    private var activityGroups: [ActivitySettingsGroup] { ActivitySettingsGroup.available(hasInternalBattery: model.hasInternalBattery) }
    private var availableFeatures: [Feature] { activityGroups.flatMap(\.features) }
    @ViewState<Bool> private var previewNotch = true
    @AppStorage("preview.blackBackground") private var previewBlackBackground = false
    @ViewState<Bool> private var accessibilityAllowed = AXIsProcessTrusted()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Page: String, CaseIterable, Identifiable {
        case activities, general, integrations, about
        var id: Self { self }
        var title: String { rawValue.capitalized }
        var symbol: String {
            switch self {
            case .activities: return "waveform.path"
            case .general: return "gearshape"
            case .integrations: return "square.stack.3d.up"
            case .about: return "info.circle"
            }
        }
    }
    @ViewState<Page> private var page = .activities
    @ViewState<NavigationSplitViewVisibility> private var columnVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(spacing: 0) {
                List(selection: $page) {
                    ForEach([Page.activities, .general, .integrations]) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }.listStyle(.sidebar).scrollContentBackground(.hidden)
                List(selection: $page) {
                    Label(Page.about.title, systemImage: Page.about.symbol).tag(Page.about)
                }.listStyle(.sidebar).scrollContentBackground(.hidden).frame(height: 42)
            }
            .background { SettingsSidebarMaterial().ignoresSafeArea() }
            .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 200)
        } detail: {
            Group {
                switch page {
                case .activities: activities
                case .general: general
                case .integrations: integrations
                case .about: AboutView(updater: model.updater, diagnostic: model.diagnostic)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .modifier(SettingsScrollEdge())
            .navigationTitle(page.title)
            .toolbarBackground(.visible, for: .windowToolbar)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 820, maxWidth: 1640, minHeight: 400)
        .animation(nil, value: page)
    }

    private var activities: some View {
        ScrollView {
            VStack(spacing: 16) {
                preview
                if !mediaKeys.active && !settings.preferences.paused {
                    HStack(spacing: 12) {
                        Image(systemName: "hand.raised").font(.title3).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Allow keyboard replacement").font(.callout.weight(.medium))
                            Text("Accessibility is needed for volume, brightness, and global Caps Lock updates.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Allow…") { mediaKeys.requestAccess() }
                        Button("Check again") { model.refreshConnections() }
                    }
                    .padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                }
                ForEach(activityGroups) { group in
                    VStack(spacing: 0) {
                        Button {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                                if collapsedGroups.contains(group.id) { collapsedGroups.remove(group.id) }
                                else { collapsedGroups.insert(group.id) }
                            }
                        } label: {
                            HStack {
                                Text(group.title).font(.callout.weight(.semibold))
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                                    .rotationEffect(.degrees(collapsedGroups.contains(group.id) ? 0 : 90))
                            }.foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 9).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("\(group.title) group")
                            .accessibilityValue(collapsedGroups.contains(group.id) ? "Collapsed" : "Expanded")
                        if !collapsedGroups.contains(group.id) {
                            ForEach(Array(group.features.enumerated()), id: \.element) { index, feature in
                                activityRow(feature)
                                if index < group.features.count - 1 { Divider().padding(.leading, 45) }
                            }
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.45)))
                }
                HStack {
                    Text(mediaKeys.active ? "Keyboard replacement is active." : "Allow Accessibility for keyboard replacement.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(settings.preferences.paused ? "Resume" : "Pause") { settings.preferences.paused.toggle() }
                }
            }.padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 24)
        }
    }

    private var preview: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Preview").font(.callout.weight(.medium))
                Spacer()
                PreviewDisplaySelector(notched: $previewNotch)
                    .frame(width: 220, height: 24)
                    .transaction { $0.animation = nil }
            }
            DisplayPreviewScene(activity: .preview(previewFeature, preferences: settings.preferences),
                                notched: previewNotch, blackBackground: previewBlackBackground)
            HStack {
                Picker("Activity", selection: $previewFeature) {
                    ForEach(availableFeatures) { Text($0.title).tag($0) }
                }.labelsHidden().frame(width: 150)
                PreviewBackgroundSelector(dark: $previewBlackBackground)
                    .frame(width: 156, height: 24)
                    .transaction { $0.animation = nil }
                Spacer()
                Button("Show on screen", systemImage: "play") { model.preview(previewFeature, notch: previewNotch) }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.45)))
    }

    private func activityRow(_ feature: Feature) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Group {
                    if feature == .airDrop { AirDropGlyph().frame(width: 19, height: 19) }
                    else { Image(systemName: feature.symbol).font(.system(size: 16)) }
                }
                    .foregroundStyle(feature == .volume || feature == .brightness || feature == .powerDisconnected ? Color.primary : feature.tint)
                    .frame(width: 22)
                Button {
                    previewFeature = feature
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                        expanded = expanded == feature ? nil : feature
                    }
                } label: {
                    HStack(spacing: 5) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(feature.title).font(.callout)
                            if feature == .lowBattery {
                                Text("Additional reminder; macOS alerts remain.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                            .rotationEffect(.degrees(expanded == feature ? 90 : 0)).foregroundStyle(.tertiary)
                        Spacer()
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("\(feature.title) settings")
                Text([.capsLock, .clockTimer, .airDrop].contains(feature) ? (settings.preferences.preference(for: feature).enabled ? "On" : "Off") : ActivityDuration.label(settings.preferences.preference(for: feature).duration, compact: true))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 44)
                Button { previewFeature = feature; model.preview(feature, notch: previewNotch) } label: {
                    Image(systemName: "play").font(.system(size: 11))
                }.buttonStyle(.borderless).help("Preview \(feature.title)").accessibilityLabel("Preview \(feature.title)")
                Toggle(feature.title, isOn: Binding(get: { settings.preferences.preference(for: feature).enabled },
                    set: { settings.setEnabled(feature, $0) }))
                    .labelsHidden().toggleStyle(.switch).controlSize(.small)
            }.padding(12)
            if expanded == feature {
                VStack(alignment: .leading, spacing: 12) {
                    if feature == .airDrop {
                        Text("Stays visible until dismissed.").foregroundStyle(.secondary)
                    } else if feature == .clockTimer {
                        Text("Shows the running timer on the internal display, or the largest external display if needed. Hover for pause or resume; click the time to open Clock. After pausing, it stays for the duration below. Hovering holds it open; moving away restarts that duration. The countdown continues with Clock’s window closed. Controls reconnect to Clock when needed.").foregroundStyle(.secondary)
                    } else if feature == .capsLock {
                        Text("Stays on the internal display, with the largest external display as a fallback. Turning Caps Lock on briefly interrupts a timer for the duration below, then the timer returns. Other temporary activities can still take its place.")
                            .foregroundStyle(.secondary)
                    }
                    if feature != .airDrop {
                    HStack {
                        Text(feature == .clockTimer ? "After pause" : feature == .capsLock ? "Interrupt for" : "Duration").frame(width: 74, alignment: .leading)
                        Slider(value: Binding(get: { ActivityDuration.index(for: settings.preferences.preference(for: feature).duration) },
                            set: { settings.setDuration(feature, ActivityDuration.seconds(at: $0)) }), in: 0...Double(ActivityDuration.steps.count - 1), step: 1)
                            .accessibilityLabel("\(feature.title) duration")
                            .accessibilityValue(ActivityDuration.label(settings.preferences.preference(for: feature).duration))
                        Text(ActivityDuration.label(settings.preferences.preference(for: feature).duration))
                            .monospacedDigit().frame(width: 76, alignment: .trailing)
                    }
                    }
                    if feature != .airDrop {
                        Button("Reset duration") { settings.setDuration(feature, feature.defaultDuration) }
                            .disabled(settings.preferences.preference(for: feature).duration == feature.defaultDuration)
                    }
                    if feature == .lowPowerMode {
                        Text("Orange when Low Power Mode turns on, white when it turns off, with the current battery percentage.")
                            .foregroundStyle(.secondary)
                    }
                    if feature == .microphoneMute {
                        MicrophoneStatus(monitor: model.microphone)
                        Text("Briefly confirms changes to the Mac’s default microphone mute control or input level reaching zero. Red means muted; green means unmuted. Call-app mute buttons can have a separate state. No audio is recorded.")
                            .foregroundStyle(.secondary)
                    }
                    if feature == .brightness {
                        Toggle("Smooth brightness", isOn: $settings.preferences.smoothBrightness)
                        Toggle("Show Vivid extra-range indicator", isOn: $settings.preferences.vividCompatibility)
                        Text("A small orange + marks Vivid’s extra range. Dynamite controls normal display brightness; changing Vivid’s boost level from the brightness keys is not supported yet.")
                            .foregroundStyle(.secondary)
                        Button("Hide Vivid’s center indicator") { _ = VividBridge.hideIndicator() }
                    }
                    if feature == .hotspot {
                        Text("Brief confirmation when this Mac joins a Personal Hotspot. macOS’s phone battery reading is unreliable, so no percentage is shown.")
                            .foregroundStyle(.secondary)
                    }
                    if feature == .wifi {
                        Text("Brief confirmation after Wi-Fi connects. Hotspot connections use their separate activity. Network names and passwords are not read.")
                            .foregroundStyle(.secondary)
                    }
                    if feature == .airDrop {
                        Text("Received files in Downloads appear with Open and Show in Finder. Dismiss with Escape, an outside click, or the close button.").foregroundStyle(.secondary)
                    }
                    if feature == .airPods {
                        Text("Shows the lowest available earbud battery reading when AirPods connect. Unknown battery readings are omitted. Matching passive connection popups are hidden where macOS allows it.").foregroundStyle(.secondary)
                    }
                    if feature == .focus {
                        Text("Focus changes appear in purple. Full Disk Access is needed to read macOS Focus state.").foregroundStyle(.secondary)
                        Button("Open Full Disk Access settings…") { openFocusAccess() }
                    }
                    if feature == .bluetooth {
                        Text("Brief confirmation for paired Bluetooth devices. Pairing prompts stay with macOS.")
                            .foregroundStyle(.secondary)
                    }
                    if feature == .chargeTarget || feature == .lowBattery {
                        HStack {
                            Text("Notify at").frame(width: 74, alignment: .leading)
                            Slider(value: threshold(feature), in: feature == .chargeTarget ? 50...100 : 5...40, step: 5)
                                .accessibilityLabel("\(feature.title) threshold")
                            Text("\(Int(threshold(feature).wrappedValue))%")
                                .monospacedDigit().frame(width: 76, alignment: .trailing)
                        }
                    }
                    if feature == .chargeTarget {
                        Text("A reminder only. Charging continues past this percentage.")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .padding(.leading, 44).padding(.trailing, 15).padding(.bottom, 14)
            }
        }
    }
    private func threshold(_ feature: Feature) -> Binding<Double> {
        Binding(get: { Double(feature == .chargeTarget ? settings.preferences.chargeTarget : settings.preferences.lowThreshold) },
                set: {
                    if feature == .chargeTarget { settings.preferences.chargeTarget = Int($0) }
                    else { settings.preferences.lowThreshold = Int($0) }
                })
    }
    private var general: some View {
        Form {
            Section("Startup and windows") {
                Toggle("Open at login", isOn: Binding(get: { loginItem.enabled }, set: { loginItem.setEnabled($0) }))
                if let message = loginItem.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                    Button("Open Login Items settings…") { loginItem.openSettings() }
                }
                Toggle("Show in menu bar", isOn: $settings.preferences.showMenuBarIcon)
                Text("Open Dynamite from Finder or Spotlight to return to settings, even when the menu bar icon is hidden.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Keep settings on top", isOn: $settings.preferences.keepSettingsOnTop)
            }
            Section("Display") {
                Picker("Show activities on", selection: $settings.preferences.placement) {
                    ForEach(DisplayPlacement.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Text("On a MacBook, activities extend from the sides of the notch at its existing height. Other displays use a small pill, 6 points below the top edge.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Presentation") {
                Toggle("Pause all activities", isOn: $settings.preferences.paused)
                Text("Nothing is drawn when idle. Active activities can appear in a screen share; pause them before presenting if needed.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Animations follow your Mac’s Reduce Motion setting.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
    private var integrations: some View {
        Form {
            Section("Permissions") {
                Button("Open setup assistant…") { onSetup() }
                PermissionRow(title: "Accessibility", symbol: "hand.raised", detail: "Volume and brightness keys, Caps Lock, and timer controls.",
                              status: accessibilityAllowed ? "Allowed" : "Needs access", granted: accessibilityAllowed) {
                    if accessibilityAllowed { openPrivacy("Privacy_Accessibility") }
                    else { mediaKeys.requestAccess() }
                }
                PermissionRow(title: "Full Disk Access", symbol: "internaldrive", detail: "For Focus changes. macOS grants broader file access.",
                              status: focusAccessStatus, granted: focusAccessStatus == "Allowed") { openFocusAccess() }
                PermissionRow(title: "Downloads folder", symbol: "folder", detail: "For received AirDrop files and their Open actions.",
                              status: downloadsAccessStatus, granted: downloadsAccessStatus == "Allowed") { openPrivacy("Privacy_FilesAndFolders") }
            }
            Section {
                if bluetooth.devices.isEmpty {
                    Label(settings.preferences.paused ? "Dynamite is paused" : "No connected Bluetooth devices", systemImage: "headphones")
                        .foregroundStyle(.secondary).padding(.vertical, 6)
                } else {
                    ForEach(bluetooth.devices) { device in ConnectedDeviceRow(device: device) }
                }
            } header: {
                HStack {
                    Text("Connected devices")
                    Spacer()
                    Button("Refresh", systemImage: "arrow.clockwise") { bluetooth.refreshDevices() }
                        .buttonStyle(.borderless).font(.caption)
                }
            } footer: {
                Text("Battery readings update on connection or refresh.")
            }
            Section("Current state") {
                IntegrationStatusRow(title: "Wi-Fi", symbol: "wifi", tint: .blue, value: wireless.status.replacingOccurrences(of: "Wi-Fi ", with: "").capitalized)
                IntegrationStatusRow(title: "Focus", symbol: "moon.fill", tint: .purple,
                                     value: focus.status == "Focus off" ? "Off" : focus.status == "Focus on" ? "On" : focus.status)
                IntegrationStatusRow(title: "Clock", symbol: "timer", tint: .orange,
                                     value: clock.reading == nil && clock.status == "Waiting for a Clock timer" ? "No active timer" : clock.status)
                MicrophoneIntegrationRow(monitor: model.microphone)
            }
            Section {
                Text("Choose activities and their durations in Activities.").foregroundStyle(.secondary)
                Text("AirDrop supports received files in Downloads. Incoming requests and transfer progress are not available yet.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Recheck permissions and connections") {
                    accessibilityAllowed = AXIsProcessTrusted()
                    model.refreshConnections()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { accessibilityAllowed = AXIsProcessTrusted(); bluetooth.refreshDevices() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityAllowed = AXIsProcessTrusted()
        }
    }
    private var focusAccessStatus: String {
        if focus.status == "Focus on" || focus.status == "Focus off" { return "Allowed" }
        return focus.status == "Needs Full Disk Access" ? "Needs access" : "Not checked"
    }
    private var downloadsAccessStatus: String {
        if airDrop.status == "Watching AirDrop receipts" || airDrop.status == "AirDrop received" { return "Allowed" }
        return airDrop.status.contains("Allow Downloads") ? "Needs access" : "Not checked"
    }
    private func openPrivacy(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }
    private func openFocusAccess() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }

}

private struct MicrophoneStatus: View {
    @ObservedObject var monitor: MicrophoneMonitor
    var body: some View { Text(monitor.status).font(.caption).foregroundStyle(.secondary) }
}

/// AppKit owns the segment layout. Changing any SwiftUI slider cannot redistribute
/// the labels or interpolate segment widths through an inherited transaction.
private struct PreviewDisplaySelector: NSViewRepresentable {
    @Binding var notched: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: ["MacBook", "External display"], trackingMode: .selectOne,
                                         target: context.coordinator, action: #selector(Coordinator.select(_:)))
        control.controlSize = .small
        control.segmentStyle = .rounded
        control.setWidth(92, forSegment: 0)
        control.setWidth(120, forSegment: 1)
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.setAccessibilityLabel("Preview display")
        return control
    }
    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.selectedSegment = notched ? 0 : 1
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: 220, height: 24)
    }
    final class Coordinator: NSObject {
        var parent: PreviewDisplaySelector
        init(_ parent: PreviewDisplaySelector) { self.parent = parent }
        @objc func select(_ control: NSSegmentedControl) { parent.notched = control.selectedSegment == 0 }
    }
}

private struct PreviewBackgroundSelector: NSViewRepresentable {
    @Binding var dark: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: ["macOS style", "Dark"], trackingMode: .selectOne,
                                         target: context.coordinator, action: #selector(Coordinator.select(_:)))
        control.controlSize = .small
        control.segmentStyle = .rounded
        control.setWidth(96, forSegment: 0)
        control.setWidth(52, forSegment: 1)
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        control.setAccessibilityLabel("Preview background")
        return control
    }
    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.selectedSegment = dark ? 1 : 0
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        CGSize(width: 156, height: 24)
    }
    final class Coordinator: NSObject {
        var parent: PreviewBackgroundSelector
        init(_ parent: PreviewBackgroundSelector) { self.parent = parent }
        @objc func select(_ control: NSSegmentedControl) { parent.dark = control.selectedSegment == 1 }
    }
}


private struct SettingsScrollEdge: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            content
        }
    }
}

/// One AppKit material spans both navigation lists. Separate list backgrounds
/// otherwise sample the desktop independently and leave visible seams.
private struct SettingsSidebarMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = StableSidebarMaterialView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        (view as? StableSidebarMaterialView)?.preserveSidebar()
    }
}


/// Preserve native toolbar collapsing, but never collapse a sidebar merely
/// because the settings window is being resized.
private final class StableSidebarMaterialView: NSVisualEffectView {
    private weak var splitController: NSSplitViewController?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in self?.preserveSidebar() }
    }
    func preserveSidebar() {
        if let splitController { configure(splitController); return }
        guard let root = window?.contentView else { return }
        // SwiftUI hosts the material in a sibling subtree, so its own responder
        // chain need not contain the navigation split controller.
        func find(in view: NSView) -> NSSplitViewController? {
            if let split = view as? NSSplitView, let owner = split.delegate as? NSSplitViewController { return owner }
            var responder: NSResponder? = view.nextResponder
            while let current = responder, !(current is NSWindow) {
                if let owner = current as? NSViewController {
                    var parent: NSViewController? = owner
                    while let candidate = parent {
                        if let split = candidate as? NSSplitViewController { return split }
                        parent = candidate.parent
                    }
                }
                responder = current.nextResponder
            }
            for child in view.subviews { if let split = find(in: child) { return split } }
            return nil
        }
        if let owner = find(in: root) { configure(owner) }
    }
    private func configure(_ controller: NSSplitViewController) {
        splitController = controller
        for item in controller.splitViewItems where item.behavior == .sidebar {
            item.minimumThickness = 200
            item.maximumThickness = 200
            item.canCollapseFromWindowResize = false
            item.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        }
    }
}
