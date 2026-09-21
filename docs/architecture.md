# Architecture

`IslandCore` owns preferences, activities, media-key decoding, battery transitions, display geometry, and stereo volume calculations. Providers emit activities through `AppModel` into `IslandController`, which owns one shared presentation and one panel per selected screen.

## Input and audio

`MediaKeyMonitor` installs a filtering HID event tap on a dedicated run-loop thread. The callback decodes keys and admits at most two pending operations. It does no Core Audio, display, menu, or SwiftUI work. Saturated or disabled handling passes through. Hardware changes run on a serial worker queue. Failed operations replay the original event with a marker that prevents a loop, followed by a key release. If macOS disables the tap, it stays disabled until an explicit refresh; it is not repeatedly re-enabled in its callback.

The user's reported freeze could not be reproduced and had no matching crash report. Removing synchronous hardware operations from the global input callback addresses a concrete blocking risk, without establishing the original cause. `--verify-input` exercises 1,000 calls to the actual admission callback without posting system keys.

`AudioController` resolves the default output for each operation. It tries the virtual main volume property first, the hardware main property next, and stereo channels last. Channel values preserve relative balance. If a channel write fails, previous writes are restored before returning control to macOS. Mute uses the output mute property.

The initial implementation assumed a main scalar property. The development Mac's output exposes virtual main volume and individual channels instead, which caused every operation to fall through to native handling. Diagnostics now expose that capability check.

## Provider lifetime

Battery updates use IOKit notifications, with no recurring timer. The first snapshot is a baseline. Only connection and threshold crossings emit events. Pausing stops providers; resuming or waking establishes a fresh baseline. No stale reminders are queued.

When a feature group is disabled, its event source is removed. `LoginItemController` queries and updates ServiceManagement only on launch, settings access, or a user action.

## Overlay geometry

`IslandGeometry` contains height, physical center width, and top gap. On a notched display, the safe-area height and gap between the auxiliary top areas define the physical hardware. On an external display, center width is zero, top gap is 6 points, and height matches the attached MacBook or defaults to 32 points.

`IslandSurface` uses a left wing, optional physical-notch space, and a right wing. Their widths determine the background. Unequal wing widths offset the entire row so the physical notch center stays centered on the display. There is no center gap on external displays. The same view renders the settings preview and real overlays.

Content uses the physical notch height, with a one-point shell lip below it. Panels reserve transparent room for the external pill spring to overshoot without clipping. Notched content never translates into the camera region. The shell grows horizontally; external pills also grow vertically from a small center capsule. Expansion uses a 0.48-second spring with damping 0.50. Dismissal begins with a 3.5% outward release over 60 ms. The physical notch then uses a 0.44-second easing curve that lands without undershoot; the external pill retains a 0.40/0.56 spring. Each content wing scales from 0.60 with its own 0.46/0.48 spring and short delay, clipped to the wing bounds so it cannot enter the hardware cutout. `IslandMorph` interpolates an animatable path rather than the container frame. This keeps width animation independent from opacity and layout transactions. Its expansion amount preserves spring overshoot above one, while side widths interpolate when the activity changes. Content and outline have separate fade timing. The black notch shape keeps a constant height and fades from 120–260 ms during dismissal, alongside the rim, so its one-point lip is gone before the wings reach the camera. Reduce Motion keeps the final geometry and fades.

`IslandOutline` is inset to keep its entire stroke in bounds. Its notched path is open at the top. A low-opacity activity-colored stroke with a soft rim supplies contrast on dark backgrounds without a capture permission or a screen-sampling loop.

Each activity replaces the current one and invalidates its old one-shot deadline. There are no repeating animation timers. Repeated keys reuse panels and extend the dismissal deadline. A screen-target change recreates panels on the new targets. At dismissal, the view retracts, then the controller closes and releases the windows. Pausing, disabling the current feature, and changing placement dismiss immediately. Duration, threshold, menu bar, and window preferences do not dismiss an active preview.

Explicit display previews target the attached MacBook when present. External-preview geometry removes the center gap and adds the physical safe area to the six-point top gap. The panel reuse key includes this preview mode. The settings stage owns its reveal state independently of preference changes.

