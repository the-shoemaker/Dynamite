# Releases

The public beta lives at https://github.com/the-shoemaker/Dynamite/releases. It is locally signed, not Developer ID signed or notarized. Recipients may need Apple's app-specific Open Anyway exception. A paid Apple Developer Program membership is needed for the conventional Developer ID and notarization route, not for granting Accessibility or the other privacy permissions.

## Build a beta

The public feed URL, verification key and versions live in `scripts/release-config.sh`. Increase `DYNOMITE_BUILD_NUMBER` for every update. Keep the bundle identifier stable. Update the marketing version separately.

```sh
source scripts/release-config.sh
./scripts/test.sh
./scripts/build.sh --no-install
./scripts/prepare-update.sh --unnotarized-beta build/Dynamite.app releases/0.1.5-beta.1-build8/ https://github.com/the-shoemaker/Dynamite/releases/download/v0.1.5-beta.1/
```

The packaging script verifies the app's code signature, preserves framework symlinks with `ditto`, and signs the archive and appcast using Sparkle's `dynamite-updates` Keychain account. It does not upload anything. Without `--unnotarized-beta`, it also requires Gatekeeper acceptance.

When changing the icon, run `scripts/render-icon.sh` and commit the generated `Resources/Dynamite.icns`. This renders explicit pixels, creates all ten standard/Retina PNGs and compiles them with Apple's `iconutil`. Do not construct ICNS chunks by hand. `scripts/verify-icon.sh` decodes every representation and checks the pill, background, indicator and transparent corners; the full test suite runs it too. These tools may need to run outside a restricted sandbox on macOS.

Create the matching GitHub prerelease and upload the archive plus a SHA-256 checksum file. Verify the public download before copying the generated `appcast.xml` to the repository root. Add `<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>` to the item for Apple Silicon-only releases and re-sign the feed after any edit. The raw `main` branch appcast is the stable feed URL. Do not rename or replace an archive after signing it.

## Signing keys

The Ed25519 private update key stays in the maintainer's Keychain under account `dynamite-updates`. Only the public key belongs in source control. Keep a secure backup outside the repository. Do not paste a private key into a command line, issue, build log or chat.

Apple app signing and Sparkle update signing serve different purposes. The local app-signing keychain used by `scripts/build.sh` also stays outside the repository. Preserve that identity across beta updates where possible; changes can disrupt privacy grants. Do not send signing credentials to testers.

The first public beta is the starting point for future updates. Before shipping a later update, test the actual upgrade from this beta, including cancellation, relaunch, permission retention and login startup. A successful archive-signature check does not prove the entire updater flow works on another Mac.

## Verification checklist

- Run all automated checks and verify the final app with `codesign --verify --deep --strict`.
- Extract the ZIP to a fresh directory and verify that copy too.
- Verify the archive signature with Sparkle's `sign_update --account dynamite-updates --verify` and the enclosure signature.
- Check feed version, HTTPS download URL, archive length, minimum OS and architecture.
- Check the bundle and publishable source for private paths, device names, diagnostics and credentials.
- Download the hosted archive and compare its SHA-256 to the original.
- Test first launch on a separate Mac with Gatekeeper enabled and a fresh user's permissions. Document what has and has not been tested.

For a notarized release, sign with Developer ID Application and the required hardened-runtime configuration, submit with `notarytool`, staple the accepted ticket, and assess with Gatekeeper before archiving. Revalidate private integrations under that configuration.

References: [Sparkle publishing](https://sparkle-project.org/documentation/publishing/), [Apple Developer ID](https://developer.apple.com/developer-id/), [Apple Open Anyway instructions](https://support.apple.com/102445).

## 0.1.5 build 8 verification

The 99 Swift tests, six updater configuration tests, native lifecycle checks, and settings persistence checks passed. The final signed app's routing check verified that Caps Lock replaces offline in the primary panel, offline returns after expiry, and a lower timer keeps its window. The isolated Clock mirror check verified that closed Clock controls produce no timer menu actions and menu actions do not reopen Clock or edit its mirror.

The archive was extracted and its code signature verified. The designated app-signing requirement, update public key and feed URL match build 7. The archive and merged feed passed Sparkle signature verification. The updater implementation is unchanged from the actual cancellation, install and relaunch verification recorded for 0.1.4; that interactive upgrade was not repeated for this release. Fresh-Mac Gatekeeper testing remains outstanding for this unnotarized beta.
