#!/usr/bin/env bash
# upload_to_testflight.sh — One-shot MAS archive + TestFlight upload for
# Klaris (kWise workspace; bundle app.kraftly.klaris).
#
# Requires:
#   - $TEAM_ID env var (10-char Apple Team ID, default TC973L6HPC)
#   - $APPLE_ID env var (Apple ID email)
#   - $APP_SPECIFIC_PASSWORD env var (appleid.apple.com → App-Specific Passwords)
#   - Apple Distribution certificate in Keychain
#
# Usage: TEAM_ID=... APPLE_ID=... APP_SPECIFIC_PASSWORD=... ./scripts/upload_to_testflight.sh [version] [build]

set -euo pipefail

: "${APPLE_ID:?APPLE_ID env var required}"
: "${APP_SPECIFIC_PASSWORD:?APP_SPECIFIC_PASSWORD env var required (generate at appleid.apple.com)}"
TEAM_ID="${TEAM_ID:-TC973L6HPC}"

WORKTREE=$(git rev-parse --show-toplevel)
PROJECT="$WORKTREE/kWise/kWise.xcodeproj"
BUILD_DIR="$WORKTREE/kWise/build"
ARCHIVE="$BUILD_DIR/Klaris.xcarchive"
VERSION="${1:-}"
BUILD_NUM="${2:-}"

# Optional version/build bump before archiving (writes project.yml + regenerates).
if [ -n "$VERSION" ]; then
  bash "$WORKTREE/Tools/version-bump.sh" "$VERSION" "${BUILD_NUM:-}"
fi

# 1. Archive (Release carries the real entitlements + team; XcodeGUI session
#    or -allowProvisioningUpdates mints the profile).
xcodebuild -project "$PROJECT" \
  -scheme kWise \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  archive

# 2. Export App Store package.
cat > "$BUILD_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>app-store-connect</string>
    <key>teamID</key><string>$TEAM_ID</string>
</dict>
</plist>
EOF

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$BUILD_DIR/export/" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -allowProvisioningUpdates

IPA=$(find "$BUILD_DIR/export" -name "*.pkg" -o -name "*.ipa" | head -1)
[ -n "$IPA" ] || { echo "error: no exported package found"; exit 1; }

# 3. Upload (altool → notarytool/iTMSTransporter replaced by Xcode's
#    native App Store Connect API auth; APP_SPECIFIC_PASSWORD remains the
#    simplest no-API-key path).
xcrun altool --upload-package \
  --type osx \
  --file "$IPA" \
  --username "$APPLE_ID" \
  --password "$APP_SPECIFIC_PASSWORD"

echo "✅ Uploaded. Check App Store Connect → TestFlight in ~10 minutes."