## Settings and application lifecycle

`SettingsStore` saves Codable preferences. Missing fields get defaults so upgrades preserve older choices. `AppDelegate` observes preferences to add/remove the status item and set the settings window's level to floating or normal. Window content is released when settings close. Reopening the app always opens settings, regardless of status-item visibility.

`NotchMenuMonitor` installs a passive right-mouse-up event tap on the main run loop, with NSEvent monitors as a permission-free fallback. It captures the click location and hit-tests the camera, a 12-point strip below it, and visible island bounds. Menu tracking starts after the callback and guards against duplicate opening. The status button explicitly handles both left and right mouse-up actions. Both use the same menu factory. There is no idle window or mouse-move tracking.

Settings use native tab and form controls and follow system appearance. Avoid decorative all-caps copy, repeating feature descriptions, and implementation detail in normal controls.

## Adding an integration

1. Prove a real event source and define which native behavior it replaces. Document any retained Apple alerts and obtain the user's scope decision before treating additive feedback as a full replacement.
2. Add the feature and its default preference, then emit activities from a provider. Keep state machines in `IslandCore` and system APIs in the app layer.
3. Start and stop the provider through `AppModel`. Avoid background polling; prefer notifications, listeners, or a validated event source.
4. Reuse `IslandSurface` and geometry. Add transition tests and run actual user-path verification.
5. A persistent timer needs a deadline/paused-state model, source controls, and arbitration with transient HUDs. Do not turn a guessed number or a static preview into a purported Clock integration.

ClockMonitor reads the timer service’s saved MTTimers mirror through a file watcher. Valid running records provide the real fire date; paused records retain their exact remaining interval. One deadline-aligned tick per second updates active countdowns from memory, with no timer tick or periodic disk reads when paused or idle. Accessibility is retained for Clock’s controls and as a fallback if the mirror is unavailable or changes format. Control targets are refreshed before each action. The app never writes the service’s preferences. FocusMonitor watches the protected Focus directory for changes after Full Disk Access is granted. AirPods reuses Bluetooth connection events, CoreAudio output-route events, and validated battery getters. Product identification arms native-popup handling before the separate battery-settling read. NativeActivityNotifications observes matching Clock and AirDrop banners. NativeSystemBanner separately observes MenuBarAgent’s exact `smart-routing-system-banner` window on macOS 27. Only passive connection content is hidden after a verified AirPods event; actionable controls or a reused window identifier restore the window. Hidden cards follow their native lifetime, including timeout extensions. Direct window move/resize events reapply verified positioning. A bounded post-connection burst supplements AX events, with no idle window scans. Clock actions stay backed by the original alert; offscreen positioning is verified by reading its position back, and reused or shared hosts are restored. Native suppression remains subject to live verification. AirDrop uses the event-driven Downloads receipt watcher only. The nonfunctional private observer and its bridge were removed. Persistent priority is AirDrop, then a running or hovered paused Clock timer, then Caps Lock. Caps Lock and Clock prefer the internal display.

## Vivid and local signing

Vivid support currently detects the extra range and can hide Vivid’s own circle. Standard hardware brightness always uses the direct DisplayServices path. `VividBridge` checks Vivid’s running process, display selection, HDR capability, and the actual gamma table. The marker uses linear hardware brightness multiplied by the minimum of the three channel peaks, with a 1% tolerance above the normal maximum. Vivid can retain a boosted transfer curve below the extra range, so gamma alone must never enable the marker. This detects the display effect, not Vivid’s private in-process state. It performs no idle sampling and never writes gamma tables.

Full keyboard control of Vivid’s boost remains unfinished. HID replay invokes Apple’s HUD. Process-targeted delivery suppressed that HUD but did not adjust Vivid’s brightness in a physical-key test. Both experimental routes were removed. Do not restore either based only on a successful build or an event-posting call; require an actual brightness change in both ranges.

Development signing uses a private, persistent certificate in `~/Library/Application Support/Dynomite/DevelopmentSigning`. The directory is private to the user. The key is imported as non-exportable into a dedicated keychain and temporary PEM/P12 key copies are removed. The generated password file is private to the user. Certificate trust is separately approved and scoped to code signing. Build requirements pin both bundle identifier and leaf certificate fingerprint, so source changes do not change app identity. Do not commit, sync intentionally, or distribute signing material.

