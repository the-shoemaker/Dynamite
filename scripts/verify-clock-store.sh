#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
clock_test_dir="$(mktemp -d)"
trap 'rm -rf "$clock_test_dir"' EXIT
swiftc -module-cache-path .build/clang-cache -emit-library -emit-module -module-name IslandCore Sources/IslandCore/IntegrationState.swift Sources/IslandCore/ClockTimerRecord.swift -emit-module-path "$clock_test_dir/IslandCore.swiftmodule" -o "$clock_test_dir/libIslandCore.dylib"
swiftc -module-cache-path .build/clang-cache -I "$clock_test_dir" -L "$clock_test_dir" -lIslandCore -Xlinker -rpath -Xlinker "$clock_test_dir" Sources/Dynamite/ClockTimerStore.swift scripts/verify-clock-store.swift -o "$clock_test_dir/verify-clock-store"
"$clock_test_dir/verify-clock-store"
