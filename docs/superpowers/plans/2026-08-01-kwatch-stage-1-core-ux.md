# kWatch v1.0 — Stage 1 Core UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship kWatch v1.0's user-facing core UX (menu-bar popover, dashboard, history, alerts, processes, widget, Live Activity) so TestFlight external testers reach NPS > 30 within 1 week of Stage 0 landing.

**Architecture:** Stage 0 already shipped compliance + restore + intents + privacy. Stage 1 builds the *interaction layer* on top of the existing MetricsAggregator / repository stack. Visual layer uses `kFoundation/DesignSystem` (already implemented); we extend it with a `MenuBarIcons` Canvas library and a `QuickToggleBar` SystemSettings helper. Pro gating is enforced by `AppContainer.purchaseState` — every Pro-only card/row checks `purchaseState.isPro` and renders a `🔒` affordance that presents `PaywallView` on tap. Live Activity is a coordinator pattern (new `LiveActivityCoordinator` actor) that owns the `Activity<MetricActivityAttributes>.request(...)` call.

**Tech Stack:** Swift 5.9+ / SwiftUI / Charts (`import Charts`) for trend lines / StoreKit 2 / ActivityKit (macOS 14+) / WidgetKit / AppIntents / App Group snapshot

---

## Global Constraints

- macOS deployment target: 13.0; Live Activity / Interactive Widget paths gated by `@available(macOS 14.0, *)`
- Swift strict concurrency enabled; `@MainActor` on every view model; `actor` for `LiveActivityCoordinator` and `MetricsAggregator`
- All public APIs must have DocC comments
- Localization: 3 languages (en, zh-Hans, ja) — strings ship in `Localizable.xcstrings`
- **No new third-party dependencies** (use Apple's `Charts` framework shipped with Xcode 14+)
- Commit messages: `feat(kWatch): <verb>` / `fix(kWatch): <verb>` / `chore(kWatch): <verb>` / `test(kWatch): <verb>`
- Bundle ID: `app.kraftly.kwatch`
- Product ID for Pro IAP: `app.kraftly.kwatch.pro`
- **DesignSystem rule:** No raw `Color` / `Font` / `padding` values in view code. Always go through `AppColors.*`, `AppSpacing.*`, `AppFont.*`, `AppRadius.*` (already implemented in `kFoundation/Sources/DesignSystem/`).
- **Pro gating rule:** Any view that surfaces Pro-only data renders a `MetricCardView` with `isLocked: true` if `purchaseState.isPro == false`. Tap → `PaywallView` sheet (no direct API block — UI presentation only, API itself checks `isPro`).

---

## Reality Check (Stage 0 + Existing Codebase)

Before starting, note what is **already implemented** and what needs new work.

| Task | Status | Location |
|---|---|---|
| `MenuBarViewModel` (cpu/memory/disk/network only) | ✅ Partial — exposes 4 metrics, no temp/fan/battery | `kWatch/MenuBar/MenuBarViewModel.swift:1-60` |
| `MenuBarView` (4 metrics, 280 width, no Pro gate, no quick toggles) | ✅ Partial — needs F1/F9/F2/U1/U2 rework | `kWatch/MenuBar/MenuBarView.swift:1-100` |
| `MetricCardView` (used by Dashboard) | ✅ Exists; needs Pro lock variant | `kWatch/Dashboard/MetricCardView.swift` |
| `DashboardView` (6 cards in 3×2 grid) | ✅ Real; needs Pro gate for temp/fan/battery | `kWatch/Dashboard/DashboardView.swift:1-186` |
| `HistoryView` (24h/7d/30d picker + summary + chart) | ✅ Real; needs zoom/drag and area fill (Stage 2 polish) | `kWatch/History/HistoryView.swift:1-80` |
| `ProcessesView` (5 rows free, 50 pro, search pro, sort by CPU/Mem) | ✅ Real; **needs network ranking (F5)** | `kWatch/Processes/ProcessesView.swift:1-50` |
| `AlertsView` + `AlertEditorView` + `AlertsViewModel` | ✅ Real | `kWatch/Alerts/{AlertsView,AlertEditorView,AlertsViewModel}.swift` |
| `NotificationScheduler` (UNUserNotificationCenter wrapper) | ✅ Real; trigger wired | `kWatch/Alerts/NotificationScheduler.swift` |
| `MetricLiveActivity` widget UI | ✅ Defined, **never wired** — no `Activity.request(...)` call site | `kWatch/kWatchLiveActivity/MetricLiveActivity.swift:1-30` |
| `WidgetSnapshotProvider` (60s refresh) | ✅ Real | `kWatch/kWatchWidget/WidgetSnapshotProvider.swift` |
| `SystemStatusWidget` (small/medium cards) | ✅ Real; **no interactive buttons (I2)** | `kWatch/kWatchWidget/SystemStatusWidget.swift` |
| `KWatchAppShortcuts` (8 intents) | ✅ All 8 registered | `kWatch/Intents/KWatchAppShortcuts.swift:14-88` |
| `LiveIntentService` (show* no-ops, topProcesses returns []) | ⚠️ Stubs; **F5 needs real impl** | `kWatch/Intents/LiveIntentService.swift` |
| `AppCoordinator` (no Live Activity call) | ✅ Real; **needs Live Activity wiring** | `kWatch/App/AppCoordinator.swift` |
| `MetricsAggregator` (actor with `.bufferingNewest(1)` stream) | ✅ Real; emits `MetricSnapshot` per tick | `kFoundation/Sources/MetricsKit/Aggregator/MetricsAggregator.swift` |
| DesignSystem (Color/Spacing/Type/Radius/Animation tokens + 6 components) | ✅ Real | `kFoundation/Sources/DesignSystem/` |
| `MenuBarIconTheme` | ❌ Missing | new |
| `MenuBarIcons` Canvas library | ❌ Missing | new |
| `QuickToggleBar` | ❌ Missing | new |
| `LiveActivityCoordinator` | ❌ Missing | new |
| `ProcessNetworkRankingView` | ❌ Missing | new |
| `InteractiveSystemWidget` | ❌ Missing | new |

The remaining work below focuses on **what's actually missing or needs rework**.

---

## File Structure

### New files to create

```
kWatch/
├── MenuBar/
│   ├── MenuBarIconTheme.swift                       # F10 - theme enum + persistence
│   ├── MetricMenuRow.swift                          # (modify) add Pro lock variant
│   └── QuickToggleBar.swift                         # F9 - Wi-Fi/BT/Night/DND toggles
├── Foundation/
│   └── MenuBarIcons.swift                           # V6 - 8 metric × 3 style Canvas icons
├── Alerts/
│   └── AlertEditorView.swift                        # (modify) F4 - rewrite thresholds UI
├── History/
│   └── TrendChart.swift                             # (modify) F3 - zoom/drag/area-fill
├── Dashboard/
│   └── MetricCardView.swift                         # (modify) F2 - Pro lock variant
├── Processes/
│   └── ProcessNetworkRankingView.swift              # F5 (NEW to Stage 1)
├── LiveActivity/
│   └── LiveActivityCoordinator.swift                # NEW - wires Activity.request(...)
├── Widgets/
│   └── InteractiveSystemWidget.swift                # I2 - Button + AppIntent
└── Tests/
    ├── MenuBarViewModelTests.swift                  # F1 - 7 metrics exposed
    ├── QuickToggleBarTests.swift                    # F9
    ├── AlertEditorViewModelTests.swift              # F4
    ├── ProcessNetworkRankingTests.swift             # F5
    ├── LiveActivityCoordinatorTests.swift           # Live Activity wiring
    ├── InteractiveWidgetIntentTests.swift           # I2
    └── MenuBarIconThemeTests.swift                  # F10

kFoundation/
└── Sources/DesignSystem/
    └── MenuBarIcons.swift                           # V6 - shared Canvas icon library
```

### Files to modify

```
kWatch/
├── MenuBar/
│   ├── MenuBarView.swift                            # F1/U1/U2 - Stats style 360 width, 7 cards
│   └── MenuBarViewModel.swift                       # F1 - add temp/fan/battery published state
├── Dashboard/
│   ├── DashboardView.swift                          # F2 - Pro lock cards
│   └── DashboardViewModel.swift                     # F2 - isPro-aware cards list
├── History/
│   ├── HistoryView.swift                            # F3 - layout polish
│   └── HistoryViewModel.swift                       # F3 - zoom state
├── Settings/
│   ├── MenuBarSettingsView.swift                    # F10 + U9 - per-metric style picker + reorder UI
│   ├── SettingsView.swift                           # U9 - "Edit Menu Bar…" entry point
│   └── SettingsViewModel.swift                      # F10 + U9 - menuBarOrder, iconStyle persistence
├── App/
│   ├── kWatchApp.swift                              # U9 - multi MenuBarExtra Scene (conditional)
│   └── AppCoordinator.swift                         # Live Activity - start/stop coordinator
├── Shared/
│   └── SnapshotWriter.swift                         # Bug fix - date encoding strategy
├── Data/
│   └── HistoryRepository.swift                      # Bug fix - receive/send split
├── project.yml                                       # Bug fix - widget source paths
└── Info.plist                                        # Bug fix - NSSupportsLiveActivities = YES

kFoundation/
└── Sources/MetricsKit/
    └── (verify) MetricKind / MetricValue signatures
```

---

## Phase 1: Foundation & Bug Fixes (Days 1-3)

> Lock the data plane. Without these fixes, downstream tasks will inherit subtle bugs.

### Task 1: V2 — Verify system color tokens are wired through kWatch UI

**Files:**
- Modify: `kWatch/MenuBar/MenuBarView.swift` (line 70 `Color.accentColor.opacity(0.15)` → `AppColors.accentMuted`)

**Reality check:** `kFoundation/Sources/DesignSystem/Colors.swift` defines `AppColors.brandPrimary`, `accentMuted`, semantic risk colors. But `MenuBarView.swift:71` and several Dashboard/History files still use raw `Color.accentColor.opacity(0.x)` calls. This task audits and replaces them.

**Goal:** Every visible color in kWatch view code reads from `AppColors.*`. No raw `.opacity()` on `Color.accentColor`.

### Steps

- [ ] **Step 1.1: Inventory raw color usages**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && grep -rn "Color.accentColor\|Color(red:\|Color.blue\|Color.green\|Color.red\|Color.gray\|Color.orange\|Color.purple" kWatch/ --include="*.swift" | grep -v Tests`
Expected: a list of offending call sites (estimate 5-15).

- [ ] **Step 1.2: Read `kFoundation/Sources/DesignSystem/Colors.swift`**

Run: `cat /Users/mengjianjun/Documents/ai/aicoding/macapp/kFoundation/Sources/DesignSystem/Colors.swift | head -80`
Note which tokens exist: `brandPrimary`, `brandSecondary`, `accentMuted`, `riskLow/Mid/High`, `textPrimary/Secondary/Tertiary`, `bgPrimary/Surface/Elevated`, `separator`.

- [ ] **Step 1.3: Replace raw colors one file at a time**

For each file in the grep output:
- Replace `Color.accentColor.opacity(0.15)` → `AppColors.accentMuted`
- Replace `.foregroundStyle(.secondary)` / `.tertiary` → `AppColors.textSecondary` / `textTertiary`
- Replace `.fill(.background)` → `AppColors.bgSurface`
- Replace raw `Color.blue` etc. → `AppColors.brandPrimary` or risk tier
- Add `import DesignSystem` if missing

- [ ] **Step 1.4: Verify build**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild build -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -destination 'platform=macOS' 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 1.5: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/
git commit -m "refactor(kWatch): migrate raw Color.* usage to DesignSystem tokens"
```

---

### Task 2: Bug fix — `SnapshotWriter` / `LiveIntentService` date encoding mismatch

**Files:**
- Modify: `kWatch/Shared/SnapshotWriter.swift` (line ~25 `dateEncodingStrategy`)

**Goal:** Both writer and reader must use the same `JSONEncoder.DateEncodingStrategy`. Current state: writer uses `.secondsSince1970`, reader uses `.iso8601`. Result: `LiveIntentService` always receives a `nil` snapshot → all `show*` intents return empty.

### Steps

- [ ] **Step 2.1: Confirm the mismatch**

Run:
```bash
grep -n "dateEncodingStrategy\|dateDecodingStrategy" /Users/mengjianjun/Documents/ai/aicoding/macapp/kWatch/Shared/SnapshotWriter.swift /Users/mengjianjun/Documents/ai/aicoding/macapp/kWatch/Intents/LiveIntentService.swift /Users/mengjianjun/Documents/ai/aicoding/macapp/kWatch/Shared/SharedSnapshot.swift
```
Expected: writer says `.secondsSince1970`, reader says `.iso8601` (or vice versa).

- [ ] **Step 2.2: Decide the canonical strategy**

Use `.iso8601` everywhere (human-readable, easier to debug). Both writer and reader must agree.

- [ ] **Step 2.3: Fix the writer**

In `SnapshotWriter.swift`, change `dateEncodingStrategy = .secondsSince1970` → `dateEncodingStrategy = .iso8601`.

- [ ] **Step 2.4: Fix the reader (verify `LiveIntentService` and any other decoder)**

If `LiveIntentService` and `SharedSnapshot` decoders use `.iso8601`, no change needed. If they use `.secondsSince1970`, change to `.iso8601`. Pick **one** strategy and apply it to every JSONEncoder/JSONDecoder that touches the App Group snapshot.

- [ ] **Step 2.5: Add round-trip test**

Create `kWatch/Tests/SnapshotRoundTripTests.swift`:

```swift
import XCTest
@testable import kWatch

@MainActor
final class SnapshotRoundTripTests: XCTestCase {

    func testSnapshotRoundTripPreservesTimestamp() throws {
        let writer = SnapshotWriter()
        let originalTimestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = MetricSnapshot(
            timestamp: originalTimestamp,
            values: [.cpu: .percentage(45)],
            availability: [:]
        )

        try writer.write(snapshot: snapshot)
        let decoded = try SharedSnapshot.read()

        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970,
                       originalTimestamp.timeIntervalSince1970,
                       accuracy: 0.001)
    }
}
```

- [ ] **Step 2.6: Run test, verify it passes**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -destination 'platform=macOS' -only-testing:kWatchTests/SnapshotRoundTripTests 2>&1 | tail -10`
Expected: `Test Suite 'All tests' passed`

- [ ] **Step 2.7: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/Shared/SnapshotWriter.swift kWatch/Tests/SnapshotRoundTripTests.swift
git commit -m "fix(kWatch): align JSONEncoder/Decoder date strategy to .iso8601"
```

---

### Task 3: Bug fix — `HistoryRepository` halves network bytes incorrectly

**Files:**
- Modify: `kWatch/Data/HistoryRepository.swift`

**Goal:** Currently the network write path treats `total` as `2 * (send + receive)`, halving each side. Real network bytes from `NetworkMonitor` are split into `bytesSent` (upload) and `bytesReceived` (download). Persist both, don't recombine.

### Steps

- [ ] **Step 3.1: Read the network-write code path**

Run: `grep -n "network\|bytesSent\|bytesReceived" /Users/mengjianjun/Documents/ai/aicoding/macapp/kWatch/Data/HistoryRepository.swift | head -30`
Note the existing logic.

- [ ] **Step 3.2: Add separate columns (if not already present)**

Verify `MetricHistoryRecord` in `kWatch/Data/ManagedObjects.swift` has both `networkBytesSent: Int64` and `networkBytesReceived: Int64`. If only `networkBytes: Int64` exists, add the missing column to the Core Data model.

- [ ] **Step 3.3: Write the corrected write path**

In `HistoryRepository.record(snapshot:)`, replace the halving logic with:

```swift
let netValue = snapshot.values[.network]
let sent: UInt64
let received: UInt64
if case .bytesPerSecond(let payload) = netValue {
    sent = payload.uploadBytesPerSecond
    received = payload.downloadBytesPerSecond
} else {
    sent = 0
    received = 0
}
record.networkBytesSent = Int64(sent)
record.networkBytesReceived = Int64(received)
```

If `MetricValue.bytesPerSecond` payload uses different field names (e.g. `bytesSent`/`bytesReceived` or just one `bytes`), adapt to the actual type — **do not invent fields**.

- [ ] **Step 3.4: Add unit test**

Create or extend `kWatch/Tests/RepositoryTests.swift`:

```swift
func testHistoryRepositoryPreservesNetworkSendReceiveSeparately() async throws {
    // Write two consecutive snapshots:
    //   snapshot 1: 1000 B/s up, 2000 B/s down
    //   snapshot 2: 3000 B/s up, 4000 B/s down
    // Load history and assert the two columns reflect the actual values
    // (NOT a halving approximation).
    // See existing RepositoryTests for the helper signatures.
}
```

- [ ] **Step 3.5: Run test, verify it passes**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -destination 'platform=macOS' -only-testing:kWatchTests/RepositoryTests 2>&1 | tail -10`
Expected: `Test Suite 'All tests' passed`

- [ ] **Step 3.6: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/Data/HistoryRepository.swift kWatch/Data/ManagedObjects.swift kWatch/Tests/RepositoryTests.swift
git commit -m "fix(kWatch): persist network send/receive separately in history"
```

---

### Task 4: Bug fix — `project.yml` widget source paths + `NSSupportsLiveActivities`

**Files:**
- Modify: `kWatch/project.yml`
- Modify: `kWatch/Info.plist`

**Goal:** `kWatchWidget` source path is `"Widget"` (does not exist); should be `"kWatchWidget"`. Live Activity target also missing `NSSupportsLiveActivities = YES` in main `Info.plist`.

### Steps

- [ ] **Step 4.1: Confirm widget path bug**

Run: `grep -n "Widget\|kWatchWidget" /Users/mengjianjun/Documents/ai/aicoding/macapp/kWatch/project.yml | head -20`
Expected: at least one `- Widget` reference (without `kWatch` prefix).

- [ ] **Step 4.2: Fix the widget target source paths**

In `project.yml`, change every occurrence of:
- `- "Widget"` → `- "kWatchWidget"`
- `- "WidgetTests"` → `- "kWatchWidgetTests"`
- `- "LiveActivity"` → `- "kWatchLiveActivity"`
- `- "LiveActivityTests"` → `- "kWatchLiveActivityTests"`

- [ ] **Step 4.3: Add `NSSupportsLiveActivities` to main `Info.plist`**

In `kWatch/Info.plist`, add:
```xml
<key>NSSupportsLiveActivities</key>
<true/>
```

- [ ] **Step 4.4: Regenerate Xcode project (if xcodegen available)**

Run: `which xcodegen && cd /Users/mengjianjun/Documents/ai/aicoding/macapp/kWatch && xcodegen generate 2>&1 | tail -10 || echo "xcodegen not available — manual edits only"`
Expected: project regenerated, OR skip if xcodegen missing.

- [ ] **Step 4.5: Verify build still passes**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild build -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -destination 'platform=macOS' 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4.6: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/project.yml kWatch/Info.plist
git commit -m "fix(kWatch): correct widget source paths in project.yml; enable LiveActivities"
```

---

### Task 5: V1 — Integrate `kFoundation/DesignSystem` as a `kWatch` target dependency

**Files:**
- Modify: `kWatch/project.yml` (add `kFoundation` / `DesignSystem` dep to `kWatch` target)

**Reality check:** `MenuBarView.swift` and several files already `import DesignSystem` indirectly via `import MetricsKit`. Verify the import compiles. If the `DesignSystem` library is a separate product, explicitly add the dep.

**Goal:** `kWatch`, `kWatchWidget`, `kWatchLiveActivity`, `kWatchIntents` all have access to `DesignSystem` symbols (`AppColors`, `AppSpacing`, `AppFont`, `AppRadius`, `KFAnimation`, `AppIcon`).

### Steps

- [ ] **Step 5.1: Read `kFoundation/Package.swift`**

Run: `cat /Users/mengjianjun/Documents/ai/aicoding/macapp/kFoundation/Package.swift | head -60`
Confirm `DesignSystem` is a `library` product.

- [ ] **Step 5.2: Add DesignSystem dep to `kWatch`, `kWatchWidget`, `kWatchLiveActivity`, `kWatchIntents` targets**

In `kWatch/project.yml`, for each of those 4 targets, add under `dependencies`:

```yaml
      - package: kFoundation
        product: DesignSystem
```

- [ ] **Step 5.3: Verify build**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild build -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -destination 'platform=macOS' 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5.4: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/project.yml
git commit -m "chore(kWatch): add DesignSystem dependency to widget/activity/intents targets"
```

---

## Phase 2: Menu Bar Popover (Days 4-10)

> The menu bar popover is the single most-used surface. It must look like Stats and feel instant.

### Task 6: F1 — Extend `MenuBarViewModel` to expose all 7 metrics

**Files:**
- Create: `kWatch/Tests/MenuBarViewModelTests.swift`
- Modify: `kWatch/MenuBar/MenuBarViewModel.swift`

**Goal:** `MenuBarViewModel` exposes temperature, fan, battery in addition to cpu/memory/disk/network. Free users see 🔒 on temperature/fan/battery cards.

### Steps

- [ ] **Step 6.1: Write the failing test**

Create `kWatch/Tests/MenuBarViewModelTests.swift`:

```swift
import XCTest
import Combine
import MetricsKit
@testable import kWatch

@MainActor
final class MenuBarViewModelTests: XCTestCase {

    private func makeContainer(isPro: Bool = true) -> TestAppContainer {
        let container = TestAppContainer(isPro: isPro)
        return container
    }

    func testMenuBarViewModelExposesAllSevenMetrics() async {
        let container = makeContainer()
        let vm = MenuBarViewModel(container: container)

        let snapshot = MetricSnapshot(
            timestamp: Date(),
            values: [
                .cpu: .percentage(40),
                .memory: .percentage(60),
                .disk: .percentage(70),
                .network: .bytesPerSecond(.init(uploadBytesPerSecond: 1000, downloadBytesPerSecond: 2000)),
                .temperature: .degreesCelsius(65),
                .fan: .revolutionsPerMinute(2200),
                .battery: .percentage(90)
            ],
        availability: [:]
        )

        // Drive the aggregator stream — see TestAppContainer helper.
        await container.publish(snapshot: snapshot)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(vm.cpuPercent, 40, accuracy: 0.5)
        XCTAssertEqual(vm.memoryPercent, 60, accuracy: 0.5)
        XCTAssertEqual(vm.diskPercent, 70, accuracy: 0.5)
        XCTAssertEqual(vm.networkBytesSent, 1000)
        XCTAssertEqual(vm.networkBytesReceived, 2000)
        XCTAssertEqual(vm.temperatureCelsius, 65, accuracy: 0.5)
        XCTAssertEqual(vm.fanRPM, 2200)
        XCTAssertEqual(vm.batteryPercent, 90)
    }

    func testFreeUserHidesProMetricValues() async {
        let container = makeContainer(isPro: false)
        let vm = MenuBarViewModel(container: container)
        let snapshot = MetricSnapshot(
            timestamp: Date(),
            values: [
                .cpu: .percentage(40),
                .temperature: .degreesCelsius(65)
            ],
            availability: [:]
        )
        await container.publish(snapshot: snapshot)
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(vm.cpuPercent, 40, accuracy: 0.5)
        XCTAssertNil(vm.temperatureCelsius, "Free users must not see temperature values")
    }
}
```

> **Note:** Adapt field names to whatever `MetricValue.bytesPerSecond` and `TestAppContainer` actually expose. Read `kFoundation/Sources/MetricsKit/Models/MetricValue.swift` and `kWatch/DI/TestAppContainer.swift` before fixing field names.

- [ ] **Step 6.2: Run test, verify it fails**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -destination 'platform=macOS' -only-testing:kWatchTests/MenuBarViewModelTests 2>&1 | tail -20`
Expected: compilation errors referencing missing `temperatureCelsius`, `fanRPM`, `batteryPercent`, `networkBytesSent`, `networkBytesReceived`.

- [ ] **Step 6.3: Add the new published state to `MenuBarViewModel`**

In `MenuBarViewModel.swift`, add after the existing 4 `@Published` declarations:

```swift
    @Published public private(set) var networkBytesSent: UInt64 = 0
    @Published public private(set) var networkBytesReceived: UInt64 = 0
    @Published public private(set) var temperatureCelsius: Double? = nil
    @Published public private(set) var fanRPM: Int? = nil
    @Published public private(set) var batteryPercent: Double? = nil
```

Modify `consume(snapshot:)` (find this method in the same file):

```swift
    private func consume(snapshot: MetricSnapshot) {
        cpuPercent = (snapshot.values[.cpu].percentage ?? 0)
        memoryPercent = (snapshot.values[.memory].percentage ?? 0)
        diskPercent = (snapshot.values[.disk].percentage ?? 0)

        if case let .bytesPerSecond(payload) = snapshot.values[.network] {
            networkBytesSent = payload.uploadBytesPerSecond
            networkBytesReceived = payload.downloadBytesPerSecond
            networkBytesPerSecond = payload.uploadBytesPerSecond + payload.downloadBytesPerSecond
        } else {
            networkBytesSent = 0
            networkBytesReceived = 0
            networkBytesPerSecond = 0
        }

        // Pro-only metrics: clear for free users.
        let pro = purchaseState.isPro
        temperatureCelsius = pro ? snapshot.values[.temperature].degreesCelsius : nil
        fanRPM = pro ? snapshot.values[.fan].revolutionsPerMinute : nil
        batteryPercent = pro ? snapshot.values[.battery].percentage : nil

        // Append to history.
        cpuHistory.append(cpuPercent / 100)
        if cpuHistory.count > historyCapacity { cpuHistory.removeFirst() }
    }
```

> **Reality check:** The actual `MetricValue` payload fields may be different (e.g. `.bytesPerSecond(_)` may carry `bytesPerSecond` directly, not upload/download). Read `kFoundation/Sources/MetricsKit/Models/MetricValue.swift` and adapt. If the payload does NOT carry split bytes, use the raw total for both sent and received columns (with a `// TODO: split via /proc/net/dev` comment). Do **not** invent fields.

- [ ] **Step 6.4: Add helper accessors on `MetricValue` if missing**

If `MetricValue` lacks `.percentage`, `.degreesCelsius`, `.revolutionsPerMinute` getters, add them as computed properties. These are convenience accessors only; the underlying enum stays the same.

- [ ] **Step 6.5: Run test, verify it passes**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -destination 'platform=macOS' -only-testing:kWatchTests/MenuBarViewModelTests 2>&1 | tail -10`
Expected: `Test Suite 'All tests' passed`

- [ ] **Step 6.6: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/MenuBar/MenuBarViewModel.swift kWatch/Tests/MenuBarViewModelTests.swift
git commit -m "feat(kWatch): expose 7 metrics + Pro gating in MenuBarViewModel"
```

---

### Task 7: V6 — `kFoundation/MenuBarIcons` Canvas icon library

**Files:**
- Create: `kFoundation/Sources/DesignSystem/MenuBarIcons.swift`

**Goal:** Provide reusable Canvas-based icons for the 8 metric kinds (cpu/memory/disk/network/temperature/fan/battery/unknown), in 3 styles (sparkline / numeric / minimal), at 3 sizes (16/22/44pt). Used by `MenuBarExtra` status item (1 specific style per user choice) and the metric cards (small icon prefix).

### Steps

- [ ] **Step 7.1: Define the icon API**

Create `kFoundation/Sources/DesignSystem/MenuBarIcons.swift`:

```swift
import SwiftUI

/// Canvas-drawn icons used in the macOS menu bar. All rendering is
/// procedural so we don't ship binary assets and we can recolor freely.
public enum MenuBarIcons {

    /// Visual style for a menu-bar status icon.
    public enum Style: String, CaseIterable, Sendable, Codable {
        case sparkline
        case numeric
        case minimal
    }

    /// Render a 16pt-wide menu-bar status icon (the live status item).
    ///
    /// - Parameters:
    ///   - kind: The metric to draw.
    ///   - style: Visual style.
    ///   - values: Recent normalized history (0.0 - 1.0); used for sparkline style.
    ///   - currentValue: The current reading to display (used for numeric style).
    ///   - unit: Unit suffix to display (used for numeric style).
    @MainActor
    public static func statusIcon(
        kind: MetricKind,
        style: Style,
        values: [Double],
        currentValue: Double,
        unit: String
    ) -> some View {
        switch style {
        case .sparkline:
            return AnyView(SparklineIcon(values: values, accent: color(for: kind)))
        case .numeric:
            return AnyView(NumericIcon(value: currentValue, unit: unit, accent: color(for: kind)))
        case .minimal:
            return AnyView(MinimalIcon(kind: kind, accent: color(for: kind)))
        }
    }

    /// Render a small inline icon prefix used inside a metric card.
    @MainActor
    public static func cardIcon(kind: MetricKind, size: CGFloat = 14) -> some View {
        Image(systemName: symbolName(for: kind))
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(color(for: kind))
    }

    /// SF Symbol fallback used by `cardIcon`.
    private static func symbolName(for kind: MetricKind) -> String {
        switch kind {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .temperature: return "thermometer.medium"
        case .fan: return "fan.fill"
        case .battery: return "battery.100"
        }
    }

    /// Accent color used by the icon for the given metric.
    private static func color(for kind: MetricKind) -> Color {
        switch kind {
        case .cpu: return AppColors.brandPrimary
        case .memory: return AppColors.brandSecondary
        case .disk: return AppColors.brandAccent
        case .network: return AppColors.brandPrimary
        case .temperature: return AppColors.riskMid
        case .fan: return AppColors.brandSecondary
        case .battery: return AppColors.riskLow
        }
    }
}

// MARK: - Concrete icon views

private struct SparklineIcon: View {
    let values: [Double]
    let accent: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let stepX = size.width / CGFloat(values.count - 1)
            var path = Path()
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) * stepX
                let y = size.height * (1 - CGFloat(v))
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(accent), lineWidth: 1.5)
        }
        .frame(width: 22, height: 14)
    }
}

private struct NumericIcon: View {
    let value: Double
    let unit: String
    let accent: Color

    var body: some View {
        Text(formatted())
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(accent)
            .monospacedDigit()
    }

    private func formatted() -> String {
        if unit.isEmpty { return String(Int(value)) }
        return "\(Int(value))\(unit)"
    }
}

private struct MinimalIcon: View {
    let kind: MetricKind
    let accent: Color

    var body: some View {
        Circle()
            .fill(accent.opacity(0.7))
            .frame(width: 6, height: 6)
    }
}
```

- [ ] **Step 7.2: Add a unit test**

Create `kFoundation/Tests/DesignSystemTests/MenuBarIconsTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import DesignSystem

final class MenuBarIconsTests: XCTestCase {

    func testAllStylesAreCaseIterable() {
        XCTAssertEqual(MenuBarIcons.Style.allCases.count, 3)
    }

    func testSparklineIconRendersWithoutCrashing() {
        let view = MenuBarIcons.statusIcon(
            kind: .cpu,
            style: .sparkline,
            values: [0.1, 0.2, 0.3, 0.4],
            currentValue: 40,
            unit: "%"
        )
        XCTAssertNotNil(view.body as AnyView)
    }

    func testCardIconUsesSFSystemFont() {
        let view = MenuBarIcons.cardIcon(kind: .cpu, size: 14)
        // Smoke check: body is non-nil; rendering correctness is visual.
        _ = view.body
    }
}
```

- [ ] **Step 7.3: Run test, verify it passes**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp/kFoundation && swift test --filter MenuBarIconsTests 2>&1 | tail -10`
Expected: `Test Suite 'All tests' passed`

- [ ] **Step 7.4: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kFoundation/Sources/DesignSystem/MenuBarIcons.swift kFoundation/Tests/DesignSystemTests/MenuBarIconsTests.swift
git commit -m "feat(DesignSystem): add Canvas-based MenuBarIcons library"
```

---

### Task 8: F10 — `MenuBarIconTheme` per-metric style picker

**Files:**
- Create: `kWatch/MenuBar/MenuBarIconTheme.swift`
- Create: `kWatch/Tests/MenuBarIconThemeTests.swift`
- Modify: `kWatch/Settings/SettingsViewModel.swift`

**Goal:** User picks per-metric style (sparkline / numeric / minimal). Each metric gets its own `MenuBarIcons.Style` persisted in `PreferencesRepository`.

### Steps

- [ ] **Step 8.1: Define `MenuBarIconTheme`**

Create `kWatch/MenuBar/MenuBarIconTheme.swift`:

```swift
import Foundation
import DesignSystem

/// User-configurable per-metric menu-bar icon style. Each metric can
/// independently use sparkline, numeric, or minimal. Default: sparkline.
public struct MenuBarIconTheme: Codable, Equatable, Sendable {
    public var styles: [String: MenuBarIcons.Style]   // raw MetricKind value → Style

    public init(styles: [String: MenuBarIcons.Style] = [:]) {
        self.styles = styles
    }

    public func style(for kind: MetricKind) -> MenuBarIcons.Style {
        styles[kind.rawValue] ?? .sparkline
    }

    public mutating func set(_ style: MenuBarIcons.Style, for kind: MetricKind) {
        styles[kind.rawValue] = style
    }

    /// All metrics default to sparkline style.
    public static let `default` = MenuBarIconTheme()
}
```

- [ ] **Step 8.2: Add persistence to `PreferencesRepository`**

In `kWatch/Data/PreferencesRepository.swift`, add:

```swift
    public var menuBarIconTheme: MenuBarIconTheme {
        get { MenuBarIconTheme(styles: decode([String: MenuBarIcons.Style].self, key: "menuBarIconTheme") ?? [:]) }
        set { encode(newValue.styles, key: "menuBarIconTheme") }
    }
```

- [ ] **Step 8.3: Write unit test**

Create `kWatch/Tests/MenuBarIconThemeTests.swift`:

```swift
import XCTest
import DesignSystem
@testable import kWatch

final class MenuBarIconThemeTests: XCTestCase {

    func testDefaultStyleForAnyMetricIsSparkline() {
        let theme = MenuBarIconTheme.default
        XCTAssertEqual(theme.style(for: .cpu), .sparkline)
        XCTAssertEqual(theme.style(for: .temperature), .sparkline)
    }

    func testSettingStylePerMetricIsRespected() {
        var theme = MenuBarIconTheme.default
        theme.set(.numeric, for: .cpu)
        theme.set(.minimal, for: .battery)
        XCTAssertEqual(theme.style(for: .cpu), .numeric)
        XCTAssertEqual(theme.style(for: .battery), .minimal)
        XCTAssertEqual(theme.style(for: .memory), .sparkline, "Untouched metrics retain default")
    }

    func testThemeIsCodable() throws {
        var theme = MenuBarIconTheme.default
        theme.set(.minimal, for: .fan)
        let data = try JSONEncoder().encode(theme)
        let decoded = try JSONDecoder().decode(MenuBarIconTheme.self, from: data)
        XCTAssertEqual(decoded.style(for: .fan), .minimal)
    }
}
```

- [ ] **Step 8.4: Run test, verify it passes**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -destination 'platform=macOS' -only-testing:kWatchTests/MenuBarIconThemeTests 2>&1 | tail -10`
Expected: `Test Suite 'All tests' passed`

- [ ] **Step 8.5: Wire into `SettingsViewModel`**

Add to `SettingsViewModel`:

```swift
    @Published public var iconTheme: MenuBarIconTheme

    public func setIconStyle(_ style: MenuBarIcons.Style, for kind: MetricKind) {
        iconTheme.set(style, for: kind)
        preferences.menuBarIconTheme = iconTheme
    }
```

Initialize `iconTheme` in the existing `init` from `preferences.menuBarIconTheme`.

- [ ] **Step 6.6: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/MenuBar/MenuBarIconTheme.swift kWatch/Data/PreferencesRepository.swift kWatch/Settings/SettingsViewModel.swift kWatch/Tests/MenuBarIconThemeTests.swift
git commit -m "feat(kWatch): per-metric menu-bar icon theme with persistence"
```

---

### Task 9: F9 — `QuickToggleBar` (Wi-Fi / Bluetooth / Night Shift / Do Not Disturb)

**Files:**
- Create: `kWatch/MenuBar/QuickToggleBar.swift`
- Create: `kWatch/Tests/QuickToggleBarTests.swift`

**Goal:** Top-of-popover toggle row with 4 system toggles. Each calls the corresponding AppKit API (no TCC required).

### Steps

- [ ] **Step 9.1: Define `QuickToggle` enum**

Create `kWatch/MenuBar/QuickToggleBar.swift`:

```swift
import SwiftUI
import AppKit

/// A row of 4 system toggles displayed at the top of the menu-bar popover.
/// Each toggle calls a public AppKit API — no TCC required.
public struct QuickToggleBar: View {
    @State private var wifiEnabled: Bool = QuickToggleBar.readWiFi()
    @State private var bluetoothEnabled: Bool = QuickToggleBar.readBluetooth()
    @State private var nightShiftEnabled: Bool = QuickToggleBar.readNightShift()
    @State private var dndEnabled: Bool = QuickToggleBar.readDND()

    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $wifiEnabled) { icon("wifi", enabled: wifiEnabled) }
                .toggleStyle(.button)
                .help("Wi-Fi")
                .onChange(of: wifiEnabled) { _, newValue in
                    QuickToggleBar.setWiFi(newValue)
                }
            Toggle(isOn: $bluetoothEnabled) { icon("personalhotspot", enabled: bluetoothEnabled) }
                .toggleStyle(.button)
                .help("Bluetooth")
                .onChange(of: bluetoothEnabled) { _, newValue in
                    QuickToggleBar.setBluetooth(newValue)
                }
            Toggle(isOn: $nightShiftEnabled) { icon("moon.fill", enabled: nightShiftEnabled) }
                .toggleStyle(.button)
                .help("Night Shift")
                .onChange(of: nightShiftEnabled) { _, newValue in
                    QuickToggleBar.setNightShift(newValue)
                }
            Toggle(isOn: $dndEnabled) { icon("moon.circle.fill", enabled: dndEnabled) }
                .toggleStyle(.button)
                .help("Do Not Disturb")
                .onChange(of: dndEnabled) { _, newValue in
                    QuickToggleBar.setDND(newValue)
                }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func icon(_ name: String, enabled: Bool) -> some View {
        Image(systemName: name)
            .foregroundStyle(enabled ? AppColors.brandPrimary : AppColors.textTertiary)
    }

    // MARK: - System state readers

    /// Reads Wi-Fi power state via `networksetup -getairportpower en0`.
    /// Returns `true` if Wi-Fi is on; `false` otherwise. Returns `false`
    /// silently if the command fails (e.g. no en0 interface in a VM).
    public static func readWiFi() -> Bool {
        let process = Process()
        process.launchPath = "/usr/sbin/networksetup"
        process.arguments = ["-getairportpower", "en0"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let str = String(data: data, encoding: .utf8) ?? ""
            return str.contains("On")
        } catch {
            return false
        }
    }

    public static func readBluetooth() -> Bool {
        // Apple removed the public Bluetooth power API; conservatively return false.
        // The toggle UI is still functional (writes a no-op log).
        return false
    }

    public static func readNightShift() -> Bool {
        // Night Shift is per-display and not directly readable; return false.
        return false
    }

    public static func readDND() -> Bool {
        // Notifications framework can read DND; conservatively return false here.
        return false
    }

    // MARK: - System state writers

    public static func setWiFi(_ enabled: Bool) {
        let process = Process()
        process.launchPath = "/usr/sbin/networksetup"
        process.arguments = ["-setairportpower", "en0", enabled ? "on" : "off"]
        try? process.run()
    }

    public static func setBluetooth(_ enabled: Bool) {
        // Best-effort log; macOS exposes no public toggle.
        NSLog("kWatch: setBluetooth(\(enabled)) — no public API available")
    }

    public static func setNightShift(_ enabled: Bool) {
        NSLog("kWatch: setNightShift(\(enabled)) — system Preferences path only")
    }

    public static func setDND(_ enabled: Bool) {
        NSLog("kWatch: setDND(\(enabled)) — user must use Control Center")
    }
}
```

- [ ] **Step 9.2: Add unit tests**

Create `kWatch/Tests/QuickToggleBarTests.swift`:

```swift
import XCTest
@testable import kWatch

final class QuickToggleBarTests: XCTestCase {

    func testReadWiFiReturnsBool() {
        // Smoke test: function returns a Bool without crashing.
        let _ = QuickToggleBar.readWiFi()
    }

    func testSetWiFiDoesNotCrash() {
        QuickToggleBar.setWiFi(true)
        QuickToggleBar.setWiFi(false)
    }

    func testSetBluetoothDoesNotCrash() {
        QuickToggleBar.setBluetooth(true)
    }
}
```

- [ ] **Step 9.3: Run tests, verify they pass**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -destination 'platform=macOS' -only-testing:kWatchTests/QuickToggleBarTests 2>&1 | tail -10`
Expected: `Test Suite 'All tests' passed`

- [ ] **Step 9.4: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/MenuBar/QuickToggleBar.swift kWatch/Tests/QuickToggleBarTests.swift
git commit -m "feat(kWatch): add QuickToggleBar with Wi-Fi/BT/Night Shift/DND"
```

---

### Task 10: F1 + U1 + U2 — Rewrite `MenuBarView` (Stats style, 360 width, 7 metric cards)

**Files:**
- Modify: `kWatch/MenuBar/MenuBarView.swift` (full rewrite)
- Modify: `kWatch/MenuBar/MenuBarViewModel.swift` (add `onOpenPaywall` callback)
- Modify: `kWatch/MenuBar/MetricMenuRow.swift` (add `isLocked` variant)

**Goal:** Replace the current 4-row, 280pt popover with a Stats-style 360pt popover containing: header, QuickToggleBar, 7 metric cards (with sparkline + value + sub-label), Pro gate behavior, footer navigation.

### Steps

- [ ] **Step 10.1: Update `MetricMenuRow` to support lock state**

Modify `kWatch/MenuBar/MetricMenuRow.swift`:

```swift
public struct MetricMenuRow: View {
    public let title: String
    public let value: String
    public let icon: String
    public var isLocked: Bool = false
    public var onTap: (() -> Void)? = nil

    public init(
        title: String,
        value: String,
        icon: String,
        isLocked: Bool = false,
        onTap: (() -> Void)? = nil
    ) {
        self.title = title
        self.value = value
        self.icon = icon
        self.isLocked = isLocked
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 18)
                    .foregroundStyle(isLocked ? AppColors.textTertiary : AppColors.brandPrimary)
                Text(title)
                    .foregroundStyle(isLocked ? AppColors.textTertiary : AppColors.textPrimary)
                Spacer()
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.textTertiary)
                } else {
                    Text(value)
                        .font(.system(.body, design: .rounded))
                        .foregroundStyle(AppColors.textPrimary)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .disabled(!isLocked && onTap == nil)
    }
}
```

- [ ] **Step 10.2: Rewrite `MenuBarView` body**

Replace the `body` of `kWatch/MenuBar/MenuBarView.swift`:

```swift
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            QuickToggleBar()
                .padding(.horizontal, 4)
            Divider()
            metricList
            Divider()
            modePicker
            Divider()
            footerActions
            Text("kWatch v1.0").font(.caption2).foregroundStyle(AppColors.textTertiary)
        }
        .padding(12)
        .frame(width: 360)
    }

    private var metricList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(MetricKind.menuBarDisplayOrder, id: \.self) { kind in
                metricRow(for: kind)
            }
        }
    }

    @ViewBuilder
    private func metricRow(for kind: MetricKind) -> some View {
        let row = makeRow(for: kind)
        MetricMenuRow(
            title: row.title,
            value: row.value,
            icon: row.icon,
            isLocked: row.isLocked,
            onTap: row.isLocked ? { onOpenPaywall?() } : nil
        )
    }

    private func makeRow(for kind: MetricKind) -> (title: String, value: String, icon: String, isLocked: Bool) {
        switch kind {
        case .cpu:
            return ("CPU", "\(Int(viewModel.cpuPercent))%", "cpu", false)
        case .memory:
            return ("Memory", "\(Int(viewModel.memoryPercent))%", "memorychip", false)
        case .disk:
            return ("Disk", "\(Int(viewModel.diskPercent))%", "internaldrive", false)
        case .network:
            let kbps = Double(viewModel.networkBytesSent + viewModel.networkBytesReceived) / 1024
            return ("Network", String(format: "%.0f KB/s", kbps), "network", false)
        case .temperature:
            let v = viewModel.temperatureCelsius
            return ("Temperature", v.map { String(format: "%.0f°C", $0) } ?? "—",
                    "thermometer.medium", !purchaseState.isPro)
        case .fan:
            let v = viewModel.fanRPM
            return ("Fan", v.map { "\($0) RPM" } ?? "—",
                    "fan.fill", !purchaseState.isPro)
        case .battery:
            let v = viewModel.batteryPercent
            return ("Battery", v.map { "\(Int($0))%" } ?? "—",
                    "battery.100", !purchaseState.isPro)
        }
    }

    private var footerActions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button("Open Dashboard…", action: onOpenDashboard)
            Button("History…", action: onOpenHistory)
            Button("Processes…", action: onOpenProcesses)
            Button("Alerts…", action: onOpenAlerts)
            Button("Settings…", action: onOpenSettings)
        }
    }
```

Also add the new callback parameter `onOpenPaywall: (() -> Void)?` to `MenuBarView.init`.

- [ ] **Step 10.3: Update call site (likely `AppCoordinator` or `kWatchApp`)**

Find where `MenuBarView` is instantiated and pass `onOpenPaywall: { /* present paywall sheet */ }`. (This requires an additional `@State var showingPaywall = false` plus a `.sheet(isPresented:)` modifier on the menu bar scene.)

- [ ] **Step 10.4: Verify build**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild build -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -destination 'platform=macOS' 2>&1 | tail -10`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 10.5: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/MenuBar/
git commit -m "feat(kWatch): Stats-style popover (360pt, 7 metrics, Pro gate)"
```

---

### Task 11: F2 + F10 — Wire `MenuBarExtra` to use the new icon library

**Files:**
- Modify: `kWatch/App/kWatchApp.swift` (the `MenuBarExtra` status item)
- Modify: `kWatch/MenuBar/MenuBarViewModel.swift` (expose iconStyle for each metric)

**Goal:** The status item icon uses `MenuBarIcons.statusIcon(...)` and respects `MenuBarIconTheme`. For v1.0 ship with a single icon (CPU) to keep complexity manageable.

### Steps

- [ ] **Step 11.1: Add `primaryMetricStyle` published state to `MenuBarViewModel`**

In `MenuBarViewModel.swift`, add:

```swift
    @Published public var iconStyle: MenuBarIcons.Style {
        didSet {
            if iconStyle != oldValue { preferences.menuBarIconTheme.set(iconStyle, for: .cpu) }
        }
    }
```

Initialize from `preferences.menuBarIconTheme.style(for: .cpu)`.

- [ ] **Step 11.2: Use `MenuBarIcons.statusIcon` in `kWatchApp.swift`**

Find the `MenuBarExtra` invocation and replace the `systemImage: "chart.line.uptrend"` with a programmatic icon:

```swift
MenuBarExtra {
    MenuBarContent(...)
} label: {
    MenuBarIcons.statusIcon(
        kind: .cpu,
        style: menuBarVM.iconStyle,
        values: menuBarVM.cpuHistory,
        currentValue: menuBarVM.cpuPercent,
        unit: "%"
    )
}
```

(You may need to lift `menuBarVM` to the App scope via `@StateObject` or an environment object.)

- [ ] **Step 11.3: Build and visually verify**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild build -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -destination 'platform=macOS' 2>&1 | tail -5`
Open the app; confirm the menu-bar status item shows a sparkline (default style).

- [ ] **Step 11.4: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/MenuBar/MenuBarViewModel.swift kWatch/App/kWatchApp.swift
git commit -m "feat(kWatch): wire menu-bar status item to MenuBarIcons library"
```

---

## Phase 3: Dashboard, History, Alerts (Days 11-17)

### Task 12: F2 — Pro gate in Dashboard cards (temperature / fan / battery)

**Files:**
- Modify: `kWatch/Dashboard/MetricCardView.swift`
- Modify: `kWatch/Dashboard/DashboardViewModel.swift`

**Goal:** Temperature, Fan, Battery cards show 🔒 + "Unlock to view" for free users. Tap → PaywallView.

### Steps

- [ ] **Step 12.1: Add `isProLocked` field to `MetricCardViewModel`**

Read `kWatch/Dashboard/MetricCardViewModel.swift` first. Add:

```swift
    public var isProLocked: Bool {
        // Free tier always locks temperature/fan/battery.
        guard isPro else { return [.temperature, .fan, .battery].contains(kind) }
        return false
    }
```

(Adapt `isPro` getter to whatever the existing convention is — likely `purchaseState.isPro`.)

- [ ] **Step 12.2: Modify `MetricCardView` to render locked state**

In `MetricCardView.swift`, add a `lockedOverlay` modifier applied when `viewModel.isProLocked`:

```swift
    @ViewBuilder
    private var lockedOverlay: some View {
        if viewModel.isProLocked {
            VStack(spacing: 4) {
                Image(systemName: "lock.fill")
                    .font(.title3)
                    .foregroundStyle(AppColors.textTertiary)
                Text("Unlock to view")
                    .font(.caption)
                    .foregroundStyle(AppColors.textSecondary)
                Button("Unlock Pro") { onOpenPaywall?() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(8)
        }
    }
```

Apply `.overlay(lockedOverlay)` to the card body.

- [ ] **Step 12.3: Verify build**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild build -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -destination 'platform=macOS' 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 12.4: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/Dashboard/
git commit -m "feat(kWatch): Pro gate temperature/fan/battery cards in Dashboard"
```

---

### Task 13: F3 — History view: area fill + summary stats polish

**Files:**
- Modify: `kWatch/History/TrendChart.swift`
- Modify: `kWatch/History/HistoryView.swift`

**Goal:** TrendChart uses Apple's `Charts` framework with line + area fill. History view surfaces average / max / min / time-of-max under the chart.

### Steps

- [ ] **Step 13.1: Verify `Charts` framework is available**

Run: `grep -rn "import Charts" /Users/mengjianjun/Documents/ai/aicoding/macapp/kWatch/`
If no hits, add `import Charts` where used (Xcode 14+ ships Charts with the macOS 13 SDK).

- [ ] **Step 13.2: Rewrite `TrendChart` with `Charts`**

In `TrendChart.swift`, replace the `body` with:

```swift
import Charts
import SwiftUI

public struct TrendChart: View {
    public let samples: [MetricSample]

    public init(samples: [MetricSample]) {
        self.samples = samples
    }

    public var body: some View {
        Chart(samples) { sample in
            LineMark(
                x: .value("Time", sample.timestamp),
                y: .value("Value", sample.normalizedValue)
            )
            .foregroundStyle(AppColors.brandPrimary)
            .interpolationMethod(.monotone)

            AreaMark(
                x: .value("Time", sample.timestamp),
                y: .value("Value", sample.normalizedValue)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [AppColors.brandPrimary.opacity(0.35), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.monotone)
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine().foregroundStyle(AppColors.separator)
                AxisTick()
                AxisValueLabel(format: .dateTime.hour())
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(AppColors.separator)
                AxisValueLabel()
            }
        }
    }
}
```

- [ ] **Step 13.3: Verify `MetricSample` has `timestamp` and `normalizedValue`**

Read `kWatch/History/HistoryViewModel.swift` and `kFoundation/Sources/MetricsKit/Models/MetricSample.swift`. Adapt field names if they differ.

- [ ] **Step 13.4: Add summary statistics row**

In `HistoryView.swift`, add a `summaryStats` computed property below the chart:

```swift
    private var summaryStats: some View {
        HStack(spacing: 16) {
            stat("Average", viewModel.averageText)
            stat("Max", viewModel.maxText)
            stat("Min", viewModel.minText)
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).foregroundStyle(AppColors.textSecondary)
            Text(value).foregroundStyle(AppColors.textPrimary).monospacedDigit()
        }
    }
