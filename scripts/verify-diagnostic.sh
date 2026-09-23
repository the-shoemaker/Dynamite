#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
diagnostic_test_dir="$(mktemp -d)"
trap 'rm -rf "$diagnostic_test_dir"' EXIT
swiftc -module-cache-path .build/clang-cache -emit-library -emit-module -module-name IslandCore Sources/IslandCore/*.swift -o "$diagnostic_test_dir/libIslandCore.dylib" -emit-module-path "$diagnostic_test_dir/IslandCore.swiftmodule"
swiftc -module-cache-path .build/clang-cache -parse-as-library -I "$diagnostic_test_dir" -L "$diagnostic_test_dir" -lIslandCore -Xlinker -rpath -Xlinker "$diagnostic_test_dir" Sources/Dynamite/PerformanceDiagnostic.swift scripts/verify-diagnostic.swift -o "$diagnostic_test_dir/verify-diagnostic"
"$diagnostic_test_dir/verify-diagnostic" "$@"
