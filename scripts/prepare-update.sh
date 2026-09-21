#!/bin/zsh
# Works with any app using MacAppUpdates/Sparkle. Creates local artifacts only.
set -euo pipefail
allow_unnotarized=false
if [[ "${1:-}" == --unnotarized-beta ]]; then
    allow_unnotarized=true
    shift
fi
if (( $# != 3 )); then
    print -u2 'Usage: prepare-update.sh [--unnotarized-beta] /path/App.app /path/release-directory https://host/downloads/'
    exit 2
fi
release_app="${1:A}"
release_dir="${2:A}"
download_prefix="$3"
repo_dir="${0:A:h:h}"
[[ -d "$release_app/Contents" ]] || { print -u2 'App bundle not found'; exit 2; }
[[ "$download_prefix" == https://* ]] || { print -u2 'Use an HTTPS download prefix'; exit 2; }
/usr/bin/codesign --verify --deep --strict "$release_app"
# Stable distribution requires Gatekeeper acceptance. Betas must opt in explicitly.
if $allow_unnotarized; then
    print -u2 'Unnotarized beta: recipients may need the app-specific Open Anyway exception.'
else
    /usr/sbin/spctl --assess --type execute "$release_app"
fi
release_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$release_app/Contents/Info.plist")
/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$release_app/Contents/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$release_app/Contents/Info.plist" >/dev/null
archive="$release_dir/${release_app:t:r}-$release_build.zip"
[[ ! -e "$archive" ]] || { print -u2 'This build already has a release archive'; exit 2; }
mkdir -p "$release_dir"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$release_app" "$archive"
"$repo_dir/.build/artifacts/sparkle/Sparkle/bin/generate_appcast" --account dynamite-updates --maximum-deltas 0 --download-url-prefix "$download_prefix" "$release_dir"
print "Prepared signed appcast and archive in $release_dir. Nothing has been uploaded."
