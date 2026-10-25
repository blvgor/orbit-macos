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
ORBIT_RUN="$(mktemp -d "$ORBIT_ROOT/.build/checks.XXXXXX")"
xcrun swiftc -swift-version 6 -O -target arm64-apple-macosx14.0 \
  -module-cache-path "$ORBIT_ROOT/.build/module-cache" \
  Sources/Processing.swift Tests/CoreChecks.swift -o "$ORBIT_RUN/CoreChecks" \
  -framework ImageIO -framework CoreGraphics
"$ORBIT_RUN/CoreChecks" "$ORBIT_RUN/fixtures" "$ORBIT_APP/Contents/Frameworks/libwebp.7.dylib"
for ORBIT_CHECK in HotKeyChecks ResponseTimeChecks; do
  xcrun swiftc -swift-version 6 -target arm64-apple-macosx14.0 \
    -module-cache-path "$ORBIT_ROOT/.build/module-cache" \
    Sources/Processing.swift Sources/WheelGeometry.swift Sources/WheelView.swift \
    Sources/RegisteredHotKey.swift Sources/Application.swift "Tests/$ORBIT_CHECK.swift" \
    -o "$ORBIT_RUN/$ORBIT_CHECK" -framework AppKit -framework ImageIO \
    -framework CoreGraphics -framework ApplicationServices -framework ServiceManagement -framework Carbon
  if [[ "$ORBIT_CHECK" == HotKeyChecks ]]; then
    "$ORBIT_RUN/$ORBIT_CHECK" "$ORBIT_RUN/hotkey-checks.json"
  else
    "$ORBIT_RUN/$ORBIT_CHECK" "$ORBIT_RUN/response"
  fi
done
"$ORBIT_APP/Contents/MacOS/Orbit" --render "$ORBIT_RUN/native"
/usr/bin/plutil -lint Info.plist entitlements.plist
codesign --verify --deep --strict "$ORBIT_APP"
print -r -- "Reports: $ORBIT_RUN"
