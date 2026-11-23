#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export ARCH=${ARCH:-arm64}
export MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-13.0}
bash "$ROOT/scripts/build-libflac.sh"
PREFIX="$ROOT/build/libflac/$ARCH-macos$MACOSX_DEPLOYMENT_TARGET/install"
APP="$ROOT/build/FLACdrop.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -swift-version 6 -O -parse-as-library \
    -target "$ARCH-apple-macosx$MACOSX_DEPLOYMENT_TARGET" \
    -sdk "$(xcrun --sdk macosx --show-sdk-path)" \
    -module-cache-path "$ROOT/build/ModuleCache" \
    -I "$ROOT/Sources/CFLAC" -Xcc -I -Xcc "$PREFIX/include" \
    "$ROOT/Sources/FLACdrop/Encoder.swift" "$ROOT/Sources/FLACdrop/App.swift" \
    "$PREFIX/lib/libFLAC.a" -o "$APP/Contents/MacOS/FLACdrop"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>FLACdrop</string>
<key>CFBundleIdentifier</key><string>com.flacdrop.app</string>
<key>CFBundleName</key><string>FLACdrop</string>
<key>CFBundleIconFile</key><string>FLACdrop.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cp "$PREFIX/share/licenses/flac/COPYING.Xiph" "$APP/Contents/Resources/"
cp "$ROOT/Assets/Icon/FLACdrop.icns" "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
printf '\nBuilt %s\n' "$APP"
