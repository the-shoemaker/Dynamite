# Verification

## Automated checks

Run `./scripts/test.sh`. The tests exercise production `IslandCore` logic:

- Baseline readings and unchanged power notifications are silent.
- Connecting power distinguishes active charging from paused charging.
- Charging across a target emits once, including a skipped percentage.
- An 80% target says “Target reached”; only 100% says “Fully charged”.
- Low battery is opt-in, triggers once per threshold crossing, and handles unplugging below the threshold.
- Disabled activities, pause/resume, and wake/reset do not replay stale events.
- Preferences round-trip through JSON and invalid stored values are bounded.
- Media key down, repeat, release, and unrelated event decoding.

Local results on September 20, 2026, macOS 27 beta, Apple silicon, Swift 6.4:

- All 15 tests passed across 3 suites.
- The optimized release bundle built successfully and passed `codesign --verify --strict` with an ad-hoc signature. Bundle size is 2.0 MB.
- The app launched and the settings layout was inspected in a live screenshot. The Accessibility tree exposes feature switches, per-feature settings and preview buttons, duration labels, placement choices, and the separate permission action. The screenshot showed the compact icon/percentage pill, green battery features, and low battery disabled with the native-alert limitation visible.
- Accessibility was not granted during verification. Real keyboard interception, hardware writes, and native-HUD suppression remain unverified.
- UI automation could not complete interactive checks because the app was being changed by the user between observations. Their interaction was left undisturbed. Per-feature setting persistence, actual preview dismissal, external displays, and capture behavior still require the checklist below.
- A subsequent three-sample `top` run reported 59, 52, and 53 MB with CPU readings of 0.0%, 4.2%, and 5.5%. The app was being interacted with, so these are mixed UI-activity samples, not a clean idle benchmark.
- With settings open, a `ps` snapshot reported 0.0% CPU and 70,064 KB RSS, about 68.4 MiB. This is not a settings-closed measurement. The media-key tap was inactive pending Accessibility; battery events were enabled.

Pure state tests do not prove hardware control or native HUD suppression. No idle energy or multi-monitor performance claim has been verified. The beta Command Line Tools emitted missing-framework-search-path warnings but linked successfully. The build script uses SwiftPM's alternate native engine because the default beta engine's debug-symbol packaging failed in the restricted environment; SwiftPM currently warns that this alternate engine is deprecated.

## Hardware acceptance checklist

These checks require the relevant devices and explicit macOS permissions. Keep unperformed checks marked as unverified.

1. Allow Accessibility, return to Dynomite, then use real volume up/down and mute keys. Confirm exactly one hardware change and only Dynomite's pill. Hold a key and use Option + Shift for fine adjustments.
2. Toggle Volume off and repeat. Confirm native behavior returns. Repeat while paused and after quitting.
3. Switch audio outputs during a key sequence. Test a writable speaker output and a fixed-volume HDMI device. Unsupported outputs must retain native behavior.
4. Repeat brightness checks on a built-in screen and a DisplayServices-compatible external display. An unsupported DDC monitor must pass keys through.
5. Trigger previews repeatedly just before their deadline. Confirm an old deadline never closes a newer activity. Wait for the exit animation; no Dynomite overlay should remain visible.
6. Change display placement and disconnect a monitor during an activity. Check pointer/main/all choices, mixed scale factors, full-screen Spaces, and the MacBook safe area.
7. Connect power, cross the charge target, unplug below the low threshold with that opt-in enabled, and sleep/wake. Confirm no repeat or stale reminders. Apple's critical-battery warning remains separate.
8. Record a full display while idle and during an activity. Idle has no overlay. Active activities can be captured. Pause must remove the overlay and stop further live events.
9. Enable Reduce Motion and use VoiceOver. Confirm fading, readable feature names and percentages, labeled toggles/sliders, and keyboard navigation.
10. Quit and relaunch. Preferences persist. The menu bar app stays quiet unless first-run setup or settings were requested.

## Resource measurement

Use a release build. Close settings and let all activities dismiss. Measure normal idle, then repeat after many previews. Record the permission state and whether battery listeners are active. A permission-free idle measurement does not include the media-key tap.

```sh
pgrep -x Dynomite
# Substitute the app PID below.
top -l 3 -s 5 -pid PID -stats pid,command,cpu,mem,threads,ports
```

There should be no recurring provider wake-ups or growing window count after previews. Use Instruments Energy Log and Allocations for a longer hardware session when Xcode is available. Resource figures vary by macOS release and whether SwiftUI settings were opened.

## Revision 2, September 20

