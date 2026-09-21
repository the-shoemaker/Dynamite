#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="${PWD}/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${PWD}/.build/swift-cache"
swift build --build-system native -c release --disable-sandbox --cache-path .build/package-cache
app="${PWD}/build/Dynamite.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
bin_dir="$(swift build --build-system native -c release --show-bin-path --disable-sandbox --cache-path .build/package-cache)"
cp "$bin_dir/Dynamite" "$app/Contents/MacOS/Dynamite.new"
# Remove linked debug records containing developer-machine source paths.
# Preserve the original SwiftPM executable for local debugging; sign afterwards.
strip -S "$app/Contents/MacOS/Dynamite.new"
mv -f "$app/Contents/MacOS/Dynamite.new" "$app/Contents/MacOS/Dynamite"
cp Resources/Dynamite.icns "$app/Contents/Resources/Dynamite.icns"
cp Resources/Info.plist "$app/Contents/Info.plist"
mkdir -p "$app/Contents/Frameworks"
# Preserve Sparkle's framework symlinks, helpers, permissions, and vendor signatures.
ditto "$bin_dir/Sparkle.framework" "$app/Contents/Frameworks/Sparkle.framework"
cp .build/checkouts/Sparkle/LICENSE "$app/Contents/Resources/Sparkle-LICENSE.txt.new"
mv -f "$app/Contents/Resources/Sparkle-LICENSE.txt.new" "$app/Contents/Resources/Sparkle-LICENSE.txt"
python3 scripts/configure-updates.py "$app/Contents/Info.plist"
# Finder/launcher indexing can add these to the reused development bundle.
# Clear only signing-incompatible presentation metadata, not quarantine flags.
xattr -dr com.apple.FinderInfo "$app" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$app" 2>/dev/null || true
signing_dir="${HOME}/Library/Application Support/Dynomite/DevelopmentSigning"
if [[ -f "$signing_dir/identity.sha1" && -f "$signing_dir/signing.keychain-db" ]]; then
    signing_identity="$(cat "$signing_dir/identity.sha1")"
    signing_password="$(cat "$signing_dir/password")"
    security unlock-keychain -p "$signing_password" "$signing_dir/signing.keychain-db"
    codesign --force --sign "$signing_identity" --keychain "$signing_dir/signing.keychain-db" \
        --timestamp=none --identifier com.dan.dynomite \
        --requirements "=designated => identifier \"com.dan.dynomite\" and certificate leaf = H\"${signing_identity}\"" "$app"
else
    codesign --force --sign - --identifier com.dan.dynomite "$app"
    print 'Ad-hoc build: Accessibility may reset. Run scripts/setup-signing.sh once for a stable local identity.'
fi
print "Built $app"
