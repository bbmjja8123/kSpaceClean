#!/usr/bin/env bash
# release_direct.sh — Archive, sign, notarize and staple the DIRECT
# (Developer ID) edition of Klaris (target KlarisDirect, non-sandboxed).
#
# Requires:
#   - $TEAM_ID (default TC973L6HPC)
#   - "Developer ID Application" certificate in Keychain
#   - $APPLE_ID + $APP_SPECIFIC_PASSWORD + the Developer ID signing identity,
#     or an App Store Connect API key for notarytool
#
# Usage: ./scripts/release_direct.sh [version] [build]

set -euo pipefail

: "${APPLE_ID:?APPLE_ID env var required}"
: "${APP_SPECIFIC_PASSWORD:?APP_SPECIFIC_PASSWORD env var required}"
TEAM_ID="${TEAM_ID:-TC973L6HPC}"
IDENTITY="${IDENTITY:-Developer ID Application}"

WORKTREE=$(git rev-parse --show-toplevel)
PROJECT="$WORKTREE/kWise/kWise.xcodeproj"
BUILD_DIR="$WORKTREE/kWise/build/direct"
ARCHIVE="$BUILD_DIR/KlarisDirect.xcarchive"
VERSION="${1:-}"
BUILD_NUM="${2:-}"

if [ -n "$VERSION" ]; then
  bash "$WORKTREE/Tools/version-bump.sh" "$VERSION" "${BUILD_NUM:-}"
fi

mkdir -p "$BUILD_DIR"

# 1. Archive the direct target (Release: real team + hardened runtime;
#    no App Sandbox — entitlements file kWiseDirect.entitlements).
xcodebuild -project "$PROJECT" \
  -scheme KlarisDirect \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  archive

# 2. Export a Developer ID app.
cat > "$BUILD_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM_ID</string>
    <key>signingCertificate</key><string>$IDENTITY</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$BUILD_DIR/export/" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"

APP=$(find "$BUILD_DIR/export" -name "Klaris.app" -maxdepth 3 | head -1)
[ -n "$APP" ] || { echo "error: exported Klaris.app not found"; exit 1; }

# 3. Zip + notarize + staple.
ZIP="$BUILD_DIR/Klaris.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

xcrun notarytool submit "$ZIP" \
  --apple-id "$APPLE_ID" \
  --password "$APP_SPECIFIC_PASSWORD" \
  --team-id "$TEAM_ID" \
  --wait

xcrun stapler staple "$APP"

echo "✅ Notarized + stapled: $APP"
echo "   Ship as a DMG/zip from the website; direct users get updates by re-download (Sparkle TBD)."
