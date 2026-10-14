#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
# Keep downloaded dependencies and the packaged app; discard rebuildable outputs.
swift package --disable-sandbox --cache-path .build/package-cache clean
print 'Removed compiler caches and build intermediates. Kept dependencies and build/Dynamite.app.'