- All 21 tests passed across 4 suites. New checks cover physical-notch height, zero top gap, external-pill sizing without a center spacer, stereo balance, and migration of existing preferences.
- Release build and ad-hoc signing succeeded.
- Read-only signed-app diagnostics on the actual Mac reported Accessibility granted, an active HID event tap, and a writable virtual main audio control on device 94 at volume 0.8125. The previous hardware-main-only assumption was invalid on this device.
- Display diagnostics reported Built-in Retina Display, notch width 220 pt, height 38 pt, top gap 0. External geometry is covered by tests; no external monitor was connected for live verification.
- The revised settings window was inspected in a live screenshot. It has native tabs/forms, compact controls, and no promotional headings.
- In General, live state showed Open at login on, Show in menu bar off, Keep settings on top on. Those user-selected values were preserved. Actual restart/login has not been performed.
- With the menu bar icon hidden, closed settings, navigated to Dynomite.app in Finder, and opened it again. A new Dynomite Settings window appeared, with Keyboard replacement is active. This verifies the real reopen path without a status item.
- The computer-use driver cannot emit `XF86AudioRaiseVolume`; it returned keyNotFound without sending an event. The user then tested a real volume key and confirmed “Only Dynomite appears.” Native-HUD suppression is user-verified on this Mac; the driver itself cannot synthesize that key.
- The remaining Clock/Focus/AirPods/AirDrop work is not claimed as complete. A preference question about allowing real-state integrations while retaining Apple's alerts remains pending.

## Revision 3, September 20

- All 23 tests passed across 4 suites. New geometry checks cover external previews below the physical camera and the one-point notch lip.
- Release build succeeded. Static renders using the actual `IslandSurface` at 2× show volume, brightness, charging, and full charge at 100% on black and light backgrounds. Inspected the complete pill border, open-top notch border, and percentage spacing. Generate these with `--render-previews=/tmp/dynomite-previews`.
- Live settings verification changed Volume duration from 2 to 12 seconds with External display selected. The preview retained its width. Restored the original 2-second duration after the test.
- Clicked Quit Dynomite in settings. `pgrep -x Dynomite` then returned no running process. Relaunched the updated build through Finder.
- The user confirmed that right-clicking the physical notch opens the menu.
- After the user reported that frame-based transitions still looked like fades, replaced them with an animatable shape path. The final release build recorded 165 expansion samples, including 90 intermediate values and a peak of 1.07875. Collapse recorded 116 samples with 50 intermediate values. The gray outline has its own opacity animation. This proves the shell geometry moves and overshoots; subjective motion quality remains for user review.
- `--verify-motion` runs this short live notch check without starting providers, prints the sampled geometry range, closes its panel, and exits. The diagnostic sample buffer is disabled in normal runs.
- Actual external-monitor hardware remains untested. The external preview is explicitly positioned below the built-in camera and does not claim a connected second screen.
- Direct integration probes and their entitlement failures are recorded in platform-support.md. Clock, Focus, AirPods, and AirDrop remain unfinished.

## Revision 4, September 20

- 27 tests pass, including unplug transitions, level-matched battery symbols, individual disablement, equal notch wings, and restricting the Vivid marker to brightness activities.
- The input diagnostic admitted 2 of 1,000 mock key callbacks and passed through the remaining 998 in 0.42 ms, with zero synchronous hardware calls. It posted no events to the system. This is a bounded-queue responsiveness check, not proof that the user's unexplained freeze cannot recur.
- Created a persistent local development certificate and dedicated keychain after user approval. Separately obtained approval for code-signing-only trust. Real-host strict signature verification passed. Verification inside the restricted development sandbox cannot read the user's trust settings and can report CSSMERR_TP_NOT_TRUSTED; run the check in the user's normal host context.
- Changed builds retain the same certificate-pinned designated requirement. Quit and relaunched after a later changed build; live settings immediately reported Keyboard replacement is active without another permission change during that check.
- Inspected real-view renders of the icon-only notch and content-sized external labels, including 100% padding and white unplug styling. The activity's spoken description remains available to accessibility.
- Vivid 2.18.1 is installed. A read-only hardware probe found normal brightness 1.0 and a transfer-curve maximum of 1.4499999, giving a real extra-range signal. Its center-indicator preference was changed through Dynomite's requested button and read back as true. The user confirmed Vivid's circle is gone, but rejected the original HID replay route because Apple's indicator always appeared and Dynomite only appeared below roughly 70%.
- Replaced HID replay for Vivid with process-targeted delivery, immediate activity feedback, and coalesced delayed readback. Release build, 27 tests, strict signature verification, and the mock input responsiveness check pass. Restarted through Finder and verified keyboard replacement is active without reauthorizing Accessibility. The user then reported that Apple’s HUD was gone but brightness and Dynomite’s value no longer changed. This route failed verification and was removed.
- The stronger spring reached expansion 1.15873 in the live geometry trace. Contents use their own spring and opacity animation. Inspected the final rendered orange plus, complete pill border, icon-only notch, equal wings, 100% spacing, and white unplug activity.

