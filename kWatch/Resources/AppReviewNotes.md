# kWatch — App Review Notes

**Bundle ID:** `app.kraftly.kwatch`
**App Store Category:** Developer Tools / Utilities
**Submission Type:** Initial release

---

## 1. What kWatch Does

kWatch is a **read-only system monitor** that surfaces CPU, memory, disk, network, battery, temperature (when available), and fan (when available) telemetry in the macOS menu bar, a Dashboard window, a Widget, an optional Live Activity (macOS 14+), and via Siri / Shortcuts / Spotlight intents. kWatch does **not** write to user files, does **not** modify system settings, and does **not** communicate with any external server.

## 2. Sandbox & Privacy

- **App Sandbox:** ENABLED (`com.apple.security.app-sandbox` = true).
- **Network access:** DISABLED (`com.apple.security.network.client` = false, `com.apple.security.network.server` = false). The app makes **zero** outbound network requests.
- **File access:** No `user-selected` file entitlement is requested. The app does **not** open arbitrary files and does **not** prompt the user to grant file access.
- **TCC permissions required:** **NONE.** kWatch reads only the system APIs documented below; it never touches the user's Contacts, Calendars, Photos, Microphone, Camera, Reminders, or location.
- **App Group:** `group.app.kraftly.shared` is declared in the entitlement (`com.apple.security.application-groups`) so the app and its Widget / Live Activity / Intents extensions can share the JSON snapshot. The app group container is **not** exposed to the user; nothing inside it is ever uploaded.

## 3. Required-Reason API Usage

kWatch declares the following `NSPrivacyAccessedAPITypes` reasons in `PrivacyInfo.xcprivacy`:

| API Category | Reason Code | Why kWatch Uses It |
|---|---|---|
| `UserDefaults` | `CA92.1` | Persists user preferences (menu-bar style, enabled metric kinds, sampling interval, launch-at-login, Pro entitlement flag) inside the App Group suite. |
| `FileTimestamp` | `C617.1` | When persisting the App Group snapshot, kWatch uses atomic file replacement that touches file timestamps; this is required for crash-safe writes. |
| `SystemBootTime` | `35F9.1` | Used by the CPU monitor to compute process CPU utilization across a sampling window (denominator is uptime). |
| `DiskSpace` | `E174.1` | The Disk monitor reads the filesystem free/total byte counts through `statfs()` so the menu bar can show "84% used". |

## 4. Data Collection

- `NSPrivacyTracking` = **false**.
- `NSPrivacyCollectedDataTypes` = **[]** (empty).
- `NSPrivacyTrackingDomains` = **[]** (empty).

kWatch collects **no** personal data. All computation is local; nothing leaves the device.

## 5. MetricKit / Crash Reporting

kWatch subscribes to `MXMetricManager` and `MXCrashManager` to receive daily performance summaries and crash/hang diagnostic payloads. These payloads are **persisted locally to the App Group container** under `Diagnostics/metric-*.json` and `Diagnostics/crash-*.json`. The app **never** uploads them, and they are only ever included in a support bundle when the user explicitly clicks **Export Diagnostics…** and chooses a save destination through an `NSSavePanel`.

## 6. Sensor Degradation

On **Apple Silicon Macs**, kWatch may report `unavailable` for the following Pro-only sensors:

- `Temperature` — gated by SMC access that is restricted on Apple Silicon. The dashboard displays "Unsupported on this Mac" instead of a fake value.
- `Fan RPM` — same restriction.

On **Intel Macs** with no SMC, the same sensors report `unavailable`. These states are honest and match `MXAppResponsivenessMetrics` reporting rules — kWatch never invents values for sensors it cannot read.

## 7. UI / Window Behavior

- `LSUIElement` = true → kWatch launches as a **menu bar accessory** with **no Dock icon**. Opening the dashboard, onboarding, or settings uses regular `Window` scenes that the user can summon from the menu bar.
- The app does not request Accessibility, Input Monitoring, or Screen Recording permissions.

## 8. StoreKit / Pro Unlock

Pro is unlocked through a **single non-consumable in-app purchase** (`app.kraftly.kwatch.pro`, $7.99 USD one-time, no subscription). The purchase unlocks:

- History view (90-day rolling window)
- Trend chart with sparkline
- Top processes table (process names only — no paths, no usernames)
- Threshold alerts with custom rules
- Temperature and Fan sensors (when SMC is available)

All Pro-only UI surfaces a paywall first; the **dashboard, menu bar, and snapshot pipeline work without a purchase**.

### How to test Pro during review

1. In Xcode, run the kWatch scheme with the `kWatch.storekit` configuration file attached (see **Developer → Scheme → Run → Options → StoreKit Configuration**).
2. The configuration file declares the Pro product and three sandbox accounts: `pro.purchased`, `pro.lapsed`, and `pro.refunded`. Choose any account from the scheme's **Features → StoreKit** panel to exercise the corresponding state.
3. Alternatively, build & run, then trigger `StoreKit → Manage Transactions → Refresh` to force a transaction fetch from the sandbox environment. The paywall will appear behind any Pro-gated action; "Restore Purchases" exercises the receipt-refresh path.

## 9. Test Plan for Reviewers

The reviewer should be able to validate every flow below without any special provisioning beyond installing the build:

1. Launch kWatch → onboarding flow (4 steps) appears because `-reset-preferences` is honored, or the menu bar item appears immediately on subsequent launches.
2. Menu bar shows CPU / Memory / Disk / Network. Clicking the menu bar icon reveals the dashboard window.
3. Switching menu-bar style (Trend / Numeric / Minimal) in Settings updates the menu bar immediately.
4. Toggling a metric off in Settings reflects in the menu bar within one sample.
5. Setting a CPU alert above 50% fires a notification (after permission grant) and persists in the Alerts view.
6. History view is gated behind Pro on free tier; tapping it opens the paywall.
7. Exporting Diagnostics… presents an `NSSavePanel`, writes a JSON file, and reopens Finder at the destination. The exported file does **not** contain "Safari", "192.168.", `/Users/<name>/`, or `MXCrashDiagnostic` raw payloads.
8. No network requests are made at any point — reviewable through Console.app or `lsof -i`.

## 10. Source-Available Notes

The kWatch codebase ships in this repository as `kWatch/`. All kFoundation shared modules live under `kFoundation/Sources/MetricsKit/`. No third-party analytics SDK is bundled; the only system frameworks used are `Foundation`, `AppKit`, `SwiftUI`, `MetricKit`, `StoreKit`, `UserNotifications`, `Combine`, and `os.log` for diagnostic logging.

---

*If a reviewer needs additional instrumentation, the Settings → Export Diagnostics… action produces a single redacted JSON file that captures the app's environment without exposing user data.*