import Foundation

/// One sleeping run loop for all native-banner observers. Delivery must not wait
/// behind SwiftUI animations on the main thread. This thread does no polling.
final class NativeBannerEventLoop {
    static let shared = NativeBannerEventLoop()
    private let ready = DispatchSemaphore(value: 0)
    private var loop: CFRunLoop!
    private var thread: Thread?

    private init() {
        let thread = Thread { [self] in
            let loop = CFRunLoopGetCurrent()!
            var context = CFRunLoopSourceContext()
            context.perform = { _ in }
            let source = CFRunLoopSourceCreate(kCFAllocatorDefault, 0, &context)!
            CFRunLoopAddSource(loop, source, .commonModes)
            self.loop = loop
            ready.signal()
            CFRunLoopRun()
        }
        thread.name = "Dynamite native banner events"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
        ready.wait()
    }
    var runLoop: CFRunLoop { loop }
}