- Restored direct DisplayServices brightness control for every brightness key. Vivid support is explicitly limited to detecting an existing boost and hiding its center circle. No gamma writes or event forwarding to Vivid remain. Settings and README explain that Vivid’s keyboard control requires disabling Dynomite’s Brightness activity.

## Revision 5, September 20

- A passive input trace recorded ordinary brightness key codes 2 and 3. Temporary application tracing then confirmed successful DisplayServices reads and writes, followed by an island update for every press. The event tap was not dropping those keys.
- The missing island came from the unconditional `didChangeScreenParametersNotification` dismissal. Real brightness ramps generated repeated display notifications even though the screen frame, notch geometry, display ID, and scale were unchanged. The controller now compares that layout and leaves the activity open when only brightness/HDR parameters change.
- The user confirmed that Dynomite now stays visible during brightness changes and that the screen brightness transitions feel smooth.
- Hardware brightness now ramps over 180 ms on the serial hardware queue. Repeated presses accumulate against the pending target and restart from the current hardware reading. A ramp schedules only its next step, cancels on retargeting or disabling brightness, and stops at the target. No idle polling was added.
- 30 tests pass, including monotonic ramping, exact endpoints, fine increments, bounds, and retaining repeated key steps during an unfinished ramp. The release build uses the same persistent signing identity.
- Removed temporary application file logging and its enable marker after diagnosis. The optional `--trace-brightness` command remains a passive, one-minute diagnostic and never runs in normal use.

- The user reported that the orange marker stayed on throughout Vivid’s range. Gamma alone was insufficient. Added a hardware-ceiling check with a 0.0001 readback tolerance. A regression test uses the observed gamma peak of 1.45 at lower brightness values, including 68.75%, 75%, and 93.75%, and verifies that all remain unmarked. Full hardware brightness plus the boosted curve enables the marker. The user confirmed that the corrected marker disappears below the normal hardware ceiling and appears at the ceiling with Vivid boost active.

- Final marker build: 31 tests pass and strict code-signature verification succeeds. Live diagnostics report `vividRunning: true` and `vividBoost: false` at the current lower brightness, with Accessibility and the media-key tap still active. Relaunched without changing macOS permissions. Temporary application tracing is absent from this build.

## Revision 6, September 20

- Settings now uses native sidebar navigation for Activities, General, and Integrations, with About pinned at the bottom. Navigated every page through the live app, inspected the About screenshot, and checked that Check for Updates opens the correct unpublished-feed alert. Quit remains in the footer. Existing login, menu-bar and window-level preferences were preserved.
- Added event-driven Caps Lock state and temporary/persistent scheduling. The user confirmed the physical sequence: Caps Lock on, volume feedback, return to the blue Active indicator, Caps Lock off. There is no idle timer for Caps Lock.
- `--verify-persistence` passed all five real-controller checks: persistent presentation, temporary replacement, return after expiry, cancellation when switched off during return, and replacement by a newer activity during return. These checks use real overlay windows without injecting keyboard input. Sleep clears obsolete temporary state before Caps Lock refreshes on wake; a physical sleep/wake test is still outstanding.
- All 34 Swift tests passed, including scheduling priorities and cancellation. All six release-configuration tests passed, covering no-feed builds, valid configuration, missing fields, unsafe feeds, invalid keys, and invalid build numbers.
- Replaced the 100% Vivid gate with linear backlight multiplied by measured transfer gain. At slider 87.5%, a read-only probe returned linear 0.72742695 and peak 1.45. The user confirmed that the orange marker now appears on entering the extra range below 100% and disappears when dimmed back into the normal range. This is an output estimate, not a read of Vivid's internal mode; other displays are unverified.
- Bundled Sparkle 2.10.0 and its license. The app bundle is about 5.1 MB on disk. The reusable MacAppUpdates library does not start a controller or network checks without a feed and public key. No release feed or production update key exists yet, and no update was published or installed. A complete download/install/relaunch test requires a host and signed release builds.
- Release build passed deep, strict code-signature verification using the existing persistent development identity. The relaunched app's diagnostics reported Accessibility and the event tap active, with Vivid detected. No permission reset was needed. Rendered and inspected notch and external-pill previews including the blue Caps Lock icon and Active label.

## Revision 7: settings, connections and multiple displays

