#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/build/FLACdrop.app"
: "${APPLE_DEVID_APP_CERT_NAME:?Signing identity is required}"
: "${APPLE_ID_USER:?Apple ID is required}"
: "${APPLE_ID_PASS:?Apple app-specific password is required}"

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid app version' >&2; exit 1; }
[[ "$(lipo -archs "$APP/Contents/MacOS/FLACdrop")" == arm64 ]] || { echo 'Release must contain only arm64 code' >&2; exit 1; }
TEAM_ID=$(printf '%s' "$APPLE_DEVID_APP_CERT_NAME" | sed -nE 's/^Developer ID Application: .*\(([A-Z0-9]{10})\)$/\1/p')
[[ -n "$TEAM_ID" ]] || { echo 'Expected a Developer ID Application identity with a team ID' >&2; exit 1; }

# The nested app must be signed for notarization, but only the DMG is submitted/stapled.
codesign --force --sign "$APPLE_DEVID_APP_CERT_NAME" --options runtime --timestamp "$APP"
codesign --verify --deep --strict "$APP"
STAGING=$(mktemp -d "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/flacdrop-dmg.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/FLACdrop.app"
ln -s /Applications "$STAGING/Applications"
mkdir -p "$ROOT/dist"
DMG="$ROOT/dist/FLACdrop-$VERSION-macOS-arm64.dmg"
hdiutil create -volname FLACdrop -srcfolder "$STAGING" -format UDZO -ov "$DMG"
codesign --sign "$APPLE_DEVID_APP_CERT_NAME" --timestamp --identifier com.flacdrop.app.dmg "$DMG"
codesign --verify --strict "$DMG"

RESULT="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/flacdrop-notarization.json"
# Preserve Apple's response even on failure so rejection details can be retrieved.
submit_status=0
xcrun notarytool submit "$DMG" --apple-id "$APPLE_ID_USER" --password "$APPLE_ID_PASS" \
    --team-id "$TEAM_ID" --wait --timeout 40m --output-format json > "$RESULT" || submit_status=$?
cat "$RESULT"
STATUS=$(plutil -extract status raw "$RESULT" 2>/dev/null || true)
if [[ "$submit_status" != 0 || "$STATUS" != Accepted ]]; then
    SUBMISSION=$(plutil -extract id raw "$RESULT" 2>/dev/null || true)
    if [[ -n "$SUBMISSION" ]]; then
        xcrun notarytool log "$SUBMISSION" --apple-id "$APPLE_ID_USER" --password "$APPLE_ID_PASS" --team-id "$TEAM_ID" || true
    fi
    echo 'DMG notarization did not complete successfully.' >&2
    exit 1
fi
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
hdiutil verify "$DMG"
printf '\nRelease ready: %s\n' "$DMG"
