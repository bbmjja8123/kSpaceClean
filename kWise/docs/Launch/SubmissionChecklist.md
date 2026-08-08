# Submission Checklist — kWise v1.0

Tick each box before clicking "Submit for Review."

## Code & Build
- [ ] `kWise.xcarchive` exists in `kWise/build/`, signed with Team ID
- [ ] `xcodebuild ... archive` reports `BUILD SUCCEEDED` with no warnings
- [ ] `xcrun altool --upload-app` reports "Upload succeeded"
- [ ] Build appears in App Store Connect → TestFlight with status "Ready to Submit"
- [ ] No "Missing compliance" warnings

## Metadata
- [ ] App name: `kWise` (matches Bundle ID)
- [ ] Subtitle ≤ 30 chars in all 3 locales
- [ ] Description ≤ 4000 chars in all 3 locales
- [ ] Keywords ≤ 100 chars total
- [ ] Promotional text ≤ 170 chars in all 3 locales
- [ ] Copyright: © 2026 Kraftly Inc.
- [ ] Support URL returns 200
- [ ] Marketing URL returns 200 (optional)

## Screenshots
- [ ] At least 3 at 2560×1600
- [ ] At least 1 at 2880×1800
- [ ] All 5 scenes present (Hero, Categories, Risk, Confirm, Menu Bar)
- [ ] No customer data visible (only synthetic fixtures)
- [ ] All text overlays translated for zh-CN and ja locales

## Privacy
- [ ] Privacy policy live at https://kraftly.app/privacy
- [ ] App Privacy nutrition label: every category = "Data Not Collected"
- [ ] `PrivacyInfo.xcprivacy` in `kWise/Resources/` and registered in `kWise/generate_project.py` (`resource_files` list)
- [ ] No tracking, no analytics, no telemetry in source

## Pricing & IAP
- [ ] Price set in all 4 territories (US $19.99, EU €19.99, CN ¥98, JP ¥2,400)
- [ ] Free trial: 7 days
- [ ] IAP product `ProAnnual` exists and matches code
- [ ] IAP review screenshot attached (SubscriptionTermsURL configured)

## Age Rating
- [ ] All 9 categories answered (expected: 4+)

## App Review Information
- [ ] Demo account: not required (no login)
- [ ] Contact info for reviewer: filled
- [ ] Notes to reviewer: "kWise requires Full Disk Access for system cache cleanup. The FDA onboarding flow at first launch explains this. No data is collected or transmitted."

## Final
- [ ] Reviewed the entire submission page in App Store Connect
- [ ] Clicked "Submit for Review"
- [ ] Confirmed submission email arrived