- 44 Swift tests and six updater-configuration tests pass. Added Low Power Mode edge/value checks, old-preference decoding for Smooth brightness, duration deadline replacement, exact top-edge menu hit testing, and the combined external brightness scale including blackout limits.
- Synthetic background input check admitted 1,000 rapid media presses with zero native fallthrough, while all 1,000 unrelated Caps Lock events passed through. The queue remained at two hardware calls plus one coalesced press. No synthetic input was posted to macOS.
- Live controller persistence check passed six assertions with external monitors attached, including returning to the persistent display after volume and cancelling an in-flight return.
- Settings was scrolled to its final Pause button. Bottom padding is visible, with no fixed footer cutting it off. About was inspected with its new Quit row. Native fixed-size preview selector and threshold-driven previews remain.
- Two attached HP E273q displays had no DisplayServices brightness control. Exact DDC registry matching succeeded. DDC reads returned empty replies; exact MonitorControl profiles supplied their saved values and maxima. The user confirmed external brightness changes with only Dynomite's indicator. The user then confirmed the combined software range reaches full black at 0%, recovers on brightness-up, and transitions smoothly. The user also confirmed the in-place Low Power Mode color animation.
- With external monitors attached, the MacBook transfer curve was neutral despite Vivid running. The user toggled Vivid off/on and confirmed this was a Vivid issue. Dynomite retains measured output detection rather than showing the marker whenever Vivid runs.
- Rendered and inspected dark/light notched and pill previews at 100%. A further inset adjustment pins equal notch outer padding; the larger drawing bounds accommodate external overshoot and glow. Low Power Mode tint changes now animate while visible.
- Final UI check changed Brightness duration from 2 to 15 seconds, started an on-screen preview, and used Reset duration. The control returned to 2 seconds and Reset became disabled. Smooth brightness and Vivid options were present. The display-style selector retained its size throughout.
- Final release signature verification passed. The running build contains the combined external dimming range and animated Low Power Mode state changes confirmed by the user.


## Dynamite rename and external pill bounds

Renamed the Swift package, source target, executable, icon, and visible app name to Dynamite. The bundle identifier and certificate-pinned designated requirement are unchanged. The signed renamed app reports Accessibility true and event tap active. All 44 Swift tests and six update-configuration checks pass. Raycast Applications settings visibly lists Dynamite after adding an Applications launcher link. The physical workspace root remains Dynomite because Codex rejects a symlinked writable root; the sibling Dynamite path is an alias instead. The former bundle path also forwards to the new build.

Removed the external outline mask, reserved 6 points of vertical drawing space above and below the resting pill, and used explicit circular corners during its uniform shrink. Dark-background previews show complete outlines and balanced padding. Live overshoot and dismissal feel still need user confirmation on the external monitor.


## Native sidebar and live integration revision

- 47 Swift tests and 6 Python checks pass, including Clock time parsing, timer values above 100 seconds, strict Focus state decoding, and timer wing sizing.
- The signed app observed real running and paused Clock countdown values. Hover controls, click-to-open, and internal-display placement require final interactive verification after the latest build.
- Real connected AirPods battery getters were read in the signed app. Missing values are not estimated. A reconnect test remains outstanding.
- Focus requires Full Disk Access for Dynamite. The user approved granting it manually; do not bypass macOS file protection.
- User approved retaining Apple's native alerts for the added integrations. AirDrop's standalone observer received no callbacks during the third-party transfer test. The signed adapter and card are implemented, but reception, action forwarding, and completion remain unverified.


## Timer controls and AirDrop receipt follow-up

- 52 Swift tests and 6 Python checks passed after adding pause grace-period and strict fresh AirDrop receipt parsing checks.
- User confirmed AirDrop completion cards for a real Downloads transfer and AirPods battery after reconnect. The AirPods fix registers disconnect listeners for initially connected devices and retries battery metadata a bounded number of times after connection.
- User explicitly approved inspecting Notification Center for Clock alert actions after automatic review initially blocked the broader accessibility read. The adapter does not log or save notification text.
- Inspected the real expanded Clock card with orange Repeat and Stop buttons. The first running build reported that the native banner remained; later suppression changes still require visual verification.
- The latest Clock reader caches verified timer nodes and samples those at 200 ms while a timer exists, publishing only changed values. Full-tree discovery remains bounded. Physical pause/resume and countdown synchronization still require verification after this change.
- Expanded cards now share circular actions and an inset animated close control. Escape dismisses AirDrop or invokes Clock’s Stop action. Native AirPods/AirDrop banner dismissal and incoming AirDrop Accept/Decline remain unverified.

Latest user verification: timer pause/resume, countdown timing, and Escape stopping the expanded finished alert all work. The signed follow-up also restores reused notification hosts when their source changes and verifies offscreen positioning before reporting replacement. Native AirDrop/AirPods banner suppression still awaits user verification.

## Finished duration and timer interruption