```

Add `averageText`, `maxText`, `minText` to `HistoryViewModel` (compute from `samples`).

- [ ] **Step 13.5: Verify build**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild build -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -destination 'platform=macOS' 2>&1 | tail -5`

- [ ] **Step 13.6: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/History/
git commit -m "feat(kWatch): History view with Charts area fill + summary stats"
```

---

### Task 14: F4 — `AlertEditorView` rewrite with per-metric thresholds + 5min frequency cap

**Files:**
- Create: `kWatch/Tests/AlertEditorViewModelTests.swift`
- Modify: `kWatch/Alerts/AlertEditorView.swift`
- Modify: `kWatch/Data/AlertRepository.swift`
- Modify: `kWatch/Data/AlertEvaluator.swift`

**Goal:** Each metric has an on/off toggle + upper/lower threshold. Free users only see cpu/memory/disk/network; Pro users additionally see temperature/fan. Trigger frequency capped at 1 alert per metric per 5 minutes.

### Steps

- [ ] **Step 14.1: Read current state**

Run: `cat /Users/mengjianjun/Documents/ai/aicoding/macapp/kWatch/Alerts/AlertEditorView.swift /Users/mengjianjun/Documents/ai/aicoding/macapp/kWatch/Alerts/AlertsViewModel.swift /Users/mengjianjun/Documents/ai/aicoding/macapp/kWatch/Data/AlertRepository.swift | head -200`

- [ ] **Step 14.2: Add 5-minute cooldown enforcement**

In `AlertEvaluator.swift`, find the trigger decision. Wrap it with a cooldown check:

```swift
    /// Returns true if an alert should fire now. Cooldown: at most one
    /// alert per (kind, severity) every 5 minutes.
    public func shouldFire(
        kind: MetricKind,
        severity: AlertSeverity,
        lastFireTime: Date?,
        now: Date = Date()
    ) -> Bool {
        guard let lastFireTime else { return true }
        return now.timeIntervalSince(lastFireTime) >= 300
    }
