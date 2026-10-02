#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
receipt_test_dir="$(mktemp -d)"
trap 'rm -rf "$receipt_test_dir"' EXIT
swiftc -module-cache-path .build/clang-cache -emit-library -emit-module -module-name IslandCore Sources/IslandCore/AirDropReceipt.swift -o "$receipt_test_dir/libIslandCore.dylib" -emit-module-path "$receipt_test_dir/IslandCore.swiftmodule"
swiftc -module-cache-path .build/clang-cache -I "$receipt_test_dir" -L "$receipt_test_dir" -lIslandCore -Xlinker -rpath -Xlinker "$receipt_test_dir" Sources/Dynamite/AirDropReceiptMonitor.swift Sources/Dynamite/AirDropMonitor.swift scripts/verify-airdrop-filesystem.swift -o "$receipt_test_dir/verify-receipts"
"$receipt_test_dir/verify-receipts"
