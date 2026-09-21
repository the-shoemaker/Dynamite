# Platform support

Inspected on macOS 27 with the installed Swift 6.4 Command Line Tools. The package targets macOS 14 or later. Runtime behavior on older supported macOS releases still needs hardware verification.

## API boundaries

- **Media keys.** A filtering CGEvent tap needs Accessibility authorization. Dynamite listens to system-defined events, performs its own successful hardware adjustment, and consumes that event. It does not kill `OSDUIHelper`, change notification settings, or suppress unrelated indicators. [Apple event tap documentation](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)).
- **Volume.** Core Audio default output, virtual main volume, hardware main volume, then stereo channel controls, plus output mute. Fixed-volume outputs use the native fallback.
- **Brightness.** `DisplayServicesGetBrightness` and `DisplayServicesSetBrightness` are private APIs loaded at runtime. Missing symbols or failing calls cause native fallback. This is a deliberate compatibility boundary, not a promise of generic external-monitor support. [A current independent implementation using the same framework](https://github.com/domus-apps/transom).
- **Battery.** `IOPSNotificationCreateRunLoopSource` delivers power-source changes without polling. Only internal-battery snapshots are considered. No internal battery means no battery alerts. [Apple power notification documentation](https://developer.apple.com/documentation/iokit/1523868-iopsnotificationcreaterunloopsou).
- **Screen capture.** Apple describes the `.none` window sharing constant as legacy and no longer used. Idle windows are removed; active overlays are not guaranteed to be excluded from capture. [Apple NSWindow.SharingType documentation](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum).
- **Clock.** A public source adapter was also inspected: it mirrors `mobiletimerd` preferences on a one-second polling loop and explicitly has no timer controls. It is not a complete replacement. The inspected `/System/Applications/Clock.app` contains no `.sdef` scripting dictionary. Its private navigation URL schemes do not provide a supported timer state/control API. AlarmKit documentation describes creating an app's own alarms on iOS/iPadOS; it is not a bridge into macOS Clock. [AlarmKit overview](https://developer.apple.com/documentation/alarmkit), [Apple's WWDC session](https://developer.apple.com/videos/play/wwdc2025/230/).
- **Focus.** Focus-status sharing is not a complete source of named Focus modes and their native UI. The installed macOS SDK exposes `INFocusStatusCenter`, but shared focus status does not supply named modes or a mechanism for replacing the system UI. [Apple Focus status API](https://developer.apple.com/documentation/intents/infocusstatuscenter).
- **Current adapters.** Clock now watches the timer service’s readable MTTimers preferences mirror for actual running deadlines and paused intervals. It continues with Clock’s window closed; bounded Accessibility requests remain for controls and as a fallback if that private mirror changes format. English Pause/Resume labels are currently required for controls. Focus reads only `~/Library/DoNotDisturb/DB/Assertions.json` after the user grants Full Disk Access to Dynamite. AirPods uses guarded device battery getters, with no inferred percentages. Recognized passive Focus banners are hidden when the replacement is available. Clock retains native action targets, and AirPods can hide the identified passive MenuBarAgent connection window; a brief first frame may precede the AX event. AirDrop uses completed Downloads receipts only; the unverified incoming observer has been removed.

## Low-battery policy

The requested native replacement cannot be guaranteed for macOS critical-battery alerts. Dynamite's separate low-battery reminder is therefore off by default, with the limitation stated next to its switch, in expanded settings, in Activities. Enabling it opts into an additional custom threshold reminder. It never disables macOS's power warning.

## Startup and window controls

Login registration uses `SMAppService.mainApp.register()` / `unregister()`. The UI reflects `.enabled` and `.requiresApproval` and displays registration errors. Hiding the menu bar removes the `NSStatusItem` without stopping providers. Reopening uses `applicationShouldHandleReopen` to show settings. The settings window uses `.floating` while Keep settings on top is enabled.

## Direct integration probes, September 20

The installed macOS 27 frameworks were loaded into a temporary, ordinary process for read-only capability checks. These probes are not part of the running app.

- `MTTimerManager.timersSync` returned nil. `mobiletimerd` logged that the process connection to `com.apple.MobileTimer.timerserver` was not entitled.
- `DNDStateService.queryCurrentStateWithError:` returned an XPC error. `donotdisturbd` logged that the connection had no valid entitlements and would be rejected.
- `SFAirDropTransferObserver` exists. On this machine it selects `_SFAirDropTransferObserver` and service `com.apple.sharing.transfer-observer`. Its remote protocol exposes `transfer:actionTriggeredForAction:`. Constructing a proxy is not proof that a transfer can be received or accepted. No incoming transfer, action forwarding, or native prompt suppression was verified.

These direct-service failures led to the separate Accessibility and file-observation adapters described above. They do not establish that every possible private or accessibility-based approach is impossible. A production integration still needs a working source, actions, replacement of native feedback, failure handling, and end-to-end hardware verification.

## Distribution and compatibility

See [sharing readiness](sharing-readiness.md) for the current permission flow, architecture limits, signing requirements, and unverified second-machine checks. Accessibility and Developer ID do not grant Apple’s restricted service entitlements.

Caps Lock uses local and global modifier-change notifications plus one state read on launch, refresh, and wake. Global notifications need Accessibility. It never reads typed text or polls, and it does not suppress macOS's inline text-field Caps Lock indicator.

## Hotspot probe and accepted scope

CoreWLAN's current scan result identified Personal Hotspot correctly before and after the user's connection. Its last tether device reported battery 50. A bounded, separate Sharing-framework discovery probe matched the connected device and also reported 50. The user confirmed the phone actually showed 37%. No battery reading is therefore exposed in Dynamite. The user explicitly chose a connection-only indicator.

The shipped provider uses [CoreWLAN Wi-Fi notifications](https://developer.apple.com/documentation/CoreWLAN) and a guarded read of the private current Personal Hotspot flag. It does not run Sharing discovery or scan for devices. It does not require Location access because it never reads network names. An unsupported private API results in an unavailable status. Other macOS versions and non-Apple hotspot devices still require verification.

## MonitorControl and external brightness

The Apple Silicon DDC adapter identifies each physical monitor by its exact registry location. It never guesses between identical monitor names. It uses DisplayServices where available, then DDC for supported external monitors. Key handling stays in Dynamite after a successful write, so MonitorControl's brightness HUD is not invoked. Unsupported writes retain the existing system/app handling.

For an exact MonitorControl display profile, Dynamite reads its saved brightness, maximum, combined-range split and blackout preference. Some monitors return empty DDC read replies; the saved target is the baseline in that case, just as it is in MonitorControl. Custom remapping, inverted curves, forced software control and unsupported ranges are left to MonitorControl. This is brightness-key compatibility, not full replacement of MonitorControl's settings or every DDC option.

The configured lower slider range uses a noninteractive black overlay, including full black only when MonitorControl's `allowZeroSwBrightness` is enabled. The upper range changes the hardware backlight. Smooth brightness applies to both; external writes are rate-limited and duplicate hardware values are skipped. The adapter does not write gamma tables, scan in the background, or poll idle monitors. Shades are released on pause, disable, sleep, display reconfiguration and quit. MonitorControl's saved brightness value is updated when a change settles.

References: [MonitorControl display model](https://github.com/MonitorControl/MonitorControl/blob/main/MonitorControl/Model/Display.swift), [DDC implementation](https://github.com/MonitorControl/MonitorControl/blob/main/MonitorControl/Support/Arm64DDC.swift).