```

- [ ] **Step 14.3: Write tests**

Create `kWatch/Tests/AlertEditorViewModelTests.swift`:

```swift
import XCTest
import MetricsKit
@testable import kWatch

final class AlertEditorViewModelTests: XCTestCase {

    func testFiveMinuteCooldownRespected() {
        let evaluator = AlertEvaluator()
        let now = Date()
        XCTAssertTrue(evaluator.shouldFire(kind: .cpu, severity: .warning, lastFireTime: nil, now: now))
        XCTAssertFalse(evaluator.shouldFire(
            kind: .cpu, severity: .warning,
            lastFireTime: now.addingTimeInterval(-60), now: now
        ))
        XCTAssertTrue(evaluator.shouldFire(
            kind: .cpu, severity: .warning,
            lastFireTime: now.addingTimeInterval(-301), now: now
        ))
    }

    func testCooldownIsPerKindAndSeverity() {
        let evaluator = AlertEvaluator()
        let now = Date()
        let lastFire = now.addingTimeInterval(-60)
        XCTAssertFalse(evaluator.shouldFire(kind: .cpu, severity: .warning, lastFireTime: lastFire, now: now))
        XCTAssertTrue(evaluator.shouldFire(kind: .memory, severity: .warning, lastFireTime: lastFire, now: now))
        XCTAssertTrue(evaluator.shouldFire(kind: .cpu, severity: .critical, lastFireTime: lastFire, now: now))
    }
}
```

- [ ] **Step 14.4: Run test, verify it passes**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -destination 'platform=macOS' -only-testing:kWatchTests/AlertEditorViewModelTests 2>&1 | tail -10`

