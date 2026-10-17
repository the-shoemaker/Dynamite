import AppKit

@main
struct VerifyMediaKeyLifecycle {
    static func main() {
        let monitor = MediaKeyMonitor()
        monitor.verifyResponsiveness {
            print("PASS: media-key admission and deferred stop handoff")
            exit(0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            fputs("FAIL: media-key lifecycle check timed out\n", stderr)
            exit(1)
        }
        RunLoop.main.run()
    }
}
