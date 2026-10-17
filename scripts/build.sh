#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
install_app=true
if [[ "${1:-}" == --no-install && $# == 1 ]]; then
    install_app=false
elif (( $# != 0 )); then
    print -u2 'Usage: build.sh [--no-install]'
    exit 2
fi
# Keep ordinary local builds on the current version without enabling release feeds.
read -r configured_version configured_build <<<"$(
    source scripts/release-config.sh
    print -r -- "$DYNOMITE_VERSION $DYNOMITE_BUILD_NUMBER"
)"
export DYNOMITE_VERSION="${DYNOMITE_VERSION:-$configured_version}"
export DYNOMITE_BUILD_NUMBER="${DYNOMITE_BUILD_NUMBER:-$configured_build}"
export CLANG_MODULE_CACHE_PATH="${PWD}/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
# Share SDK modules with tests and the standalone verification scripts.
build_flags=(--build-system native -c release --disable-sandbox
    --cache-path .build/package-cache --disable-dependency-cache --disable-index-store
    -Xswiftc -module-cache-path -Xswiftc "$CLANG_MODULE_CACHE_PATH")
swift build "${build_flags[@]}"
app="${PWD}/build/Dynamite.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
bin_dir="$(swift build "${build_flags[@]}" --show-bin-path)"
cp "$bin_dir/Dynamite" "$app/Contents/MacOS/Dynamite.new"
# Remove linked debug records and local symbols from the packaged executable.
# Preserve the original SwiftPM executable for local debugging; sign afterwards.
strip -Sx "$app/Contents/MacOS/Dynamite.new"
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
if $install_app; then
    installed_app='/Applications/Dynamite.app'
    # Stage a complete signed bundle so a failed copy leaves the installed app intact.
    install_stage="$(mktemp -d /Applications/.Dynamite-install.XXXXXX)"
    cleanup_install() {
        local result=$?
        if [[ ! -e "$installed_app" && ! -L "$installed_app" &&
              ( -e "$install_stage/previous.app" || -L "$install_stage/previous.app" ) ]]; then
            mv "$install_stage/previous.app" "$installed_app"
        fi
        rm -rf "$install_stage"
        return $result
    }
    trap cleanup_install EXIT
    ditto "$app" "$install_stage/Dynamite.app"
    codesign --verify --deep --strict "$install_stage/Dynamite.app"
    if [[ -e "$installed_app" || -L "$installed_app" ]]; then
        mv "$installed_app" "$install_stage/previous.app"
    fi
    mv "$install_stage/Dynamite.app" "$installed_app"
    print "Installed $installed_app"
fi