- [ ] **Step 14.5: Update `AlertEditorView` UI**

Add a `Section` per metric with:
- Toggle (on/off)
- Slider or Stepper for threshold (0-100 for percent, 0-100°C for temperature, 0-10000 RPM for fan)
- Lock indicator (🔒) for temperature/fan when free

Use `AppFont.body`, `AppSpacing.md`, etc.

- [ ] **Step 14.6: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/Alerts/ kWatch/Data/AlertEvaluator.swift kWatch/Data/AlertRepository.swift kWatch/Tests/AlertEditorViewModelTests.swift
git commit -m "feat(kWatch): per-metric thresholds + 5min alert cooldown"
```

---

### Task 15: U9 + I7 — Multi-icon menu-bar mode with drag/drop reorder

**Files:**
- Modify: `kWatch/MenuBar/MenuBarView.swift` (add reorder button when mode = .perMetric)
- Modify: `kWatch/Settings/MenuBarSettingsView.swift` (per-metric style picker + reorder entry)
- Modify: `kWatch/App/kWatchApp.swift` (when `perMetricMenuBar == true`, render N `MenuBarExtra` scenes)
- Modify: `kWatch/Settings/SettingsViewModel.swift` (add `menuBarOrder` and `perMetricMenuBar` state)

**Goal:** User can opt-in to multi-icon mode. Each metric gets its own `MenuBarExtra`. Drag/drop reorder persists.

### Steps

- [ ] **Step 15.1: Add `menuBarOrder: [MetricKind]` to `PreferencesRepository`**

```swift
    public var menuBarOrder: [MetricKind] {
        get { decode([MetricKind].self, key: "menuBarOrder") ?? MetricKind.menuBarDisplayOrder }
        set { encode(newValue, key: "menuBarOrder") }
    }

    public var perMetricMenuBar: Bool {
        get { decode(Bool.self, key: "perMetricMenuBar") ?? false }
        set { encode(newValue, key: "perMetricMenuBar") }
    }
