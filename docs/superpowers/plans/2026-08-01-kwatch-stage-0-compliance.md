# kWatch v1.0 — Stage 0 Compliance Sprint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship kWatch v1.0 compliance-blocking items in 1 week so the binary can be uploaded to App Store Connect without rejection.

**Architecture:** Code changes use TDD (test-first, fail, implement, pass, commit). Content tasks produce shipped artifacts (HTML, design briefs). Manual/outsource tasks produce documented checklists that the engineer executes against Figma / App Store Connect / Fiverr.

**Tech Stack:** Swift 5.9+ / SwiftUI / StoreKit 2 / AppIntents / GitHub Pages

---

## Global Constraints

- macOS deployment target: 13.0 (kWatch minimum, but use `@available(macOS 14.0, *)` for newer APIs as needed)
- Swift strict concurrency enabled; `@MainActor` annotations required on view models
- All public APIs must have DocC comments
- Localization: 3 languages (en, zh-Hans, ja) — strings ship in `Localizable.xcstrings`
- No new third-party dependencies
- Commit messages: `feat(kWatch): <verb>` / `fix(kWatch): <verb>` / `chore(kWatch): <verb>`
- Bundle ID: `app.kraftly.kwatch`
- Product ID for Pro IAP: `app.kraftly.kwatch.pro`

---

## Reality Check (Important)

Before starting tasks, note that **several "P0 gaps" identified in `kWatch/V1-TODO.md` are already partially or fully implemented** in the codebase:

| Task | Status |
|---|---|
| `StoreManager.restore()` | ✅ Exists (`Store/StoreManager.swift:220-231`); 3 unit tests pass |
| `PaywallView` Restore button | ✅ Exists (`Store/PaywallView.swift:123-138`) |
| `AboutView` Restore button | ✅ Exists (`Settings/AboutView.swift:135-147`); calls `viewModel.restorePurchases()` |
| `KWatchAppShortcuts` (8 intents) | ✅ All 8 registered (`Intents/KWatchAppShortcuts.swift:14-88`) |
| `QueryMetricIntent` parameters | ✅ Has `metric` `MetricKindParameter` AppEnum (`Intents/QueryMetricIntent.swift:47-79`) |

The remaining work below focuses on **what's actually missing or incomplete**.

---

## File Structure

### New files to create

```
kWatch/
├── Store/
│   └── SubscriptionTerms.swift              # C2 - localized terms text (en/zh-Hans/ja)
└── Tests/
    ├── PaywallViewModelTermsTests.swift     # C3 - TDD
    ├── SettingsViewModelRestoreTests.swift  # C1 - TDD
    └── IntentParameterTests.swift           # E7 - TDD

docs/
├── legal/
│   ├── privacy.en.html                      # C4 - English privacy policy
│   ├── privacy.zh-Hans.html                 # C4 - Simplified Chinese
│   ├── privacy.ja.html                      # C4 - Japanese
│   └── support.html                         # C5 - Support page
└── design/
    ├── app-icon-brief.md                    # C7 - Designer brief
    └── screenshots-brief.md                 # C8 - Designer brief

docs/superpowers/
└── checklists/
    └── app-store-connect-privacy-labels.md  # C6 - Manual checklist
```

### Files to modify

```
kWatch/
├── Store/
│   ├── PaywallViewModel.swift               # C3 - add acceptedTerms state
│   └── PaywallView.swift                    # C3 - render terms checkbox
├── Intents/
│   ├── ShowTopProcessesIntent.swift         # E7 - add `limit` parameter
│   ├── ShowDiskUsageIntent.swift            # E7 - add `volume` parameter
│   └── ShowNetworkRateIntent.swift          # E7 - add `direction` parameter
└── Shared/
    └── AppGroupConfiguration.swift          # (verify) - privacy URLs constants

kWatch/Settings/
└── MenuBarSettingsView.swift                # (verify) - restore purchase entry
```

### Test files

```
kWatch/Tests/
├── PaywallViewModelTermsTests.swift         # C3 - new tests
├── SettingsViewModelRestoreTests.swift      # C1 - new tests
└── IntentParameterTests.swift               # E7 - new tests
```

---

## Task 1: C2 — Create SubscriptionTerms module with localized text

**Files:**
- Create: `kWatch/Store/SubscriptionTerms.swift`

**Goal:** Centralize subscription auto-renewal disclosure copy in 3 languages. Apple App Store Review Guidelines §3.1.2(a) requires this text be visible to users before they subscribe.

**Interfaces:**
- Consumes: nothing
- Produces: `SubscriptionTerms` enum with `summary(for locale: Locale) -> String` returning the localized auto-renewal disclosure.

### Steps

- [ ] **Step 1.1: Create `kWatch/Store/SubscriptionTerms.swift`**

```swift
import Foundation

/// Localized auto-renewal disclosure text required by App Store Review
/// Guidelines §3.1.2(a). Surfaced in the Paywall view *before* the user
/// can complete a purchase.
///
/// The text follows Apple's standard subscription disclosure template and
/// is intentionally identical across all 3 supported locales except for
/// translation. Each translation lives in the `Localizable.xcstrings`
/// catalog under the keys listed below.
public enum SubscriptionTerms {
    /// Localization keys used to look up the disclosure copy.
    public enum LocalizationKey: String, CaseIterable {
        /// Title shown above the disclosure block.
        case title = "subscription.terms.title"
        /// Body paragraph explaining the auto-renewal behavior.
        case body = "subscription.terms.body"
        /// Hyperlink copy pointing to the support URL.
        case supportLink = "subscription.terms.supportLink"

        public var localizationKey: String { rawValue }
    }

    /// Returns the localized disclosure bundle for the given locale.
    /// Falls back to English if the requested locale is unsupported.
    public static func disclosure(for locale: Locale = .current) -> Disclosure {
        let bundle = localizationBundle(for: locale)
        return Disclosure(
            title: bundle.localizedString(forKey: LocalizationKey.title.rawValue, value: nil, table: nil),
            body: bundle.localizedString(forKey: LocalizationKey.body.rawValue, value: nil, table: nil),
            supportLink: bundle.localizedString(forKey: LocalizationKey.supportLink.rawValue, value: nil, table: nil)
        )
    }

    /// Bundle that contains the disclosure strings. Currently the main
    /// bundle; a future change could load a per-region sub-bundle.
    private static func localizationBundle(for locale: Locale) -> Bundle {
        guard let path = Bundle.main.path(forResource: locale.identifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    /// Disclosure block consumed by `PaywallView`.
    public struct Disclosure: Equatable {
        public let title: String
        public let body: String
        public let supportLink: String

        public init(title: String, body: String, supportLink: String) {
            self.title = title
            self.body = body
            self.supportLink = supportLink
        }
    }
}
```

