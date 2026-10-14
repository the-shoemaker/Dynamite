#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
internet_perf_dir="$(mktemp -d)"
trap 'rm -rf "$internet_perf_dir"' EXIT
swiftc -O -module-cache-path .build/clang-cache -emit-library -emit-module -module-name IslandCore Sources/IslandCore/*.swift -emit-module-path "$internet_perf_dir/IslandCore.swiftmodule" -o "$internet_perf_dir/libIslandCore.dylib"
swiftc -O -module-cache-path .build/clang-cache -I "$internet_perf_dir" -L "$internet_perf_dir" -lIslandCore -Xlinker -rpath -Xlinker "$internet_perf_dir" Sources/Dynamite/InternetMonitor.swift scripts/verify-internet-performance.swift -o "$internet_perf_dir/verify-internet-performance"
"$internet_perf_dir/verify-internet-performance"
