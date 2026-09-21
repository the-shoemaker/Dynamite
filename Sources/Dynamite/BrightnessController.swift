import AppKit
import IslandCore
import Darwin

/// Optional private framework, isolated here. Unsupported displays fall through to macOS.
final class BrightnessController {
    typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    typealias SetBrightness = @convention(c) (UInt32, Float) -> Int32
    private let library: UnsafeMutableRawPointer?
    private let get: GetBrightness?
    private let getLinear: GetBrightness?
    private let set: SetBrightness?
    private let external = ExternalBrightnessController()
    private var externalIDs = Set<UInt32>()
    private var ramps: [UInt32: (token: UUID, ramp: BrightnessRamp, vivid: Bool)] = [:]
    var onSoftwareBrightness: ((UInt32, Float) -> Void)? {
        didSet { external.onSoftwareBrightness = onSoftwareBrightness }
    }
    var onSettled: ((Activity) -> Void)?
    init() {
        library = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY | RTLD_LOCAL)
        get = library.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetBrightness.self) }
        getLinear = library.flatMap { dlsym($0, "DisplayServicesGetLinearBrightness") }.map { unsafeBitCast($0, to: GetBrightness.self) }
        set = library.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetBrightness.self) }
    }
    deinit { if let library { dlclose(library) } }
    func snapshot(displayID: UInt32, vivid: Bool) -> Activity? {
        guard let value = read(displayID) else { return nil }
        return Activity(.brightness, value: Int((value * 100).rounded()),
                        isBoosted: vivid && boosted(displayID: displayID), sourceDisplayID: displayID)
    }
    /// All accesses, including scheduled steps, run on AppModel's hardware queue.
    func adjust(_ key: MediaKey, fine: Bool, displayID: UInt32?, vivid: Bool = false, smooth: Bool = true,
                queue: DispatchQueue) -> Activity? {
        guard let id = displayID, let value = read(id) else { return nil }
        let now = ProcessInfo.processInfo.systemUptime
        let ramp = BrightnessRamp(current: value, pendingTarget: ramps[id]?.ramp.target,
                                  direction: key.direction, fine: fine, now: now)
        // Validate the write before consuming the key. Subsequent writes never run
        // on the input callback or the main thread.
        let write = write(id, smooth ? ramp.value(at: now + 1.0 / 60) : ramp.target)
        guard write else { ramps[id] = nil; return nil }
        if smooth {
            let token = UUID()
            ramps[id] = (token, ramp, vivid)
            scheduleStep(displayID: id, token: token, queue: queue)
        } else { ramps[id] = nil; external.didSettle(id) }
        return Activity(.brightness, value: Int((ramp.target * 100).rounded()),
                        isBoosted: vivid && boosted(displayID: id), sourceDisplayID: id)
    }
    private func read(_ id: UInt32) -> Float? {
        var value: Float = 0
        if let get, get(id, &value) == 0, value.isFinite { return value }
        if let value = external.read(id) { externalIDs.insert(id); return value }
        return nil
    }
    private func write(_ id: UInt32, _ value: Float) -> Bool {
        if externalIDs.contains(id) { return external.set(id, value: value) }
        return set?(id, value) == 0
    }
    func displaysChanged() { cancelRamps(); external.invalidate(); externalIDs.removeAll() }
    private func boosted(displayID: UInt32) -> Bool {
        var linear: Float = 0
        guard let getLinear, getLinear(displayID, &linear) == 0 else { return false }
        return VividBridge.isBoosted(displayID: displayID, linearBrightness: linear)
    }
    private func scheduleStep(displayID: UInt32, token: UUID, queue: DispatchQueue) {
        queue.asyncAfter(deadline: .now() + (externalIDs.contains(displayID) ? 1.0 / 30 : 1.0 / 60)) { [weak self] in
            guard let self, let state = self.ramps[displayID], state.token == token else { return }
            let now = ProcessInfo.processInfo.systemUptime
            guard self.write(displayID, state.ramp.value(at: now)) else { self.ramps[displayID] = nil; return }
            if state.ramp.isComplete(at: now) {
                self.ramps[displayID] = nil
                self.external.didSettle(displayID)
                if let activity = self.snapshot(displayID: displayID, vivid: state.vivid) { self.onSettled?(activity) }
                return
            }
            self.scheduleStep(displayID: displayID, token: token, queue: queue)
        }
    }
    func cancelRamps() { ramps.removeAll() }
}
