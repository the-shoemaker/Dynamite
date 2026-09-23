# Local performance diagnostic

Open Settings → About → Performance diagnostic, then choose Start 12-hour test. Leave Dynamite running and use the Mac normally. Stop test ends recording early. Show diagnostic files opens the saved run. No upload occurs.

A utility timer reads this process's cumulative CPU time, resident memory and physical footprint once a minute, with scheduling leeway. CPU percentage is relative to one core and calculated from counter differences. The recorder creates no audio stream and reads no notification content or received-file names. It does no periodic work when stopped.

Three consecutive samples trigger a three-second process stack capture if CPU is at least 20%, physical footprint is at least 300 MiB, or footprint has increased at least 150 MiB from the first sample. This intentionally tolerates short animations. At most three captures occur, at least 30 minutes apart. A capture subprocess is killed if it exceeds 20 seconds. Failed stack capture leaves the counters available.

Logs live under `~/Library/Application Support/Dynamite/Diagnostics`. Metrics include timestamps and build version. Stack samples can include executable/library paths and OS details. Inspect files before sharing them. The recorder retains three test folders. Starting another test removes older diagnostic folders beyond that limit.

The duration uses wall time. Sleep is allowed and no assertion keeps the Mac awake. Sampling resumes when the Mac wakes; the test completes on the first callback after its 12-hour deadline. A clean quit stops the test. An unexpected exit leaves a Recording marker; the next launch reports an interrupted test. This marker cannot by itself distinguish a crash, force quit, or power loss. It does not auto-resume or auto-restart the app.

Verification includes deterministic threshold/cooldown/capture-limit tests and an accelerated recorder lifecycle check using real process counters. `scripts/verify-diagnostic.sh --capture`, run outside restrictive development sandboxes, adds real CPU load and verifies a completed stack file. Ordinary tests do not require permission to sample another process.

A completed recording is evidence, not an automatic all-clear. Check normal-use periods, sleep/wake, device changes and the memory trend before drawing a long-term stability conclusion.
