# Observer audit after the second high-CPU incident

## Captured failure

The output-volume property listener could repeatedly rediscover volume controls, keeping the hardware queue busy and delaying indicators. This is separate from the microphone listener-registration loop fixed in 0.1.1. A test provider models read-triggered notifications to exercise the feedback risk. Raw diagnostic logs are not included in the repository.


## Changes

- Output monitoring keeps its route listener for the full enabled lifecycle, ignores duplicate route IDs, coalesces notifications, and rejects callbacks from retired devices and previous activations.
- Volume observation caches the selected scalar properties instead of rediscovering writable controls and reading virtual volume on every notification. Media-key writes retain their existing virtual/stereo behavior and rollback.
- A virtual-only device emitting unchanged read-triggered notifications backs off to at most one scheduled read per second. Ordinary scalar monitoring keeps a 50 ms coalescing interval. No polling timer is added.
- Bluetooth output-route notifications coalesce before expensive UID/paired-device lookup. Unchanged route IDs skip that lookup. Activation tokens reject stale work, and failed connection registration cleans up existing listeners.
- Wi-Fi change bursts keep one delayed refresh rather than cancel/reallocate work for each event.
- Battery start also checks the power-state observer, preventing duplicate registrations if macOS fails to create the power-source run-loop source.
- Sleep stops output monitoring; reconciliation cannot restart Wi-Fi/Bluetooth while sleeping.

## Hook inventory and findings

| Hook | Review result |
| --- | --- |
| Output Core Audio | Confirmed hot path; changed and tested with production-controller fake-driver tests. |
| Microphone Core Audio | Stable route listener, device/activation checks, one pending read; existing lifecycle and churn tests retained. Reads can still cost work under a pathological driver notification storm; no such storm was present in this sample. |
| Bluetooth connection/disconnection and audio route | Stable subscriptions, bounded battery retries; changed route burst handling and failed-start cleanup. Real accessory reconnection still needs user verification. |
| Wi-Fi delegate | One read in flight plus one follow-up; changed notification coalescing. Read-only calls do not change Wi-Fi state. |
| Battery / low-power notifications | Read-only snapshot callback, removal on stop; fixed partial-start idempotence. |
| Focus filesystem source | One source, descriptor closed on cancel, read-only file access. No self-write feedback. Directory replacement recovery and repeated status publication remain improvement opportunities, not observed runaway causes. |
| Clock preference file/directory sources | One pending refresh, file signature filtering, descriptors closed on cancellation. Preference synchronization could generate directory activity, but unchanged signatures prevent repeated reloads. |
| Clock accessibility / ticker | Coalesced reads, 180-node and 350 ms traversal limits, stable window subscriptions, one ticker. Foreground fallback can still be expensive if Clock repeatedly defeats node caching. Original-duration history is now pruned to current timers plus the last timer needed for the finished-alert transition. |
| AirDrop filesystem events | Read-only xattrs, three retries, generation checks, stopped stream cleanup. Duplicate events for a file now share one retry chain, and receipt publication uses one pending batch. The receipt deduplication set still grows with actual transfers until stop; removing entries blindly could reannounce old receipts. |
| MenuBarAgent accessibility | Traversal/time limits, existing-position check avoids rewriting already parked windows, source removed on detach. Continuous OS repositioning could still cause repeated corrective work; source review alone cannot rule that out. |
| Notification Center accessibility | Coalesced requests and bounded traversal, positional guard, restore on disable. Same OS-repositioning risk remains. |
| Media keys | Replay tag prevents own-event recursion, at most two admitted hardware requests plus one deferred press per key. Disabled tap fails open. A saturated shared hardware queue delayed these requests in this incident. |
| Caps Lock / notch context menu | Passive event hooks, idempotent registration and removal, no polling. Caps Lock deduplicates modifier state. |
| Brightness / display changes | Generation-checked finite ramps; no idle brightness polling. Display cache invalidation is tied to changed display IDs. Hardware IPC can still block on a malfunctioning monitor. |
| Island windows / animations | Finite expiry and retirement work, cancellation on reuse/stop, no perpetual animation or frame polling found. |
| App lifecycle / settings / updater | Delegate start guard, removable observers and Combine subscriptions; corrected sleep gaps. Settings writes debounce; Sparkle KVO does not write its observed properties. |

## Verification scope

The output test exercises initial registration callbacks, 2,000 duplicate route events, 2,000 volume bursts, read-generated callbacks, external volume and mute changes, media-key deduplication, stereo write rollback, device changes, old callbacks, restart, zero-output recovery, and virtual-only feedback backoff. The full suite also includes existing microphone and AirDrop lifecycle checks.

This is a code audit of all app-owned monitoring entry points, not proof that every macOS callback or driver is safe. Bluetooth, Wi-Fi, accessibility, and sleep changes compile in the complete app but are not all backed by injected native-provider tests. A short post-restart CPU reading cannot establish eight-hour stability. These changes are included in the 0.1.2 beta.

## Automated verification

All 84 Swift tests and six update-configuration tests passed, along with AirDrop, microphone, output and diagnostic lifecycle checks. The output stress test exercises 200 route changes, 100,000 route events, 100,000 output-event bursts, and ten restarts, checking for six active listeners and none after stop.

Longer real-world operation and other Macs still need testing. The opt-in diagnostic in About records local counters and captures a stack on sustained load. No automatic restart or periodic heap purge is used to conceal failures.