- Original timer duration is read separately from the decreasing countdown label and retained when the timer reaches its final second. The finished Clock card uses the native alert duration or this retained value. Unknown durations show “Timer” rather than a fabricated zero or estimated duration.
- 54 Swift tests and 6 Python checks passed, including strict parsing of seconds, minutes, and compound original-duration labels and rejection of countdown/custom-label text.
- Caps Lock modifier events can temporarily interrupt a persistent Clock timer; baseline refreshes do not trigger that interruption. The existing per-feature duration controls this interval, defaulting to two seconds. Turning Caps Lock off early removes its temporary activity.
- Expanded cards opening from compact timers retain their width and expand downward with a damped spring; content appears after the shell starts moving.
- AirDrop display placement and revised exit motion were confirmed by the user. Native AirDrop suppression and transfer progress remain unresolved. The retained diagnostic sees one native banner but cannot identify it as AirDrop. Automatic approval review blocked direct Notification Center inspection because the prior approval covered Clock only; an AirDrop-specific approval is pending.
- Live verification after relaunch: the running timer showed 0:14; its finished card then exposed “0:23” alongside Repeat and Stop. This confirms the original 23-second duration is retained instead of using the last observed countdown or 0:00.

## Microphone mute and content motion

- 56 Swift tests plus 6 Python checks passed. New tests cover master mute, input gain zero, multi-channel mute/zero combinations, unknown controls, quiet baseline/device changes, and duplicate events.
- The signed app reports the real default input as unmuted. Settings exposes the enabled Microphone mute activity, a two-second duration slider, Reset duration, and the red muted preview; inspected live through accessibility and a screenshot.
- Actual hardware mute/unmute confirmation is pending user verification. The agreed scope is the default microphone's device mute or input level zero, not separate call-app mute state.
- Icon and text replacements are keyed by activity type/state and spring inside stable wings. Expanded-card springs remain centered and now have extra transparent room beneath their overshoot.
- User confirmed both real microphone mute/unmute indicators and the Caps Lock-over-timer content transition work correctly.

### Top-edge hover and card transitions, September 20

- Added boundary tests for notch hover at exact screen maxY, across the physical camera, shifted display coordinates, external top gaps, and exclusion of panel overshoot margins. All 58 Swift tests and 6 update configuration tests pass.
- Signed release builds succeed with the existing local identity.
- Finished 3-second Clock test exposed Dynamite's original `0:03`, Repeat, and Stop controls. UI automation switched back to Settings during the attempted Repeat click, so this did not verify Repeat or animation quality.
- Physical pointer hover at the screen ceiling, menu second-click/outside-click dismissal, Repeat handover, and the moving outline on black still need user confirmation. The compact shell timing was retained after the user identified early outline fading as the visual problem; only its rim fade timing changed.
- Final build also reuses the existing NSPanel across compact/card changes, retaining its WindowServer surface during expansion. Relaunched successfully through the app UI.
- Opt-in `--verify-persistence` passed all six live checks: persistent visibility, temporary replacement, return without collapse, expiry return, cancellation, and a new activity interrupting a return.

### Resource audit and horizontal compact dismissal

See `performance-2026-09-20.md` for calibrated measurements and their limits. The clean one-minute idle sample averaged 0.0097% of one core with a stable 71.3 MiB footprint. Eight-cycle rendering comparisons averaged 9.88% -> 8.58% for the notch and 9.30% -> 7.44% for the external-style preview. Retained changes remove native window transformations and redundant synchronous display updates. Sizing and GPU drawing-group experiments were rejected based on their measurements.

The compact notch now retracts only horizontally and fades its moving rim from 120–280 ms into the 440 ms collapse. External pill timing is unchanged. The final test suite passed 58 Swift and six Python tests.

### Clock persistence and compact notch seam, September 20

- Reproduced loss of a running countdown after closing Clock's window, plus loss of detection when repeating a finished timer while that window remained closed. The AX-only reader discarded missing windows and relied on finding controls for each new countdown.
- Verified Clock's read-only MTTimers mirror against a real two-minute timer: state 3 stores its absolute fire date; state 2 stores the exact paused remaining interval (54.504978 seconds in the live check). The running app loaded that same timer as paused at 55 seconds. No native preferences are written.
- Added strict timer-record decoding and continuity regression tests: 67 Swift tests and six Python update checks pass. Unknown active record formats fall back to the bounded AX adapter. File changes refresh the cache; running countdowns use one deadline-aligned in-memory tick per second; paused/idle records have no ticker.
- Timer controls now refresh AX targets before use and attempt a background Clock reopen if controls are absent. Repeat reconciles the saved timer state without opening Clock's window. Final user confirmation of resume, closed-window countdown persistence, and pause/resume controls is pending.
- The compact notch retains its horizontal retraction. The first black-fill fade at 260–400 ms still left a visible strip against wallpaper, as reported by the user. The revised fill fades at 120–260 ms alongside the existing outline while the shape keeps its constant height. The user confirmed this revision closes cleanly against colored wallpaper. External pill timing and shape are unchanged.

