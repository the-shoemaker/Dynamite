# Release performance audit, October 14, 2026

The new internet monitor passed repeated-session and live cadence checks. This audit found and fixed excessive probe launches during network-path bursts, unnecessary lower-pill animations, and a same-feature preview that could hide an actionable card.

## Executed checks

| Check | Result |
| --- | --- |
| Core suite | 98 tests across 30 suites passed |
| Other automated checks | Six updater tests, icon decoding, AirDrop lifecycle/filesystem, microphone, output, diagnostic, internet lifecycle and settings persistence passed |
| Network stress | 16,000 start/stop sessions and 160,000 repeated satisfied-path events; one initial probe and cancellation per session; no leftover deadline |
| Stress memory after warmup | 3.063, 3.344 and 3.391 MiB after successive 5,000-session batches |
| Real loopback probes | 93 seconds at the production 30-second cadence; online throughout |
| Monitor-process CPU | 0.00774% average, relative to one logical core |
| Live footprint | 3.094 to 3.204 MiB across three samples |
| Actual overlay windows | Primary replacement/restoration, lower timer stability, promotion, interrupted floating moves, Caps Lock return and expanded-card motion passed |
| Input callback | 1,000 handled keys, 1,000 unrelated Caps Lock events passed through; about 0.32 ms per callback |

The performance harness imports the actual InternetMonitor and InternetPing. Stress callbacks use a bounded fake probe; the cadence measurement runs real packets against loopback. No external network configuration is changed. CPU figures cover the monitor process, not child ping, WindowServer, the complete app, energy use or battery runtime. These short checks do not establish indefinite leak freedom.

## Risks found and fixed

Every satisfied path event previously cancelled and launched another process. An independent executable reproduced 100 starts for 100 repeated events. Subsequent satisfied events now debounce for 350 ms on the single shared deadline. Initial route recovery stays immediate, and route loss cancels immediately. The lifecycle harness confirms one probe after a 100-event burst and rejects old completions.

The probe owns one process and bounds each packet to two seconds on a utility queue. Stop, disabled features, pause and sleep remove the monitor and deadline. Cancellation retains the probe until queued process cleanup executes. Generation tokens protect both process completions and deadline handlers. Repeated inactive stops do no work, and unchanged online readings do not republish UI state.

Lower persistent rows previously scheduled an animation even when their position was unchanged. The controller now skips unchanged destinations and computes an absolute target during interrupted motion. The signed app's promotion check includes a second destination and 100 unchanged updates during movement.

A temporary preview with the same feature as an expanded Clock or AirDrop card previously removed that card's persistent row. Routing now keeps actionable cards and ignores their duplicate preview on that display. Tests cover both primary cards and cards below persistent offline status.

## Remaining limits

A selected ping target can be unreachable while other internet services work. IPv4 validation and a resettable address limit configuration mistakes; this is a reachability indicator, not a DNS or captive-portal test. Zero-frame native popup suppression on affected secondary displays, a fresh-user install on a separate Mac, and a real AirPods reconnect were not verified in this audit.

Run ./scripts/verify-internet-performance.sh for the optional stress and cadence check. The regular test suite keeps the shorter lifecycle check.
