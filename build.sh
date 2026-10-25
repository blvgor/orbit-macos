#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
ORBIT_ROOT="$PWD"
if [[ "$(uname -m)" != arm64 ]]; then
  print -u2 'This build currently supports Apple Silicon Macs only.'
  exit 1
fi
if [[ -n "${ORBIT_WEBP_LIB_DIR:-}" ]]; then
  ORBIT_CODEC_DIR="$ORBIT_WEBP_LIB_DIR"
elif command -v brew >/dev/null 2>&1 && brew --prefix webp >/dev/null 2>&1; then
  ORBIT_CODEC_DIR="$(brew --prefix webp)/lib"
else
  print -u2 'libwebp is required. Run: brew install webp'
  print -u2 'Or set ORBIT_WEBP_LIB_DIR to a directory containing libwebp.7.dylib and libsharpyuv.0.dylib.'
  exit 1
fi
for ORBIT_CODEC in libwebp.7.dylib libsharpyuv.0.dylib; do
  if [[ ! -f "$ORBIT_CODEC_DIR/$ORBIT_CODEC" ]]; then
    print -u2 "Missing dependency: $ORBIT_CODEC_DIR/$ORBIT_CODEC"
    exit 1
  fi
  lipo -verify_arch arm64 "$ORBIT_CODEC_DIR/$ORBIT_CODEC"
done
mkdir -p .build/module-cache dist
ORBIT_STAGE="$(mktemp -d "$ORBIT_ROOT/.build/package.XXXXXX")"
ORBIT_APP="$ORBIT_STAGE/Orbit.app"
mkdir -p "$ORBIT_APP/Contents/"{MacOS,Frameworks,Resources}
cp Info.plist "$ORBIT_APP/Contents/Info.plist"
for ORBIT_CODEC in libwebp.7.dylib libsharpyuv.0.dylib; do
  cp -L "$ORBIT_CODEC_DIR/$ORBIT_CODEC" "$ORBIT_APP/Contents/Frameworks/$ORBIT_CODEC"
  chmod u+w "$ORBIT_APP/Contents/Frameworks/$ORBIT_CODEC"
  install_name_tool -id "@rpath/$ORBIT_CODEC" "$ORBIT_APP/Contents/Frameworks/$ORBIT_CODEC"
done
ORBIT_WEBP="$ORBIT_APP/Contents/Frameworks/libwebp.7.dylib"
ORBIT_SHARPYUV_REF="$(otool -L "$ORBIT_WEBP" | awk 'NR > 2 && /libsharpyuv/ {print $1}')"
if [[ -n "$ORBIT_SHARPYUV_REF" ]]; then
  install_name_tool -change "$ORBIT_SHARPYUV_REF" '@loader_path/libsharpyuv.0.dylib' "$ORBIT_WEBP"
fi
cp LICENSE THIRD_PARTY_NOTICES.md "$ORBIT_APP/Contents/Resources/"
mkdir -p "$ORBIT_APP/Contents/Resources/docs/licenses"
cp docs/licenses/libwebp-COPYING docs/licenses/libwebp-PATENTS "$ORBIT_APP/Contents/Resources/docs/licenses/"
xcrun swiftc -swift-version 6 -O -target arm64-apple-macosx14.0 \
  -module-cache-path "$ORBIT_ROOT/.build/module-cache" Sources/*.swift \
  -o "$ORBIT_APP/Contents/MacOS/Orbit" \
  -framework AppKit -framework ImageIO -framework CoreGraphics \
  -framework ServiceManagement -framework ApplicationServices -framework Carbon
codesign --force --sign - "$ORBIT_APP/Contents/Frameworks/libsharpyuv.0.dylib"
codesign --force --sign - "$ORBIT_WEBP"
codesign --force --sign - --entitlements entitlements.plist "$ORBIT_APP"
codesign --verify --deep --strict "$ORBIT_APP"
if [[ -e dist/Orbit.app ]]; then
  mv dist/Orbit.app "$ORBIT_STAGE/Orbit-previous.app"
fi
mv "$ORBIT_APP" dist/Orbit.app
print -r -- "$ORBIT_ROOT/dist/Orbit.app"
