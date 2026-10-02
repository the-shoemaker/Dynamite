#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift -module-cache-path .build/clang-cache scripts/verify-icon.swift "${1:-Resources/Dynamite.icns}"
