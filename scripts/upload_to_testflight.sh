#!/usr/bin/env bash
# upload_to_testflight.sh — One-shot TestFlight uploader for kSpaceClean.
#
# Requires:
#   - $TEAM_ID env var (10-char Apple Team ID)
#   - $APPLE_ID env var (Apple ID email)
#   - $APP_SPECIFIC_PASSWORD env var (https://appleid.apple.com → App-Specific Passwords)
#   - Apple Distribution certificate installed in Keychain
#
# Run from worktree root: ./scripts/upload_to_testflight.sh

set -euo pipefail

: "${TEAM_ID:?TEAM_ID env var required}"
: "${APPLE_ID:?APPLE_ID env var required}"
: "${APP_SPECIFIC_PASSWORD:?APP_SPECIFIC_PASSWORD env var required (generate at appleid.apple.com)}"

WORKTREE=$(git rev-parse --show-toplevel)
PROJECT="$WORKTREE/kSpaceClean/kSpaceClean.xcodeproj"
ARCHIVE="$WORKTREE/kSpaceClean/build/kSpaceClean.xcarchive"
EXPORT_PLIST="$WORKTREE/kSpaceClean/build/ExportOptions.plist"

# 1. Patch ExportOptions.plist with TEAM_ID
/usr/libexec/PlistBuddy -c "Set :teamID $TEAM_ID" "$EXPORT_PLIST" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Add :teamID string $TEAM_ID" "$EXPORT_PLIST"

# 2. Re-archive with signing
xcodebuild -project "$PROJECT" \
  -scheme kSpaceClean \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  archive

# 3. Export .ipa
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$WORKTREE/kSpaceClean/build/" \
  -exportOptionsPlist "$EXPORT_PLIST"

# 4. Upload
xcrun altool --upload-app \
  --type osx \
  --file "$WORKTREE/kSpaceClean/build/kSpaceClean.ipa" \
  --username "$APPLE_ID" \
  --password "$APP_SPECIFIC_PASSWORD"

echo "✅ Uploaded. Check App Store Connect → TestFlight in ~10 minutes."
