// Appended to the real controller source by verify-external-brightness.sh.
// Every I2C call uses these fakes. No display or preference is changed.
private var verificationHardware: UInt16 = 160
private var verificationWrites = 0
// An invented ID is deliberately classified as external. No WindowServer
// connection or physical display is needed in the restricted test process.
private func CGDisplayIsBuiltin(_ display: CGDirectDisplayID) -> boolean_t { 0 }

extension ExternalBrightnessController {
    fileprivate func installVerificationDisplay(_ id: UInt32) {
        services[id] = "verification-display" as CFString
        maxima[id] = 160
        readI2C = { _, _, _, output, count in
            guard count == 11 else { return -1 }
            var reply: [UInt8] = [0x6E, 0x88, 0x02, 0, 0x10, 0, 0, 160,
                                 UInt8(verificationHardware >> 8), UInt8(verificationHardware & 255)]
            reply.append(reply.reduce(UInt8(0x50), ^))
            output.copyMemory(from: reply, byteCount: reply.count)
            return 0
        }
        writeI2C = { _, _, _, input, count in
            let bytes = input.assumingMemoryBound(to: UInt8.self)
            if count == 6 && bytes[1] == 0x03 && bytes[2] == 0x10 {
                verificationHardware = UInt16(bytes[3]) << 8 | UInt16(bytes[4])
                verificationWrites += 1
            }
            return 0
        }
    }
    fileprivate func expireVerificationBaseline(_ id: UInt32) {
        if let value = lastValues[id] { lastValues[id] = (value.0, -.infinity) }
    }
    fileprivate func installVerificationScale(_ id: UInt32) {
        scales[id] = ExternalBrightnessScale(split: 0.5, allowBlackout: false)!
    }
}

@main
struct VerifyExternalBrightness {
    static func require(_ value: Bool, _ message: String) {
        guard value else { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    static func main() {
        let display: UInt32 = 0xFFFFFFFD
        let controller = ExternalBrightnessController()
        controller.installVerificationDisplay(display)
        require(controller.set(display, value: 1), "Initial hardware write failed")
        verificationHardware = 150 // Another controller changes the monitor.
        controller.expireVerificationBaseline(display)
        require(controller.read(display) == 0.9375, "Fresh DDC read missed the external change")
        require(controller.set(display, value: 1), "Brightness-up write failed")
        require(verificationHardware == 160,
                "Stale lastHardware skipped brightness-up after another controller lowered the monitor")

        verificationHardware = 150 // Repeat while the two-second baseline is cached.
        require(controller.read(display) == 1, "Expected the short cached baseline")
        require(controller.set(display, value: 1), "Cached-baseline write failed")
        require(verificationHardware == 160, "Cached baseline prevented reasserting hardware brightness")

        let writes = verificationWrites
        require(controller.set(display, value: 1), "Repeated ramp write failed")
        require(verificationWrites == writes, "Duplicate ramp steps should still skip hardware writes")

        controller.installVerificationScale(display)
        var software: Float?
        controller.onSoftwareBrightness = { _, value in software = value }
        require(controller.set(display, value: 0.25), "Combined-range write failed")
        require(verificationHardware == 0 && abs((software ?? 0) - 0.575) < 0.0001,
                "MonitorControl combined hardware/software range changed")
        let dimmedWrites = verificationWrites
        require(controller.set(display, value: 0.20), "Software-only ramp step failed")
        require(verificationWrites == dimmedWrites && abs((software ?? 0) - 0.49) < 0.0001,
                "Software ramp must keep its scale and skip duplicate hardware values")
        print("External brightness: fresh/cached external changes recover, duplicate ramp writes stay skipped, combined MonitorControl scale stays intact; fake I2C only")
    }
}
