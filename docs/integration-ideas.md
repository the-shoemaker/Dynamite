# Ideas only

None of these suggestions has been implemented. Each needs an API and native-feedback check before development. Keep them opt-in, silent by default, and event-driven; no repeated reminders or idle animations.

| Candidate | Subtle behavior |
| --- | --- |
| Audio output changed | One brief headphone/speaker icon and the newly selected output name. Helpful when headphones disconnect or a dock takes over sound. |
| Microphone muted | A brief crossed-out mic on mute/unmute in a supported call app. Persistent muted state could return after temporary activities, like Caps Lock. |
| Keyboard layout changed | Brief “EN”, “DE”, etc. only when switching input languages. |
| Peripheral low battery | One alert when a keyboard, mouse, or trackpad crosses a chosen threshold; no recurring low-battery nag. |
| VPN disconnected unexpectedly | One quiet warning after an established connection drops; suppress intentional disconnects where the provider can distinguish them. |
| Drive safe to remove | A short confirmation after an eject operation succeeds. Do not imply that an active transfer has finished without a verified source. |
| Long download finished | One completion after a download that took longer than a chosen duration, through an explicit browser/download-manager adapter. |
| Long build or export finished | A small success/failure result from tools the user connects, only for jobs that exceeded a duration threshold. |
| External display connected | A brief display icon and resolution or refresh rate after the configuration settles, without repeating during every brightness change. |
| Keep-awake session | A short confirmation on starting/stopping a keep-awake session, with an optional quiet countdown if Dynamite owns the session. |

The strongest first candidates are audio output, keyboard layout, and safe-eject confirmation. They answer a specific state question and can disappear immediately afterward. The adapter-based ideas should accept bounded activity data, never arbitrary executable commands or updater configuration.
