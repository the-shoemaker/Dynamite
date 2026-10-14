#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
internet_test_dir="$(mktemp -d)"
trap 'rm -rf "$internet_test_dir"' EXIT
swiftc -module-cache-path .build/clang-cache -emit-library -emit-module -module-name IslandCore Sources/IslandCore/*.swift -emit-module-path "$internet_test_dir/IslandCore.swiftmodule" -o "$internet_test_dir/libIslandCore.dylib"
swiftc -module-cache-path .build/clang-cache -I "$internet_test_dir" -L "$internet_test_dir" -lIslandCore -Xlinker -rpath -Xlinker "$internet_test_dir" Sources/Dynamite/InternetMonitor.swift scripts/verify-internet-lifecycle.swift -o "$internet_test_dir/verify-internet"
"$internet_test_dir/verify-internet"