- Follow-up signed build succeeded. A real 20-second Clock timer returned after a volume interruption and counted down to 0:03. Finished-alert and Repeat verification did not complete: the control session returned to Settings, and Notification Center capture was unavailable. This does not establish that Repeat is fixed.


### Concurrent activity routing

- 71 Swift tests and six Python checks pass, including same-screen interruption, cross-screen coexistence, expanded-card protection, expiry routing, and stacked pill geometry.
- `--verify-routing` passed six live lifecycle checks: one persistent display, one panel per temporary target, return after expiry, visible exit on former screens, final removal, and cleanup.
- User confirmed expanded cards remain visible while alerts appear alongside/below them. A later report found that lower pills did not move upward; the direct window-position regression reproduced zero movement with the origin animator. The user also confirmed prompt start/pause response from Clock after adding foreground cached-control reads.
- A follow-up cleanup restores normal display geometry for activities after a promoted pill expires. Signed build and live lifecycle checks cover that final source. Exact energy impact of simultaneous animations remains unmeasured; no extra idle ticker was introduced.

- The promotion regression failed with `setFrameOrigin`: zero points of movement. Switching to the animated full-frame setter passed with a 51-point intermediate position and the full expected 132-point upward movement. The 320 ms duration is unchanged. `--verify-promotion` now checks both progress and final position.

### Repeat content entrance and card spacing

- Signed release build passes after separating compact content visibility from shell expansion. The six live persistence/handoff checks pass.
- Card-to-compact returns now start with content hidden while the shell remains open, then trigger the normal content spring/fade after 60 ms. Timer card bottom space is reduced by eight points; AirDrop bottom space is reduced by four points. Visual confirmation of a real Repeat transition remains pending.

- User reported an expansion/Repeat regression after the separate global content flag. Removed that flag and restored ordinary expansion coupling. The delayed content entrance now exists only as local state on the new compact view after a card return. Repeat reconciliation also invalidates the cached native Start control.
- Signed correction builds successfully. Motion sampling records 175 expansion samples, including overshoot to 1.159, and 134 collapse samples; this verifies interpolation remains active, not visual acceptance of Repeat. Final user confirmation is pending.

### Overlapping Repeat and timer-finish priority

- The local delayed entrance was still perceived as sequential by the user. The compact return content now enters inside the flattening card shell, before the controller replaces the hosting view. Bottom padding changes are retained.
- Expanded-card rim visibility now follows shell expansion, preserving the rim through flattening and fading it during retraction. This addresses the closing motion becoming invisible on black backgrounds.
- 74 Swift tests and six Python checks pass. New handoff tests cover a stable final-second deadline, pause/cancel/restart invalidation, and an immediate fallback when the final second is missed. Signed build succeeds. Visual confirmation of these latest overlapping transitions and finish priority is pending.

### Expanded spring regression

- Reproduced the lost spring in the actual expanded shell: a 97-point target reached exactly 97, with no overshoot. The fill/rim fade animations were overriding geometry interpolation.
- Scoped opacity animations to their opacity modifiers and retained the existing geometry spring. The same live check now peaks at 100.167 points for the 97-point target, with 106 intermediate samples. `--verify-card-motion` guards this behavior.
- Restored opaque black backing throughout opening so the camera seam cannot flash while the card expands. Repeat overlap, final-second priority, and tighter card spacing are unchanged. Signed build succeeds.

### Native Clock flash and expansion tuning

- Clock window creation and expected finish events now bypass the former 80 ms debounce, including promotion of a queued ordinary read to an immediate read. Stop/Repeat discovery ends once both controls have been found. The lookup remains bounded and adds no polling. An initial native frame may still precede macOS delivering its accessibility event; zero-flash replacement is not yet verified.
- Expanded opening uses a 0.46/0.60 spring, with a separate small spring on its content. Live shape verification passes at a 102.759-point peak for a 97-point target. Opening/closing opacity stays scoped separately from geometry.
- Signed release builds pass. Native flash and subjective animation quality need confirmation on a real timer completion.

### Expanded outline synchronization
- User confirmed the native Clock banner no longer flashes and the expansion feels good, but reported the dark-background rim lagging behind the fill.
- Combined expanded fill/rim geometry under one interpolator and anchored the rim fade to the screen edge. Previously its gradient spanned the final card height, masking much of the rim while the card was still short.
- All 74 Swift and six Python checks pass. Signed release build succeeds. The live `--verify-card-motion` check retains the same peak of 102.759 points for a 97-point target, with 55 shared intermediate geometry samples. The accepted spring and native-notification suppression were left unchanged. Visual acceptance of the synchronized rim remains for user review.

