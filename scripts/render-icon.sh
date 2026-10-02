#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
icon_build_dir="$(mktemp -d)"
trap 'rm -rf "$icon_build_dir"' EXIT
mkdir "$icon_build_dir/Dynamite.iconset"
swift -module-cache-path .build/clang-cache scripts/render-icon.swift "$icon_build_dir/master.png"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$icon_build_dir/master.png" --out "$icon_build_dir/Dynamite.iconset/icon_${size}x${size}.png" >/dev/null
    retina_size=$((size * 2))
    sips -z "$retina_size" "$retina_size" "$icon_build_dir/master.png" --out "$icon_build_dir/Dynamite.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
# Apple's compiler supplies valid small-icon encodings and separate Retina slots.
# Hand-written PNG chunks in the small ICNS slots can decode as corrupted pixels.
iconutil -c icns "$icon_build_dir/Dynamite.iconset" -o Resources/Dynamite.icns
print 'Rebuilt Resources/Dynamite.icns with all ten standard/Retina sizes.'
