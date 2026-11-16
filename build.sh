#!/bin/bash
# Compila "Study Timer.app" in ./build. Con --install la copia anche in /Applications e la avvia.
set -euo pipefail
cd "$(dirname "$0")"
APP="build/Study Timer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -o "$APP/Contents/MacOS/StudyTimer" Sources/*.swift \
  -framework Cocoa -framework WebKit -framework Carbon -framework ServiceManagement
cp Info.plist "$APP/Contents/"
cp Resources/timer.html Resources/widget.html Resources/grid.html Resources/ring.html "$APP/Contents/Resources/"
if [ ! -f build/AppIcon.icns ]; then
  swiftc -o build/icon tools/icon.swift
  build/icon build/AppIcon
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP" >/dev/null
echo "OK → $APP"

if [ "${1:-}" = "--install" ]; then
  pkill -x StudyTimer 2>/dev/null || true; sleep 0.5
  DEST="/Applications"; [ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }
  rm -rf "$DEST/Study Timer.app"
  cp -R "$APP" "$DEST/"
  open "$DEST/Study Timer.app"
  echo "Installata in $DEST e avviata"
fi
