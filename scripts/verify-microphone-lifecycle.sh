#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
microphone_test_dir="$(mktemp -d)"
trap 'rm -rf "$microphone_test_dir"' EXIT
swiftc -module-cache-path .build/clang-cache -emit-library -emit-module -module-name IslandCore Sources/IslandCore/*.swift -o "$microphone_test_dir/libIslandCore.dylib" -emit-module-path "$microphone_test_dir/IslandCore.swiftmodule"
swiftc -module-cache-path .build/clang-cache -parse-as-library -I "$microphone_test_dir" -L "$microphone_test_dir" -lIslandCore -Xlinker -rpath -Xlinker "$microphone_test_dir" Sources/Dynamite/MicrophoneAudioAccess.swift Sources/Dynamite/MicrophoneMonitor.swift scripts/verify-microphone-lifecycle.swift -o "$microphone_test_dir/verify-microphone"
"$microphone_test_dir/verify-microphone" "$@"
