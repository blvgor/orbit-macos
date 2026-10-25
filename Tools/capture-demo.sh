#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
ORBIT_ROOT="$PWD"
ORBIT_APP="$ORBIT_ROOT/dist/Orbit.app"
if [[ ! -x "$ORBIT_APP/Contents/MacOS/Orbit" ]]; then
  print -u2 'Build first: zsh build.sh'
  exit 1
fi
mkdir -p .build/module-cache
ORBIT_DEMO="$(mktemp -d "$ORBIT_ROOT/.build/demo.XXXXXX")"
xcrun swiftc -swift-version 6 -target arm64-apple-macosx14.0 \
  -module-cache-path "$ORBIT_ROOT/.build/module-cache" \
  Sources/Processing.swift Sources/WheelView.swift Sources/WheelGeometry.swift \
  Sources/Application.swift Sources/RegisteredHotKey.swift \
  Tools/DemoCapture.swift -o "$ORBIT_DEMO/DemoCapture" \
  -framework AppKit -framework ImageIO -framework CoreGraphics \
  -framework ServiceManagement -framework ApplicationServices -framework Carbon
"$ORBIT_DEMO/DemoCapture" "$ORBIT_DEMO/capture" "$ORBIT_APP/Contents/Frameworks/libwebp.7.dylib"
print -r -- "Demo captures: $ORBIT_DEMO/capture"
