# App Privacy Details — kSpaceClean

> Apple requires every App Store listing to declare what data the app collects.
> kSpaceClean collects NOTHING. Every question on Apple's privacy nutrition label is answered "Data Not Collected."

## App Privacy Nutrition Label Answers

App Store Connect → App Privacy → for each category, answer "Data Not Collected":

- Contact Info: Data Not Collected
- Health & Fitness: Data Not Collected
- Financial Info: Data Not Collected
- Location: Data Not Collected
- Sensitive Info: Data Not Collected
- Contacts: Data Not Collected
- User Content: Data Not Collected
- Browsing History: Data Not Collected
- Search History: Data Not Collected
- Identifiers: Data Not Collected
- Usage Data: Data Not Collected
- Diagnostics: Data Not Collected
- Purchases: Data Not Collected (App Store handles subscriptions; we never see them)
- Other Data: Data Not Collected

## Privacy Policy URL
https://kraftly.app/privacy

The policy must:
1. State explicitly: "kSpaceClean does not collect any data."
2. Explain why Full Disk Access is required (Apple-mandated for system cache cleanup).
3. Explain MetricKit crash diagnostics are processed locally and reported only to App Store Connect's automatic crash aggregation (user-consented at install).
4. Be no longer than 1 printed page.

## Privacy Manifest (`PrivacyInfo.xcprivacy`)
The privacy manifest file lives at `kSpaceClean/Resources/PrivacyInfo.xcprivacy` and is registered in `kSpaceClean/project.yml` so `generate_project.py` includes it in the build.

The manifest declares:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyCollectedDataTypes</key>
    <array/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryFileTimestamp</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>C617.1</string>
            </array>
        </dict>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>CA92.1</string>
            </array>
        </dict>
        <dict>
            <key>NSPrivacyAccessedAPIType</key>
            <string>NSPrivacyAccessedAPICategorySystemBootTime</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>35F9.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

Why each `NSPrivacyAccessedAPIType` is declared:

- `NSPrivacyAccessedAPICategoryFileTimestamp` (reason `C617.1`): used to compute file age when deciding which cached/leftover files qualify as Recommended vs Optional cleanup candidates.
- `NSPrivacyAccessedAPICategoryUserDefaults` (reason `CA92.1`): used to read/write the user's scan preferences (excluded paths, last-scan date) in `UserPreferences.swift`.
- `NSPrivacyAccessedAPICategorySystemBootTime` (reason `35F9.1`): used to measure elapsed uptime for the menu bar "Mac is warm" indicator.

`NSPrivacyTracking` is `false` and `NSPrivacyCollectedDataTypes` is empty, matching the nutrition label above.