### Expanded action entrance
- Replaced the nearly full-size whole-card content entrance with a shared centered spring on the Clock/AirDrop action row. The current shell path also clips the row during expansion.
- All 74 Swift and six Python checks pass; signed release build succeeds.
- `--verify-card-motion` now renders the real action-row modifier as well as the shell. Live verification passes with 45 intermediate action samples and progress peaking at 1.0683, corresponding to roughly 1.1% button-size overshoot. Shell peak remains 102.759 points for its 97-point target. Subjective entrance feel remains for user review.
- Live Clock check: Repeat remained clickable, returned a running 0:04 countdown, and reopened the expanded 0:05 card with both controls visible.

### Repeat notification priority
- Found that notification priority was armed only once per timer ID. Clock reuses that ID for Repeat, so later layout events could return to the 80 ms debounce after the first priority window expired.
- Priority now re-arms for an expired window even when the ID is unchanged. Three regression tests cover Repeat, bounded duplicate updates, and another timer's finish. All 77 Swift and six Python checks pass. No notification scope, polling, or shell spring changes were introduced. A native first-frame flash still requires visual confirmation because the AX event may arrive after macOS draws it.
- User still observed a brief flash after the priority fix. The subsequent revision parks an identified Clock alert before its Stop/Repeat traversal, batches related AX attributes into single IPCs, and gives urgent reads user-initiated scheduling priority. Failed control discovery restores the native alert in the same bounded scan. All 83 checks and the signed release build pass. Zero visible native frames is not yet established.

### AirPods connection popup investigation
- Apple's audioaccessoryd logs identify the connection UI as a Bluetooth Smart Routing `Connected` banner with a four-second timeout. Further inspection of the actual macOS `_smartRoutingShowBanner` implementation shows `CUUserNotificationSession` publishing under `com.apple.BTUserNotifications`. The first BluetoothUIService hypothesis came from a different platform path; that observer captured nothing and was removed.
- The legacy `com.apple.bluetooth/srConnectionAlert` preference is read but not consumed on this build's display path. No system preference was changed.
- Restored the 250 ms battery-read delay after a failed immediate-read experiment. Added a CoreAudio default-output event listener for Smart Routing switches that occur while the Bluetooth link is already connected. Device UID matches the paired device address, and battery product getters still verify it is AirPods. Duplicate route/connect events are coalesced.
- Native matching now includes child labels and the verified connected device's name. A bounded retry after a confirmed AirPods reading catches delayed banners. A temporary five-minute, AirPods-text-only diagnostic captures matching notification controls in `/tmp/dynamite-airpods-popup-observation.json` for validation. Native suppression is still awaiting verification.
- All 83 checks and the signed release build pass. The failed BluetoothUIService observer is no longer in the app.

### AirPods MenuBarAgent host correction
- The user confirmed Dynamite's battery activity returned, but Apple's popup remained. Notification Center traces found no matching banner.
- A bounded, redacted window-owner trace identified MenuBarAgent's 352 × 152 connection popup. Its runtime accessibility identifier is `smart-routing-system-banner`. MenuBarAgent logs independently confirm the identifier and four-second lifecycle. The Notification Center and BluetoothUIService hypotheses do not describe this presentation on macOS 27.
- The real popup exposes no dismiss action. It does expose a movable, dedicated window. `NativeSystemBanner` observes that host and verifies offscreen positioning only for its exact identifier and passive contents, after a validated AirPods connection. Actionable content, reused window identifiers, disabling the feature, and shutdown restore the native window. Reads are bounded to 120 ms plus the current AX call, with a short post-connection retry burst and no idle scans.
- A live reconnect produced “Native connection popup hidden” with verified position readback. The user confirmed the duplicate now disappears, but initially remains visible briefly. Product identification now arms the handler before the independent 250 ms battery-settling delay. Zero-flash behavior of that final timing change is awaiting confirmation.
- Removed both temporary trace implementations and the broad Notification Center name-based matcher. No system preferences, Bluetooth services, or audio-routing settings were changed. All 77 Swift tests and six Python checks pass; the final early-detection release build is signed successfully.

- The early-detection test initially appeared silent, then the user reported both indicators after roughly ten seconds. MenuBarAgent logs also show Apple extending a banner beyond its initial four-second timeout. Removed expiry-based restoration of a still-existing, already identified card. New banners are eligible for twenty seconds after product verification; existing hidden cards follow their actual window lifetime. Direct move/resize observation handles system repositioning. Passive battery/text refreshes no longer restore the same card; actionable controls or a changed window identifier still do. The lifecycle build is signed and running, with final reconnect validation pending.

