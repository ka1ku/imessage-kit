#!/bin/sh
# Restarts Messages.app with the helper loaded. IMKIT_HELPER_PORT must match the SDK's `privateApi.port`.
set -eu
cd "$(dirname "$0")"
[ -f build/IMKitHelper.dylib ] || ./build.sh
osascript -e 'quit app "Messages"' >/dev/null 2>&1 || true
while pgrep -x Messages >/dev/null; do sleep 0.2; done
open -a Messages --env DYLD_INSERT_LIBRARIES="$(pwd)/build/IMKitHelper.dylib" --env IMKIT_HELPER_PORT="${IMKIT_HELPER_PORT:-45677}"
echo "Messages relaunched with the helper; check: log show --last 1m --predicate 'eventMessage CONTAINS \"imessage-kit helper\"'"
