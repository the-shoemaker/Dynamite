#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
clock_menu_test_dir="$(mktemp -d)"
trap 'rm -rf "$clock_menu_test_dir"' EXIT
swiftc -module-cache-path .build/clang-cache -emit-library -emit-module -module-name IslandCore Sources/IslandCore/IntegrationState.swift Sources/IslandCore/ClockTimerRecord.swift Sources/IslandCore/ClockContinuity.swift -emit-module-path "$clock_menu_test_dir/IslandCore.swiftmodule" -o "$clock_menu_test_dir/libIslandCore.dylib"
swiftc -module-cache-path .build/clang-cache -I "$clock_menu_test_dir" -L "$clock_menu_test_dir" -lIslandCore -Xlinker -rpath -Xlinker "$clock_menu_test_dir" Sources/Dynamite/ClockTimerStore.swift Sources/Dynamite/ClockMonitor.swift scripts/verify-clock-menu.swift -o "$clock_menu_test_dir/verify-clock-menu"
"$clock_menu_test_dir/verify-clock-menu"
