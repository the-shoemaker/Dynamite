#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
settings_test_dir="$(mktemp -d)"
trap 'rm -rf "$settings_test_dir"' EXIT
swiftc -module-cache-path .build/clang-cache -emit-library -emit-module -module-name IslandCore Sources/IslandCore/*.swift -emit-module-path "$settings_test_dir/IslandCore.swiftmodule" -o "$settings_test_dir/libIslandCore.dylib"
swiftc -module-cache-path .build/clang-cache -I "$settings_test_dir" -L "$settings_test_dir" -lIslandCore -Xlinker -rpath -Xlinker "$settings_test_dir" Sources/Dynamite/SettingsStore.swift scripts/verify-settings-persistence.swift -o "$settings_test_dir/verify-settings"
"$settings_test_dir/verify-settings"
