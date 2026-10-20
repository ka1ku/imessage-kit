#!/bin/sh
# Installs (or with --remove, removes) a LaunchAgent that reopens Messages.app,
# hidden and with the helper loaded, within seconds of it quitting.
set -eu
cd "$(dirname "$0")"
LABEL=com.github.imessage-kit.helper
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST"
[ "${1:-}" = "--remove" ] && { echo "removed $LABEL"; exit 0; }
[ -f build/IMKitHelper.dylib ] || ./build.sh
DYLIB="$(pwd)/build/IMKitHelper.dylib"
PORT="${IMKIT_HELPER_PORT:-45677}"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string><string>-c</string>
    <string>pgrep -x Messages >/dev/null || open -j -g -a Messages --env DYLD_INSERT_LIBRARIES="$DYLIB" --env IMKIT_HELPER_PORT=$PORT</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>5</integer>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "installed $LABEL: Messages reopens with the helper whenever it quits (remove: $0 --remove)"
