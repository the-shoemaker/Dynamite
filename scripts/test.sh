#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="${PWD}/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
# Some Command Line Tools releases omit the Testing macro search path.
swift_compiler="$(xcrun --find swiftc)"
testing_plugin="${swift_compiler:h:h}/lib/swift/host/plugins/testing/libTestingMacros.dylib"
extra_flags=()
if [[ -f "$testing_plugin" ]]; then
    extra_flags=(-Xswiftc -load-plugin-library -Xswiftc "$testing_plugin")
fi
# Native SwiftPM can pass -I/-L for Testing even when CLT ships it as a framework.
testing_frameworks="${swift_compiler:h:h:h}/Library/Developer/Frameworks"
if [[ -d "$testing_frameworks/Testing.framework" ]]; then
    extra_flags+=(-Xswiftc -F -Xswiftc "$testing_frameworks"
        -Xlinker -rpath -Xlinker "$testing_frameworks")
fi
swift test --build-system native "${extra_flags[@]}" --disable-xctest --disable-sandbox \
    --cache-path .build/package-cache --disable-dependency-cache --disable-index-store \
    -Xswiftc -module-cache-path -Xswiftc "$CLANG_MODULE_CACHE_PATH"
python3 scripts/test-update-config.py
./scripts/verify-icon.sh

./scripts/verify-airdrop-lifecycle.sh
./scripts/verify-airdrop-filesystem.sh

./scripts/verify-microphone-lifecycle.sh

./scripts/verify-output-lifecycle.sh

./scripts/verify-diagnostic.sh
./scripts/verify-internet-lifecycle.sh
./scripts/verify-settings-persistence.sh
./scripts/verify-clock-menu.sh
