#!/usr/bin/env bash
# Runs the FileAppCore tests. Works with just the Command Line Tools: the app target is left out
# (CORE_ONLY=1) and the Swift Testing macro plugin is passed explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."
PLUGINS="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
# A core-only build rewrites Package.resolved without Sparkle; keep the real one.
cp Package.resolved .build/Package.resolved.keep 2>/dev/null || true
trap '[[ -f .build/Package.resolved.keep ]] && mv .build/Package.resolved.keep Package.resolved' EXIT
CORE_ONLY=1 swift test --scratch-path .build/core -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
