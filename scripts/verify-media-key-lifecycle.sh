#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
media_key_test_dir="$(mktemp -d)"
trap 'rm -rf "$media_key_test_dir"' EXIT
swiftc -module-cache-path .build/clang-cache -emit-library -emit-module -module-name IslandCore Sources/IslandCore/*.swift -emit-module-path "$media_key_test_dir/IslandCore.swiftmodule" -o "$media_key_test_dir/libIslandCore.dylib"
swiftc -module-cache-path .build/clang-cache -I "$media_key_test_dir" -L "$media_key_test_dir" -lIslandCore -Xlinker -rpath -Xlinker "$media_key_test_dir" Sources/Dynamite/MediaKeyEventDecoder.swift Sources/Dynamite/MediaKeyMonitor.swift scripts/verify-media-key-lifecycle.swift -o "$media_key_test_dir/verify-media-key-lifecycle"
"$media_key_test_dir/verify-media-key-lifecycle"
