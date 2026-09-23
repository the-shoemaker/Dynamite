#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
output_test_dir="$(mktemp -d)"
trap 'rm -rf "$output_test_dir"' EXIT
swiftc -module-cache-path .build/clang-cache -emit-library -emit-module -module-name IslandCore Sources/IslandCore/*.swift -o "$output_test_dir/libIslandCore.dylib" -emit-module-path "$output_test_dir/IslandCore.swiftmodule"
swiftc -module-cache-path .build/clang-cache -parse-as-library -I "$output_test_dir" -L "$output_test_dir" -lIslandCore -Xlinker -rpath -Xlinker "$output_test_dir" Sources/Dynamite/OutputAudioAccess.swift Sources/Dynamite/AudioController.swift scripts/verify-output-lifecycle.swift -o "$output_test_dir/verify-output"
"$output_test_dir/verify-output" "$@"