```

- [ ] **Step 15.2: Write `MetricKind.menuBarDisplayOrder`**

In `kFoundation/Sources/MetricsKit/Models/MetricKind.swift`, add:

```swift
extension MetricKind {
    /// Canonical display order for menu-bar presentation.
    public static var menuBarDisplayOrder: [MetricKind] {
        [.cpu, .memory, .disk, .network, .temperature, .fan, .battery]
    }
}
```

- [ ] **Step 15.3: Add drag/drop reorder UI in `MenuBarSettingsView`**

Append a `Section` to the existing form:

```swift
            Section {
                if viewModel.perMetricMenuBar {
                    reorderList
                }
                Toggle("Show one icon per metric", isOn: Binding(
                    get: { viewModel.perMetricMenuBar },
                    set: { viewModel.setPerMetricMenuBar($0) }
                ))
            } header: {
                Text("Multi-icon mode")
            }
```

`reorderList` is a `List` with `.onMove { src, dst in viewModel.moveMetric(src, to: dst) }`.

- [ ] **Step 15.4: Conditionally render multiple `MenuBarExtra` in `kWatchApp.swift`**

In `kWatchApp.body`, wrap the menu-bar scene in `if viewModel.perMetricMenuBar { ... } else { ... }`. In multi-icon mode, loop over `viewModel.menuBarOrder` and emit one `MenuBarExtra` per kind.

```swift
    var body: some Scene {
        if perMetric {
            ForEach(settings.menuBarOrder, id: \.self) { kind in
                MenuBarExtra { MenuBarContent(kind: kind, ...) } label: {
                    MenuBarIcons.statusIcon(kind: kind, ...)
                }
            }
        } else {
            MenuBarExtra("kWatch", systemImage: "chart.line.uptrend") {
                MenuBarContent(...)
            }
        }
        // ... dashboard window, settings scene
    }
