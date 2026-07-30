# TestFlight Distribution Runbook — kSpaceClean v1.0

## Prerequisites
- Apple Developer Program enrollment active ($99/year, paid)
- Distribution certificate installed in Keychain (`Developer ID Application: <Team Name>` OR `Apple Distribution: <Team Name>`)
- Team ID known (10-char alphanumeric, e.g. `A1B2C3D4E5`)
- `kSpaceClean.xcarchive` produced by Task D1 (path: `kSpaceClean/build/kSpaceClean.xcarchive`)

## Steps

### 1. Configure code signing
Edit `kSpaceClean/project.yml`:
```yaml
settings:
  base:
    DEVELOPMENT_TEAM: "A1B2C3D4E5"  # <REPLACE WITH YOUR TEAM ID>
    CODE_SIGN_STYLE: Automatic
    CODE_SIGN_IDENTITY: "Apple Distribution"
```
Then regenerate the project:
```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1
python3 kSpaceClean/generate_project.py
```

### 2. Re-archive with signing
```bash
xcodebuild -project kSpaceClean.xcodeproj \
  -scheme kSpaceClean \
  -configuration Release \
  -archivePath kSpaceClean/build/kSpaceClean.xcarchive \
  archive
```
Expected: `BUILD SUCCEEDED` and `.xcarchive/Info.plist` shows a non-empty `SigningIdentity`.

### 3. Export .ipa
Use the existing `kSpaceClean/build/ExportOptions.plist` template (already produced by D1; verify the `teamID` field is filled in).

```bash
xcodebuild -exportArchive \
  -archivePath kSpaceClean/build/kSpaceClean.xcarchive \
  -exportPath kSpaceClean/build/ \
  -exportOptionsPlist kSpaceClean/build/ExportOptions.plist
```
Expected: `kSpaceClean/build/kSpaceClean.ipa` created.

### 4. Upload to App Store Connect
Either via Transporter (GUI) or CLI:
```bash
xcrun altool --upload-app \
  --type ios \
  --file kSpaceClean/build/kSpaceClean.ipa \
  --username "$APPLE_ID" \
  --password "$APP_SPECIFIC_PASSWORD"
```
After upload, App Store Connect automatically processes the build (5-15 min) and emails the team.

### 5. Activate internal testing group
In App Store Connect → My Apps → kSpaceClean → TestFlight → Internal Testing:
- Click the build to add it to the group
- (If not yet created) Create an internal group: "kSpaceClean Internal"
- Add testers by email — they receive a redemption link

### 6. First-day smoke test
Before inviting the wider 5, install the build yourself on a personal machine:
- Verify the app launches
- Run a scan
- Trigger a cleanup
- Confirm `~/Library/Application Support/kSpaceClean/metric-kit/` is created

If any step fails, fix and re-archive — do NOT distribute a broken build.

## Failure Modes
- **"No code signing identities"**: cert not in Keychain — re-install from developer.apple.com
- **"Bundle identifier is not available"**: bundle ID collision — change in `project.yml` and `Info.plist`
- **"Missing compliance"**: `ITSAppUsesNonExemptEncryption` set to `false` in `Info.plist`
- **"Invalid bundle"**: derived data stale — `rm -rf ~/Library/Developer/Xcode/DerivedData` and re-archive

## Estimated Time
30 minutes (assuming all prerequisites are ready).