## Brightness updates and display notifications

`BrightnessController` ramps the actual hardware value over 180 ms on AppModel’s serial hardware queue. `BrightnessRamp` computes monotonic intermediate values and accumulates repeat presses against the pending target. A token cancels an old ramp when another key arrives. Scheduled work ends at the target or a failed write; there is no idle timer.

`NSApplication.didChangeScreenParametersNotification` also fires during brightness/HDR changes. `IslandController.screenParametersChanged()` compares display IDs, frames, scale factors, and notch geometry before dismissing. Never dismiss unconditionally here: that hid the brightness activity immediately after each successful hardware write, and smooth ramps made the bug more frequent.

## Persistent activities

`ActivitySchedule` gives the most recent temporary activity precedence over persistent state. Caps Lock supplies that state through `CapsLockMonitor`, using modifier-change events and a state read on launch or wake. The visible persistent activity has no expiry timer. A temporary activity replaces it and owns a one-shot deadline. At expiry, `IslandController.transition` replaces the content in place, preserving the expanded shell and panels. Turning Caps Lock off clears persistent state, so no later temporary expiry can restore it. Pause, disabling a feature, sleep, and placement changes reset obsolete presentation state.

Keep future providers independent of rendering. They should emit `Activity` values and state changes to `AppModel`; do not create provider-specific windows or animations. Extend the schedule's arbitration explicitly if a second persistent source is introduced. Add a feature preference, event-driven lifetime, priority and cancellation tests, preview, and a support entry that states which native UI is replaced. Failure must preserve system controls. A notification from another app must not be allowed to change the software-update feed or install code.

## Vivid range estimation

The perceptual brightness slider is not linear light output. `DisplayServicesGetLinearBrightness` and the measured gamma peak estimate output relative to the normal maximum. `BrightnessRange` marks values when their product exceeds 1.01, allowing rounding tolerance. Neither a running Vivid process, a retained boosted gamma table, nor a 100% slider check suffices alone. At an observed slider value of 0.875, the linear value was 0.72742695 and the gamma peak was 1.45, yielding about 1.055. The marker can therefore appear below 100%.

This is an output estimate, not a direct read of Vivid's private internal mode. The user confirmed that it now appears in the extra range below 100% and disappears on returning to the normal range on this Mac. Other display configurations remain unverified. The settled ramp callback updates only a still-visible brightness activity, so it cannot overwrite a later volume or Caps Lock activity. It does not extend the dismissal deadline or schedule idle work.

## Software updates

`MacAppUpdates.NativeUpdater` owns Sparkle and knows nothing about activity providers or island rendering. The host bundle supplies an HTTPS feed and public Ed25519 key. It does not construct an updater until both are present. About observes its state and opens Sparkle's native update workflow; releases cannot currently be checked because this development build has no feed. See [release setup](releases.md).

## Caps Lock crash regression

Four September 20 crash reports had the same stack: `MediaKeyMonitor.receive` converted a CGEvent through `NSEvent(cgEvent:)` on the input thread. HIToolbox's Caps Lock processing then asserted that it was not on its required queue. This was separate from SwiftUI transition scheduling.

`MediaKeyEventDecoder` now reads the optional Core Graphics subtype and compound-data fields directly, without AppKit or HIToolbox in the callback or fallback release path. Before installing the filtering tap, the main thread validates those field IDs against two locally constructed AppKit media-event samples. No samples are posted. If validation fails, native handling remains available. The background regression exercise covers bounded admission, unrelated Caps Lock events and release decoding. The optional passive brightness trace uses the main run loop and is separate from normal operation.

## Hotspot provider

`WirelessMonitor` keeps one CoreWLAN client while enabled, subscribing only to SSID, link, and power changes. It coalesces callbacks and limits reads to one in flight plus one pending refresh. Reads and registration run on a utility queue, never on the main thread or media-key thread. A generation token rejects callbacks after pause or disable. `HotspotTransitions` suppresses baseline, repeated, unknown, and wake readings.