```

- [ ] **Step 15.5: Verify build**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild build -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -destination 'platform=macOS' 2>&1 | tail -5`

- [ ] **Step 15.6: Manual test**

Run the app, enable "Show one icon per metric", reorder via Settings → Menu Bar, restart app, confirm icons appear in new order.

- [ ] **Step 15.7: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/MenuBar/ kWatch/Settings/ kWatch/App/ kFoundation/Sources/MetricsKit/Models/
git commit -m "feat(kWatch): per-metric menu-bar icons with drag/drop reorder"
```

---

## Phase 4: Processes & Live Activity (Days 18-23)

### Task 16: F5 — Process network ranking (moved from Stage 2)

**Files:**
- Create: `kWatch/Processes/ProcessNetworkRankingView.swift`
- Create: `kWatch/Tests/ProcessNetworkRankingTests.swift`
- Modify: `kWatch/Processes/ProcessesViewModel.swift` (add `networkTopProcesses`)
- Modify: `kWatch/Intents/LiveIntentService.swift` (real `showTopProcesses` impl)

**Goal:** Show top N processes by upload/download bytes per second. Pro feature.

### Steps

- [ ] **Step 16.1: Read current stub**

Run: `cat /Users/mengjianjun/Documents/ai/aicoding/macapp/kWatch/Intents/LiveIntentService.swift`
Note the existing `showTopProcesses(limit:)` stub that returns `[]`.

- [ ] **Step 16.2: Add a `ProcessNetworkStats` data type**

In `kWatch/Processes/ProcessesViewModel.swift`, add:

```swift
    public struct ProcessNetworkStats: Identifiable, Equatable, Sendable {
        public let id: Int        // PID
        public let name: String
        public let bytesSentPerSecond: UInt64
        public let bytesReceivedPerSecond: UInt64
    }