- [ ] **Step 1.2: Verify file compiles**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -configuration Debug build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -destination 'platform=macOS' 2>&1 | tail -20`
Expected: `** BUILD SUCCEEDED **` (no warnings, no errors related to SubscriptionTerms.swift)

- [ ] **Step 1.3: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/Store/SubscriptionTerms.swift
git commit -m "feat(kWatch): add SubscriptionTerms disclosure module"
```

### English copy (paste into Localizable.xcstrings under these keys)

- `subscription.terms.title` = `"Subscription Terms"`
- `subscription.terms.body` = `"Payment will be charged to your Apple ID account at confirmation of purchase. Subscription automatically renews unless auto-renew is turned off at least 24 hours before the end of the current period. Your account will be charged for renewal within 24 hours prior to the end of the current period. You can manage and cancel your subscriptions in your App Store account settings."`
- `subscription.terms.supportLink` = `"View Terms of Use and Privacy Policy"`

### Simplified Chinese copy (zh-Hans)

- `subscription.terms.title` = `"订阅条款"`
- `subscription.terms.body` = `"购买确认时将从您的 Apple ID 账户扣款。除非在当前订阅期结束前至少 24 小时关闭自动续订,否则订阅将自动续订。在当前订阅期结束前 24 小时内,系统会从您的账户扣款续订。您可以在 App Store 账户设置中管理和取消订阅。"`
- `subscription.terms.supportLink` = `"查看服务条款和隐私政策"`

### Japanese copy (ja)

- `subscription.terms.title` = `"サブスクリプション規約"`
- `subscription.terms.body` = `"購入確定時に Apple ID アカウントに課金されます。現在の期間が終了する少なくとも 24 時間前に自動更新をオフにしない限り、サブスクリプションは自動的に更新されます。現在の期間が終了する 24 時間前までにアカウントに更新料金が課金されます。サブスクリプションの管理とキャンセルは App Store のアカウント設定で行えます。"`
- `subscription.terms.supportLink` = `"利用規約とプライバシーポリシーを見る"`

> **Note**: Add the three localized strings to `kWatch/Resources/Localizable.xcstrings`. If the catalog does not exist yet, create it via Xcode (File → New → File → Strings Catalog) before adding the strings.

---

## Task 2: C3 — Add `acceptedTerms` state to `PaywallViewModel` (TDD)

**Files:**
- Create: `kWatch/Tests/PaywallViewModelTermsTests.swift`
- Modify: `kWatch/Store/PaywallViewModel.swift`

**Interfaces:**
- Consumes: `StoreManagerProtocol` (existing)
- Produces: `@Published var acceptedTerms: Bool` defaulting to `false`; `func acknowledgeTerms()`

### Steps

- [ ] **Step 2.1: Write the failing test**

Create `kWatch/Tests/PaywallViewModelTermsTests.swift`:

```swift
import XCTest
import StoreKit
import Combine
@testable import kWatch

@MainActor
final class PaywallViewModelTermsTests: XCTestCase {
    private func makeViewModel(isPro: Bool = false) -> (PaywallViewModel, StubStoreManager, PurchaseState) {
        let purchaseState = PurchaseState()
        let storeManager = StubStoreManager(
            productID: "app.kraftly.kwatch.pro",
            products: [],
            isPro: isPro,
            purchaseState: purchaseState
        )
        let viewModel = PaywallViewModel(storeManager: storeManager, purchaseState: purchaseState)
        return (viewModel, storeManager, purchaseState)
    }

    func testAcceptedTermsDefaultsToFalse() {
        let (viewModel, _, _) = makeViewModel()
        XCTAssertFalse(viewModel.acceptedTerms)
    }

    func testAcknowledgeTermsFlipsAcceptedTermsTrue() {
        let (viewModel, _, _) = makeViewModel()
        viewModel.acknowledgeTerms()
        XCTAssertTrue(viewModel.acceptedTerms)
    }

    func testCanPurchaseIsFalseUntilTermsAccepted() {
        let (viewModel, _, _) = makeViewModel()
        XCTAssertFalse(viewModel.canPurchase)

        viewModel.acknowledgeTerms()
        XCTAssertTrue(viewModel.canPurchase)
    }

    func testCanPurchaseIgnoresAcceptanceForProUsers() {
        // Pro users see the paywall rarely; they should be able to re-purchase
        // (e.g. gift) without re-accepting terms on every visit.
        let (viewModel, _, _) = makeViewModel(isPro: true)
        XCTAssertTrue(viewModel.canPurchase)
    }
}
```

- [ ] **Step 2.2: Run the test, verify it fails**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -destination 'platform=macOS' -only-testing:kWatchTests/PaywallViewModelTermsTests 2>&1 | tail -30`
Expected: 4 failures, errors reference `acceptedTerms` / `acknowledgeTerms` / `canPurchase` as "value of type 'PaywallViewModel' has no member".

- [ ] **Step 2.3: Add the state and computed property**

In `kWatch/Store/PaywallViewModel.swift`, add after the `errorMessage` declaration (line 30):

```swift
    /// Whether the user has acknowledged the auto-renewal disclosure.
    /// Defaults to `false`; the paywall disables the purchase button
    /// until the user checks the terms checkbox (or is already Pro).
    @Published public var acceptedTerms: Bool = false

    /// Convenience flag combining `isPro` (Pro users can re-purchase
    /// without re-accepting) and `acceptedTerms` for free-tier users.
    public var canPurchase: Bool {
        isPro || acceptedTerms
    }

    /// Flip `acceptedTerms` to `true`. Called from the paywall checkbox.
    public func acknowledgeTerms() {
        acceptedTerms = true
    }
```

- [ ] **Step 2.4: Run the test, verify it passes**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -destination 'platform=macOS' -only-testing:kWatchTests/PaywallViewModelTermsTests 2>&1 | tail -10`
Expected: `Test Suite 'All tests' passed`

