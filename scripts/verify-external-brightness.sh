#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
external_test_dir="$(mktemp -d)"
trap 'rm -rf "$external_test_dir"' EXIT
swiftc -module-cache-path .build/clang-cache -emit-library -emit-module -module-name IslandCore Sources/IslandCore/ExternalBrightnessScale.swift -emit-module-path "$external_test_dir/IslandCore.swiftmodule" -o "$external_test_dir/libIslandCore.dylib"
# Compile the fixture extension in the controller's file so private I2C state
# can be replaced without exposing testing hooks in the shipped app.
cat Sources/Dynamite/ExternalBrightnessController.swift scripts/verify-external-brightness.swift > "$external_test_dir/ControllerVerification.swift"
swiftc -parse-as-library -module-cache-path .build/clang-cache -I "$external_test_dir" -L "$external_test_dir" -lIslandCore -Xlinker -rpath -Xlinker "$external_test_dir" "$external_test_dir/ControllerVerification.swift" -o "$external_test_dir/verify-external"
"$external_test_dir/verify-external"