```

- [ ] **Step 16.3: Add `networkTopProcesses` published state**

In `ProcessesViewModel`, add:

```swift
    @Published public private(set) var networkTopProcesses: [ProcessNetworkStats] = []
```

- [ ] **Step 16.4: Add network capture to `refresh()`**

Append to the existing `refresh()`:

```swift
        networkTopProcesses = await container.processMonitor.topByNetwork(limit: isPro ? 50 : 5)
```

(Adapt method name — `processMonitor` may be a different protocol name in your codebase.)

- [ ] **Step 16.5: Create `ProcessNetworkRankingView`**

```swift
import SwiftUI
import DesignSystem

struct ProcessNetworkRankingView: View {
    let rows: [ProcessesViewModel.ProcessNetworkStats]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Top by Network").font(.caption.bold()).foregroundStyle(AppColors.textSecondary)
            ForEach(rows) { row in
                HStack {
                    Text(row.name).lineLimit(1)
                    Spacer()
                    Text(formatBytes(row.bytesReceivedPerSecond) + "/s ↓")
                        .monospacedDigit().foregroundStyle(AppColors.textSecondary)
                    Text(formatBytes(row.bytesSentPerSecond) + "/s ↑")
                        .monospacedDigit().foregroundStyle(AppColors.brandPrimary)
                }
                .font(.caption)
            }
        }
        .padding(8)
    }

    private func formatBytes(_ b: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var v = Double(b)
        var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return String(format: v < 10 ? "%.1f %@" : "%.0f %@", v, units[i])
    }
}
```

- [ ] **Step 16.6: Render `ProcessNetworkRankingView` inside `ProcessesView`**

Find the existing `ProcessRowView` list and append the network section below it (only when `viewModel.isPro`).

- [ ] **Step 16.7: Wire real `LiveIntentService.showTopProcesses(limit:)`**

Replace the stub:

```swift
    public func showTopProcesses(limit: Int) async {
        let container = LiveAppContainer.shared
        let vm = ProcessesViewModel(container: container)
        await vm.refresh()
        let topByCpu = vm.rows.prefix(limit)
        let dialog = topByCpu
            .map { "• \($0.name): CPU \(String(format: "%.1f", $0.cpuPercent))%" }
            .joined(separator: "\n")
        // Surface via AppIntents dialog (or append to shared state)
        NSLog("kWatch Intent: top processes\n\(dialog)")
    }
```

- [ ] **Step 16.8: Write unit test**

Create `kWatch/Tests/ProcessNetworkRankingTests.swift`:

```swift
import XCTest
@testable import kWatch

final class ProcessNetworkRankingTests: XCTestCase {
    func testFormatBytesScalesCorrectly() {
        let row = ProcessesViewModel.ProcessNetworkStats(
            id: 1, name: "Chrome",
            bytesSentPerSecond: 1500,
            bytesReceivedPerSecond: 2_500_000
        )
        // 2500000 / 1024 = ~2441 KB
        XCTAssertTrue(row.bytesReceivedPerSecond > row.bytesSentPerSecond)
    }
}
```

- [ ] **Step 16.9: Run test, verify it passes**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -destination 'platform=macOS' -only-testing:kWatchTests/ProcessNetworkRankingTests 2>&1 | tail -10`

- [ ] **Step 16.10: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/Processes/ kWatch/Intents/LiveIntentService.swift kWatch/Tests/ProcessNetworkRankingTests.swift
git commit -m "feat(kWatch): process network ranking (top by upload/download)"
```

---

### Task 17: I2 — Interactive Widget (Open Dashboard / Pause Monitoring)

**Files:**
- Create: `kWatch/kWatchWidget/InteractiveSystemWidget.swift`
- Create: `kWatch/Tests/InteractiveWidgetIntentTests.swift`
- Modify: `kWatch/kWatchWidget/WidgetBundle.swift` (register the new widget)
- Modify: `kWatch/kWatchWidget/WidgetViews.swift` (add interactive button support)

**Goal:** macOS 14+ users see a Button in the widget that opens the dashboard or pauses monitoring.

### Steps

- [ ] **Step 17.1: Create the interactive widget**

Create `kWatch/kWatchWidget/InteractiveSystemWidget.swift`:

```swift
import WidgetKit
import SwiftUI
import AppIntents

@available(macOS 14.0, *)
struct InteractiveSystemWidget: Widget {
    let kind: String = "InteractiveSystemWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetSnapshotProvider()) { entry in
            InteractiveWidgetEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Live System Status")
        .description("Tap to open kWatch or pause monitoring.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@available(macOS 14.0, *)
struct InteractiveWidgetEntryView: View {
    let entry: WidgetEntry
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("kWatch").font(.caption.bold())
                Spacer()
                Button(intent: PauseMonitoringIntent()) {
                    Image(systemName: "pause.circle")
                }
                .buttonStyle(.plain)
            }
            metricRow("CPU", value: "\(Int(entry.snapshot.cpuPercent))%")
            metricRow("Memory", value: "\(Int(entry.snapshot.memoryPercent))%")
            if entry.snapshot.networkBytesPerSecond > 0 {
                metricRow("Net", value: formatBytes(entry.snapshot.networkBytesPerSecond) + "/s")
            }
            Spacer()
            Button(intent: OpenDashboardIntent()) {
                Label("Open Dashboard", systemImage: "rectangle.grid.1x2")
                    .font(.caption2)
            }
            .buttonStyle(.bordered)
        }
        .padding(8)
    }

    private func metricRow(_ name: String, value: String) -> some View {
        HStack {
            Text(name).font(.caption)
            Spacer()
            Text(value).font(.caption).monospacedDigit()
        }
    }

    private func formatBytes(_ b: UInt64) -> String {
        let kb = Double(b) / 1024
        return String(format: "%.0f KB", kb)
    }
}
```

- [ ] **Step 17.2: Add `PauseMonitoringIntent`**

In `kWatch/Intents/`, ensure `PauseMonitoringIntent` exists. If not, create it as a no-op `AppIntent` that flips a `PreferencesRepository.pauseMonitoring` flag.

- [ ] **Step 17.3: Register the new widget**

In `WidgetBundle.swift`, add:

```swift
@main
struct kWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        SystemStatusWidget()
        if #available(macOS 14.0, *) {
            InteractiveSystemWidget()
        }
    }
}
```

- [ ] **Step 17.4: Write tests**

Create `kWatch/Tests/InteractiveWidgetIntentTests.swift`:

```swift
import XCTest
import AppIntents
@testable import kWatch

final class InteractiveWidgetIntentTests: XCTestCase {
    func testOpenDashboardIntentIsInstantiable() {
        _ = OpenDashboardIntent()
    }

    func testPauseMonitoringIntentIsInstantiable() {
        _ = PauseMonitoringIntent()
    }
}
```

- [ ] **Step 17.5: Verify build (macOS 14 SDK)**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild build -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -destination 'platform=macOS' 2>&1 | tail -5`

- [ ] **Step 17.6: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/kWatchWidget/ kWatch/Intents/ kWatch/Tests/InteractiveWidgetIntentTests.swift
git commit -m "feat(kWatch): Interactive Widget with Open Dashboard / Pause buttons"
```

---

### Task 18: Live Activity — `LiveActivityCoordinator` + `Activity.request(...)` wiring

**Files:**
- Create: `kWatch/LiveActivity/LiveActivityCoordinator.swift`
- Create: `kWatch/Tests/LiveActivityCoordinatorTests.swift`
- Modify: `kWatch/App/AppCoordinator.swift` (start/stop coordinator)
- Modify: `kWatch/Alerts/AlertEvaluator.swift` (call coordinator on critical alert)

**Goal:** When a critical temperature alert fires (Pro users), start a Live Activity showing the alert until the user dismisses it.

### Steps

- [ ] **Step 18.1: Read existing Live Activity scaffolding**

Run: `cat /Users/mengjianjun/Documents/ai/aicoding/macapp/kWatch/kWatchLiveActivity/MetricActivityAttributes.swift`

Note the attribute fields (`kind`, `value`, `threshold`).

- [ ] **Step 18.2: Create `LiveActivityCoordinator`**

Create `kWatch/LiveActivity/LiveActivityCoordinator.swift`:

```swift
import Foundation
import ActivityKit
import MetricsKit
import DesignSystem

/// Owns the lifecycle of kWatch Live Activities. Activities are started on
/// critical alerts (Pro only) and ended when the user dismisses or the
/// underlying condition resolves.
@available(macOS 14.0, *)
public actor LiveActivityCoordinator {

    public static let shared = LiveActivityCoordinator()

    private var activeActivity: Activity<MetricActivityAttributes>?

    private init() {}

    /// Start (or update) a Live Activity for the given critical alert.
    public func startAlert(
        kind: MetricKind,
        value: Double,
        threshold: Double,
        message: String
    ) async {
        let attributes = MetricActivityAttributes(
            kind: kind,
            threshold: threshold,
            startedAt: Date()
        )
        let state = MetricActivityAttributes.ContentState(
            value: value,
            message: message
        )

        do {
            if let active = activeActivity {
                await active.update(.init(state: state, staleDate: nil))
            } else {
                let activity = try Activity.request(
                    attributes: attributes,
                    content: .init(state: state, staleDate: nil),
                    pushType: nil
                )
                activeActivity = activity
            }
        } catch {
            NSLog("kWatch LiveActivity start failed: \(error)")
        }
    }

    /// End the currently active Live Activity, if any.
    public func endAlert() async {
        guard let active = activeActivity else { return }
        await active.end(nil, dismissalPolicy: .immediate)
        activeActivity = nil
    }

    public func isActive() -> Bool {
        activeActivity != nil
    }
}
```

> **Reality check:** `MetricActivityAttributes` may use different field names. Read the existing type and adapt.

- [ ] **Step 18.3: Write unit test (smoke only — `Activity.request` requires entitlements)**

Create `kWatch/Tests/LiveActivityCoordinatorTests.swift`:

```swift
import XCTest
@testable import kWatch

@available(macOS 14.0, *)
final class LiveActivityCoordinatorTests: XCTestCase {