### Focus, stem volume, and external-display follow-up
- The user confirmed the AirPods connection lifecycle fix worked. Focus and AirPods stem volume now use MenuBarAgent's runtime-confirmed `focus-system-banner` and `volume-system-banner` identifiers. CoreAudio property listeners supply real volume changes, while source-availability gates retain native feedback if an integration cannot read state.
- Early window-created handling improved Focus, but the user still reported a brief volume flash and occasional native popups after moving to another display. Zero-flash suppression is not established.
- A bounded metadata-only trace captured the same MenuBarAgent window at an offscreen position and then back onscreen. The old scan restored tracked windows whenever they were missing from a scan, including AX timeouts and budget exhaustion. Verification-read failures also restored them.
- The follow-up refreshes known windows first, handles their movement directly, and distinguishes explicit actionable contents from unavailable reads. Failed or partial reads no longer restore a successfully hidden popup. Destroyed windows are forgotten without a position write; identifier reuse, actionable controls, disabling, and shutdown still restore live windows. The shared AX run loop is independent of the main UI thread and does no idle polling.
- Removed the temporary host trace after capturing the failure. The temporary Focus test shortcut was deleted with the user's explicit confirmation. All 77 Swift tests and six Python checks pass. External-display and first-frame behavior of this latest fix still requires a live test.

- Live follow-up: the user reports only a very short flash on the first AirPods volume swipe after the native popup has fully closed; subsequent behavior is correct. The return-after-hiding issue is resolved in that test. Signature verification passes using the approved user keychain. A read-only inspection of MenuBarAgent and ControlCenter did not establish a per-volume pre-presentation suppression switch. The current AX window-created handler cannot promise suppression before the first rendered frame. Retained the validated build without changing system preferences or the working AirPods connection path.

### Display preview and integration settings redesign
- Replaced the isolated gray preview stage with a fixed-height display crop using the real activity renderer, a vector wallpaper, and a persisted black-background option. The revised bezel is seven points; outer/inner radii are 20/13, and the menu-bar tint is removed. Native fixed-width segments select MacBook/external style and macOS style/Dark without popup menus. Existing activity selection and Show on screen remain.
- Integrations now leads with permission status and settings links, then connected Bluetooth devices and optional component batteries, followed by useful current state. Removed repeated native-popup diagnostics and implementation paragraphs from the main page. AirDrop's incomplete request/progress support is still stated plainly.
- The live page displayed real left/right AirPods readings and the lower-earbud summary, plus allowed Accessibility, Focus-file access, and Downloads access. Settings refreshes add no background polling and do not produce a connection activity.
- Rendered and inspected notch/external previews against wallpaper and black, including a three-digit brightness value and the Vivid badge. The 77 Swift and six Python checks pass; signed release builds succeed. Live inspection confirmed the final Dark and macOS style segments, the notch outline on black, the external pill on black, and the restored wallpaper preview. The user can switch directly with no background popup menu.
- Research findings and the unimplemented integration shortlist are recorded in open-source-research.md with commit-pinned source links across 11 projects. No downloaded project was executed.

- The render-only lifecycle now skips AppModel.stop when the model was never started, preventing diagnostic processes from flushing their settings snapshot over the running app’s preferences. Static render transactions disable animations for exports; live previews retain their normal transitions.

## Portability, setup, and duration audit, September 21

- Removed the unverified incoming AirDrop bridge. Received-file monitoring and Open/Show in Finder remain. Preview now says Received rather than presenting a transfer percentage. Stale AirDrop callbacks after stop/restart are rejected; the standalone lifecycle harness tests receipt delivery, dismissal, stopped and restarted sessions, empty receipts, and multiple files.
- Setup assistant visually inspected in the signed app. Accessibility and Focus availability displayed correctly; the explicit Downloads check changed to Available; Start returned to Settings. Existing login state was preserved. Fresh-account denial and first-install OS prompts still require a separate account/Mac; existing permissions were not reset for testing.
- Window sizing is centralized and hosting-view minimum-size propagation is retained so page changes cannot override the 820–1640 width range and 400 minimum content height.
- Persistent feature summaries now derive On/Off from their switches.
- Duration steps start at 0.5 seconds and end at one hour. Tests cover slider round trips, invalid values, unit labels, serialization of short/long/legacy values, and replacement of a one-hour deadline with a half-second deadline. Defaults and existing stored durations are retained.
- 80 Swift tests and 6 updater tests passed, plus the AirDrop lifecycle harness. No new integration ideas, release feed, donation link, or publication were implemented.

### Sidebar resize correction

The previous 760-point minimum allowed the Activities controls to exceed available width, and disabling hosting-view size propagation made clipping possible. The root now has a consistent 820-point minimum width and 400-point minimum content height; the maximum content width is 1640 points. Native sidebar thickness is fixed at 200 points. The sidebar item's canCollapseFromWindowResize is disabled without disabling its toolbar collapse action. Hosting-view minimum sizing is retained. The build and signature verification passed; the native toolbar button was exercised. Interactive minimum-size feel is awaiting the user's resize check on their display arrangement.
