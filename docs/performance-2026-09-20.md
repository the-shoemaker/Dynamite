# Resource check, September 20, 2026

Idle resource use is low in the measured release build. Frequent animations cost materially more, and the changes retained from this audit reduce that cost rather than making it negligible. Battery runtime has not been measured.

## Measurements on this Mac

MacBookPro18,1, 10 logical CPU cores, macOS 27.0 (26A428). AC power was connected at 80% battery. All activity toggles were enabled for the idle sample; Settings was closed and the user left media keys, timers, and previews untouched for one minute.

| Scenario | Average CPU, one core = 100% | Memory / other observations |
| --- | ---: | --- |
| Quiet background, 60 seconds | 0.0097% | 71.3 MiB physical footprint, unchanged throughout; 0.33 interrupt wakeups/sec; no measured disk reads/writes |
| Mixed user testing, 60 seconds | 9.28% | 65–67 MiB footprint; about 51 interrupt wakeups/sec; no measured disk I/O. This was not idle. |
| Repeated notch sequence, previous rendering | 9.88% | Mean of two runs, eight appearances per run with three value updates each |
| Same notch sequence, retained changes | 8.58% | Mean of two runs; approximately 13% lower CPU |
| Repeated external-style sequence, previous rendering | 9.30% | One run |
| Same external-style sequence, retained changes | 7.44% | One run; approximately 20% lower CPU |

The animation averages include opening, numeric updates, short holds, closing, and gaps. They are not peak CPU during a single animation. Animation benchmarks use actual overlay windows but intentionally disable providers to isolate rendering. The external style was previewed on the internal display; this is not a physical multi-monitor benchmark. The benchmark warms the renderer before recording CPU time.

The baseline binary SHA-256 was `ccea50e84c392b2d099e5d881d1f9e039b25cf8302317c3305072be90b0e15cd`. Raw local diagnostics are excluded from the public repository. These historical results have not been independently reproduced.

## Changes retained

- Disable AppKit's automatic overlay-window transformations. The process stack sample caught these running in addition to the island's own animation.
- Let SwiftUI coalesce visible value changes into its display pass. Force synchronous layout/drawing only for a window's first visible frame.
- Keep the requested small-notch exit horizontal: no outward release or vertical size change; the rim moves inward for 120 ms, then fades over 160 ms, before the 440 ms retraction finishes. The external pill's shape, spring, and fade timing are unchanged.

Two additional rendering experiments were rejected. Disabling intrinsic hosting-view sizing did not reliably reduce CPU, and grouping the shell into a GPU drawing group increased CPU in this workload. Neither is enabled or retained in production rendering.

## What the code review found

Most providers use events rather than polling: battery, microphone input controls, Caps Lock, Wi-Fi/Bluetooth connections, Focus file changes, and Downloads receipt metadata. The microphone feature does not open an audio stream. Brightness ramps schedule work only during their 180 ms transition. Mouse-movement monitoring is removed when the island panels close. There is no repeating idle animation in the source.

Clock remained an exception in the measured build: while a timer reading existed, its cached Accessibility controls were checked every 200 ms, including while paused. The subsequent timer fix reads a file-watched timer-state mirror and updates cached running deadlines once per second. Paused and idle timers have no ticker; the old Accessibility reader remains a fallback when that mirror cannot be decoded. The resulting cost for a running/paused timer was not isolated in this audit. Notification accessibility reads are event-triggered and bounded, but their cost depends on incoming notifications. These paths should be measured separately before promising the same idle figures with persistent activities.

No Dynamite sleep-prevention assertion was reported by `pmset` at the time of the check. Receipt and dismissal identifier sets retain entries for the integration's lifetime; their long-session growth was not stress-tested.

## Battery and measurement limits

These are short process measurements on a plugged-in, otherwise busy Mac. They do not establish watts, minutes of battery life lost, GPU/WindowServer cost, all-monitor cost, or long-term memory leak freedom. Xcode's `xctrace`/Instruments tools were not installed. A controlled unplugged A/B energy run is still needed for a battery-runtime claim.

CPU time from `proc_pid_rusage` was calibrated against a CPU-bound `getrusage` test. This machine uses 125/3 nanoseconds per Mach tick. An initial collector treated those ticks as nanoseconds; its preliminary 0.2% mixed-activity CPU claim was corrected, and the saved log explicitly records the conversion. The separate idle sample and animation benchmarks use the correct units. Apple documents the process counter interface in [libproc.h](https://github.com/apple-oss-distributions/xnu/blob/main/libsyscall/wrappers/libproc/libproc.h); the unit conversion was verified locally rather than assumed.

All 58 Swift tests and six update-configuration tests passed after the final source changes. Visual confirmation of the revised rim fade remains separate from performance measurement.