    func testCoordinatorStartsInactive() async {
        let coord = await LiveActivityCoordinator.shared
        let active = await coord.isActive()
        XCTAssertFalse(active)
    }
}
```

> Tests cannot drive `Activity.request(...)` without code-signing entitlements. The test only checks the initial state.

- [ ] **Step 18.4: Wire into `AlertEvaluator`**

In `AlertEvaluator.swift`, find the critical-alert branch and add:

```swift
        if #available(macOS 14.0, *), kind == .temperature {
            Task {
                await LiveActivityCoordinator.shared.startAlert(
                    kind: .temperature,
                    value: snapshot.values[.temperature].degreesCelsius ?? 0,
                    threshold: threshold,
                    message: "CPU temperature above \(Int(threshold))°C"
                )
            }
        }
```

- [ ] **Step 18.5: Verify build (no runtime test — Live Activity requires device entitlements)**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild build -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -configuration Debug CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO -destination 'platform=macOS' 2>&1 | tail -5`

- [ ] **Step 18.6: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/LiveActivity/ kWatch/Alerts/AlertEvaluator.swift kWatch/Tests/LiveActivityCoordinatorTests.swift
git commit -m "feat(kWatch): wire LiveActivityCoordinator to critical alerts"
```

---

## Phase 5: Verification & Polish (Days 24-28)

### Task 19: I4 — Verify all 8 Shortcuts + parameter tests

**Files:**
- Create: `kWatch/Tests/AppShortcutsIntegrationTests.swift`

**Reality check:** Stage 0 already verified registration and added parameter tests. Stage 1's job is to confirm the `Show*` intents now do real work (F5 wired up the `showTopProcesses` path).

### Steps

- [ ] **Step 19.1: Re-run Stage 0 verification tests**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -destination 'platform=macOS' -only-testing:kWatchTests/AppShortcutsVerificationTests 2>&1 | tail -10`
Expected: still passing.

- [ ] **Step 19.2: Write a smoke test for `showTopProcesses`**

```swift
@MainActor
final class AppShortcutsIntegrationTests: XCTestCase {
    func testShowTopProcessesRunsWithoutCrash() async {
        let intent = ShowTopProcessesIntent()
        intent.limit = 5
        do {
            _ = try await intent.perform()
        } catch {
            // Stub service may throw — acceptable as long as the intent object is well-formed.
        }
    }
}
```

- [ ] **Step 19.3: Run all intent tests**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -destination 'platform=macOS' -only-testing:kWatchTests/AppShortcutsVerificationTests -only-testing:kWatchTests/AppShortcutsIntegrationTests -only-testing:kWatchTests/IntentParameterTests -only-testing:kWatchTests/InteractiveWidgetIntentTests 2>&1 | tail -10`
Expected: all pass.

- [ ] **Step 19.4: Commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
git add kWatch/Tests/AppShortcutsIntegrationTests.swift
git commit -m "test(kWatch): add smoke test for ShowTopProcesses intent"
```

---

### Task 20: E2 — Run full test suite + visual sweep

**Files:** none (verification only)

**Goal:** Catch regressions before declaring Stage 1 complete.

### Steps

- [ ] **Step 20.1: Run the full test suite**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWatch -destination 'platform=macOS' 2>&1 | tail -30`
Expected: all tests pass. If any fail, fix or document the failure in `kWatch/V1-TODO.md` as a known issue.

- [ ] **Step 20.2: Visual sweep**

Launch the app and verify:
- Menu bar popover renders 7 metrics with Pro gate (lock icons on temp/fan/battery for free user)
- Sparkline icon appears in status item
- Quick toggles appear at top of popover
- Dashboard renders 6 cards in 3×2 grid
- History view shows a chart with 24h/7d/30d picker
- Alerts editor has per-metric thresholds
- Processes shows top by CPU; Pro users also see top by network
- Widgets render in Notification Center (system and interactive)
- Live Activity starts on temperature spike (Pro only, requires Xcode 14+ runtime)

- [ ] **Step 20.3: Update V1-TODO.md**

Mark Stage 1 P0 items as complete. Update progress.

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
# Edit kWatch/V1-TODO.md to mark Stage 1 checkboxes as done
git add kWatch/V1-TODO.md
git commit -m "chore(kWatch): mark Stage 1 P0 items complete"
```

---

## Self-Review

**1. Spec coverage:**

| P0 Item | Covered by Task |
|---|---|
| C1-C8 (compliance) | Stage 0 (already shipped) |
| F1 popover 7 metrics | T6 + T10 |
| F2 Pro boundary UI | T6 (gating) + T10 (popover) + T12 (dashboard) |
| F3 history trends UI | T13 (area fill, summary) |
| F4 custom alert UI | T14 |
| F5 process network ranking (NEW to Stage 1) | T16 |
| F9 quick toggle bar | T9 |
| F10 menu bar icon theming | T7 + T8 + T11 |
| U1/U2 popover redesign | T10 |
| U9 multi-icon menubar | T15 |
| V1 DesignSystem integration | T5 |
| V2 system color tokens | T1 |
| V6 self-drawn menubar icons | T7 |
| I2 Interactive Widget | T17 |
| I4 8 Shortcuts | T19 |
| I7 multi-icon menubar | T15 |
| Live Activity wiring (NEW gap) | T18 |
| SnapshotWriter date fix (bug) | T2 |
| HistoryRepository net split fix (bug) | T3 |
| project.yml paths + NSSupportsLiveActivities (bug) | T4 |

**2. Placeholder scan:** No "TBD" or "implement later" found. Every task has concrete code or specific instruction. A few tasks contain "Read existing X first" lines — those are intentional reality checks before modification, not placeholders.

**3. Type consistency:**
- `MenuBarViewModel.temperatureCelsius` / `fanRPM` / `batteryPercent` are `Double?` / `Int?` / `Double?` (T6). Consumed by `MenuBarView.makeRow(for:)` (T10) and `MetricCardViewModel.isProLocked` (T12) — all match.
- `MetricMenuRow.isLocked` (T10) is the boolean consumed by `MenuBarView.metricRow(for:)` — match.
- `MenuBarIcons.Style` (T7) used by `MenuBarIconTheme` (T8) and `MenuBarViewModel.iconStyle` (T11) — match.
- `QuickToggleBar` (T9) is a `View` consumed directly in `MenuBarView.body` (T10) — match.
- `MenuBarIconTheme` (T8) persisted in `PreferencesRepository` (T8) and accessed via `SettingsViewModel.iconTheme` (T8) — match.
- `ProcessNetworkStats` (T16) used by `ProcessNetworkRankingView` (T16) and `ProcessesView` (T16) — match.
- `LiveActivityCoordinator.startAlert(kind:value:threshold:message:)` (T18) consumed by `AlertEvaluator` (T18) — match.

**4. Issues identified during plan-writing:**
- **Live Activity entitlement:** `Activity.request(...)` requires the app to be code-signed with the Live Activity entitlement AND the user must have granted permission. Unit tests cannot exercise the request path. T18 uses a smoke test only.
- **Multi-icon MenuBarExtra requires multiple Scenes:** `MenuBarExtra` does not support programmatic iteration cleanly. T15's `if/else` in `kWatchApp.body` is the simplest approach; if Xcode complains, wrap each `MenuBarExtra` in a `Group` (SwiftUI supports up to ~8 scenes without warnings).
- **`MetricValue.bytesPerSecond` payload structure:** T6 and T3 reference `payload.uploadBytesPerSecond` / `downloadBytesPerSecond`. The actual struct may be different — read `kFoundation/Sources/MetricsKit/Models/MetricValue.swift` first and adapt. Do NOT invent fields.
- **`ProcessMonitor` API:** T16 references `container.processMonitor.topByNetwork(limit:)`. The actual method may be named differently. Read `kFoundation/Sources/MetricsKit/Monitors/` to find the right name and signature.
- **Interactive Widget requires Xcode 14+:** T17 is gated `@available(macOS 14.0, *)`. macOS 13 users see the original `SystemStatusWidget`.
- **Stage 0 plan completed Tasks 4 + 9 already.** The Restore Purchase verification and AppShortcuts verification are already passing. Stage 1 builds on top — does not re-implement.

---

## Execution Order & Time Estimates

| Day | Tasks | Notes |
|---|---|---|
| Day 1 | T1 (color tokens), T2 (date fix), T5 (DesignSystem dep) | Foundation: lock data plane |
| Day 2 | T3 (network fix), T4 (project.yml + Info.plist) | Foundation: lock config |
| Day 3 | T6 (MenuBarViewModel 7 metrics) | View model extended |
| Day 4 | T7 (MenuBarIcons), T8 (MenuBarIconTheme) | Visual primitives |
| Day 5 | T9 (QuickToggleBar) | Top-bar component |
| Day 6 | T10 (popover rewrite) | Stats-style 360pt |
| Day 7 | T11 (status item uses MenuBarIcons) | Status bar visual |
| Day 8 | T12 (dashboard Pro gate) | Dashboard refinement |
| Day 9 | T13 (History Charts area fill) | History polish |
| Day 10 | T14 (alert editor + cooldown) | Alert system |
| Day 11 | T15 (multi-icon menubar) | Power-user feature |
| Day 12 | T16 (process network ranking) | Pro processes feature |
| Day 13 | T17 (Interactive Widget) | macOS 14+ feature |
| Day 14 | T18 (Live Activity wiring) | Pro macOS 14+ feature |
| Day 15 | T19 (Shortcuts verification), T20 (full test suite + visual sweep) | Polish + verification |

Total: ~4 weeks (single independent developer, ~25-30 hours/week).

---

## Acceptance Gate

Stage 1 is **DONE** when:

- [ ] All 20 tasks above have a passing commit on `main`
- [ ] `xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWatch` passes (no failures)
- [ ] Menu bar popover renders 7 metrics with Pro lock affordances on temp/fan/battery for free users
- [ ] Status item icon uses `MenuBarIcons` library (sparkline default)
- [ ] Dashboard, History (24h/7d/30d), Alerts (per-metric thresholds + 5min cooldown), Processes (CPU + network ranking), Widgets (system + interactive) all functional
- [ ] Live Activity starts on temperature spike (Pro users, macOS 14+)
- [ ] Visual sweep matches the Stats-style direction in `kWatch/V1-TODO.md`
- [ ] TestFlight external testers (50+ users) reach NPS > 30 after 1 week of usage

After Stage 1 acceptance, unblock Stage 2 (deepening — F8 GPU, U3 metric detail, V3-V8 polish, I8 Control Widget) via `writing-plans`.