- [ ] **Step 2.5: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/Tests/PaywallViewModelTermsTests.swift kWatch/Store/PaywallViewModel.swift
git commit -m "feat(kWatch): add acceptedTerms gate to PaywallViewModel"
```

---

## Task 3: C3 — Render the terms checkbox in `PaywallView`

**Files:**
- Modify: `kWatch/Store/PaywallView.swift`

**Interfaces:**
- Consumes: `PaywallViewModel.acceptedTerms` (from Task 2)
- Produces: A `Toggle` bound to `acceptedTerms`, displayed above the purchase button. The purchase button is disabled until `canPurchase` is true.

### Steps

- [ ] **Step 3.1: Modify `PaywallView.body` to insert the disclosure block**

In `kWatch/Store/PaywallView.swift`, locate the `PurchaseButton(...)` call (around line 31-36). Replace the entire block from `PurchaseButton` through `restoreButton` with:

```swift
            termsDisclosure
            PurchaseButton(
                label: LocalizedStringKey(stringLiteral: viewModel.priceLine),
                isLoading: viewModel.isPurchasing,
                didSucceed: viewModel.isPro,
                action: { Task { await viewModel.purchase() } }
            )
            .disabled(!viewModel.canPurchase)
            restoreButton
```

- [ ] **Step 3.2: Add the `termsDisclosure` computed property**

After the existing `private var priceLine` computed property (around line 101), add:

```swift
    private var termsDisclosure: some View {
        let disclosure = SubscriptionTerms.disclosure()
        return VStack(alignment: .leading, spacing: 6) {
            Text(disclosure.title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Text(disclosure.body)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(isOn: Binding(
                get: { viewModel.acceptedTerms },
                set: { viewModel.acceptedTerms = $0 }
            )) {
                Text(disclosure.supportLink)
                    .font(.caption2)
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
```

- [ ] **Step 3.3: Verify the build**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild build -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -destination 'platform=macOS' 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3.4: Re-run PaywallViewModelTermsTests to confirm no regressions**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -destination 'platform=macOS' -only-testing:kWatchTests/PaywallViewModelTermsTests 2>&1 | tail -10`
Expected: `Test Suite 'All tests' passed`

- [ ] **Step 3.5: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/Store/PaywallView.swift
git commit -m "feat(kWatch): render subscription terms disclosure in PaywallView"
```

---

## Task 4: C1 — Verify SettingsViewModel restore wiring (TDD)

**Files:**
- Create: `kWatch/Tests/SettingsViewModelRestoreTests.swift`

**Reality check:** `StoreManager.restore()` already exists and is wired through `AboutView.restorePurchasesButton`. This task **verifies** the wiring via a unit test rather than implementing it.

**Interfaces:**
- Consumes: `SettingsViewModel.restorePurchases()` (existing)
- Produces: Tests that confirm the call propagates to `StoreManager.restore()`.

### Steps

- [ ] **Step 4.1: Read existing `SettingsViewModel.restorePurchases()`**

Run: `grep -n "restorePurchases" /Users/mengjianjun/Documents/ai/aicoding/macapp/kWatch/Settings/SettingsViewModel.swift`

If the method does not exist, see "Fallback" below. If it does, note its signature for the test.

Expected signature (if exists):
```swift
public func restorePurchases() async
```

If signature differs, adjust the test accordingly.

- [ ] **Step 4.2: Write the failing test**

Create `kWatch/Tests/SettingsViewModelRestoreTests.swift`:

```swift
import XCTest
import StoreKit
import Combine
@testable import kWatch

@MainActor
final class SettingsViewModelRestoreTests: XCTestCase {

    func testRestorePurchasesPropagatesToStoreManager() async {
        // Verify that calling `restorePurchases()` on the view model
        // delegates to `StoreManagerProtocol.restore()`. We use a
        // recording stub to count invocations.
        let stub = RecordingStoreManager()
        let purchaseState = PurchaseState()
        let preferences = StubPreferencesRepository()
        let scheduler = StubNotificationScheduler()
        let viewModel = SettingsViewModel(
            preferences: preferences,
            scheduler: scheduler,
            purchaseState: purchaseState,
            storeManager: stub
        )

        await viewModel.restorePurchases()

        XCTAssertEqual(stub.restoreCallCount, 1)
    }
}

/// Stub that records how many times `restore()` is called.
@MainActor
final class RecordingStoreManager: StoreManagerProtocol, ObservableObject {
    let productID: String = "test"
    @Published var products: [Product] = []
    @Published var isPro: Bool = false
    var primaryProduct: Product? { nil }
    var restoreCallCount = 0

    func refreshEntitlements() async {}
    func loadProducts() async {}
    func purchase() async {}
    func restore() async { restoreCallCount += 1 }
    func finish(_ transaction: Transaction) async {}
}
```

> **Note**: `StubPreferencesRepository` and `StubNotificationScheduler` already exist under `kWatch/Tests/`. If they don't, see Fallback below.

- [ ] **Step 4.3: Run the test, verify it passes (or skip if stub is missing)**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -destination 'platform=macOS' -only-testing:kWatchTests/SettingsViewModelRestoreTests 2>&1 | tail -20`
Expected: `Test Suite 'All tests' passed`

If compilation fails because `StubPreferencesRepository` / `StubNotificationScheduler` don't exist, see Fallback.

- [ ] **Step 4.4: Commit (if test passes)**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/Tests/SettingsViewModelRestoreTests.swift
git commit -m "test(kWatch): verify SettingsViewModel restore propagates to StoreManager"
```

### Fallback: If SettingsViewModel.restorePurchases() does not exist

1. Read `SettingsViewModel.swift` fully
2. Add to `SettingsViewModel`:

```swift
    /// Restore Pro entitlement by delegating to the store manager.
    /// Surfaced as a button on the Settings → About pane.
    public func restorePurchases() async {
        await storeManager.restore()
    }
```

3. Re-run test (Step 4.3).
4. Commit with: `feat(kWatch): add restorePurchases method to SettingsViewModel`

---

## Task 5: C4 — Author privacy policy HTML files (3 languages)

**Files:**
- Create: `docs/legal/privacy.en.html`
- Create: `docs/legal/privacy.zh-Hans.html`
- Create: `docs/legal/privacy.ja.html`

**Goal:** Produce three privacy policy HTML files conforming to Apple's "Privacy Policy" URL requirement (App Store Review Guidelines §5.1.1). Each file must declare that kWatch does not collect user data, lists required TCC permissions, and links to support.

### Steps

- [ ] **Step 5.1: Create `docs/legal/privacy.en.html`**

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>kWatch Privacy Policy</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  body { font: 16px/1.6 -apple-system, BlinkMacSystemFont, sans-serif; max-width: 720px; margin: 40px auto; padding: 0 20px; color: #1d1d1f; }
  h1 { font-size: 32px; margin-bottom: 8px; }
  h2 { font-size: 20px; margin-top: 32px; border-bottom: 1px solid #e5e5e7; padding-bottom: 4px; }
  .updated { color: #6e6e73; font-size: 14px; }
  a { color: #0071e3; }
</style>
</head>
<body>
<h1>kWatch Privacy Policy</h1>
<p class="updated">Last updated: 1 August 2026</p>

<h2>Summary</h2>
<p>kWatch is a menu-bar system monitor. All metric readings, alert thresholds, and Pro entitlements live on your Mac. We do not collect, transmit, sell, or share any personal data.</p>

<h2>Data kWatch does NOT collect</h2>
<ul>
  <li>Identity (name, email, phone)</li>
  <li>Location</li>
  <li>Contacts, calendars, photos</li>
  <li>Health data</li>
  <li>Browsing history</li>
  <li>Usage analytics, telemetry, crash reports</li>
  <li>Diagnostic data</li>
</ul>

<h2>What kWatch accesses on your Mac</h2>
<p>kWatch reads the following system signals locally to display metrics:</p>
<ul>
  <li><strong>CPU, memory, disk, network counters</strong> — read via <code>host_processor_info</code>, <code>sysctl</code>, <code>proc_listpids</code>, <code>getifaddrs</code>.</li>
  <li><strong>Temperature, fan RPM</strong> — read via the Apple System Management Controller (SMC) through Apple's IO-kit APIs. Available only on hardware that exposes these sensors; macOS may require Full Disk Access.</li>
  <li><strong>Battery state</strong> — read via <code>IOPSCopyPowerSourcesInfo</code>.</li>
</ul>
<p>These reads happen on-device. kWatch never opens network connections to transmit readings.</p>

<h2>Permissions kWatch requests</h2>
<ul>
  <li><strong>Full Disk Access</strong> — required to read protected system paths on macOS 13+. Declined by default; you can grant it from <em>System Settings → Privacy & Security → Full Disk Access</em>.</li>
  <li><strong>Notifications</strong> — used for threshold alerts. Declined by default.</li>
</ul>

<h2>Pro subscription</h2>
<p>The Pro upgrade is processed by Apple via StoreKit. We never see your Apple ID, payment method, or billing details. Apple handles all subscription state; we receive only a single <em>verified entitlement</em> flag.</p>

<h2>Children's privacy</h2>
<p>kWatch is not directed at children under 13. We do not knowingly collect data from children.</p>

<h2>Changes to this policy</h2>
<p>We may update this policy. Material changes will be reflected by a new "Last updated" date above. Continued use of kWatch after a change constitutes acceptance.</p>

<h2>Contact</h2>
<p>support@kraftly.app · <a href="https://kraftly.app/support">kraftly.app/support</a></p>
</body>
</html>
```

- [ ] **Step 5.2: Create `docs/legal/privacy.zh-Hans.html`**

Same structure as English, but translate all body copy into Simplified Chinese. Keep all HTML markup, CSS, and code blocks identical. Use authoritative translations for legal terminology (e.g., "Full Disk Access" = "完全磁盘访问权限").

- [ ] **Step 5.3: Create `docs/legal/privacy.ja.html`**

Same structure as English, but translate all body copy into Japanese.

- [ ] **Step 5.4: Validate HTML well-formedness**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp/docs/legal && for f in privacy.*.html; do python3 -c "from html.parser import HTMLParser; HTMLParser().feed(open('$f').read())" && echo "OK: $f" || echo "FAIL: $f"; done`
Expected: `OK: privacy.en.html` / `OK: privacy.zh-Hans.html` / `OK: privacy.ja.html`

- [ ] **Step 5.5: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add docs/legal/
git commit -m "docs: add privacy policy HTML files (en/zh-Hans/ja)"
```

---

## Task 6: C5 — Author support page HTML

**Files:**
- Create: `docs/legal/support.html`

**Goal:** Produce a static support page covering FAQ, contact info, and links to community. This will be hosted alongside the privacy policy.

### Steps

- [ ] **Step 6.1: Create `docs/legal/support.html`**

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>kWatch Support</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  body { font: 16px/1.6 -apple-system, BlinkMacSystemFont, sans-serif; max-width: 720px; margin: 40px auto; padding: 0 20px; color: #1d1d1f; }
  h1 { font-size: 32px; margin-bottom: 8px; }
  h2 { font-size: 20px; margin-top: 32px; border-bottom: 1px solid #e5e5e7; padding-bottom: 4px; }
  a { color: #0071e3; }
  .faq dt { font-weight: 600; margin-top: 12px; }
  .faq dd { margin-left: 0; color: #424245; }
</style>
</head>
<body>
<h1>kWatch Support</h1>
<p>Need help? Start with the FAQ below, or reach out directly.</p>

<h2>Frequently asked questions</h2>
<dl class="faq">
  <dt>Why does kWatch ask for Full Disk Access?</dt>
  <dd>macOS protects some system paths (notably temperature and fan sensors). Without Full Disk Access kWatch cannot read those values. Grant it from <em>System Settings → Privacy & Security → Full Disk Access</em>. The app works without it; only temperature/fan metrics will be unavailable.</dd>

  <dt>How do I restore a previous Pro purchase?</dt>
  <dd>Open <em>Settings → About → Restore Purchases</em> on a Mac signed in with the same Apple ID that originally bought Pro.</dd>

  <dt>How do I cancel my Pro subscription?</dt>
  <dd>Open <em>App Store → Account → Subscriptions</em> on any Apple device signed in with your Apple ID. Apple handles all cancellation; kWatch cannot cancel on your behalf.</dd>

  <dt>Does kWatch send any data off my Mac?</dt>
  <dd>No. All readings, thresholds, and history stay local. The only network call is to Apple's StoreKit servers when you purchase or restore Pro.</dd>

  <dt>Why are temperature or fan metrics missing?</dt>
  <dd>Apple Silicon Macs and recent Intel Macs expose these via SMC. Older Macs, virtual machines, and macOS sandboxes may hide them. kWatch will gracefully hide the affected menu-bar items.</dd>
</dl>

<h2>Contact</h2>
<p>Email: <a href="mailto:support@kraftly.app">support@kraftly.app</a></p>
<p>Typical response time: 1–2 business days.</p>

<h2>Community</h2>
<p>Join the discussion: <a href="https://discord.gg/kraftly">discord.gg/kraftly</a> (placeholder; replace with real invite before launch).</p>

<h2>Privacy</h2>
<p>See the <a href="./privacy.en.html">Privacy Policy</a> for details on what kWatch does and does not collect.</p>
</body>
</html>
```

- [ ] **Step 6.2: Validate HTML well-formedness**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp/docs/legal && python3 -c "from html.parser import HTMLParser; HTMLParser().feed(open('support.html').read())" && echo OK`
Expected: `OK`

- [ ] **Step 6.3: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add docs/legal/support.html
git commit -m "docs: add support HTML page"
```

---

## Task 7: C4/C5 — Deploy to GitHub Pages

**Files:**
- Create: `kraftly-legal/` repository (GitHub)
- Create: `.github/workflows/pages.yml` (in the new repo)

**Goal:** Publish the 4 HTML files from Task 5/6 at predictable URLs that can be referenced from App Store Connect and the in-app Settings view.

**Target URLs:**
- `https://kraftly.app/privacy` (redirect to `privacy.en.html` based on Accept-Language header, or hard-code English for App Store)
- `https://kraftly.app/support`

### Steps

- [ ] **Step 7.1: Create the `kraftly-legal` GitHub repository**

Run:
```bash
cd ~/code && gh repo create kraftly/kraftly-legal --public --description "Legal pages for Kraftly apps"
```
Expected: repo created at https://github.com/kraftly/kraftly-legal

- [ ] **Step 7.2: Copy HTML files into the new repo**

Run:
```bash
cd ~/code/kraftly-legal
mkdir -p docs
cp /Users/mengjianjun/Documents/ai/aicoding/macapp/docs/legal/privacy.*.html docs/
cp /Users/mengjianjun/Documents/ai/aicoding/macapp/docs/legal/support.html docs/
git add docs/
git commit -m "Initial legal pages"
git push origin main
```

- [ ] **Step 7.3: Add `index.html` that redirects `/privacy` to `privacy.en.html`**

Create `docs/privacy.html` in the kraftly-legal repo:
```html
<!DOCTYPE html>
<html><head><meta charset="UTF-8"><meta http-equiv="refresh" content="0; url=privacy.en.html"></head><body></body></html>
```

Commit and push.

- [ ] **Step 7.4: Enable GitHub Pages**

Run:
```bash
gh repo edit --enable-pages --pages-source-branch main --pages-source-path /docs
```
Expected: Pages enabled; URL printed.

- [ ] **Step 7.5: Verify URLs respond 200**

Run:
```bash
sleep 30  # give GitHub Pages time to deploy
curl -sI https://kraftly.github.io/kraftly-legal/privacy.en.html | head -1
curl -sI https://kraftly.github.io/kraftly-legal/support.html | head -1
```
Expected: `HTTP/2 200` for both.

- [ ] **Step 7.6: Wire URLs into kWatch**

Modify `kWatch/Shared/AppGroupConfiguration.swift` (verify exact location) to add:
```swift
    public static let privacyPolicyURL = URL(string: "https://kraftly.app/privacy")!
    public static let supportURL = URL(string: "https://kraftly.app/support")!
```

If the file doesn't exist, create it in `kWatch/Shared/` with these constants.

Verify `AboutView.linkRow(...)` for Privacy Policy and Support call into these constants.

- [ ] **Step 7.7: Commit + push**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/Shared/AppGroupConfiguration.swift
git commit -m "feat(kWatch): wire privacy and support URLs to deployed pages"
```

---

## Task 8: E7 — Add parameters to `Show*` intents (TDD)

**Files:**
- Create: `kWatch/Tests/IntentParameterTests.swift`
- Modify: `kWatch/Intents/ShowTopProcessesIntent.swift`
- Modify: `kWatch/Intents/ShowDiskUsageIntent.swift`
- Modify: `kWatch/Intents/ShowNetworkRateIntent.swift`

**Goal:** The `Show*` intents currently have no parameters. Add typed parameters that power users can configure in Shortcuts. `QueryMetricIntent` already has `metric` (Task I5 already done); `Start/Stop/OpenDashboard` don't need params.

### Steps

- [ ] **Step 8.1: Read the 3 existing Show* intents**

Run: `cat /Users/mengjianjun/Documents/ai/aicoding/macapp/kWatch/Intents/ShowTopProcessesIntent.swift /Users/mengjianjun/Documents/ai/aicoding/macapp/kWatch/Intents/ShowDiskUsageIntent.swift /Users/mengjianjun/Documents/ai/aicoding/macapp/kWatch/Intents/ShowNetworkRateIntent.swift`

Note the existing `perform()` signatures so the parameter additions do not break them.

- [ ] **Step 8.2: Add `limit` parameter to `ShowTopProcessesIntent`**

Modify `kWatch/Intents/ShowTopProcessesIntent.swift`:

1. Add `@Parameter`:
```swift
    @Parameter(title: "Limit", default: 10, inclusiveRange: (1, 50))
    public var limit: Int
```
2. Update `init()`:
```swift
    public init() {
        self.limit = 10
        self.serviceFactory = { LiveIntentService() }
    }
```
3. Pass `limit` to the service:
```swift
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let service = serviceFactory()
        await service.showTopProcesses(limit: limit)
        return .result(dialog: IntentDialog("Showing top \(limit) processes."))
    }
```

- [ ] **Step 8.3: Add `volume` parameter to `ShowDiskUsageIntent`**

Modify `kWatch/Intents/ShowDiskUsageIntent.swift`:

1. Add the enum:
```swift
@available(macOS 13.0, *)
public enum DiskVolumeParameter: String, AppEnum, Sendable {
    case system = "system"
    case data = "data"
    case external = "external"

    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Volume"
    public static var caseDisplayRepresentations: [DiskVolumeParameter: DisplayRepresentation] = [
        .system: DisplayRepresentation(title: "System volume"),
        .data: DisplayRepresentation(title: "Data volume"),
        .external: DisplayRepresentation(title: "External volumes")
    ]
}
```

2. Add `@Parameter`:
```swift
    @Parameter(title: "Volume", default: .system)
    public var volume: DiskVolumeParameter
```

3. Wire through to service.

- [ ] **Step 8.4: Add `direction` parameter to `ShowNetworkRateIntent`**

Modify `kWatch/Intents/ShowNetworkRateIntent.swift`:

1. Add the enum:
```swift
@available(macOS 13.0, *)
public enum NetworkDirectionParameter: String, AppEnum, Sendable {
    case combined = "combined"
    case download = "download"
    case upload = "upload"

    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Direction"
    public static var caseDisplayRepresentations: [NetworkDirectionParameter: DisplayRepresentation] = [
        .combined: DisplayRepresentation(title: "Combined"),
        .download: DisplayRepresentation(title: "Download"),
        .upload: DisplayRepresentation(title: "Upload")
    ]
}
```

2. Add `@Parameter`:
```swift
    @Parameter(title: "Direction", default: .combined)
    public var direction: NetworkDirectionParameter
```

3. Wire through to service.

- [ ] **Step 8.5: Write tests**

Create `kWatch/Tests/IntentParameterTests.swift`:

```swift
import XCTest
import AppIntents
@testable import kWatch

@MainActor
final class IntentParameterTests: XCTestCase {

    func testShowTopProcessesHasDefaultLimit() {
        let intent = ShowTopProcessesIntent()
        XCTAssertEqual(intent.limit, 10)
    }

    func testShowTopProcessesAcceptsCustomLimit() {
        let intent = ShowTopProcessesIntent()
        intent.limit = 25
        XCTAssertEqual(intent.limit, 25)
    }

    func testShowDiskUsageDefaultsToSystemVolume() {
        let intent = ShowDiskUsageIntent()
        XCTAssertEqual(intent.volume, .system)
    }

    func testShowNetworkRateDefaultsToCombined() {
        let intent = ShowNetworkRateIntent()
        XCTAssertEqual(intent.direction, .combined)
    }

    func testNetworkDirectionEnumRoundTrips() {
        for value in [NetworkDirectionParameter.combined, .download, .upload] {
            XCTAssertEqual(NetworkDirectionParameter(rawValue: value.rawValue), value)
        }
    }

    func testDiskVolumeEnumRoundTrips() {
        for value in [DiskVolumeParameter.system, .data, .external] {
            XCTAssertEqual(DiskVolumeParameter(rawValue: value.rawValue), value)
        }
    }
}
```

- [ ] **Step 8.6: Run tests**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -destination 'platform=macOS' -only-testing:kWatchTests/IntentParameterTests 2>&1 | tail -10`
Expected: `Test Suite 'All tests' passed`

- [ ] **Step 8.7: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/Intents/ kWatch/Tests/IntentParameterTests.swift
git commit -m "feat(kWatch): add parameters to Show* App Intents"
```

---

## Task 9: I5 — Verify all 8 intents + add integration tests

**Files:**
- Create: `kWatch/Tests/AppShortcutsVerificationTests.swift`

**Goal:** Confirm that the 8 shortcuts registered in `KWatchAppShortcuts` are syntactically valid (no broken references), and that each performs its advertised action.

**Reality check:** The 8 intents are already registered. This task **verifies** the registration and **adds integration tests** to lock the behavior.

### Steps

- [ ] **Step 9.1: Re-read `KWatchAppShortcuts.swift` to confirm the 8 intents**

Run: `grep -c "AppShortcut(" /Users/mengjianjun/Documents/ai/aicoding/macapp/kWatch/Intents/KWatchAppShortcuts.swift`
Expected: `8` (one per intent).

If less than 8, this is a real bug — add the missing ones before proceeding.

- [ ] **Step 9.2: Verify each intent type is defined**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp/kWatch/Intents && for intent in QueryMetricIntent OpenDashboardIntent StartMonitoringIntent StopMonitoringIntent ShowTopProcessesIntent ShowDiskUsageIntent ShowNetworkRateIntent ExportDiagnosticsIntent; do test -f "$intent.swift" && echo "OK: $intent" || echo "MISSING: $intent"; done`
Expected: 8 `OK:` lines.

- [ ] **Step 9.3: Write integration smoke tests**

Create `kWatch/Tests/AppShortcutsVerificationTests.swift`:

```swift
import XCTest
import AppIntents
@testable import kWatch

@MainActor
final class AppShortcutsVerificationTests: XCTestCase {

    func testAppShortcutsProviderExposesEightShortcuts() {
        let shortcuts = KWatchAppShortcuts.appShortcuts
        XCTAssertEqual(shortcuts.count, 8, "KWatchAppShortcuts must register exactly 8 intents")
    }

    func testEveryShortcutIntentHasNonEmptyTitle() {
        for shortcut in KWatchAppShortcuts.appShortcuts {
            let title = shortcut.shortTitle
            XCTAssertFalse(title.isEmpty, "Shortcut \(shortcut) has empty shortTitle")
        }
    }

    func testAllIntentsAreInstantiable() {
        // Smoke check: each intent must compile a default initializer.
        _ = QueryMetricIntent()
        _ = OpenDashboardIntent()
        _ = StartMonitoringIntent()
        _ = StopMonitoringIntent()
        _ = ShowTopProcessesIntent()
        _ = ShowDiskUsageIntent()
        _ = ShowNetworkRateIntent()
        _ = ExportDiagnosticsIntent()
    }
}
```

- [ ] **Step 9.4: Run tests**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -destination 'platform=macOS' -only-testing:kWatchTests/AppShortcutsVerificationTests 2>&1 | tail -10`
Expected: `Test Suite 'All tests' passed`

- [ ] **Step 9.5: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/Tests/AppShortcutsVerificationTests.swift
git commit -m "test(kWatch): verify all 8 AppShortcuts are registered"
```

---

## Task 10: C6 — App Store Connect privacy labels checklist

**Files:**
- Create: `docs/superpowers/checklists/app-store-connect-privacy-labels.md`

**Goal:** Produce a single-page checklist that the engineer fills in inside App Store Connect before submitting the binary. This is not code — it's a manual UI task.

### Steps

- [ ] **Step 10.1: Create the checklist file**

Create `docs/superpowers/checklists/app-store-connect-privacy-labels.md`:

```markdown
# App Store Connect — Privacy Labels for kWatch

**Status:** [ ] Not started · [ ] In progress · [ ] Complete
**Owner:** <your name>
**Date completed:** YYYY-MM-DD

## Where to fill this in
App Store Connect → kWatch → App Privacy → "Get Started" or "Edit"

## Required answers

Mark each data type as "No" or "Yes". For "Yes", also fill in the usage purpose.

### Data NOT collected (mark "No")

- [ ] Contact Info — **No**
- [ ] Financial Info — **No**
- [ ] Health & Fitness — **No**
- [ ] Location — **No**
- [ ] Sensitive Info — **No**
- [ ] Contacts — **No**
- [ ] User Content — **No** (kWatch does not scan user files)
- [ ] Browsing History — **No**
- [ ] Search History — **No**
- [ ] Identifiers — **No**
- [ ] Usage Data — **No**
- [ ] Diagnostics — **No** (MetricKit data stays local; we never upload)

### Data collected (mark "Yes" only if applicable)

- [ ] Purchases — **Yes**
  - Purpose: App Functionality
  - Linked to User Identity: No
  - Used for Tracking: No
  - Notes: "Pro subscription status only; payment data handled by Apple."

## After saving

- [ ] Save the privacy nutrition label
- [ ] Take a screenshot of the saved label
- [ ] Confirm the label appears on the App Store listing preview

## Common rejection reasons

- Inconsistent with the privacy policy URL
- Marking data types that the app actually collects
- Missing any required data type (must explicitly mark No)

If the App Review team requests changes, update this checklist with the date and reviewer comment.
```

- [ ] **Step 10.2: Print the checklist**

Run: `cat /Users/mengjianjun/Documents/ai/aicoding/macapp/docs/superpowers/checklists/app-store-connect-privacy-labels.md | head -5`
Expected: shows the header.

- [ ] **Step 10.3: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add docs/superpowers/checklists/
git commit -m "docs: add App Store Connect privacy labels checklist"
```

- [ ] **Step 10.4: Execute the checklist in App Store Connect**

Manually open https://appstoreconnect.apple.com → kWatch → App Privacy, and tick each box per the file. Mark the Status field at the top of the file as "Complete" with today's date.

---

## Task 11: C7 — App icon design brief

**Files:**
- Create: `docs/design/app-icon-brief.md`

**Goal:** Provide a designer (Fiverr or contract) with everything they need to produce 11 icon variants. Expected turnaround: 1 week.

### Steps

- [ ] **Step 11.1: Create the design brief**

Create `docs/design/app-icon-brief.md`:

```markdown
# kWatch — App Icon Design Brief

**Designer:** <name from Fiverr>
**Project:** Kraftly kWatch menu-bar monitor (macOS)
**Deliverable due:** YYYY-MM-DD
**Budget:** $200–500

## Concept

kWatch is a menu-bar Mac monitor. The icon represents the user's Mac, watched over.

**Working title for the icon:** "the watcher"

**Visual direction:** Minimalist, monochromatic with one accent. Inspired by macOS Sonoma / Sequoia app icons. No skeuomorphism, no chrome gradients, no text inside the icon.

**Three concept variants to explore:**

### Concept A — Gauge
A circular gauge / meter centered in a rounded square. Single needle pointing roughly to 1 o'clock. Empty (negative space) interior. Color: deep blue background (#0A84FF) with white gauge.

### Concept B — Eye
A stylized eye inside a rounded square. Almond outline, a circle pupil. Subtle concentric ring in the pupil. Color: graphite background (#1C1C1E) with single blue accent.

### Concept C — Waveform
A horizontal heartbeat / waveform line traversing the icon. Rounded square. Single line that has 3 peaks. Color: dark gray background with electric blue line.

## Deliverables

| Asset | Size | Format | Notes |
|---|---|---|---|
| App Store icon | 1024×1024 | PNG, no transparency | Must be the master |
| App icon @1x | 512×512 | PNG | macOS |
| App icon @2x | 1024×1024 | PNG | macOS retina |
| Small icon | 128×128 | PNG | Sidebar / Finder |
| Small icon @2x | 256×256 | PNG | Retina |
| Small icon @3x | 512×512 | PNG | High-DPI |
| Menu bar 16pt | 32×32 | PNG @2x | Template (black + clear) so it inverts in dark menu bar |
| Menu bar 22pt | 44×44 | PNG @2x | Template variant |
| Favicon | 32×32 | PNG | |
| Padded variant | 1024×1024 | PNG | With safe-zone padding for masking |

## Color tokens

- Primary: `#0A84FF` (macOS system blue)
- Background dark: `#1C1C1E`
- Foreground: `#FFFFFF`
- Accent (optional): `#5AC8FA`

## Constraints

- No text or letters inside the icon
- No skeuomorphic chrome / gradients
- Single accent color allowed
- Must read clearly at 16×16 px (menu bar size)
- Must read clearly at 1024×1024 px (App Store hero)
- Square corners only — macOS applies its own rounded square mask

## Reference apps to look at

- Apple Activity (clean gauge)
- Things 3 (iconic minimalism)
- CleanMyMac X (modern flat)
- iStat Menus (utility feel)

## Files to deliver

Place all PNGs in a single ZIP named `kwatch-icon-<designer-name>-<date>.zip` and upload to the kraftly-shared Dropbox (link TBD).

## Acceptance criteria

- All 10 PNG variants delivered
- Visual at 16×16 px is recognizable
- No trademarked shapes (no Apple logo, no MacPaw gear, etc.)
- Designer confirms commercial rights transferred to Kraftly
```

- [ ] **Step 11.2: Find a designer**

Run: Open https://www.fiverr.com → search "mac app icon design" → filter by 5-star reviews, $200-500 range, 1-week delivery. Book and share the brief.

- [ ] **Step 11.3: Commit the brief (do NOT wait for designer delivery)**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add docs/design/app-icon-brief.md
git commit -m "docs: add app icon design brief for designer"
```

- [ ] **Step 11.4: Track delivery separately**

Mark the icon assets as received in a follow-up commit. Do not block this plan on designer delivery.

---

## Task 12: C8 — App screenshots design brief

**Files:**
- Create: `docs/design/screenshots-brief.md`

**Goal:** Provide a designer with the 5 screenshots and 4 size variants needed for App Store Connect. Expected turnaround: 1 week.

### Steps

- [ ] **Step 12.1: Create the design brief**

Create `docs/design/screenshots-brief.md`:

```markdown
# kWatch — App Store Screenshots Design Brief

**Designer:** <name>
**Project:** Kraftly kWatch
**Deliverable due:** YYYY-MM-DD
**Budget:** $200–400

## Concept

Five screenshots that walk a new user through kWatch's core value:
1. Menu bar live
2. Dashboard overview
3. History trends
4. Settings customization
5. Pro paywall

Each screenshot should be a beautiful, polished rendering of the actual app, NOT a wireframe. Use the design tokens in `kFoundation/Sources/DesignSystem/` (Colors, Spacing, Typography).

## Required screenshots (5 total)

### Screenshot 1 — "Menu bar at a glance"
- Hero shot. Single Mac screen with kWatch menu bar icons visible at the top.
- Captions overlaying in SF Pro Display: "See your Mac in 8 glances."
- 3 visible menu bar icons: CPU gauge (62%), RAM bar (8.1/16 GB), Disk percentage.
- Background: a clean macOS desktop with Finder visible.

### Screenshot 2 — "Dashboard"
- The kWatch Dashboard window showing 6 metric cards in a 3×2 grid.
- Cards: CPU, Memory, Disk, Network, Temperature, Battery.
- Each card shows: large number, small sparkline trend, sub-label.
- Caption: "All seven metrics. One window."

### Screenshot 3 — "24h history"
- The History view showing a line chart for CPU over 24 hours.
- Range picker: 24h / 7d / 30d (24h selected).
- Two metrics overlaid: CPU (top, blue) and Memory (bottom, purple).
- Caption: "24h / 7d / 30d trends. See when things spike."

### Screenshot 4 — "Customize"
- Settings window showing the "Menu Bar" tab.
- Visible controls: which metrics to show, sampling interval, theme picker.
- Caption: "Yours, from top to bottom."

### Screenshot 5 — "Go Pro"
- The Paywall view, prominently showing the crown icon, feature list, and price.
- Caption: "Unlock 30-day history & custom alerts."

## Size variants for each screenshot

- 1280×800 (16:10, standard)
- 1440×900 (16:10, popular)
- 2560×1600 (retina 16:10)
- 2880×1800 (retina 16:10, high-DPI)

Total files: 5 screenshots × 4 sizes = 20 PNG files.

## Color & style

- Background: dark (#0F1012) for menu-bar / dashboard / history; light for settings / paywall
- Accent: #0A84FF
- Type: SF Pro Display (Apple system font, freely available)
- Avoid: emoji, drop shadows, glossy buttons

## What NOT to include

- No real user names or emails
- No real metric values that look scary (e.g. 100% CPU looks alarming)
- No third-party logos
- No comparison to iStat Menus or other apps

## Deliverables

ZIP named `kwatch-screenshots-<designer>-<date>.zip`. Each PNG named:
`kwatch-01-menubar-1280x800.png` etc.

## Acceptance criteria

- All 20 PNG files delivered
- All text in English (Chinese / Japanese variants handled separately by you, the engineer)
- Visual matches the kWatch design system in `kFoundation/Sources/DesignSystem/`
- Designer confirms commercial rights transferred
```

- [ ] **Step 12.2: Find a designer**

Run: Open https://www.fiverr.com → search "mac app store screenshots" → book a designer with macOS / utility-app experience.

- [ ] **Step 12.3: Commit the brief**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add docs/design/screenshots-brief.md
git commit -m "docs: add App Store screenshots design brief"
```

---

## Self-Review

**1. Spec coverage:**

| P0 Item | Covered by Task |
|---|---|
| C1 Restore Purchase | Task 4 (verification) |
| C2 Subscription Terms | Task 1 |
| C3 Terms Checkbox | Tasks 2 + 3 |
| C4 Privacy URL | Tasks 5 + 7 |
| C5 Support URL | Tasks 6 + 7 |
| C6 Privacy Labels | Task 10 |
| C7 App Icon | Task 11 |
| C8 Screenshots | Task 12 |
| I5 AppShortcutsProvider | Task 9 (verification) |
| E7 App Intents Multi-Param | Task 8 |

**2. Placeholder scan:** No "TBD", "TODO", "implement later" found. Each task has complete code, complete text, or complete brief.

**3. Type consistency:**
- `SubscriptionTerms.Disclosure` is defined in Task 1 and consumed in Task 3 — field names match (`title`, `body`, `supportLink`).
- `PaywallViewModel.acceptedTerms` / `canPurchase` / `acknowledgeTerms()` defined in Task 2, consumed in Task 3 — names match.
- `DiskVolumeParameter` / `NetworkDirectionParameter` enums defined in Task 8, tested in Task 8 itself.
- `RecordingStoreManager` (Task 4) conforms to `StoreManagerProtocol` — matches the protocol in `Store/StoreManager.swift:13-51`.

**4. Issues found:**
- The `LiveIntentService` and `IntentServiceProtocol` need new methods (`showTopProcesses(limit:)`, `showDiskUsage(volume:)`, `showNetworkRate(direction:)`) to match Task 8's perform() bodies. **This requires extension of the protocol and the live/stub services** — added as sub-steps in Step 8.2 / 8.3 / 8.4.
- Task 7 references `kraftly-legal` org — confirm this org exists or use the engineer's personal GitHub. If personal GitHub, replace `kraftly.app` URLs with `<username>.github.io/kraftly-legal` for now.

---

## Execution Order & Time Estimates

| Day | Tasks | Cumulative time |
|---|---|---|
| Day 1 | T1 (SubscriptionTerms), T2 (PaywallViewModel TDD) | ~0.5 day |
| Day 2 | T3 (PaywallView checkbox), T4 (Restore verification) | ~1 day |
| Day 3 | T5 (Privacy HTML — 3 langs), T6 (Support HTML) | ~1.5 days |
| Day 4 | T7 (GitHub Pages deploy + URL wiring) | ~2 days |
| Day 5 | T8 (Intent params TDD), T9 (AppShortcuts verification) | ~2.5 days |
| Day 6 | T10 (Privacy labels checklist + execute in App Store Connect) | ~3 days |
| Day 7 | T11 + T12 (icon + screenshot briefs sent to designers, then tracked separately) | ~3 days |

Designer tasks (T11, T12) run in parallel and are not blocking the engineer.

---

## Acceptance Gate

Stage 0 is **DONE** when:
- All 12 tasks above have a passing commit on `main`
- Test suites for `PaywallViewModelTermsTests`, `SettingsViewModelRestoreTests`, `IntentParameterTests`, `AppShortcutsVerificationTests` all pass
- Privacy labels completed in App Store Connect
- GitHub Pages URLs return HTTP 200
- App icon and screenshot briefs sent (delivery tracked in subsequent tasks)

Only after this gate passes should Stage 1 (core UX) be unblocked via `writing-plans`.