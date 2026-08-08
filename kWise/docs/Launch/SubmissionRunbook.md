# App Store Submission Runbook — kSpaceClean v1.0

## Prerequisites
- [ ] Apple Developer Program active, distribution cert + Team ID configured (see `kWise/docs/TestFlight/DistributionRunbook.md` Steps 1–4)
- [ ] Screenshots captured per `kWise/docs/Launch/ScreenshotsSpec.md`
- [ ] Privacy Policy live at https://kraftly.app/privacy
- [ ] Support URL live at https://kraftly.app/support/sclean
- [ ] Subscription product created in App Store Connect (kSpaceClean Pro Annual: $19.99)
- [ ] Free trial configured (7 days, non-renewing)

## Steps

### 1. Re-archive with final signing
```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/.claude/worktrees/feat-kspaceclean-v1
xcodebuild -project kWise/kSpaceClean.xcodeproj \
  -scheme kSpaceClean \
  -configuration Release \
  -archivePath kWise/build/kSpaceClean.xcarchive \
  archive
```

### 2. Export to App Store
```bash
xcodebuild -exportArchive \
  -archivePath kWise/build/kSpaceClean.xcarchive \
  -exportPath kWise/build/ \
  -exportOptionsPlist kWise/build/ExportOptions.plist
```
Expected: `kWise/build/kSpaceClean.ipa` + prompt for "Export Compliance" (answer: "No, this app does not use non-exempt encryption").

### 3. Upload build to App Store Connect
Either via Transporter (GUI) or:
```bash
xcrun altool --upload-app \
  --type osx \
  --file kWise/build/kSpaceClean.ipa \
  --username "$APPLE_ID" \
  --password "$APP_SPECIFIC_PASSWORD"
```
App Store Connect processes the build in 5–15 minutes. Email confirmation arrives.

### 4. Fill the new version page
In App Store Connect → kSpaceClean → + Version → 1.0.0:
- Copy each field block from `AppStoreMetadata.md` into the matching field
- Attach screenshots (in display order) from `ScreenshotsSpec.md`
- Fill App Privacy from `PrivacyDetails.md`

### 5. Age rating
Complete the age rating questionnaire:
- Cartoon or Fantasy Violence: No
- Realistic Violence: No
- Sexual Content or Nudity: No
- Profanity or Crude Humor: No
- Horror or Fear Themes: No
- Medical/Treatment Information: No
- Gambling: No
- Alcohol, Tobacco, or Drug References: No
- Mature/Suggestive Themes: No

Expected rating: 4+.

### 6. Pricing & availability
- Price: $19.99/yr (verify in all tier prices from `AppStoreMetadata.md`)
- Availability: all territories except where App Store forbids (none)

### 7. In-App Purchases
- kSpaceClean Pro Annual: $19.99/yr, 7-day free trial
- Verify the IAP product ID matches `ProAnnual` in code

### 8. Submit for Review
- Click "Add for Review"
- Answer the export-compliance prompt (No)
- Click "Submit"

Apple typically responds in 24–48 hours with approval, rejection (with reasons), or hold for further information.

## Failure Modes
- **"Missing compliance"**: re-run Step 2 and answer the export-compliance prompt correctly
- **"Invalid binary"**: clean DerivedData (`rm -rf ~/Library/Developer/Xcode/DerivedData`) and re-archive
- **"Metadata rejected"**: the most common cause is a trademark violation — search your description for "CleanMyMac" and remove
- **"App Review rejected"**: usually for sandbox / TCC issues — see `kWise/docs/Onboarding/FDAGuideView.swift` to verify the FDA onboarding flow is intact

## Post-Approval
- Enable auto-release or click "Release" manually
- Submit a ProductHunt post (text template in `kWise/docs/Marketing/ProductHuntLaunch.md` — to be written)
- Email the 10 reviewers from `kWise/docs/Marketing/ReviewerList.md` (to be written)