# Microphone observer idle CPU incident

On September 22, the running 0.1.0 build 2 was reported using about 92% CPU while idle, with roughly 360 MB shown in Activity Monitor. This is a defect, not expected animation cost. The earlier short idle measurement did not cover this long-running failure.

## Evidence

A five-second process sample found the main, native-banner and media-key threads sleeping. On the microphone serial queue, 2,414 of 2,415 samples passed through the default-input callback into `MicrophoneMonitor.attach`, repeatedly removing and adding Core Audio listeners.

A separate ten-second counter sample measured 86.94% CPU relative to one core. Physical footprint rose from 363.63 to 364.33 MiB during those ten seconds. This short interval demonstrates growth, but does not establish a sustained leak rate.

The faulty callback rebuilt every listener, including its own system route listener, for every default-input notification. It also reset the mute-state baseline even when the device ID was unchanged. The precise hardware event that started the cycle is unknown; it has not been attributed to AirPods or any particular driver.

## Change

The default-input listener now remains installed for one enabled lifecycle. Notifications are coalesced, and device listeners change only when the actual default-input ID changes. Duplicate route notifications preserve the mute baseline. Stop/restart tokens reject stale callbacks. Input-property notifications use one pending read instead of repeatedly allocating and cancelling delayed reads; unchanged status does not publish another UI update.

Core Audio access is behind a read-only injectable boundary. A regression harness compiles the production observer with a fake provider that immediately sends a route notification upon registration. It checks 2,000 duplicate route events, mute/unmute, input level zero, real route changes, zero-device recovery, old device callbacks and stop/restart cleanup. No microphone audio is recorded or started.

## Verification and limits

The 80 Swift tests, six update configuration tests, AirDrop lifecycle harness and new microphone lifecycle harness pass. The rebuilt app is locally signed and running with the microphone activity enabled.

The first 60-second post-restart sample averaged 0.532% CPU, with 0–0.017% intervals for its first 40 seconds. The last ten seconds included additional app activity, so the whole minute is not an isolated idle baseline. Physical footprint ended at 20.06 MiB, versus 15.39 MiB at the start; resident size ended at 64.09 MiB. These are different memory metrics. The memory reduction after restart does not by itself prove a leak has been eliminated. A subsequent 30-second sample during user testing averaged 0.092% CPU, with physical footprint changing from 48.75 to 48.64 MiB. The user provisionally confirmed the indicators worked, while noting that the original fault only appeared after about a day. A full-day run remains unverified.

An accelerated listener stress run passed 1,000 device-route changes, 100,000 route notifications and ten restarts. The fake Core Audio provider retained exactly six active listeners throughout, including only one system-route listener. This checks listener ownership under churn, not every real hardware driver's behavior or overnight operation.

The raw process sample and counter logs stay in the ignored local diagnostics directory. They are not source-release material. This document describes a local fix; the original published beta archive has not been replaced.

The related output-volume observer has a similar route-listener lifecycle pattern. It was not the hot thread in this incident and is unchanged in this targeted fix.
