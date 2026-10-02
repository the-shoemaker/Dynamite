# AirDrop replay and icon audit

## Reproduced AirDrop failure

The observer deduplicated quarantine receipts by UUID plus Downloads path. Renaming a received file changed that key, so the next Finder event announced it again. A copied file retaining its quarantine UUID had the same problem. Restarting the observer cleared its deduplication history. The metadata timestamp was only compared with observer startup, so later filesystem events could still match a receipt from earlier in that activation.

The new filesystem harness reproduces a dismissed card reopening on rename with the original observer. Only directory injection and canonicalizing the temporary directory were added to that original source for the test. The fixed production pipeline passes the same scenario.

## Changes

- Track delivered files by receipt UUID and filesystem device/inode identity. A pathname change cannot create another receipt.
- Track consumed receipt UUIDs across observer stops and starts. A copied file or late file with an already-announced receipt can update the same open card, but cannot reopen a dismissed card or replace an unrelated newer transfer. New receipt UUIDs still announce normally, including reused filenames.
- Batch distinct files together even when they share a receipt UUID. Late files retain the open card's identity and append their actions.
- Recheck both file identity and quarantine UUID before publishing a batch. Deleted, replaced or retagged paths are not offered as received files. Pending renames use the final pathname.
- Resolve the watched directory's symlinks so FSEvents' canonical paths match it.
- Capture callbacks for each observer activation on the caller's thread. Retired callbacks retain their original activation checks instead of adopting a restarted session's callback.
- Stop the FSEvent stream during destruction, cancel pending batches/retries, clear downstream card state on stop, and make repeated dismissal silent.
- Clear native AirDrop filename matching and its retry generation when the feature is disabled or the notification adapter stops. Ignore receipts submitted while it is disabled.

The observer still reads metadata only, accepts `sharingd` receipts only, uses one utility queue and one pending publication, and retries missing metadata at most three times. No directory polling or idle timer was added. Consumed identifiers remain in memory for the observer's lifetime, proportional to received receipts/files. Clearing that history during an activation would permit old receipts to reappear.

## Icon repair

The previous ICNS contained seven PNG chunks, including PNG payloads in its small-icon entries, and omitted the separate Retina slots. Apple's icon extraction also interpreted its 64-pixel entry as a 48-pixel icon. The large preview could look correct while another icon consumer chose a different decoding path.

The icon is now rendered into an explicit 1024-pixel bitmap and compiled from all ten standard/Retina sizes with Apple's `iconutil`. The design is unchanged. Apple ImageIO successfully decodes every compiled representation. Pixel checks cover the black pill, peach background, indicator and transparent corners at each size. The previous asset fails the new representation-completeness check. This is a compatibility repair; the reported corruption has not been inspected on a second Mac.

Apple documents the supported iconset workflow in [Optimizing for High Resolution](https://developer.apple.com/library/archive/documentation/GraphicsAnimation/Conceptual/HighResolutionOSX/Optimizing/Optimizing.html).

## Verification

On the development Mac, macOS 27 beta and Apple silicon:

- All 84 Swift tests and six updater-configuration checks passed.
- The card lifecycle harness covers receipts, repeated dismissal, stop clearing downstream state, stale callbacks after restart, empty/multiple files, same-card continuation, and rejected dismissed/unrelated continuations.
- The filesystem harness drives the production FSEvents, quarantine parser and card monitor. Child-process writes preserve production's IgnoreSelf flag. It covers rename, copy, 100 metadata changes, restart, new receipts, shared-UUID batches, late files, dismissal, Safari/old/hidden/nested files, delayed quarantine, pending deletion/rename and stop.
- Existing microphone, output-audio and diagnostic lifecycle tests passed.
- The release app and freshly extracted archive pass deep, strict code-signature verification outside the sandbox. The icon passes decoding checks in both bundles.

The release is 0.1.3, build 5, with the existing bundle identifier, local signing identity, update public key and HTTPS feed. It retains the Apple Silicon and macOS 14 requirements and the existing unnotarized-beta distribution model. The archive and feed use the existing Sparkle signing account. Existing users who enabled automatic checks receive it through that feed.

Real sender-to-receiver AirDrop, visual inspection on another Mac and an upgrade on a second Mac remain untested. The filesystem tests establish replay handling without requiring a real sender; they do not establish Apple's incoming request/progress behavior.
