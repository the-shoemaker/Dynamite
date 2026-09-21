# Sharing readiness

Audited September 21, 2026. This is an early public beta. A fresh second-Mac installation has not yet been verified.

## What to send

Send the actual `build/Dynamite.app` bundle in a ZIP, not a launcher symlink, executable alone, build directory, or project folder. Preserve the embedded Sparkle framework and its symlinks. Recipients should unzip, move the app to Applications, and then launch and grant their own permissions. Downloads is not a required runtime location; use a stable location before granting permissions or registering login startup. Received AirDrop files are currently detected only in Downloads.

The present executable is **arm64 (Apple Silicon)**. It is not an Intel build. The package deployment minimum is macOS 14; only the development Mac running macOS 27 has been exercised. A deployment target is not proof of integration compatibility.

The existing signature is local development signing, not Developer ID, with no notarization ticket and no hardened-runtime release validation. Another Mac will not inherit local certificate trust or privacy grants. Gatekeeper can block a downloaded copy. Do not distribute the local signing keychain, password, certificate private key, or instructions to disable Gatekeeper. For normal public distribution, use Developer ID Application signing, hardened runtime, notarization, and stapling, then test the downloaded artifact on a separate Mac/account with Gatekeeper enabled. The beta uses an explicit unnotarized packaging mode and a separate Ed25519-signed Sparkle update feed. See the release instructions and README for the app-specific Open Anyway route.

Apple references: [Developer ID](https://developer.apple.com/developer-id/), [distribution signing](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac/), [packaging and separate-Mac testing](https://developer.apple.com/documentation/xcode/packaging-mac-software-for-distribution).

## Permissions and setup

First launch presents an assistant before starting integration providers. Accessibility enables keyboard replacement, Caps Lock, and UI controls. Full Disk Access is optional for Focus; the assistant explains that macOS grants broader access. Downloads access is optional for AirDrop receipts. Access is checked on entry, explicit retry, and returning from System Settings, with no ongoing polling. macOS owns the separate permission dialogs; the assistant cannot grant them itself. Bluetooth permission can also be requested by macOS when that integration starts.

Start is enabled with Accessibility; Set up later permits limited use. Optional access is not a universal readiness check: a readable Focus file, for example, does not prove every private integration works. Open at login is opt-in and uses the actual SMAppService status; pending system approval is shown. Existing installations retain settings and are not forced through setup. Reopen the assistant from Integrations. Closing the assistant leaves it available next launch.

## Portability boundaries

| Feature | Remaining boundary |
| --- | --- |
| Volume, microphone state, battery | Device must expose the relevant Core Audio/IOKit properties; fixed-volume outputs and Macs without batteries differ. |
| Brightness | Private DisplayServices; compatible Apple Silicon DDC monitors only for external hardware. MonitorControl profile matching is device-derived. Unsupported writes pass through. |
| Vivid | Optional installed-app preferences and output-curve estimate; not universal HDR control. |
| Clock | Private timer preference format plus Accessibility. Some controls match English labels. Other languages/OS revisions need validation. |
| Focus | Protected, undocumented state file; Full Disk Access and supported file format. Unknown modes use a generic icon/name. |
| AirPods | Guarded private getters and known Apple product IDs, not personal device names. New models/firmware may omit battery data; zero fields are ambiguous and omitted. |
| Native popup hiding | Exact macOS UI host/window identifiers. Conditional on readable, recognized passive UI; initial flashes can still occur. OS changes may retain native UI. Not guaranteed for all macOS 27 Macs. |
| AirDrop | Completed file receipts in Downloads only. Open/Show in Finder are supported; request acceptance and transfer progress remain native. The nonfunctional transfer observer was removed. |
| Wi-Fi/hotspot | CoreWLAN events with an optional private Apple hotspot read. Generic phone battery data and Android hotspot classification are not promised. |

A second-machine check must cover fresh permissions, launch from the downloaded artifact, login startup, sleep/wake, multiple displays, actual timer actions, an AirDrop receipt, and the recipient's AirPods. Those checks have not been performed here.

## Personal-data audit

Runtime source has no hardcoded user home path, personal Bluetooth device name/address, Wi-Fi SSID, account email, or credentials. Home and Downloads paths are resolved for the current user. The old `com.dan.dynomite` identifier remains intentionally: changing it would change app identity and disrupt existing settings/permissions. It is a public identifier, not a machine dependency.

Removed the real photo filename from test fixtures, replacing it with a generic name. Documentation now describes actual behavior instead of claiming an incoming AirDrop implementation. Local diagnostic and signing-file patterns are ignored by source control. Diagnostic reports and generated build directories should not be included in a source release; diagnostic commands can expose current device information when explicitly run. No signing material is bundled in the app. The linked executable initially contained developer paths in debug records. The build now strips those records before signing; the bundled executable is checked for remaining home paths. Original debug records stay in the ignored local build cache.

System paths, Apple product IDs, framework symbols, and third-party bundle identifiers are compatibility assumptions, not personal data. They cannot simply be replaced with arbitrary values; the limits above remain part of release readiness.