The read uses the current scan result's `isPersonalHotspot` property through a guarded optional private API. It does not scan or query SSID, BSSID, phone identity, credentials, or battery. Public CoreWLAN has connection notifications but no accurate source-phone battery API. The tested private battery sources were inaccurate; user-approved scope is connection-only.

## Settings containment

Settings uses an explicit fixed-width sidebar and independent detail header. It does not attach NavigationSplitView's toolbar or titlebar safe-area behavior to the AppKit hosting window. Sidebar icons have a fixed 20-point column. Preview display selection is an AppKit NSSegmentedControl with fixed segment widths, insulated from SwiftUI slider transactions. Preview thresholds come from the same Preferences values as real reminders, and value-only edits update the staged activity without restarting its appearance animation.


`WirelessMonitor` distinguishes ordinary Wi-Fi from Personal Hotspot, with one baseline and subscription set. `BluetoothMonitor` observes paired connection events and installs per-device disconnect observers to deduplicate reconnects. Stop invalidates queued reads. `BatteryMonitor` also subscribes to ProcessInfo power-state changes; the same snapshot includes battery percentage and Low Power Mode.

Settings persistence coalesces writes over 150 ms. Provider reconciliation compares only enablement, pause, and placement, so dragging duration/threshold sliders does not restart event taps or hardware providers. Duration changes have a separate 120 ms debounce and replace the current transient deadline while preserving the preview display style. The segmented preview selector is a fixed-size NSSegmentedControl. Style changes crossfade independent reveal stages without a delayed close/wait/open sequence.

Media input admits at most two hardware operations and one latest deferred press per media key. Repeats coalesce rather than fall through to the native HUD during bursts. Unsupported hardware still replays the consumed event. The CG callback neither calls AppKit nor waits on hardware.

MicrophoneMonitor observes Core Audio's default input device and its mute/level properties on a utility queue. Listener events are coalesced for 25 ms; there is no audio stream or idle polling. Device changes, wake, and re-enabling establish a quiet baseline. Mute and zero gain resolve to a single state; only real edges create timed activities. Listener removal and generation checks prevent events from a disabled or replaced device from resurfacing.

Compact activity changes keep the shell alive while independently transitioning each wing's contents with a short symmetric offset, scale, and fade. Identity changes follow activity type/state, so ordinary volume changes and timer ticks do not replay the whole replacement animation. Expanded shells retain their centered layout while using more spring in opening, flattening, and retraction. Reduce Motion keeps fades and suppresses geometric spring animation.

Activity hover uses passive local/global mouse movement callbacks only while island panels exist. The hit region extends through the physical camera and includes the exact screen maxY boundary and external pill's top gap, but excludes transparent overshoot space. Published screen IDs change only on region entry/exit. Clock pause visibility uses that same region.

Expanded cards animate a path inside fixed layout bounds, keeping the upper edge anchored. Card-to-compact changes retain the card for a 280 ms flattening phase; incoming samples replace the pending destination without restarting that phase. Replacement windows are drawn before the previous backing store is retired. Closing clears all card transition state. Compact outlines retain their rim during the outward release and fade for 320 ms during inward retraction.

Notch context menus receive passive button callbacks through the common-mode run loop so dismissal remains available inside AppKit menu tracking. A second right-button press cancels the active menu and consumes its following release to avoid reopening it. Outside left clicks cancel tracking; left clicks in native popup-menu windows retain normal item selection.


### Concurrent display activities

`IslandCoordinator` owns one `IslandController` per display/position. `ActivityRouting` chooses primary and below-card slots. Compact persistent activities yield only on the same display; expanded cards never yield. A colliding temporary activity uses a floating pill 14 points below the card. Temporary display targets are captured when the event arrives, so later timer updates do not follow the pointer.

Each slot retains its renderer and presentation. Removing a slot runs its normal exit before releasing the panel after 750 ms. Promoting a lower pill reuses its window and animates its origin for 320 ms through WindowServer; it keeps a pill shape until that temporary event ends. Subsequent events restore the display's normal geometry. One expiry timer serves temporary activity across all displays. Only Clock and expanded cards install hover monitors. No extra idle polling accompanies additional panels.

