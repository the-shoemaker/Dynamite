#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="${PWD}/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${PWD}/.build/swift-cache"
# Some Command Line Tools releases omit the Testing macro search path.
swift_compiler="$(xcrun --find swiftc)"
testing_plugin="${swift_compiler:h:h}/lib/swift/host/plugins/testing/libTestingMacros.dylib"
extra_flags=()
if [[ -f "$testing_plugin" ]]; then
    extra_flags=(-Xswiftc -load-plugin-library -Xswiftc "$testing_plugin")
fi
swift test "${extra_flags[@]}" --disable-xctest --disable-sandbox --cache-path .build/package-cache
python3 scripts/test-update-config.py

./scripts/verify-airdrop-lifecycle.sh
