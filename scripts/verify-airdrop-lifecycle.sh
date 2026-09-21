#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
airdrop_test_dir="$(mktemp -d)"
trap 'rm -rf "$airdrop_test_dir"' EXIT
swiftc -module-cache-path .build/clang-cache Sources/Dynamite/AirDropMonitor.swift scripts/verify-airdrop-lifecycle.swift -o "$airdrop_test_dir/verify-airdrop"
"$airdrop_test_dir/verify-airdrop"
