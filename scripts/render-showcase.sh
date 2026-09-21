#!/bin/zsh
# Compile the real views with inert sample providers, outside the application.
set -euo pipefail
cd "${0:A:h:h}"
render_dir="$(mktemp -d /tmp/dynamite-showcase.XXXXXX)"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
swiftc -emit-library -emit-module -module-name IslandCore Sources/IslandCore/*.swift -o "$render_dir/libIslandCore.dylib" -emit-module-path "$render_dir/IslandCore.swiftmodule"
swiftc -parse-as-library -I "$render_dir" -L "$render_dir" -lIslandCore -Xlinker -rpath -Xlinker "$render_dir" \
    Sources/Dynamite/IslandView.swift Sources/Dynamite/IslandCloseButton.swift \
    Sources/Dynamite/DisplayPreviewScene.swift Sources/Dynamite/ExpandedIslandShell.swift \
    Sources/Dynamite/ClockAlertView.swift Sources/Dynamite/AirDropExpandedView.swift \
    Sources/Dynamite/IslandActionButton.swift scripts/showcase/*.swift -o "$render_dir/render"
"$render_dir/render" "$PWD/docs/images"