While Clock is foreground, its cached timer/Start controls are sampled every 250 ms because the preference mirror can arrive several seconds late. Background countdowns retain the deadline-aligned one-second cached tick; paused/idle background timers do not poll. This foreground change has not received a separate CPU measurement.

Ordinary compact shell and content visibility share the expansion flag. Only a newly mounted compact view returning from an expanded card delays its own content entrance by 60 ms, while retaining the flattened shell. This local view state uses the normal content spring, scale, offset and opacity and cannot hold other activities hidden. Timer cards leave about nine points below their buttons, and AirDrop cards leave eight.

During a card-to-compact return, `compactReturn` mounts the new icon/value content inside the existing expanded shell while it flattens. The shell-only view transition completes after 400 ms, retaining the now-visible compact content pose instead of starting a second entrance. Expanded outlines remain through flattening, then fade during horizontal retraction.

`TimerFinishHandoff` schedules one event 450 ms into the final displayed second. It expires an older temporary activity so the running timer returns before the finished card expands. A newly received finished alert also preempts an older temporary activity if the final-second update was missed. New temporary alerts after the card has opened still appear alongside it. Pausing, cancelling, restarting, or stopping the app invalidates the pending handoff.

Expanded-shell opacity uses scoped SwiftUI animation closures. Applying a value-triggered fade directly after a Shape can replace its path animation and remove the spring overshoot. Keep shell/rim opacity animation scoped to opacity; the geometry uses its 0.46/0.60 spring. The black camera backing stays opaque throughout opening and fades only during closing.

Clock window-creation events, existing Clock action updates, and the short expected-finish window use immediate coalesced AX reads. Ordinary native-activity events retain the 80 ms debounce. The expected-finish hint changes event priority only; it does not poll Notification Center.

Expanded cards now interpolate their fill and rim in one `ExpandedShellSurface`.
Both paths use the same sampled bounds and corner radius; their independent
opacity fades remain scoped to opacity. The notch attachment mask has a fixed
fade band based on the compact shell height, rather than stretching over the
expanded card. Mask overscan preserves the rim during spring overshoot.

Expanded action rows use `ExpandedActionsEntrance`: a centered uniform scale
from 0.84 with a ten-point downward settlement, a 0.46/0.64 spring delayed
35 ms, and a separate opacity fade. Clock and AirDrop share it. The header no
longer scales with the buttons. The shared shell interpolator clips content
against its current path, so controls remain inside the growing black shape.
No timers or persistent animation loops were added.

NativeSystemBanner also watches the exact `focus-system-banner` and `volume-system-banner` identifiers when their corresponding state sources are available. CoreAudio property listeners detect stem-driven volume changes without polling. All three AX observers share a sleeping run-loop thread, independent of SwiftUI rendering. Known hidden windows are refreshed before scanning the application window list. AX timeouts, missing snapshots, and inconclusive content reads retain the last confirmed state; only explicit actionable content, identifier reuse, feature disablement, or shutdown restores a live window. Destruction removes tracking without moving the closed window. No display coordinate determines eligibility.

Settings previews use DisplayPreviewScene: a fixed-height cropped display with a seven-point bezel, matched inset corner radii, an original vector wallpaper, and a plain-black option. The actual IslandSurface renders the activity inside it. Background selection is a local UI preference; both native segmented controls keep explicit widths independent of slider transactions. No wallpaper capture, image decoding, or continuous preview timer is used.

Integrations groups permissions, connected devices, and current state. BluetoothMonitor publishes connected-device snapshots from its existing serial read queue at startup, on connection changes, on settings entry, or explicit refresh. AirPodsBattery supplies optional left/right/case readings while retaining the lower-earbud percentage used by the activity. Missing fields are omitted. Snapshot refreshes coalesce and never announce an activity. Disconnection removes a device immediately; in-flight snapshots are filtered against registered connections.


First-run setup owns a short-lived permission-check view; it rechecks on activation or explicit retry. Providers start after completion or deferral. Existing installations retain their launch preference. Settings sizing is owned by NSWindow across all pages, with NSHostingView minimum-size propagation retained. Width limits are 820 and 1640 points; minimum content height is 400.
