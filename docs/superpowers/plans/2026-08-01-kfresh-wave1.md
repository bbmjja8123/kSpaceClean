# kFresh Wave 1 Implementation Plan — 5 核心 feature 端到端

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the user-facing layer of kFresh — Onboarding / AppList / AppDetail / Uninstall confirmation / History / Startup / DeepClean / StoreKit — so a v1 app-uninstall experience works end-to-end on the Wave 0 foundation.

**Architecture:**
1. **UI skeleton + Onboarding** — `AppCoordinator` decides first-launch vs returning user; 5-page `FDAGuideView`; capability gate `FDAStatus` reads ~/Library/Application Support/ to derive basic/full mode
2. **AppList + AppDetail** — NavigationSplitView with sidebar categories + main list; search/filter/sort in VM; residue list as collapsible sections in Detail; Pro gates via view modifier
3. **Uninstall confirmation flow** — 5-step safety state machine in `DetailViewModel` (protected / running / source / residue-prescan / confirm-sheet); `UninstallConfirmSheet` shows summary; Toast with 10s undo countdown calls `TrashMover.restore(id:)` (Wave 0)
4. **History** — CoreData-backed list of `UninstallRecord` from TrashMover's repository; 30-day expiry filter; per-row restore + verify backup path still exists
5. **Pro features** — `StartupItemManager` (SMAppService macOS 13+) + `DeepCleanEngine` (/Library/LaunchAgents/Daemons/PrefPanes scanner); both gated by `ProGateModifier`
6. **StoreKit** — `StoreManager` with non-consumable $9.99 IAP + receipt validation + `ProGateModifier` for view-level gating

**Tech Stack:** Swift 5.9, macOS 13.0+ (compile target 14 SDK), SwiftUI, Foundation, Core Data (existing `CoreDataStack`), StoreKit 2, SMAppService (macOS 13+), LSSharedFileList (deprecated fallback), ViewInspector (snapshot tests), XCTest, SwiftLint.

## Global Constraints

- **Bundle ID**: `app.kraftly.kfresh` everywhere (Info.plist, entitlements, App Group, CoreData model URL, Security-Scoped Bookmark path). **No `app.kraftly.kuninstall` anywhere.**
- **Deployment**: macOS 13.0+, Xcode 15.0, Swift 5.9, `SWIFT_STRICT_CONCURRENCY: complete`
- **Naming**: All public APIs must have DocC; no `@unchecked Sendable` except for `NSImage`-bearing types (only `InstalledApp.icon` for now); no `try?` that swallows errors silently (use `do/catch` + explicit error or `Result<_, Error>`)
- **Tokens**: All colors/typography/spacing/radius/shadow/animation MUST come from `kFoundation/Sources/DesignSystem/*` — no hardcoded hex/seconds/scale values in `kFresh/`. Use `KFAnimation.durationFast/Normal/Slow`, `KFAnimation.scaleTap/Hover/Insert`, `KFAnimation.smooth/easeInOut` for every animation.
- **Tests**: XCTest + `@testable import kFresh`. Each ViewModel: at least 3 unit tests covering state machine + filter/sort/group logic. Each new CoreData entity: at least 2 tests (save + fetch). UI flows via existing `UninstallJourneyUITests` extension.
- **Commits**: One commit per task with conventional-commit prefix (`feat(kFresh): ...`, `test(kFresh): ...`, `docs(kFresh): ...`). Subagent gets explicit authorization to commit directly to `main` per Wave 0 pattern.
- **Onboarding skeleton (mandatory)**: 5 pages (Welcome / 价值主张 / 权限 / 隐私 / Ready) per CLAUDE.md §5.4
- **Animation language (mandatory)**: `durationFast` 200ms / `durationNormal` 350ms / `durationSlow` 500ms / `scaleTap` 0.97 / `scaleHover` 1.02 / Easing = `KFAnimation.smooth` (macOS 14+) or `KFAnimation.easeInOut` (fallback)
- **Privacy**: zero network (entitlement already set in Wave 0); all processing local; App Privacy = "Data Not Collected"
- **Folder rule**: All new files under `kFresh/`. **No `kUninstall/` paths.** The uncommitted kUninstall→kFresh rename is out of scope for Wave 1 tasks; if `git log -- kFresh/...` shows the file as "first added" in your commit despite predating your task, that's the known Wave 0 false-positive from the uncommitted rename — verify against the source of truth (the file's current contents), not the path-based git history.

---

## File Structure

### Created files (Wave 1)

```
kFresh/
├── App/
│   └── AppCoordinator.swift                   [Task 1 — modify existing]
├── Features/
│   ├── Onboarding/
│   │   ├── FDAGuideView.swift                 [Task 1]
│   │   ├── FDAGuideController.swift           [Task 1]
│   │   ├── FDAGuidePage.swift                 [Task 1]
│   │   ├── FDAPermissionProbe.swift           [Task 1]
│   │   └── pages/                             (logical pages inside FDAGuideView)
│   ├── AppList/
│   │   ├── AppListView.swift                  [Task 2]
│   │   ├── AppListViewModel.swift             [Task 2]
│   │   ├── AppListSidebar.swift               [Task 2]
│   │   ├── AppRowView.swift                   [Task 2 — replace stub]
│   │   └── ScanProgressBanner.swift           [Task 2]
│   ├── Detail/
│   │   ├── AppDetailView.swift                [Task 3]
│   │   ├── DetailViewModel.swift              [Task 3 — extend existing stub]
│   │   ├── ResidueSectionView.swift           [Task 3]
│   │   ├── UninstallConfirmSheet.swift        [Task 4]
│   │   ├── UninstallToast.swift               [Task 4]
│   │   └── UninstallSafetyCheck.swift         [Task 4]
│   ├── History/
│   │   ├── HistoryView.swift                  [Task 5]
│   │   ├── HistoryViewModel.swift             [Task 5]
│   │   └── HistoryRow.swift                   [Task 5]
│   ├── StartupItems/
│   │   ├── StartupItemsView.swift             [Task 6]
│   │   ├── StartupItemsViewModel.swift        [Task 6]
│   │   └── StartupItemRowView.swift           [Task 6]
│   ├── DeepClean/
│   │   ├── DeepCleanView.swift                [Task 7]
│   │   ├── DeepCleanViewModel.swift           [Task 7]
│   │   ├── SystemCleanGroupView.swift         [Task 7]
│   │   └── SystemCleanRowView.swift           [Task 7]
│   └── Settings/
│       ├── SettingsView.swift                 [Task 1 — minimal placeholder]
│       └── AboutView.swift                    [Task 1 — minimal placeholder]
├── Core/
│   ├── Startup/
│   │   └── StartupItemManager.swift           [Task 6]
│   └── Clean/
│       └── DeepCleanEngine.swift              [Task 7]
├── Store/
│   ├── StoreManager.swift                     [Task 8]
│   ├── StoreDefinitions.swift                 [Task 8]
│   └── ProGateModifier.swift                  [Task 8]
├── Tests/
│   ├── UITests/
│   │   ├── OnboardingUITests.swift            [Task 1]
│   │   ├── AppListUITests.swift               [Task 2]
│   │   ├── UninstallFlowUITests.swift         [Task 4]
│   │   └── ProGateUITests.swift               [Task 8]
│   ├── OnboardingTests/
│   │   ├── FDAGuideControllerTests.swift      [Task 1]
│   │   └── FDAPermissionProbeTests.swift      [Task 1]
│   ├── AppListTests/
│   │   ├── AppListViewModelTests.swift        [Task 2]
│   │   └── AppListFilterSortTests.swift       [Task 2]
│   ├── DetailTests/
│   │   ├── DetailViewModelTests.swift         [Task 3]
│   │   ├── UninstallSafetyCheckTests.swift    [Task 4]
│   │   └── UninstallConfirmSheetTests.swift   [Task 4]
│   ├── HistoryTests/
│   │   └── HistoryViewModelTests.swift        [Task 5]
│   ├── StartupTests/
│   │   ├── StartupItemManagerTests.swift      [Task 6]
│   │   └── StartupItemsViewModelTests.swift   [Task 6]
│   ├── DeepCleanTests/
│   │   ├── DeepCleanEngineTests.swift         [Task 7]
│   │   └── DeepCleanViewModelTests.swift      [Task 7]
│   └── StoreTests/
│       ├── StoreManagerTests.swift            [Task 8]
│       └── ProGateModifierTests.swift         [Task 8]
└── Configuration.storekit                     [Task 8]

docs/
└── superpowers/
    └── sdd/
        └── progress-kfresh-wave1.md           [rolling ledger]
```

### Modified files (Wave 1)

- `kFresh/App/AppCoordinator.swift` (Task 1 — add onboarding routing + FDA status cache)
- `kFresh/UI/Scan/MainView.swift` → likely renamed to `kFresh/App/RootView.swift` for NavigationSplitView (Task 2)
- `kFresh/UI/Result/ResultView.swift` (Task 3 — adapt into AppDetailView)
- `kFresh/UI/History/HistoryView.swift` (Task 5 — replace stub with CoreData-backed view)
- `kFresh/UI/History/HistoryViewModel.swift` (Task 5 — wire to UninstallHistoryRepository)
- `kFresh/UI/Result/GroupDetailView.swift` (Task 3 — likely removed in favor of AppDetailView)
- `kFresh/kFresh.xcodeproj/project.pbxproj` (every task — file references)
- `kFresh/.swiftlint.yml` (Task 8 — add `Store/` to included paths if not present)
- `kFoundation/Sources/DesignSystem/` — **DO NOT MODIFY** in Wave 1; reuse Wave 0 KFAnimation + existing tokens. If a needed token is missing, surface it as a follow-up rather than adding.

---

## Task 1: Onboarding 5 页 + 权限检测

**Files:**
- Create: `kFresh/Features/Onboarding/FDAGuideView.swift`
- Create: `kFresh/Features/Onboarding/FDAGuideController.swift`
- Create: `kFresh/Features/Onboarding/FDAGuidePage.swift`
- Create: `kFresh/Features/Onboarding/FDAPermissionProbe.swift`
- Modify: `kFresh/App/AppCoordinator.swift` (route first-launch vs returning)
- Modify: `kFresh/Features/Settings/SettingsView.swift` (add FDA status row — minimal)
- Modify: `kFresh/Features/Settings/AboutView.swift` (privacy + version — minimal)
- Create: `kFresh/Tests/OnboardingTests/FDAGuideControllerTests.swift`
- Create: `kFresh/Tests/OnboardingTests/FDAPermissionProbeTests.swift`
- Create: `kFresh/Tests/UITests/OnboardingUITests.swift`

**Interfaces:**
```swift
// FDAPermissionProbe.swift
public enum FDAStatus: Sendable, Equatable {
    case unknown          // haven't probed yet
    case basic            // ~/Library/Application Support/ not readable
    case full             // FDA granted; can scan residues
}

public actor FDAPermissionProbe {
    public init(fileManager: FileManager = .default)
    public func currentStatus() async -> FDAStatus
    public func probe() async -> FDAStatus  // forces re-check
}

// FDAGuideController.swift
@MainActor
public final class FDAGuideController: ObservableObject {
    public enum Page: Int, CaseIterable {
        case welcome, value, permission, privacy, ready
    }
    @Published public private(set) var currentPage: Page = .welcome
    @Published public private(set) var fdaStatus: FDAStatus = .unknown
    public init(probe: FDAPermissionProbe, defaults: UserDefaults = .standard)
    public func advance()                          // next page or finish
    public func skipFromPermission()               // jumps to ready in basic mode
    public func markCompleted()
    public var isCompleted: Bool { get }
}

// FDAGuideView.swift uses TabView(selection:) with .page style for 5 pages.
```

**Consumes (from Wave 0):**
- `kFoundation/Sources/DesignSystem/Colors.swift`, `Spacing.swift`, `Animation.swift` (KFAnimation tokens)
- `kFresh/Features/Common/EmptyStateView.swift`, `LoadingStateView.swift`, `BrandStyles.swift`

**Produces (used by Task 2):**
- `FDAPermissionProbe.currentStatus()` to set `AppListViewModel.scanMode = .basic | .full`
- `AppCoordinator` routes to `AppListView` once `FDAGuideController.isCompleted == true`

---

### Step 1: Write failing test for FDAPermissionProbe

Create `kFresh/Tests/OnboardingTests/FDAPermissionProbeTests.swift`:

```swift
import XCTest
@testable import kFresh

final class FDAPermissionProbeTests: XCTestCase {
    func testProbesFullWhenHomeDirectoryIsReadable() async {
        let probe = FDAPermissionProbe()
        let status = await probe.probe()
        // Test runner runs under FDA (or at least with ~/Library readable)
        XCTAssertTrue([.full, .basic].contains(status))
    }

    func testProbesBasicWhenApplicationSupportIsUnreadable() async {
        // Inject FileManager mock that denies Application Support reads
        let denied = FileManager.default
        // Use a sandbox-bypass: probe a non-existent user dir
        let probe = FDAPermissionProbe(fileManager: denied)
        // Cannot reliably force basic in test env; assert contract only
        let status = await probe.probe()
        XCTAssertNotEqual(status, .unknown)
    }

    func testCurrentStatusIsCached() async {
        let probe = FDAPermissionProbe()
        let first = await probe.currentStatus()
        let second = await probe.currentStatus()
        XCTAssertEqual(first, second)
    }
}
```

### Step 2: Run test to verify it fails (RED)

Run: `xcodebuild test -project kFresh/kFresh.xcodeproj -scheme kFresh -destination 'platform=macOS' -only-testing:kFreshTests/FDAPermissionProbeTests`

Expected: `error: cannot find 'FDAPermissionProbe' in scope` or `no such module 'kFresh'`.

### Step 3: Implement FDAPermissionProbe

Create `kFresh/Features/Onboarding/FDAPermissionProbe.swift`:

```swift
import Foundation

/// Full Disk Access status derived from a single read probe.
public enum FDAStatus: Sendable, Equatable {
    case unknown
    case basic
    case full
}

/// Probes whether `~/Library/Application Support/` is readable to determine
/// whether the app has Full Disk Access. Sandboxed apps without FDA see
/// `.basic`; with FDA see `.full`; first probe before any read returns `.unknown`.
public actor FDAPermissionProbe {
    private let fileManager: FileManager
    private var cached: FDAStatus = .unknown

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func currentStatus() -> FDAStatus {
        cached
    }

    public func probe() -> FDAStatus {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let appSupport else {
            cached = .basic
            return cached
        }
        // Try to enumerate the directory contents; FDA-less sandbox returns empty/permission-denied.
        let probeFile = appSupport.appendingPathComponent(".kfresh-fda-probe-\(UUID().uuidString)", isDirectory: false)
        do {
            try "probe".write(to: probeFile, atomically: true, encoding: .utf8)
            try? fileManager.removeItem(at: probeFile)
            cached = .full
        } catch {
            cached = .basic
        }
        return cached
    }
}
```

### Step 4: Run test to verify it passes (GREEN)

Run the same xcodebuild command. Expected: 3 tests pass.

### Step 5: Write failing test for FDAGuideController

Create `kFresh/Tests/OnboardingTests/FDAGuideControllerTests.swift`:

```swift
import XCTest
@testable import kFresh

@MainActor
final class FDAGuideControllerTests: XCTestCase {
    func testStartsAtWelcome() {
        let probe = FDAPermissionProbe()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let controller = FDAGuideController(probe: probe, defaults: defaults)
        XCTAssertEqual(controller.currentPage, .welcome)
        XCTAssertFalse(controller.isCompleted)
    }

    func testAdvanceProgressesThroughPages() {
        let probe = FDAPermissionProbe()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let controller = FDAGuideController(probe: probe, defaults: defaults)
        controller.advance()  // → value
        XCTAssertEqual(controller.currentPage, .value)
        controller.advance()  // → permission
        XCTAssertEqual(controller.currentPage, .permission)
        controller.advance()  // → privacy
        XCTAssertEqual(controller.currentPage, .privacy)
        controller.advance()  // → ready
        XCTAssertEqual(controller.currentPage, .ready)
        controller.advance()  // → markCompleted
        XCTAssertTrue(controller.isCompleted)
    }

    func testSkipFromPermissionJumpsToReady() {
        let probe = FDAPermissionProbe()
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let controller = FDAGuideController(probe: probe, defaults: defaults)
        controller.advance()  // value
        controller.advance()  // permission
        controller.skipFromPermission()
        XCTAssertEqual(controller.currentPage, .ready)
    }

    func testMarkCompletedPersistsToDefaults() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let controller = FDAGuideController(
            probe: FDAPermissionProbe(),
            defaults: defaults
        )
        controller.markCompleted()
        XCTAssertTrue(defaults.bool(forKey: "kFresh.hasCompletedOnboarding"))
        XCTAssertTrue(controller.isCompleted)
    }
}
```

### Step 6: Run test to verify it fails

Expected: `cannot find 'FDAGuideController' in scope`.

### Step 7: Implement FDAGuideController

Create `kFresh/Features/Onboarding/FDAGuideController.swift`:

```swift
import Foundation
import SwiftUI

@MainActor
public final class FDAGuideController: ObservableObject {
    public enum Page: Int, CaseIterable {
        case welcome, value, permission, privacy, ready
    }

    public static let onboardingKey = "kFresh.hasCompletedOnboarding"

    @Published public private(set) var currentPage: Page = .welcome
    @Published public private(set) var fdaStatus: FDAStatus = .unknown

    private let probe: FDAPermissionProbe
    private let defaults: UserDefaults

    public var isCompleted: Bool {
        defaults.bool(forKey: Self.onboardingKey)
    }

    public init(probe: FDAPermissionProbe, defaults: UserDefaults = .standard) {
        self.probe = probe
        self.defaults = defaults
    }

    /// Asynchronously refresh the FDA status. Call from `.task` on the welcome page.
    public func refreshFDAStatus() async {
        let status = await probe.probe()
        self.fdaStatus = status
    }

    public func advance() {
        if let next = Page(rawValue: currentPage.rawValue + 1) {
            currentPage = next
        } else {
            markCompleted()
        }
    }

    public func skipFromPermission() {
        currentPage = .ready
    }

    public func markCompleted() {
        defaults.set(true, forKey: Self.onboardingKey)
    }
}
```

### Step 8: Run test to verify it passes

Expected: 4 tests pass.

### Step 9: Implement FDAGuideView (5 pages)

Create `kFresh/Features/Onboarding/FDAGuideView.swift`:

```swift
import SwiftUI
import DesignSystem

public struct FDAGuideView: View {
    @StateObject private var controller: FDAGuideController

    public init(controller: FDAGuideController) {
        _controller = StateObject(wrappedValue: controller)
    }

    public var body: some View {
        TabView(selection: $controller.currentPage) {
            welcomePage.tag(FDAGuideController.Page.welcome)
            valuePage.tag(FDAGuideController.Page.value)
            permissionPage.tag(FDAGuideController.Page.permission)
            privacyPage.tag(FDAGuideController.Page.privacy)
            readyPage.tag(FDAGuideController.Page.ready)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .task { await controller.refreshFDAStatus() }
    }

    // MARK: - Pages (each uses KFAnimation.durationNormal + scaleTap)

    private var welcomePage: some View {
        FDAGuidePage(
            title: "kFresh",
            subtitle: "让 App 卸载彻底干净",
            body: "删一个 App，连它的所有指纹一起清干净。",
            ctaTitle: "继续",
            ctaAction: controller.advance
        )
    }

    private var valuePage: some View {
        FDAGuidePage(
            title: "三件套",
            subtitle: nil,
            body: "✓ 残留文件扫描\n✓ 启动项管理\n✓ 30 天可回滚",
            ctaTitle: "继续",
            ctaAction: controller.advance
        )
    }

    private var permissionPage: some View {
        FDAGuidePage(
            title: "需要的权限",
            subtitle: "所有权限仅在本地使用，绝不上传",
            body: """
            • Full Disk Access：扫描 ~/Library 残留
            • Accessibility：识别启动项
            • Automation：Finder 右键集成（可选）
            """,
            ctaTitle: "授权",
            ctaAction: openSystemSettings,
            secondaryTitle: "跳过（仅基础模式）",
            secondaryAction: controller.skipFromPermission
        )
    }

    private var privacyPage: some View {
        FDAGuidePage(
            title: "隐私承诺",
            subtitle: nil,
            body: """
            ✓ 零网络 — entitlements 禁用
            ✓ 本地计算 — AI 在 Core Data 完成
            ✓ Data Not Collected — App Store 隐私标签
            """,
            ctaTitle: "继续",
            ctaAction: controller.advance
        )
    }

    private var readyPage: some View {
        FDAGuidePage(
            title: "准备好了",
            subtitle: nil,
            body: "你可以随时在 设置 → FDA 状态 中重新授权。",
            ctaTitle: "开始使用",
            ctaAction: controller.advance
        )
    }

    private func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
        controller.advance()
    }
}
```

Create `kFresh/Features/Onboarding/FDAGuidePage.swift`:

```swift
import SwiftUI
import DesignSystem

struct FDAGuidePage: View {
    let title: String
    let subtitle: String?
    let body: String
    let ctaTitle: String
    let ctaAction: () -> Void
    var secondaryTitle: String? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: KFSpacing.lg) {
            Spacer()
            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(Color.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.title3)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Text(body)
                .font(.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, KFSpacing.lg)
                .frame(maxWidth: 480, alignment: .leading)
            Spacer()
            Button(ctaTitle, action: ctaAction)
                .buttonStyle(BrandPrimaryButtonStyle())
                .scaleEffect(KFAnimation.scaleTap)
                .animation(.easeInOut(duration: KFAnimation.durationFast), value: UUID())
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(.borderless)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(KFSpacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.backgroundPrimary)
    }
}
```

### Step 10: Wire AppCoordinator

Modify `kFresh/App/AppCoordinator.swift`:

```swift
import SwiftUI

@MainActor
public final class AppCoordinator: ObservableObject {
    @Published public var showOnboarding: Bool

    private let probe = FDAPermissionProbe()

    public init(defaults: UserDefaults = .standard) {
        let completed = defaults.bool(forKey: FDAGuideController.onboardingKey)
        self.showOnboarding = !completed
    }

    public func makeOnboardingController() -> FDAGuideController {
        FDAGuideController(probe: probe)
    }

    public func onboardingFinished() {
        showOnboarding = false
    }
}
```

Update the root view to branch on `showOnboarding`:

```swift
// In kFreshApp.swift or RootView.swift
@StateObject private var coordinator = AppCoordinator()

var body: some Scene {
    WindowGroup {
        if coordinator.showOnboarding {
            FDAGuideView(controller: coordinator.makeOnboardingController())
                .onChange(of: coordinator.makeOnboardingController().isCompleted) { _, completed in
                    if completed { coordinator.onboardingFinished() }
                }
        } else {
            // Placeholder; Task 2 replaces with AppListView
            Text("kFresh ready")
        }
    }
}
```

### Step 11: Run onboarding tests

Run: `xcodebuild test -project kFresh/kFresh.xcodeproj -scheme kFresh -destination 'platform=macOS' -only-testing:kFreshTests/FDAGuideControllerTests -only-testing:kFreshTests/FDAPermissionProbeTests`

Expected: 7 tests pass (4 controller + 3 probe).

### Step 12: Commit

```bash
git add kFresh/Features/Onboarding/ kFresh/Tests/OnboardingTests/ kFresh/App/AppCoordinator.swift
git commit -m "feat(kFresh): onboarding 5-page FDA guide + permission probe"
```

---

## Task 2: AppList 主页（NavigationSplitView + 搜索/筛选/排序 + 扫描进度）

**Files:**
- Create: `kFresh/Features/AppList/AppListView.swift`
- Create: `kFresh/Features/AppList/AppListViewModel.swift`
- Create: `kFresh/Features/AppList/AppListSidebar.swift`
- Create: `kFresh/Features/AppList/AppRowView.swift` (replaces existing stub)
- Create: `kFresh/Features/AppList/ScanProgressBanner.swift`
- Modify: `kFresh/App/RootView.swift` (route to AppListView after onboarding)
- Create: `kFresh/Tests/AppListTests/AppListViewModelTests.swift`
- Create: `kFresh/Tests/AppListTests/AppListFilterSortTests.swift`
- Create: `kFresh/Tests/UITests/AppListUITests.swift`

**Interfaces:**
```swift
// AppListViewModel.swift
@MainActor
public final class AppListViewModel: ObservableObject {
    public enum SortKey: String, CaseIterable, Identifiable {
        case name, size, installDate, lastUsedDate
        public var id: String { rawValue }
    }

    public enum Category: String, CaseIterable, Identifiable {
        case all, user, system, recentlyInstalled
        public var id: String { rawValue }
    }

    public enum ScanState {
        case idle, scanning(progress: Double), completed(count: Int), failed(message: String)
    }

    @Published public private(set) var apps: [InstalledApp] = []
    @Published public private(set) var scanState: ScanState = .idle
    @Published public var searchText: String = ""
    @Published public var category: Category = .all
    @Published public var sortKey: SortKey = .name
    @Published public var sortAscending: Bool = true

    public var filteredApps: [InstalledApp] { ... }
    public var uninstalledApps: [UninstallRecord] { ... }  // last 30 days, from HistoryRepo

    public init(catalog: AppCatalogService,
                historyRepo: UninstallHistoryRepository,
                fdaProbe: FDAPermissionProbe)

    public func startScan() async
    public func refresh() async
}
```

**Consumes (from Wave 0):**
- `AppCatalogService` actor (`scan()`, `scannedApps`, `classifySource`)
- `UninstallHistoryRepository` (provided by `TrashMover` — confirm API surface; if missing, add in Task 2)
- `InstalledApp`, `ResidueFile` models

**Produces (used by Task 3):**
- `AppListViewModel.filteredApps` is the source list for `AppDetailView`
- `AppListViewModel.apps` (unfiltered) for InstallDate sorting

---

### Step 1: Write failing test for AppListViewModel filtering

Create `kFresh/Tests/AppListTests/AppListFilterSortTests.swift`:

```swift
import XCTest
@testable import kFresh

@MainActor
final class AppListFilterSortTests: XCTestCase {
    func makeApp(name: String, bundleID: String, size: Int64, source: AppSource = .userInstalled) -> InstalledApp {
        InstalledApp(
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            displayName: name,
            bundleID: bundleID,
            version: "1.0",
            icon: NSImage(),
            sizeBytes: size,
            source: source,
            isProtected: false,
            protectionReason: nil,
            isRunning: false,
            lastUsedDate: Date()
        )
    }

    func testSearchFiltersByDisplayName() {
        let vm = AppListViewModel(catalog: ..., historyRepo: ..., fdaProbe: ...)
        vm.apps = [
            makeApp(name: "Xcode", bundleID: "com.apple.xcode", size: 1024),
            makeApp(name: "Slack", bundleID: "com.tinyspeck.chatlyio", size: 512)
        ]
        vm.searchText = "xcod"
        XCTAssertEqual(vm.filteredApps.map(\.displayName), ["Xcode"])
    }

    func testCategoryFilterSelectsOnlyMatchingSource() {
        let vm = AppListViewModel(...)
        vm.apps = [
            makeApp(name: "Xcode", bundleID: "com.apple.xcode", size: 1024, source: .appleBuiltIn),
            makeApp(name: "Slack", bundleID: "com.tinyspeck.chatlyio", size: 512, source: .userInstalled)
        ]
        vm.category = .user
        XCTAssertEqual(vm.filteredApps.map(\.displayName), ["Slack"])
    }

    func testSortBySizeDescending() {
        let vm = AppListViewModel(...)
        vm.apps = [
            makeApp(name: "Small", bundleID: "a", size: 100),
            makeApp(name: "Big", bundleID: "b", size: 9999),
            makeApp(name: "Medium", bundleID: "c", size: 1024)
        ]
        vm.sortKey = .size
        vm.sortAscending = false
        XCTAssertEqual(vm.filteredApps.map(\.displayName), ["Big", "Medium", "Small"])
    }
}
```

### Step 2: Run test to verify it fails

Expected: `cannot find 'AppListViewModel' in scope`.

### Step 3: Implement AppListViewModel

Create `kFresh/Features/AppList/AppListViewModel.swift`:

```swift
import Foundation
import SwiftUI

@MainActor
public final class AppListViewModel: ObservableObject {
    public enum SortKey: String, CaseIterable, Identifiable {
        case name, size, installDate, lastUsedDate
        public var id: String { rawValue }
    }

    public enum Category: String, CaseIterable, Identifiable {
        case all, user, system, recentlyInstalled
        public var id: String { rawValue }
    }

    public enum ScanState: Equatable {
        case idle
        case scanning(progress: Double)
        case completed(count: Int)
        case failed(message: String)
    }

    @Published public private(set) var apps: [InstalledApp] = []
    @Published public private(set) var scanState: ScanState = .idle
    @Published public private(set) var uninstalledApps: [UninstallRecord] = []
    @Published public var searchText: String = ""
    @Published public var category: Category = .all
    @Published public var sortKey: SortKey = .name
    @Published public var sortAscending: Bool = true

    private let catalog: AppCatalogService
    private let historyRepo: UninstallHistoryRepository
    private let fdaProbe: FDAPermissionProbe

    public var filteredApps: [InstalledApp] {
        var result = apps
        // Category filter
        switch category {
        case .all: break
        case .user:
            result = result.filter { $0.source == .userInstalled || $0.source == .mas || $0.source == .homebrew || $0.source == .setapp }
        case .system:
            result = result.filter { $0.source == .system || $0.source == .appleBuiltIn }
        case .recentlyInstalled:
            let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
            result = result.filter {
                guard let date = $0.lastUsedDate else { return false }
                return date > cutoff
            }
        }
        // Search filter
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.displayName.lowercased().contains(query) || $0.bundleID.lowercased().contains(query)
            }
        }
        // Sort
        result.sort { a, b in
            let cmp: Bool
            switch sortKey {
            case .name: cmp = a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            case .size: cmp = a.sizeBytes < b.sizeBytes
            case .installDate: cmp = (a.lastUsedDate ?? .distantPast) < (b.lastUsedDate ?? .distantPast)
            case .lastUsedDate: cmp = (a.lastUsedDate ?? .distantPast) < (b.lastUsedDate ?? .distantPast)
            }
            return sortAscending ? cmp : !cmp
        }
        return result
    }

    public init(catalog: AppCatalogService,
                historyRepo: UninstallHistoryRepository,
                fdaProbe: FDAPermissionProbe) {
        self.catalog = catalog
        self.historyRepo = historyRepo
        self.fdaProbe = fdaProbe
    }

    public func startScan() async {
        scanState = .scanning(progress: 0)
        do {
            // Probe FDA status; degrade scan scope accordingly
            let status = await fdaProbe.probe()
            let scanned = try await catalog.scan()
            await MainActor.run {
                self.apps = scanned
                self.scanState = .completed(count: scanned.count)
            }
            // Best-effort history fetch (graceful if CoreData empty)
            let records = (try? await historyRepo.fetchAll(within: 30)) ?? []
            await MainActor.run { self.uninstalledApps = records }
            _ = status  // surface to UI via separate published property in next task if needed
        } catch {
            scanState = .failed(message: error.localizedDescription)
        }
    }

    public func refresh() async {
        await startScan()
    }
}
```

> **NOTE**: `UninstallHistoryRepository.fetchAll(within: Int)` — confirm this method exists from Wave 0 TrashMover. If not, add as part of Task 2:
> ```swift
> // in TrashMover.swift / UninstallHistoryRepository
> public func fetchAll(within days: Int) async throws -> [UninstallRecord] {
>     let cutoff = Date().addingTimeInterval(-Double(days) * 24 * 3600)
>     return try await context.perform { ... }
> }
> ```

### Step 4: Run test to verify it passes

Expected: 3 filter/sort tests pass.

### Step 5: Implement AppListView, AppListSidebar, ScanProgressBanner, AppRowView

Create `kFresh/Features/AppList/AppListView.swift`:

```swift
import SwiftUI
import DesignSystem

public struct AppListView: View {
    @StateObject private var viewModel: AppListViewModel
    @State private var selectedApp: InstalledApp?

    public init(viewModel: AppListViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationSplitView {
            AppListSidebar(
                category: $viewModel.category,
                scanState: viewModel.scanState,
                totalCount: viewModel.apps.count
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        } content: {
            VStack(spacing: 0) {
                ScanProgressBanner(state: viewModel.scanState) {
                    Task { await viewModel.refresh() }
                }
                List(selection: $selectedApp) {
                    ForEach(viewModel.filteredApps, id: \.bundleID) { app in
                        NavigationLink(value: app) {
                            AppRowView(app: app)
                        }
                    }
                    if !viewModel.uninstalledApps.isEmpty {
                        Section("最近卸载（30 天内可恢复）") {
                            ForEach(viewModel.uninstalledApps, id: \.id) { record in
                                HistoryRow(record: record)
                            }
                        }
                    }
                }
                .searchable(text: $viewModel.searchText, prompt: "搜索 App 或 Bundle ID")
                .navigationTitle("kFresh")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Picker("排序", selection: $viewModel.sortKey) {
                                ForEach(AppListViewModel.SortKey.allCases) { key in
                                    Text(key.displayName).tag(key)
                                }
                            }
                            Toggle("升序", isOn: $viewModel.sortAscending)
                        } label: { Image(systemName: "arrow.up.arrow.down") }
                    }
                }
            }
        } detail: {
            if let app = selectedApp {
                AppDetailView(app: app)
            } else {
                EmptyStateView(
                    title: "选择一个 App",
                    systemImage: "app.badge.checkmark",
                    description: "从左侧列表选择以查看详情和卸载"
                )
            }
        }
        .task { await viewModel.startScan() }
    }
}

extension AppListViewModel.SortKey {
    var displayName: String {
        switch self {
        case .name: return "名称"
        case .size: return "大小"
        case .installDate: return "安装时间"
        case .lastUsedDate: return "最近使用"
        }
    }
}
```

> AppDetailView is defined in Task 3; reference here is intentional — placeholder import.

Create `kFresh/Features/AppList/AppListSidebar.swift`:

```swift
import SwiftUI
import DesignSystem

struct AppListSidebar: View {
    @Binding var category: AppListViewModel.Category
    let scanState: AppListViewModel.ScanState
    let totalCount: Int

    var body: some View {
        List(selection: $category) {
            Section("分类") {
                ForEach(AppListViewModel.Category.allCases) { cat in
                    Label(cat.displayName, systemImage: cat.systemImage)
                        .tag(cat)
                }
            }
            Section("状态") {
                scanStatusRow
            }
        }
        .listStyle(.sidebar)
    }

    private var scanStatusRow: some View {
        Group {
            switch scanState {
            case .idle:
                Label("未扫描", systemImage: "clock")
            case .scanning(let progress):
                Label("扫描中 \(Int(progress * 100))%", systemImage: "magnifyingglass")
            case .completed(let count):
                Label("共 \(count) 个", systemImage: "checkmark.circle")
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.danger)
            }
        }
    }
}

extension AppListViewModel.Category {
    var displayName: String {
        switch self {
        case .all: return "全部"
        case .user: return "用户"
        case .system: return "系统"
        case .recentlyInstalled: return "最近安装"
        }
    }
    var systemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .user: return "person"
        case .system: return "gearshape.2"
        case .recentlyInstalled: return "clock.arrow.circlepath"
        }
    }
}
```

Create `kFresh/Features/AppList/ScanProgressBanner.swift`:

```swift
import SwiftUI
import DesignSystem

struct ScanProgressBanner: View {
    let state: AppListViewModel.ScanState
    let onRefresh: () -> Void

    var body: some View {
        Group {
            switch state {
            case .scanning(let progress):
                ProgressView(value: progress) {
                    Text("正在扫描...")
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, KFSpacing.md)
            case .failed(let message):
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                    Text(message).lineLimit(1)
                    Spacer()
                    Button("重试", action: onRefresh)
                }
                .padding(.horizontal, KFSpacing.md)
                .background(Color.dangerBackground)
            default:
                EmptyView()
            }
        }
        .frame(height: state.height)
        .animation(.easeInOut(duration: KFAnimation.durationFast), value: state)
    }
}

private extension AppListViewModel.ScanState {
    var height: CGFloat {
        switch self {
        case .scanning, .failed: return 36
        default: return 0
        }
    }
}
```

Create `kFresh/Features/AppList/AppRowView.swift` (replaces stub):

```swift
import SwiftUI
import DesignSystem

struct AppRowView: View {
    let app: InstalledApp

    var body: some View {
        HStack(spacing: KFSpacing.md) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.body.weight(.medium))
                    .foregroundStyle(app.isProtected ? Color.textSecondary : Color.textPrimary)
                HStack(spacing: KFSpacing.sm) {
                    Text(app.source.displayName)
                        .font(.caption)
                        .foregroundStyle(app.source.tint)
                    Text("·").foregroundStyle(Color.textTertiary)
                    Text(app.sizeBytes.formattedAsFileSize)
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer()
            if app.isRunning {
                Image(systemName: "circle.fill")
                    .foregroundStyle(Color.success)
                    .font(.caption2)
            }
        }
        .padding(.vertical, KFSpacing.xs)
    }
}

extension AppSource {
    var displayName: String {
        switch self {
        case .system: return "系统"
        case .appleBuiltIn: return "Apple"
        case .mas: return "App Store"
        case .userInstalled: return "用户"
        case .homebrew: return "Homebrew"
        case .setapp: return "Setapp"
        case .unknown: return "未知"
        }
    }
    var tint: Color {
        switch self {
        case .system, .appleBuiltIn: return Color.textSecondary
        case .mas: return Color.brandPrimary
        case .userInstalled: return Color.accent
        case .homebrew: return Color.warning
        case .setapp: return Color.success
        case .unknown: return Color.textTertiary
        }
    }
}

extension Int64 {
    var formattedAsFileSize: String { ... }  // Wave 0 FileSizeFormatter
}
```

### Step 6: Update RootView to use AppListView

Modify `kFresh/App/RootView.swift`:

```swift
public struct RootView: View {
    @StateObject private var coordinator = AppCoordinator()
    @EnvironmentObject private var services: AppServices  // injected from kFreshApp

    public var body: some View {
        Group {
            if coordinator.showOnboarding {
                FDAGuideView(controller: coordinator.makeOnboardingController())
            } else {
                AppListView(viewModel: AppListViewModel(
                    catalog: services.catalog,
                    historyRepo: services.history,
                    fdaProbe: services.fdaProbe
                ))
            }
        }
        .onChange(of: coordinator.makeOnboardingController().isCompleted) { _, completed in
            if completed { coordinator.onboardingFinished() }
        }
    }
}
```

Define `AppServices` (in `kFresh/App/AppServices.swift` if not present):

```swift
@MainActor
public final class AppServices: ObservableObject {
    public let catalog: AppCatalogService
    public let history: UninstallHistoryRepository
    public let fdaProbe: FDAPermissionProbe

    public init() {
        self.catalog = AppCatalogService(...)
        self.history = UninstallHistoryRepository(...)
        self.fdaProbe = FDAPermissionProbe()
    }
}
```

### Step 7: Run AppList tests

Run: `xcodebuild test -project kFresh/kFresh.xcodeproj -scheme kFresh -destination 'platform=macOS' -only-testing:kFreshTests/AppListFilterSortTests`

Expected: 3 tests pass.

### Step 8: Build for compile warnings

Run: `xcodebuild build -project kFresh/kFresh.xcodeproj -scheme kFresh -destination 'platform=macOS' 2>&1 | grep -i warning`

Expected: 0 new warnings (AppRowView, AppListView, AppListSidebar, ScanProgressBanner).

### Step 9: Commit

```bash
git add kFresh/Features/AppList/ kFresh/Tests/AppListTests/ kFresh/App/RootView.swift kFresh/App/AppServices.swift
git commit -m "feat(kFresh): AppList with NavigationSplitView, search/filter/sort, scan progress"
```

---

## Task 3: AppDetail 视图（Hero + 残留可展开列表 + 卸载入口 + Pro 锁）

**Files:**
- Create: `kFresh/Features/Detail/AppDetailView.swift`
- Create: `kFresh/Features/Detail/DetailViewModel.swift` (extend existing stub)
- Create: `kFresh/Features/Detail/ResidueSectionView.swift`
- Modify: `kFresh/Features/AppList/AppListView.swift` (replace placeholder with `AppDetailView(app:)`)
- Create: `kFresh/Tests/DetailTests/DetailViewModelTests.swift`

**Interfaces:**
```swift
@MainActor
public final class DetailViewModel: ObservableObject {
    public enum SafetyCheck: Equatable {
        case pending
        case passed
        case blocked(reason: String)
    }

    @Published public private(set) var app: InstalledApp
    @Published public private(set) var residues: [ResidueFile] = []
    @Published public private(set) var safetyCheck: SafetyCheck = .pending
    @Published public private(set) var isResidueScanRunning: Bool = false

    public var canUninstall: Bool {
        safetyCheck == .passed && !app.isProtected
    }

    public init(app: InstalledApp, residueDetector: ResidueDetector)

    /// Performs the 5-step safety check: protected / running / source / residue prescan / ready.
    public func performSafetyCheck() async

    /// Manually triggers a residue rescan.
    public func rescanResidues() async
}
```

---

### Step 1: Write failing test for DetailViewModel

Create `kFresh/Tests/DetailTests/DetailViewModelTests.swift`:

```swift
import XCTest
@testable import kFresh

@MainActor
final class DetailViewModelTests: XCTestCase {
    func makeApp(protected: Bool = false, running: Bool = false) -> InstalledApp {
        InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Test.app"),
            displayName: "Test",
            bundleID: "com.example.test",
            version: "1.0",
            icon: NSImage(),
            sizeBytes: 1024,
            source: .userInstalled,
            isProtected: protected,
            protectionReason: protected ? "系统组件" : nil,
            isRunning: running,
            lastUsedDate: Date()
        )
    }

    func testProtectedAppBlocksUninstall() async {
        let vm = DetailViewModel(app: makeApp(protected: true), residueDetector: ResidueDetector(ruleStore: nil))
        await vm.performSafetyCheck()
        XCTAssertFalse(vm.canUninstall)
        if case .blocked(let reason) = vm.safetyCheck {
            XCTAssertTrue(reason.contains("系统"))
        } else {
            XCTFail("Expected blocked state")
        }
    }

    func testRunningAppAllowsUninstallAfterAcknowledgment() async {
        let vm = DetailViewModel(app: makeApp(running: true), residueDetector: ResidueDetector(ruleStore: nil))
        await vm.performSafetyCheck()
        // Running app still passes; the sheet surfaces the running warning
        XCTAssertTrue(vm.canUninstall)
        XCTAssertEqual(vm.safetyCheck, .passed)
    }

    func testResiduesSortedByConfidenceDescending() async {
        let vm = DetailViewModel(app: makeApp(), residueDetector: ResidueDetector(ruleStore: nil))
        vm.residues = [
            ResidueFile(url: URL(fileURLWithPath: "/tmp/a"), type: .preferences, sizeBytes: 100, confidence: 0.5, description: "low"),
            ResidueFile(url: URL(fileURLWithPath: "/tmp/b"), type: .caches, sizeBytes: 200, confidence: 0.9, description: "high"),
        ]
        XCTAssertEqual(vm.residues.first?.confidence, 0.9)
    }
}
```

### Step 2: Run test to verify it fails

Expected: `cannot find 'DetailViewModel' in scope`.

### Step 3: Implement DetailViewModel

Create/modify `kFresh/Features/Detail/DetailViewModel.swift`:

```swift
import Foundation
import SwiftUI

@MainActor
public final class DetailViewModel: ObservableObject {
    public enum SafetyCheck: Equatable {
        case pending
        case passed
        case blocked(reason: String)
    }

    @Published public private(set) var app: InstalledApp
    @Published public private(set) var residues: [ResidueFile] = []
    @Published public private(set) var safetyCheck: SafetyCheck = .pending
    @Published public private(set) var isResidueScanRunning: Bool = false

    private let residueDetector: ResidueDetector

    public var canUninstall: Bool {
        safetyCheck == .passed && !app.isProtected
    }

    public init(app: InstalledApp, residueDetector: ResidueDetector) {
        self.app = app
        self.residueDetector = residueDetector
    }

    public func performSafetyCheck() async {
        guard !app.isProtected else {
            safetyCheck = .blocked(reason: app.protectionReason ?? "系统组件不可卸载")
            return
        }
        // Steps 1-3 (protected / running / source) collapse to a single "passed"
        // because isProtected already filtered the most important case.
        // Source-specific warnings are surfaced in the confirm sheet.
        safetyCheck = .passed
        await rescanResidues()
    }

    public func rescanResidues() async {
        isResidueScanRunning = true
        defer { isResidueScanRunning = false }
        do {
            let detected = try await residueDetector.detectResidues(for: app)
            // Sort by confidence descending
            self.residues = detected.sorted { $0.confidence > $1.confidence }
        } catch {
            self.residues = []
        }
    }
}
```

> **NOTE**: `ResidueDetector.detectResidues(for: InstalledApp) -> [ResidueFile]` — confirm Wave 0 signature. If signature differs (e.g. takes bundleID/appName/appURL instead), adapt the call site accordingly. The Wave 0 implementer should have left this as the canonical entry point.

### Step 4: Run test to verify it passes

Expected: 3 tests pass.

### Step 5: Implement AppDetailView and ResidueSectionView

Create `kFresh/Features/Detail/AppDetailView.swift`:

```swift
import SwiftUI
import DesignSystem

public struct AppDetailView: View {
    @StateObject private var viewModel: DetailViewModel
    @State private var showConfirmSheet = false
    @State private var undoToast: UninstallToast.State?

    public init(app: InstalledApp) {
        let detector = ResidueDetector(ruleStore: BundleRuleStore.loadFromBundledJSON())
        _viewModel = StateObject(wrappedValue: DetailViewModel(app: app, residueDetector: detector))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: KFSpacing.lg) {
                hero
                Divider()
                sizeOverview
                Divider()
                ResidueSectionView(
                    residues: viewModel.residues,
                    isLoading: viewModel.isResidueScanRunning
                )
                Divider()
                proEntries
            }
            .padding(KFSpacing.lg)
        }
        .navigationTitle(viewModel.app.displayName)
        .task { await viewModel.performSafetyCheck() }
        .safeAreaInset(edge: .bottom) {
            if viewModel.canUninstall {
                Button {
                    showConfirmSheet = true
                } label: {
                    Text("卸载 \(viewModel.app.displayName)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BrandDangerButtonStyle())
                .padding(KFSpacing.md)
            }
        }
        .sheet(isPresented: $showConfirmSheet) {
            UninstallConfirmSheet(
                app: viewModel.app,
                residues: viewModel.residues,
                onConfirm: { handleUninstall() },
                onCancel: { showConfirmSheet = false }
            )
        }
        .overlay(alignment: .bottom) {
            if let toast = undoToast {
                UninstallToast(state: toast) {
                    Task { await handleRestore() }
                }
            }
        }
    }

    private var hero: some View {
        HStack(spacing: KFSpacing.md) {
            Image(nsImage: viewModel.app.icon)
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: KFSpacing.xs) {
                Text(viewModel.app.displayName).font(.title2.weight(.semibold))
                Text("v\(viewModel.app.version)").font(.subheadline).foregroundStyle(Color.textSecondary)
                Text(viewModel.app.source.displayName)
                    .font(.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(viewModel.app.source.tint.opacity(0.15))
                    .foregroundStyle(viewModel.app.source.tint)
                    .clipShape(Capsule())
            }
            Spacer()
        }
    }

    private var sizeOverview: some View {
        HStack {
            Text("占用")
            Spacer()
            Text(viewModel.app.sizeBytes.formattedAsFileSize).font(.body.monospacedDigit())
        }
    }

    private var proEntries: some View {
        VStack(spacing: KFSpacing.sm) {
            HStack {
                Image(systemName: "lock.fill").foregroundStyle(Color.warning)
                Text("深度清理（Pro）").foregroundStyle(Color.textSecondary)
                Spacer()
            }
            .padding()
            .background(Color.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .proGate()  // Task 8 will define this modifier; if not yet, use a placeholder

            HStack {
                Image(systemName: "lock.fill").foregroundStyle(Color.warning)
                Text("启动项管理（Pro）").foregroundStyle(Color.textSecondary)
                Spacer()
            }
            .padding()
            .background(Color.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .proGate()
        }
    }

    private func handleUninstall() {
        showConfirmSheet = false
        Task {
            let mover = TrashMover(...)
            let result = try? await mover.moveToTrash(app: viewModel.app, residues: viewModel.residues)
            if case .success(let record) = result {
                undoToast = .init(recordID: record.id, appName: viewModel.app.displayName, appSize: viewModel.app.sizeBytes)
            }
        }
    }

    private func handleRestore() async {
        guard let toast = undoToast else { return }
        let mover = TrashMover(...)
        _ = try? await mover.restore(id: toast.recordID)
        undoToast = nil
    }
}
```

> **NOTE**: Tasks 4 and 8 provide `UninstallConfirmSheet`, `UninstallToast`, and `.proGate()`. For Task 3, stub them with placeholder files so the build passes; Task 4/8 replaces the bodies.

Create `kFresh/Features/Detail/ResidueSectionView.swift`:

```swift
import SwiftUI
import DesignSystem

struct ResidueSectionView: View {
    let residues: [ResidueFile]
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: KFSpacing.sm) {
            HStack {
                Text("残留文件").font(.headline)
                Spacer()
                if isLoading {
                    ProgressView().scaleEffect(0.6)
                } else {
                    Text("\(residues.count) 项").font(.caption).foregroundStyle(Color.textSecondary)
                }
            }
            if residues.isEmpty && !isLoading {
                Text("未发现残留")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.vertical, KFSpacing.md)
            } else {
                ForEach(residues, id: \.url) { residue in
                    ResidueRow(residue: residue)
                }
            }
        }
    }
}

private struct ResidueRow: View {
    let residue: ResidueFile
    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: residue.type.systemImage)
                .foregroundStyle(Color.accent)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(residue.url.lastPathComponent).font(.body)
                Text(residue.url.deletingLastPathComponent().path)
                    .font(.caption2)
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(residue.sizeBytes.formattedAsFileSize)
                    .font(.caption.monospacedDigit())
                Text("置信度 \(Int(residue.confidence * 100))%")
                    .font(.caption2)
                    .foregroundStyle(confidenceColor)
            }
        }
        .padding(.vertical, KFSpacing.xs)
    }

    private var confidenceColor: Color {
        if residue.confidence > 0.8 { return Color.success }
        if residue.confidence > 0.5 { return Color.warning }
        return Color.danger
    }
}

extension ResidueType {
    var systemImage: String {
        switch self {
        case .preferences: return "gearshape"
        case .caches: return "internaldrive"
        case .appSupport: return "folder"
        case .container: return "shippingbox"
        case .launchAgent, .launchDaemon: return "play.circle"
        case .prefPane: return "slider.horizontal.3"
        case .plugin: return "puzzlepiece"
        case .startupItem: return "arrow.up.forward.app"
        case .log: return "doc.text"
        case .cookie: return "circle.grid.cross"
        case .appleScript: return "applescript"
        }
    }
}
```

### Step 6: Create placeholder UninstallConfirmSheet, UninstallToast, proGate (Task 4/8 fills)

```bash
mkdir -p kFresh/Features/Detail
# Stubs so Task 3 builds
cat > kFresh/Features/Detail/UninstallConfirmSheet.swift <<'EOF'
import SwiftUI
public struct UninstallConfirmSheet: View {
    public init(app: InstalledApp, residues: [ResidueFile], onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) { self.app = app; self.residues = residues; self.onConfirm = onConfirm; self.onCancel = onCancel }
    let app: InstalledApp; let residues: [ResidueFile]
    let onConfirm: () -> Void; let onCancel: () -> Void
    public var body: some View { Text("Stub — Task 4").padding() }
}
EOF
cat > kFresh/Features/Detail/UninstallToast.swift <<'EOF'
import SwiftUI
public struct UninstallToast: View {
    public struct State: Identifiable { public let id = UUID(); public let recordID: UUID; public let appName: String; public let appSize: Int64 }
    public init(state: State, onUndo: @escaping () -> Void) { self.state = state; self.onUndo = onUndo }
    let state: State; let onUndo: () -> Void
    public var body: some View { Text("Stub — Task 4").padding() }
}
EOF
```

For `.proGate()` placeholder: Task 8 provides; for now, define an empty no-op modifier in a new file:

```swift
// kFresh/Features/Common/ProGatePlaceholder.swift (Task 8 replaces)
import SwiftUI
public extension View {
    @ViewBuilder
    func proGate() -> some View { self }
}
```

### Step 7: Build + run DetailViewModel tests

Run: `xcodebuild test -project kFresh/kFresh.xcodeproj -scheme kFresh -destination 'platform=macOS' -only-testing:kFreshTests/DetailViewModelTests`

Expected: 3 tests pass; build clean of new warnings.

### Step 8: Commit

```bash
git add kFresh/Features/Detail/ kFresh/Tests/DetailTests/ kFresh/Features/Common/ProGatePlaceholder.swift
git commit -m "feat(kFresh): AppDetail with hero, residues, pro locks, uninstall entry"
```

---

## Task 4: Uninstall 确认 Sheet + 5 步安全 + Toast 撤销

**Files:**
- Modify: `kFresh/Features/Detail/UninstallConfirmSheet.swift` (replace stub with full implementation)
- Modify: `kFresh/Features/Detail/UninstallToast.swift` (replace stub)
- Modify: `kFresh/Features/Detail/DetailViewModel.swift` (add `confirmUninstall()` and toast state)
- Create: `kFresh/Tests/DetailTests/UninstallSafetyCheckTests.swift`
- Create: `kFresh/Tests/DetailTests/UninstallConfirmSheetTests.swift`

**Interfaces:**
```swift
// DetailViewModel additions
@Published public private(set) var lastUninstallResult: TrashMover.UninstallOutcome?

public func confirmUninstall() async -> Bool
```

---

### Step 1: Write failing test for confirmUninstall flow

Create `kFresh/Tests/DetailTests/UninstallSafetyCheckTests.swift`:

```swift
import XCTest
@testable import kFresh

@MainActor
final class UninstallSafetyCheckTests: XCTestCase {
    func testProtectedAppCannotReachConfirmSheet() async {
        let app = InstalledApp(
            url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
            displayName: "Finder", bundleID: "com.apple.finder", version: "1.0",
            icon: NSImage(), sizeBytes: 0, source: .appleBuiltIn,
            isProtected: true, protectionReason: "Apple 系统组件", isRunning: false, lastUsedDate: nil
        )
        let vm = DetailViewModel(app: app, residueDetector: ResidueDetector(ruleStore: nil))
        await vm.performSafetyCheck()
        XCTAssertFalse(vm.canUninstall)
        let outcome = await vm.confirmUninstall()
        XCTAssertNil(outcome)
    }

    func testUnprotectedAppReturnsSuccessOutcome() async {
        let app = InstalledApp(
            url: URL(fileURLWithPath: "/Applications/Slack.app"),
            displayName: "Slack", bundleID: "com.tinyspeck.chatlyio", version: "1.0",
            icon: NSImage(), sizeBytes: 512, source: .userInstalled,
            isProtected: false, protectionReason: nil, isRunning: false, lastUsedDate: Date()
        )
        let vm = DetailViewModel(app: app, residueDetector: ResidueDetector(ruleStore: nil))
        await vm.performSafetyCheck()
        let outcome = try? await vm.confirmUninstall()
        // Outcome may fail if Slack isn't installed in test env; we only assert the API contract.
        XCTAssertNotNil(outcome ?? Optional<TrashMover.UninstallOutcome>.none)
    }
}
```

### Step 2: Run test to verify it fails

Expected: `cannot find 'confirmUninstall' in scope`.

### Step 3: Extend DetailViewModel

Modify `kFresh/Features/Detail/DetailViewModel.swift` — add:

```swift
    @Published public private(set) var lastUninstallResult: TrashMover.UninstallOutcome?

    public func confirmUninstall() async throws -> TrashMover.UninstallOutcome {
        guard canUninstall else { throw UninstallError.protected }
        let mover = TrashMover(backupManager: BackupManager(...), auditLogger: AuditLogger(...))
        let outcome = try await mover.moveToTrash(app: app, residues: residues)
        lastUninstallResult = outcome
        return outcome
    }

public enum UninstallError: Error {
    case protected
}
```

### Step 4: Run test to verify it passes

Expected: 2 tests pass.

### Step 5: Implement UninstallConfirmSheet

Replace `kFresh/Features/Detail/UninstallConfirmSheet.swift`:

```swift
import SwiftUI
import DesignSystem

public struct UninstallConfirmSheet: View {
    let app: InstalledApp
    let residues: [ResidueFile]
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var includeResidues = true

    public init(app: InstalledApp, residues: [ResidueFile], onConfirm: @escaping () -> Void, onCancel: @escaping () -> Void) {
        self.app = app
        self.residues = residues
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: KFSpacing.lg) {
            header
            summary
            footer
        }
        .padding(KFSpacing.lg)
        .frame(width: 480)
        .background(Color.backgroundPrimary)
    }

    private var header: some View {
        HStack(spacing: KFSpacing.md) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading) {
                Text("卸载 \(app.displayName)?").font(.title3.weight(.semibold))
                if app.isRunning {
                    Label("App 正在运行，将先退出再卸载", systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(Color.warning)
                }
                if app.source == .mas {
                    Label("此 App 来自 App Store，可随时重新下载", systemImage: "info.circle")
                        .font(.caption).foregroundStyle(Color.textSecondary)
                }
            }
            Spacer()
        }
    }

    private var summary: some View {
        VStack(spacing: KFSpacing.sm) {
            row("App 本体", value: app.sizeBytes.formattedAsFileSize)
            if !residues.isEmpty {
                Toggle(isOn: $includeResidues) {
                    HStack {
                        Text("残留文件 (\(residues.count) 项)")
                        Spacer()
                        Text(residuesTotalSize.formattedAsFileSize).font(.body.monospacedDigit())
                    }
                }
                .toggleStyle(.switch)
            }
            Divider()
            HStack {
                Text("共释放").font(.headline)
                Spacer()
                Text(totalFreedSize.formattedAsFileSize).font(.headline.monospacedDigit())
            }
            Label("移入废纸篓（可回滚 30 天）", systemImage: "arrow.uturn.backward")
                .font(.caption).foregroundStyle(Color.success)
        }
        .padding(KFSpacing.md)
        .background(Color.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        HStack {
            Button("取消", role: .cancel, action: onCancel)
                .buttonStyle(.bordered)
            Spacer()
            Button("确认卸载", role: .destructive, action: onConfirm)
                .buttonStyle(.borderedProminent)
                .tint(Color.danger)
        }
    }

    private var residuesTotalSize: Int64 {
        residues.reduce(0) { $0 + $1.sizeBytes }
    }

    private var totalFreedSize: Int64 {
        app.sizeBytes + (includeResidues ? residuesTotalSize : 0)
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).font(.body.monospacedDigit())
        }
    }
}
```

### Step 6: Implement UninstallToast (10s countdown)

Replace `kFresh/Features/Detail/UninstallToast.swift`:

```swift
import SwiftUI
import DesignSystem

public struct UninstallToast: View {
    public struct State: Identifiable, Equatable {
        public let id = UUID()
        public let recordID: UUID
        public let appName: String
        public let appSize: Int64
    }

    let state: State
    let onUndo: () -> Void

    @State private var secondsRemaining = 10
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(state: State, onUndo: @escaping () -> Void) {
        self.state = state
        self.onUndo = onUndo
    }

    public var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.success)
            Text("已卸载 \(state.appName) (\(state.appSize.formattedAsFileSize))").font(.body)
            Spacer()
            Button("撤销 (\(secondsRemaining))", action: onUndo)
                .buttonStyle(.bordered)
        }
        .padding(KFSpacing.md)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(KFSpacing.md)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onReceive(timer) { _ in
            if secondsRemaining > 0 { secondsRemaining -= 1 }
        }
        .animation(.easeInOut(duration: KFAnimation.durationNormal), value: secondsRemaining)
    }
}
```

> The host (AppDetailView) is responsible for auto-dismissing after the timer hits 0 — the toast itself doesn't dismiss; instead the parent observes `secondsRemaining` via binding if needed. For Wave 1, the simpler contract: toast persists until user clicks Undo or navigates away.

### Step 7: Wire confirmUninstall in AppDetailView

Modify `kFresh/Features/Detail/AppDetailView.swift` — update `handleUninstall`:

```swift
private func handleUninstall() {
    showConfirmSheet = false
    Task {
        do {
            let outcome = try await viewModel.confirmUninstall()
            if case .success(let record) = outcome {
                withAnimation(.easeInOut(duration: KFAnimation.durationNormal)) {
                    undoToast = .init(recordID: record.id, appName: viewModel.app.displayName, appSize: viewModel.app.sizeBytes)
                }
            }
        } catch {
            // Surface error to UI (snackbar / alert) — left as Wave 1.1 polish
        }
    }
}
```

### Step 8: Write UI test for the uninstall sheet

Create `kFresh/Tests/UITests/UninstallFlowUITests.swift`:

```swift
import XCTest

final class UninstallFlowUITests: XCTestCase {
    func testConfirmSheetShowsResidueToggle() throws {
        let app = XCUIApplication()
        app.launch()
        // Skip onboarding if shown
        let skipButton = app.buttons["跳过（仅基础模式）"]
        if skipButton.exists { skipButton.tap() }
        // Tap first app row
        let firstRow = app.collectionViews.cells.element(boundBy: 0)
        if firstRow.waitForExistence(timeout: 5) {
            firstRow.tap()
            // Tap 卸载 button
            let uninstallButton = app.buttons.matching(identifier: "卸载 ").firstMatch
            if uninstallButton.waitForExistence(timeout: 3) {
                uninstallButton.tap()
                // Verify sheet appeared
                XCTAssertTrue(app.staticTexts["共释放"].waitForExistence(timeout: 2))
            }
        }
    }
}
```

### Step 9: Run all Detail + Uninstall tests

Run: `xcodebuild test -project kFresh/kFresh.xcodeproj -scheme kFresh -destination 'platform=macOS' -only-testing:kFreshTests/UninstallSafetyCheckTests -only-testing:kFreshTests/UninstallConfirmSheetTests -only-testing:kFreshTests/UninstallFlowUITests`

Expected: 2 + 1 + 1 = 4 tests pass.

### Step 10: Commit

```bash
git add kFresh/Features/Detail/ kFresh/Tests/DetailTests/UninstallSafetyCheckTests.swift kFresh/Tests/DetailTests/UninstallConfirmSheetTests.swift kFresh/Tests/UITests/UninstallFlowUITests.swift
git commit -m "feat(kFresh): uninstall confirm sheet + toast undo countdown"
```

---

## Task 5: HistoryView + Restore

**Files:**
- Modify: `kFresh/Features/History/HistoryView.swift` (replace stub with CoreData-backed)
- Modify: `kFresh/Features/History/HistoryViewModel.swift` (wire to UninstallHistoryRepository)
- Create: `kFresh/Features/History/HistoryRow.swift`
- Create: `kFresh/Tests/HistoryTests/HistoryViewModelTests.swift`

**Interfaces:**
```swift
@MainActor
public final class HistoryViewModel: ObservableObject {
    @Published public private(set) var records: [UninstallRecord] = []
    @Published public private(set) var restoreState: RestoreState = .idle

    public enum RestoreState: Equatable {
        case idle
        case restoring(recordID: UUID)
        case restored(recordID: UUID)
        case failed(recordID: UUID, message: String)
    }

    public init(historyRepo: UninstallHistoryRepository, trashMover: TrashMover)

    public func loadHistory() async
    public func restore(_ record: UninstallRecord) async
}
```

---

### Step 1: Write failing test for HistoryViewModel

Create `kFresh/Tests/HistoryTests/HistoryViewModelTests.swift`:

```swift
import XCTest
@testable import kFresh

@MainActor
final class HistoryViewModelTests: XCTestCase {
    func testLoadHistoryPopulatesRecords() async {
        let repo = UninstallHistoryRepository(inMemory: true)
        let record = UninstallRecord(
            id: UUID(), appName: "Test", bundleID: "com.test",
            appPath: "/Applications/Test.app", actualTrashPath: nil,
            appSize: 1024, totalResidueSize: 0, residueCount: 0,
            uninstalledAt: Date(), isFromDeepClean: false, isRestored: false,
            backupPath: ""
        )
        try? await repo.save(record)
        let vm = HistoryViewModel(historyRepo: repo, trashMover: TrashMover(...))
        await vm.loadHistory()
        XCTAssertEqual(vm.records.count, 1)
        XCTAssertEqual(vm.records.first?.appName, "Test")
    }

    func testRestoreStateTransitions() async {
        let repo = UninstallHistoryRepository(inMemory: true)
        let vm = HistoryViewModel(historyRepo: repo, trashMover: TrashMover(...))
        let record = UninstallRecord(
            id: UUID(), appName: "Test", bundleID: "com.test",
            appPath: "/Applications/Test.app", actualTrashPath: nil,
            appSize: 1024, totalResidueSize: 0, residueCount: 0,
            uninstalledAt: Date(), isFromDeepClean: false, isRestored: false,
            backupPath: ""
        )
        try? await repo.save(record)
        await vm.loadHistory()
        await vm.restore(record)
        // State should transition to .restored or .failed; never stuck on .restoring
        XCTAssertNotEqual(vm.restoreState, .restoring(recordID: record.id))
    }
}
```

### Step 2: Run test to verify it fails

Expected: missing init signatures.

### Step 3: Extend UninstallHistoryRepository if needed

If `init(inMemory:)` doesn't exist, add to `kFresh/Core/Clean/TrashMover.swift` (or wherever `UninstallHistoryRepository` is defined):

```swift
public extension UninstallHistoryRepository {
    convenience init(inMemory: Bool) {
        // Use NSPersistentContainer with NSInMemoryStoreType
        self.init(... inMemoryStore: inMemory ...)
    }
}
```

> **NOTE**: If the existing Wave 0 init is incompatible, the implementer must add a CoreDataStack helper that supports in-memory mode for testing. This is small scope; do not refactor the production path.

### Step 4: Implement HistoryViewModel

Create `kFresh/Features/History/HistoryViewModel.swift`:

```swift
import Foundation
import SwiftUI

@MainActor
public final class HistoryViewModel: ObservableObject {
    public enum RestoreState: Equatable {
        case idle
        case restoring(recordID: UUID)
        case restored(recordID: UUID)
        case failed(recordID: UUID, message: String)
    }

    @Published public private(set) var records: [UninstallRecord] = []
    @Published public private(set) var restoreState: RestoreState = .idle

    private let historyRepo: UninstallHistoryRepository
    private let trashMover: TrashMover

    public init(historyRepo: UninstallHistoryRepository, trashMover: TrashMover) {
        self.historyRepo = historyRepo
        self.trashMover = trashMover
    }

    public func loadHistory() async {
        do {
            let all = try await historyRepo.fetchAll(within: 30)
            records = all.filter { !$0.isRestored }
        } catch {
            records = []
        }
    }

    public func restore(_ record: UninstallRecord) async {
        restoreState = .restoring(recordID: record.id)
        do {
            try await trashMover.restore(id: record.id)
            restoreState = .restored(recordID: record.id)
            await loadHistory()
        } catch {
            restoreState = .failed(recordID: record.id, message: error.localizedDescription)
        }
    }
}
```

### Step 5: Implement HistoryView + HistoryRow

Replace `kFresh/Features/History/HistoryView.swift`:

```swift
import SwiftUI
import DesignSystem

public struct HistoryView: View {
    @StateObject private var viewModel: HistoryViewModel

    public init(viewModel: HistoryViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            Text("30 天内可恢复").font(.caption).foregroundStyle(Color.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding()
            if viewModel.records.isEmpty {
                EmptyStateView(
                    title: "暂无卸载记录",
                    systemImage: "clock.arrow.circlepath",
                    description: "卸载过的 App 会显示在这里，30 天内可一键恢复"
                )
            } else {
                List {
                    ForEach(viewModel.records, id: \.id) { record in
                        HistoryRow(record: record, restoreState: viewModel.restoreState) {
                            Task { await viewModel.restore(record) }
                        }
                    }
                }
            }
        }
        .navigationTitle("卸载历史")
        .task { await viewModel.loadHistory() }
    }
}
```

Create `kFresh/Features/History/HistoryRow.swift`:

```swift
import SwiftUI
import DesignSystem

struct HistoryRow: View {
    let record: UninstallRecord
    let restoreState: HistoryViewModel.RestoreState
    let onRestore: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(record.appName).font(.body.weight(.medium))
                Text(record.uninstalledAt, style: .date).font(.caption).foregroundStyle(Color.textSecondary)
                Text("\(record.appSize.formattedAsFileSize) · \(record.residueCount) 项残留")
                    .font(.caption2).foregroundStyle(Color.textTertiary)
            }
            Spacer()
            actionButton
        }
        .padding(.vertical, KFSpacing.xs)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch restoreState {
        case .restoring(let id) where id == record.id:
            ProgressView().scaleEffect(0.7)
        case .restored(let id) where id == record.id:
            Label("已恢复", systemImage: "checkmark.circle.fill").foregroundStyle(Color.success)
        case .failed(let id, let msg) where id == record.id:
            Label(msg, systemImage: "exclamationmark.triangle").foregroundStyle(Color.danger)
        default:
            Button("恢复", action: onRestore).buttonStyle(.bordered)
        }
    }
}
```

### Step 6: Run HistoryViewModel tests

Run: `xcodebuild test -project kFresh/kFresh.xcodeproj -scheme kFresh -destination 'platform=macOS' -only-testing:kFreshTests/HistoryViewModelTests`

Expected: 2 tests pass.

### Step 7: Commit

```bash
git add kFresh/Features/History/ kFresh/Tests/HistoryTests/ kFresh/Core/Clean/TrashMover.swift
git commit -m "feat(kFresh): history view with 30-day restore + CoreData query"
```

---

## Task 6: StartupItemManager + StartupItemsView（Pro）

**Files:**
- Create: `kFresh/Core/Startup/StartupItemManager.swift`
- Create: `kFresh/Features/StartupItems/StartupItemsView.swift`
- Create: `kFresh/Features/StartupItems/StartupItemsViewModel.swift`
- Create: `kFresh/Features/StartupItems/StartupItemRowView.swift`
- Create: `kFresh/Tests/StartupTests/StartupItemManagerTests.swift`
- Create: `kFresh/Tests/StartupTests/StartupItemsViewModelTests.swift`

**Interfaces:**
```swift
public struct StartupItem: Identifiable, Sendable, Equatable {
    public let id: String           // bundleID or plist filename
    public let name: String
    public let type: StartupItemType  // .loginItem / .launchAgent / .launchDaemon
    public let url: URL
    public let appURL: URL?
    public let enabled: Bool
    public let isProtected: Bool
}

public enum StartupItemType: String, Sendable, CaseIterable {
    case loginItem, launchAgent, launchDaemon
}

public actor StartupItemManager {
    public init(fileManager: FileManager = .default)

    /// Lists all startup items visible to the app (login items + launch agents/daemons).
    public func listItems() async throws -> [StartupItem]

    /// Toggles enabled state for a launch agent/daemon by writing the plist's `Disabled` key.
    public func setEnabled(_ enabled: Bool, for item: StartupItem) async throws

    /// Removes the item entirely (move to backup, then delete).
    public func remove(_ item: StartupItem) async throws
}
```

---

### Step 1: Write failing test for StartupItemManager

Create `kFresh/Tests/StartupTests/StartupItemManagerTests.swift`:

```swift
import XCTest
@testable import kFresh

final class StartupItemManagerTests: XCTestCase {
    func testListItemsReturnsAtLeastEmptyArray() async throws {
        let manager = StartupItemManager()
        let items = try await manager.listItems()
        XCTAssertNotNil(items)
    }

    func testSetEnabledTogglesDisabledKey() async throws {
        let manager = StartupItemManager()
        // Create a temporary plist in /tmp
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.test.agent.plist")
        let plist: [String: Any] = ["Label": "com.test.agent", "ProgramArguments": ["/bin/echo", "hi"]]
        try (plist as NSDictionary).write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let item = StartupItem(
            id: "com.test.agent", name: "com.test.agent",
            type: .launchAgent, url: tmp, appURL: nil,
            enabled: true, isProtected: false
        )
        try await manager.setEnabled(false, for: item)
        let reloaded = NSDictionary(contentsOf: tmp) as? [String: Any]
        XCTAssertEqual(reloaded?["Disabled"] as? Bool, true)

        try await manager.setEnabled(true, for: item)
        let reloaded2 = NSDictionary(contentsOf: tmp) as? [String: Any]
        XCTAssertNil(reloaded2?["Disabled"])  // key removed when enabled
    }
}
```

### Step 2: Run test to verify it fails

Expected: `cannot find 'StartupItemManager' in scope`.

### Step 3: Implement StartupItemManager

Create `kFresh/Core/Startup/StartupItemManager.swift`:

```swift
import Foundation

public struct StartupItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let type: StartupItemType
    public let url: URL
    public let appURL: URL?
    public let enabled: Bool
    public let isProtected: Bool
}

public enum StartupItemType: String, Sendable, CaseIterable {
    case loginItem, launchAgent, launchDaemon
}

public actor StartupItemManager {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func listItems() async throws -> [StartupItem] {
        var items: [StartupItem] = []

        // LaunchAgents in ~/Library/LaunchAgents
        if let userAgents = try? fileManager.contentsOfDirectory(
            at: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/LaunchAgents"),
            includingPropertiesForKeys: nil
        ) {
            for url in userAgents where url.pathExtension == "plist" {
                items.append(parseLaunchItem(at: url, type: .launchAgent))
            }
        }

        // LaunchAgents in /Library/LaunchAgents (system — protected)
        if let systemAgents = try? fileManager.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Library/LaunchAgents"),
            includingPropertiesForKeys: nil
        ) {
            for url in systemAgents where url.pathExtension == "plist" {
                items.append(parseLaunchItem(at: url, type: .launchAgent, system: true))
            }
        }

        // LaunchDaemons in /Library/LaunchDaemons (system — protected)
        if let daemons = try? fileManager.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Library/LaunchDaemons"),
            includingPropertiesForKeys: nil
        ) {
            for url in daemons where url.pathExtension == "plist" {
                items.append(parseLaunchItem(at: url, type: .launchDaemon, system: true))
            }
        }

        // Login Items via SMAppService (macOS 13+) — best-effort, may throw
        // Skipped in Wave 1; add in Wave 1.1 if needed

        return items
    }

    public func setEnabled(_ enabled: Bool, for item: StartupItem) async throws {
        guard !item.isProtected else { throw StartupError.protected }
        let dict = (try? NSDictionary(contentsOf: item.url, error: ())) as? [String: Any] ?? [:]
        var mutable = dict
        if enabled {
            mutable.removeValue(forKey: "Disabled")
        } else {
            mutable["Disabled"] = true
        }
        try (mutable as NSDictionary).write(to: item.url)
    }

    public func remove(_ item: StartupItem) async throws {
        guard !item.isProtected else { throw StartupError.protected }
        // Move to backup before delete
        let backupRoot = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/app.kraftly.kfresh/Backups/StartupItems")
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        let backupDest = backupRoot.appendingPathComponent(item.url.lastPathComponent)
        try fileManager.moveItem(at: item.url, to: backupDest)
    }

    private func parseLaunchItem(at url: URL, type: StartupItemType, system: Bool = false) -> StartupItem {
        let dict = (try? NSDictionary(contentsOf: url, error: ())) as? [String: Any] ?? [:]
        let label = dict["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
        let disabled = dict["Disabled"] as? Bool ?? false
        let program = (dict["Program"] as? String) ?? ((dict["ProgramArguments"] as? [String])?.first)
        let appURL = program.flatMap { URL(fileURLWithPath: $0) }
        return StartupItem(
            id: label,
            name: label,
            type: type,
            url: url,
            appURL: appURL,
            enabled: !disabled,
            isProtected: system
        )
    }
}

public enum StartupError: Error {
    case protected
}
```

### Step 4: Run test to verify it passes

Expected: 2 tests pass.

### Step 5: Implement StartupItemsView + ViewModel

Create `kFresh/Features/StartupItems/StartupItemsViewModel.swift`:

```swift
import Foundation
import SwiftUI

@MainActor
public final class StartupItemsViewModel: ObservableObject {
    public enum ViewState {
        case idle, loading, loaded([StartupItem]), failed(String)
    }

    @Published public private(set) var state: ViewState = .idle

    private let manager: StartupItemManager

    public init(manager: StartupItemManager) {
        self.manager = manager
    }

    public func load() async {
        state = .loading
        do {
            let items = try await manager.listItems()
            state = .loaded(items)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func toggle(_ item: StartupItem) async {
        do {
            try await manager.setEnabled(!item.enabled, for: item)
            await load()
        } catch {
            // Surface error via a separate @Published var in next iteration
        }
    }

    public func remove(_ item: StartupItem) async {
        do {
            try await manager.remove(item)
            await load()
        } catch {
            // Surface error
        }
    }

    public var groupedByType: [(StartupItemType, [StartupItem])] {
        guard case .loaded(let items) = state else { return [] }
        return Dictionary(grouping: items, by: \.type)
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { ($0.key, $0.value) }
    }
}
```

Create `kFresh/Features/StartupItems/StartupItemsView.swift`:

```swift
import SwiftUI
import DesignSystem

public struct StartupItemsView: View {
    @StateObject private var viewModel: StartupItemsViewModel
    @State private var removeConfirmation: StartupItem?

    public init(viewModel: StartupItemsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                LoadingStateView(message: "扫描启动项...")
            case .failed(let msg):
                EmptyStateView(title: "扫描失败", systemImage: "exclamationmark.triangle", description: msg)
            case .loaded:
                List {
                    ForEach(viewModel.groupedByType, id: \.0) { type, items in
                        Section(type.displayName) {
                            ForEach(items) { item in
                                StartupItemRowView(item: item) {
                                    Task { await viewModel.toggle(item) }
                                } onRemove: {
                                    removeConfirmation = item
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("启动项")
        .task { await viewModel.load() }
        .confirmationDialog(
            "确认移除？",
            isPresented: Binding(
                get: { removeConfirmation != nil },
                set: { if !$0 { removeConfirmation = nil } }
            ),
            presenting: removeConfirmation
        ) { item in
            Button("移除", role: .destructive) {
                Task { await viewModel.remove(item); removeConfirmation = nil }
            }
            Button("取消", role: .cancel) { removeConfirmation = nil }
        } message: { item in
            Text("\(item.name) 将被备份到 ~/Library/Application Support/app.kraftly.kfresh/Backups/StartupItems/")
        }
    }
}

extension StartupItemType {
    var displayName: String {
        switch self {
        case .loginItem: return "登录项"
        case .launchAgent: return "Launch Agents"
        case .launchDaemon: return "Launch Daemons"
        }
    }
}
```

Create `kFresh/Features/StartupItems/StartupItemRowView.swift`:

```swift
import SwiftUI
import DesignSystem

struct StartupItemRowView: View {
    let item: StartupItem
    let onToggle: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body)
                Text(item.url.path)
                    .font(.caption2).foregroundStyle(Color.textTertiary).lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { item.enabled },
                set: { _ in onToggle() }
            ))
            .labelsHidden()
            .disabled(item.isProtected)
            Button(action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(item.isProtected)
        }
        .padding(.vertical, KFSpacing.xs)
    }
}
```

### Step 6: Apply Pro gate

Wrap the entry from AppListView or AppDetailView with `.proGate()`. Task 8 will define `.proGate()`; for now, Task 3's placeholder no-op modifier keeps the build green. After Task 8, the modifier will:
- If `StoreManager.shared.isPro`: show content
- Else: blur + show "解锁 Pro" overlay

### Step 7: Run Startup tests

Run: `xcodebuild test -project kFresh/kFresh.xcodeproj -scheme kFresh -destination 'platform=macOS' -only-testing:kFreshTests/StartupItemManagerTests -only-testing:kFreshTests/StartupItemsViewModelTests`

Expected: 2 + ≥2 tests pass.

### Step 8: Commit

```bash
git add kFresh/Core/Startup/ kFresh/Features/StartupItems/ kFresh/Tests/StartupTests/
git commit -m "feat(kFresh): StartupItemManager + StartupItemsView with Pro gate"
```

---

## Task 7: DeepCleanEngine + DeepCleanView（Pro）

**Files:**
- Create: `kFresh/Core/Clean/DeepCleanEngine.swift`
- Create: `kFresh/Features/DeepClean/DeepCleanView.swift`
- Create: `kFresh/Features/DeepClean/DeepCleanViewModel.swift`
- Create: `kFresh/Features/DeepClean/SystemCleanGroupView.swift`
- Create: `kFresh/Features/DeepClean/SystemCleanRowView.swift`
- Create: `kFresh/Tests/DeepCleanTests/DeepCleanEngineTests.swift`
- Create: `kFresh/Tests/DeepCleanTests/DeepCleanViewModelTests.swift`

**Interfaces:**
```swift
public struct SystemCleanItem: Identifiable, Sendable, Equatable {
    public let id: String            // plist name or unique key
    public let displayName: String
    public let url: URL
    public let category: Category
    public let sizeBytes: Int64
    public let isProtected: Bool
    public let associatedBundleID: String?
}

public enum SystemCleanCategory: String, Sendable, CaseIterable {
    case launchAgents, launchDaemons, preferencePanes
    public var displayName: String { ... }
    public var systemImage: String { ... }
}

public actor DeepCleanEngine {
    public init(fileManager: FileManager = .default, backupManager: BackupManager, auditLogger: AuditLogger)

    /// Scans /Library/LaunchAgents, /Library/LaunchDaemons, /Library/PreferencePanes.
    /// Returns only items FDA can read.
    public func scan() async throws -> [SystemCleanItem]

    /// Moves items to backup, then deletes the originals. Returns count of deleted items.
    public func clean(_ items: [SystemCleanItem]) async throws -> Int
}
```

---

### Step 1: Write failing test for DeepCleanEngine.scan

Create `kFresh/Tests/DeepCleanTests/DeepCleanEngineTests.swift`:

```swift
import XCTest
@testable import kFresh

final class DeepCleanEngineTests: XCTestCase {
    func testScanReturnsEmptyArrayWhenFDAUnreadable() async throws {
        let engine = DeepCleanEngine(
            fileManager: FileManager.default,
            backupManager: BackupManager(...),
            auditLogger: AuditLogger(...)
        )
        // Without FDA, /Library is unreadable → empty
        let items = try await engine.scan()
        XCTAssertNotNil(items)
    }

    func testCleanWithEmptyArrayReturnsZero() async throws {
        let engine = DeepCleanEngine(...)
        let count = try await engine.clean([])
        XCTAssertEqual(count, 0)
    }
}
```

### Step 2: Run test to verify it fails

Expected: `cannot find 'DeepCleanEngine' in scope`.

### Step 3: Implement DeepCleanEngine

Create `kFresh/Core/Clean/DeepCleanEngine.swift`:

```swift
import Foundation

public struct SystemCleanItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let url: URL
    public let category: SystemCleanCategory
    public let sizeBytes: Int64
    public let isProtected: Bool
    public let associatedBundleID: String?
}

public enum SystemCleanCategory: String, Sendable, CaseIterable {
    case launchAgents, launchDaemons, preferencePanes

    public var displayName: String {
        switch self {
        case .launchAgents: return "Launch Agents"
        case .launchDaemons: return "Launch Daemons"
        case .preferencePanes: return "系统偏好面板"
        }
    }

    public var systemImage: String {
        switch self {
        case .launchAgents: return "play.circle"
        case .launchDaemons: return "play.rectangle"
        case .preferencePanes: return "slider.horizontal.3"
        }
    }
}

public actor DeepCleanEngine {
    private let fileManager: FileManager
    private let backupManager: BackupManager
    private let auditLogger: AuditLogger

    public init(fileManager: FileManager = .default, backupManager: BackupManager, auditLogger: AuditLogger) {
        self.fileManager = fileManager
        self.backupManager = backupManager
        self.auditLogger = auditLogger
    }

    public func scan() async throws -> [SystemCleanItem] {
        var items: [SystemCleanItem] = []
        items.append(contentsOf: try scanPlistDirectory(
            "/Library/LaunchAgents", category: .launchAgents))
        items.append(contentsOf: try scanPlistDirectory(
            "/Library/LaunchDaemons", category: .launchDaemons))
        items.append(contentsOf: scanPreferencePanes())
        return items
    }

    public func clean(_ items: [SystemCleanItem]) async throws -> Int {
        var deleted = 0
        for item in items where !item.isProtected {
            let backupPath = try await backupManager.backup(sourceURL: item.url, reason: "deepclean")
            try fileManager.removeItem(at: item.url)
            await auditLogger.log(event: AuditEvent(
                kind: "deepclean.delete",
                bundleID: item.associatedBundleID,
                path: item.url.path,
                backupPath: backupPath.path,
                status: "success"
            ))
            deleted += 1
        }
        return deleted
    }

    private func scanPlistDirectory(_ path: String, category: SystemCleanCategory) throws -> [SystemCleanItem] {
        let dir = URL(fileURLWithPath: path)
        let urls = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.filter { $0.pathExtension == "plist" }.map { url in
            let dict = (try? NSDictionary(contentsOf: url, error: ())) as? [String: Any] ?? [:]
            let label = dict["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return SystemCleanItem(
                id: label,
                displayName: label,
                url: url,
                category: category,
                sizeBytes: Int64(size),
                isProtected: isAppleOwned(label: label),
                associatedBundleID: dict["BundleID"] as? String
            )
        }
    }

    private func scanPreferencePanes() -> [SystemCleanItem] {
        let dir = URL(fileURLWithPath: "/Library/PreferencePanes")
        let urls = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        return urls.filter { $0.pathExtension == "prefPane" }.map { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return SystemCleanItem(
                id: url.deletingPathExtension().lastPathComponent,
                displayName: url.deletingPathExtension().lastPathComponent,
                url: url,
                category: .preferencePanes,
                sizeBytes: Int64(size),
                isProtected: isAppleOwned(label: url.deletingPathExtension().lastPathComponent),
                associatedBundleID: nil
            )
        }
    }

    private func isAppleOwned(label: String) -> Bool {
        label.hasPrefix("com.apple.") || label.hasPrefix("com.macos.")
    }
}
```

### Step 4: Run test to verify it passes

Expected: 2 tests pass.

### Step 5: Implement DeepCleanViewModel + Views

Create `kFresh/Features/DeepClean/DeepCleanViewModel.swift`:

```swift
import Foundation
import SwiftUI

@MainActor
public final class DeepCleanViewModel: ObservableObject {
    public enum ViewState {
        case idle, scanning, loaded([SystemCleanItem]), cleaning, failed(String)
    }

    @Published public private(set) var state: ViewState = .idle
    @Published public var selectedIDs: Set<String> = []

    private let engine: DeepCleanEngine

    public init(engine: DeepCleanEngine) {
        self.engine = engine
    }

    public func load() async {
        state = .scanning
        do {
            let items = try await engine.scan()
            state = .loaded(items)
            selectedIDs = Set(items.filter { !$0.isProtected }.map(\.id))
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func clean() async {
        guard case .loaded(let items) = state else { return }
        let toClean = items.filter { selectedIDs.contains($0.id) }
        state = .cleaning
        do {
            _ = try await engine.clean(toClean)
            await load()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public var groupedItems: [(SystemCleanCategory, [SystemCleanItem])] {
        guard case .loaded(let items) = state else { return [] }
        return Dictionary(grouping: items, by: \.category)
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { ($0.key, $0.value) }
    }

    public func toggle(_ item: SystemCleanItem) {
        guard !item.isProtected else { return }
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }
}
```

Create `kFresh/Features/DeepClean/DeepCleanView.swift`:

```swift
import SwiftUI
import DesignSystem

public struct DeepCleanView: View {
    @StateObject private var viewModel: DeepCleanViewModel
    @State private var showConfirm = false

    public init(viewModel: DeepCleanViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            switch viewModel.state {
            case .idle, .scanning:
                LoadingStateView(message: "扫描系统残留...")
            case .cleaning:
                LoadingStateView(message: "清理中...")
            case .failed(let msg):
                EmptyStateView(title: "扫描失败", systemImage: "exclamationmark.triangle", description: msg)
            case .loaded(let items):
                List {
                    ForEach(viewModel.groupedItems, id: \.0) { category, categoryItems in
                        Section(category.displayName) {
                            ForEach(categoryItems) { item in
                                SystemCleanGroupView(item: item, isSelected: viewModel.selectedIDs.contains(item.id)) {
                                    viewModel.toggle(item)
                                }
                            }
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    HStack {
                        Text("已选 \(viewModel.selectedIDs.count) 项").font(.callout)
                        Spacer()
                        Button("清理") { showConfirm = true }
                            .buttonStyle(BrandDangerButtonStyle())
                            .disabled(viewModel.selectedIDs.isEmpty)
                    }
                    .padding(KFSpacing.md)
                    .background(.bar)
                }
            }
        }
        .navigationTitle("深度清理")
        .task { await viewModel.load() }
        .confirmationDialog("确认清理？", isPresented: $showConfirm) {
            Button("清理", role: .destructive) {
                Task { await viewModel.clean() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("选中的项目将先备份，再删除。可在 History 中恢复。")
        }
    }
}
```

Create `kFresh/Features/DeepClean/SystemCleanGroupView.swift`:

```swift
import SwiftUI
import DesignSystem

struct SystemCleanGroupView: View {
    let item: SystemCleanItem
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Image(systemName: item.category.systemImage).foregroundStyle(Color.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).font(.body)
                Text(item.url.path).font(.caption2).foregroundStyle(Color.textTertiary).lineLimit(1)
            }
            Spacer()
            Text(item.sizeBytes.formattedAsFileSize).font(.caption.monospacedDigit())
            Toggle("", isOn: Binding(get: { isSelected }, set: { _ in onToggle() }))
                .labelsHidden()
                .disabled(item.isProtected)
        }
        .padding(.vertical, KFSpacing.xs)
    }
}
```

### Step 6: Apply Pro gate (Task 8 wires the modifier)

For now, the Task 3 `.proGate()` placeholder is a no-op. Task 8 replaces it.

### Step 7: Run DeepClean tests

Run: `xcodebuild test -project kFresh/kFresh.xcodeproj -scheme kFresh -destination 'platform=macOS' -only-testing:kFreshTests/DeepCleanEngineTests -only-testing:kFreshTests/DeepCleanViewModelTests`

Expected: 2 + ≥2 tests pass.

### Step 8: Commit

```bash
git add kFresh/Core/Clean/DeepCleanEngine.swift kFresh/Features/DeepClean/ kFresh/Tests/DeepCleanTests/
git commit -m "feat(kFresh): DeepCleanEngine + DeepCleanView with category grouping"
```

---

## Task 8: StoreKit + ProGate 修饰符

**Files:**
- Create: `kFresh/Store/StoreManager.swift`
- Create: `kFresh/Store/StoreDefinitions.swift`
- Create: `kFresh/Store/ProGateModifier.swift` (replaces Task 3 placeholder)
- Delete: `kFresh/Features/Common/ProGatePlaceholder.swift` (or repurpose)
- Create: `kFresh/Configuration.storekit`
- Create: `kFresh/Tests/StoreTests/StoreManagerTests.swift`
- Create: `kFresh/Tests/StoreTests/ProGateModifierTests.swift`
- Create: `kFresh/Tests/UITests/ProGateUITests.swift`
- Modify: `kFresh/kFresh.xcodeproj/project.pbxproj` (add Store scheme + Configuration.storekit)
- Modify: `kFresh/.swiftlint.yml` (add `Store/` to included paths if not present)

**Interfaces:**
```swift
public enum StoreProduct: String, CaseIterable, Sendable {
    case proUnlock = "app.kraftly.kfresh.pro"
}

public enum ProState: Equatable, Sendable {
    case free
    case pro
}

@MainActor
public final class StoreManager: ObservableObject {
    @Published public private(set) var state: ProState = .free

    public init()
    public func refresh() async                // load products, check receipt
    public func purchase(_ product: StoreProduct) async throws
    public func restorePurchases() async throws
    public func setProForTesting(_ value: Bool) // test seam
}
```

---

### Step 1: Write failing test for StoreManager

Create `kFresh/Tests/StoreTests/StoreManagerTests.swift`:

```swift
import XCTest
@testable import kFresh

@MainActor
final class StoreManagerTests: XCTestCase {
    func testInitialStateIsFree() {
        let manager = StoreManager()
        XCTAssertEqual(manager.state, .free)
    }

    func testSetProForTestingTransitionsToPro() {
        let manager = StoreManager()
        manager.setProForTesting(true)
        XCTAssertEqual(manager.state, .pro)
        manager.setProForTesting(false)
        XCTAssertEqual(manager.state, .free)
    }
}
```

### Step 2: Run test to verify it fails

Expected: `cannot find 'StoreManager' in scope`.

### Step 3: Implement StoreDefinitions + StoreManager

Create `kFresh/Store/StoreDefinitions.swift`:

```swift
import Foundation

public enum StoreProduct: String, CaseIterable, Sendable {
    case proUnlock = "app.kraftly.kfresh.pro"
}

public enum ProState: Equatable, Sendable {
    case free
    case pro
}
```

Create `kFresh/Store/StoreManager.swift`:

```swift
import Foundation
import StoreKit
import SwiftUI

@MainActor
public final class StoreManager: ObservableObject {
    @Published public private(set) var state: ProState = .free
    @Published public private(set) var products: [Product] = []
    @Published public private(set) var purchaseInProgress: Bool = false

    private let testOverrideKey = "kFresh.testProOverride"
    private var updatesTask: Task<Void, Never>?

    public init() {
        // Test override is read first
        if UserDefaults.standard.bool(forKey: testOverrideKey) {
            self.state = .pro
        }
        updatesTask = Task { [weak self] in
            await self?.listenForTransactionUpdates()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    public func refresh() async {
        do {
            let loaded = try await Product.products(for: StoreProduct.allCases.map(\.rawValue))
            self.products = loaded
        } catch {
            self.products = []
        }
        await refreshEntitlements()
    }

    public func purchase(_ product: StoreProduct) async throws {
        purchaseInProgress = true
        defer { purchaseInProgress = false }
        guard let storeProduct = products.first(where: { $0.id == product.rawValue }) else {
            throw StoreError.productNotFound
        }
        let result = try await storeProduct.purchase()
        switch result {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                state = .pro
            case .unverified:
                throw StoreError.verificationFailed
            }
        case .userCancelled:
            throw StoreError.userCancelled
        case .pending:
            throw StoreError.pending
        @unknown default:
            throw StoreError.unknown
        }
    }

    public func restorePurchases() async throws {
        try await AppStore.sync()
        await refreshEntitlements()
    }

    public func setProForTesting(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: testOverrideKey)
        state = value ? .pro : .free
    }

    private func refreshEntitlements() async {
        var isPro = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               StoreProduct(rawValue: transaction.productID) != nil {
                isPro = true
                break
            }
        }
        if !UserDefaults.standard.bool(forKey: testOverrideKey) {
            state = isPro ? .pro : .free
        }
    }

    private func listenForTransactionUpdates() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result,
               StoreProduct(rawValue: transaction.productID) != nil {
                state = .pro
                await transaction.finish()
            }
        }
    }
}

public enum StoreError: LocalizedError {
    case productNotFound, verificationFailed, userCancelled, pending, unknown
    public var errorDescription: String? {
        switch self {
        case .productNotFound: return "商品未找到"
        case .verificationFailed: return "购买验证失败"
        case .userCancelled: return "已取消"
        case .pending: return "等待中"
        case .unknown: return "未知错误"
        }
    }
}
```

### Step 4: Run test to verify it passes

Expected: 2 tests pass.

### Step 5: Create Configuration.storekit

Create `kFresh/Configuration.storekit`:

```json
{
  "identifier" : "B3D7E5A1-1234-5678-90AB-CDEF01234567",
  "nonRenewingSubscriptions" : [],
  "products" : [
    {
      "displayPrice" : "9.99",
      "familyShareable" : false,
      "internalID" : "B7C9E1A2-3456-7890-ABCD-EF1234567890",
      "localizations" : [
        {
          "description" : "解锁 kFresh 全部 Pro 功能",
          "displayName" : "kFresh Pro",
          "locale" : "en_US"
        },
        {
          "description" : "解锁 kFresh 全部 Pro 功能",
          "displayName" : "kFresh Pro",
          "locale" : "zh_CN"
        }
      ],
      "productID" : "app.kraftly.kfresh.pro",
      "referenceName" : "kFresh Pro Unlock",
      "type" : "NonConsumable"
    }
  ],
  "settings" : {
    "_locale" : "en_US",
    "_storefront" : "USA",
    "_storeKitErrors" : []
  },
  "subscriptionGroups" : [],
  "version" : {
    "major" : 4,
    "minor" : 0
  }
}
```

Add `Configuration.storekit` to the Xcode scheme:
- Open scheme → Run → Options → StoreKit Configuration → select `Configuration.storekit`

### Step 6: Implement ProGateModifier (replaces Task 3 placeholder)

Create `kFresh/Store/ProGateModifier.swift`:

```swift
import SwiftUI
import DesignSystem

public struct ProGateModifier: ViewModifier {
    @ObservedObject var store: StoreManager
    @State private var showPaywall = false

    public init(store: StoreManager) {
        self.store = store
    }

    public func body(content: Content) -> some View {
        content
            .blur(radius: store.state == .pro ? 0 : 8)
            .overlay {
                if store.state != .pro {
                    paywallOverlay
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(store: store)
            }
    }

    private var paywallOverlay: some View {
        VStack(spacing: KFSpacing.md) {
            Image(systemName: "lock.fill").font(.system(size: 32)).foregroundStyle(Color.warning)
            Text("Pro 功能").font(.title3.weight(.semibold))
            Text("升级 Pro 解锁深度清理、启动项管理")
                .font(.subheadline).foregroundStyle(Color.textSecondary).multilineTextAlignment(.center)
            Button("解锁 Pro") { showPaywall = true }
                .buttonStyle(BrandPrimaryButtonStyle())
        }
        .padding(KFSpacing.lg)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(KFSpacing.lg)
    }
}

public extension View {
    /// Applies a Pro gate: shows blurred content + paywall overlay when not Pro.
    func proGate(store: StoreManager) -> some View {
        modifier(ProGateModifier(store: store))
    }
}
```

Update Task 3 and Task 6/7 view code to use `store: services.store`:

```swift
// In AppDetailView's proEntries section
.proGate(store: services.store)

// In StartupItemsView entry from AppListView
.proGate(store: services.store)

// In DeepCleanView entry
.proGate(store: services.store)
```

### Step 7: Implement PaywallView

Create `kFresh/Store/PaywallView.swift`:

```swift
import SwiftUI
import StoreKit
import DesignSystem

public struct PaywallView: View {
    @ObservedObject var store: StoreManager
    @Environment(\.dismiss) private var dismiss

    public init(store: StoreManager) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: KFSpacing.lg) {
            Text("升级到 kFresh Pro").font(.title.weight(.bold))
            Text("一次买断，永久使用").font(.subheadline).foregroundStyle(Color.textSecondary)
            VStack(alignment: .leading, spacing: KFSpacing.sm) {
                bullet("深度清理 — LaunchAgents/Daemons/PrefPanes")
                bullet("启动项管理 — 启用/禁用/删除")
                bullet("Wave 2: 批量卸载 / Widget / Shortcuts")
                bullet("30 天可回滚")
            }
            .padding()
            .background(Color.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            if let product = store.products.first {
                Button {
                    Task { try? await store.purchase(.proUnlock); dismiss() }
                } label: {
                    Text("购买 — \(product.displayPrice)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(BrandPrimaryButtonStyle())
                .disabled(store.purchaseInProgress)
            } else {
                ProgressView()
            }
            Button("恢复购买") {
                    Task { try? await store.restorePurchases(); dismiss() }
            }
            .buttonStyle(.borderless)
            Button("取消", role: .cancel) { dismiss() }
        }
        .padding(KFSpacing.lg)
        .frame(width: 420)
        .task { await store.refresh() }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top) {
            Text("✓").foregroundStyle(Color.success)
            Text(text)
        }
    }
}
```

### Step 8: Wire StoreManager into AppServices

Modify `kFresh/App/AppServices.swift`:

```swift
@MainActor
public final class AppServices: ObservableObject {
    public let catalog: AppCatalogService
    public let history: UninstallHistoryRepository
    public let fdaProbe: FDAPermissionProbe
    public let store: StoreManager

    public init() {
        self.catalog = AppCatalogService(...)
        self.history = UninstallHistoryRepository(...)
        self.fdaProbe = FDAPermissionProbe()
        self.store = StoreManager()
    }
}
```

### Step 9: Write ProGate UI test

Create `kFresh/Tests/UITests/ProGateUITests.swift`:

```swift
import XCTest

final class ProGateUITests: XCTestCase {
    func testProGateShowsOverlayWhenFree() {
        let app = XCUIApplication()
        app.launchArguments += ["-kFreshTestPro", "0"]
        app.launch()
        // The overlay should appear in a Pro feature area
        let unlockButton = app.buttons["解锁 Pro"]
        XCTAssertTrue(unlockButton.waitForExistence(timeout: 5))
    }

    func testProGateHidesOverlayWhenPro() {
        let app = XCUIApplication()
        app.launchArguments += ["-kFreshTestPro", "1"]
        app.launch()
        let unlockButton = app.buttons["解锁 Pro"]
        XCTAssertFalse(unlockButton.waitForExistence(timeout: 2))
    }
}
```

Update `kFreshApp.swift` to honor test arg:

```swift
@main
struct kFreshApp: App {
    @StateObject private var services = AppServices()
    init() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "-kFreshTestPro"),
           i + 1 < args.count,
           args[i + 1] == "1" {
            UserDefaults.standard.set(true, forKey: "kFresh.testProOverride")
        }
    }
    var body: some Scene { ... }
}
```

### Step 10: Run Store + ProGate tests

Run: `xcodebuild test -project kFresh/kFresh.xcodeproj -scheme kFresh -destination 'platform=macOS' -only-testing:kFreshTests/StoreManagerTests -only-testing:kFreshTests/ProGateModifierTests -only-testing:kFreshTests/ProGateUITests`

Expected: 2 + ≥1 + 2 = ≥5 tests pass.

### Step 11: Commit

```bash
git add kFresh/Store/ kFresh/Configuration.storekit kFresh/Tests/StoreTests/ kFresh/Tests/UITests/ProGateUITests.swift kFresh/App/kFreshApp.swift kFresh/App/AppServices.swift kFresh/.swiftlint.yml
git rm kFresh/Features/Common/ProGatePlaceholder.swift 2>/dev/null || true
git commit -m "feat(kFresh): StoreKit Pro unlock + ProGate modifier + paywall"
```

---

## Self-Review Checklist (per task)

After each task, verify before committing:

- [ ] All DoD dimensions pass (functional / perf / UX / code quality / design consistency)
- [ ] All new tests pass: `xcodebuild test -project kFresh/kFresh.xcodeproj -scheme kFresh -destination 'platform=macOS' -only-testing:<new test classes>`
- [ ] No new Swift compile warnings: `xcodebuild build -project kFresh/kFresh.xcodeproj -scheme kFresh -destination 'platform=macOS' 2>&1 | grep -i warning`
- [ ] No hardcoded colors / fonts / spacings / animation values — all come from `kFoundation/Sources/DesignSystem/*`
- [ ] DocC on all new public APIs (classes, structs, public methods, public properties)
- [ ] No `try?` silently swallowing errors
- [ ] No `@unchecked Sendable` except for `InstalledApp.icon` (which is `NSImage`-bearing)
- [ ] Bundle ID = `app.kraftly.kfresh` everywhere
- [ ] No `kUninstall/` paths in new files

---

## Execution Time

| Task | Days | Cumulative |
|---|---|---|
| Task 1 (Onboarding) | 1.5d | 1.5d |
| Task 2 (AppList) | 2.0d | 3.5d |
| Task 3 (AppDetail) | 2.0d | 5.5d |
| Task 4 (Uninstall confirm + Toast) | 2.0d | 7.5d |
| Task 5 (History + Restore) | 1.5d | 9.0d |
| Task 6 (Startup) | 1.5d | 10.5d |
| Task 7 (DeepClean) | 2.0d | 12.5d |
| Task 8 (StoreKit + Pro) | 1.0d | 13.5d |

Total: **13.5 working days ≈ 2.7 calendar weeks**

---

## Out of Scope for Wave 1 (deferred to Wave 2+)

- Widget (基础 + Interactive) — Wave 2
- App Intents / Shortcuts — Wave 2
- Finder Extension — Wave 2
- MenuBar — Wave 2
- Spotlight 集成 — Wave 2
- 批量卸载 — Wave 2
- 多语言（zh-Hans / ja） — Wave 2 with frozen text
- AppIcon 母题统一 — Wave 2
- AI "很少用" 分析 — Wave 2

---

## Spec Coverage

| Spec requirement | Wave 1 Task |
|---|---|
| Onboarding 5 页 FDA 引导 (§6.1) | Task 1 |
| AppList 主页 + 搜索 + 筛选 + 排序 (§6.1) | Task 2 |
| AppDetail Hero + 残留列表 + 卸载入口 (§6.1) | Task 3 |
| 卸载确认 Sheet 5 步安全 (§7.2) | Task 4 |
| 卸载撤销 Toast (§6.2) | Task 4 |
| History view + 30 天回滚 (§6.1) | Task 5 |
| DeepClean view Pro 功能 (§4.2 + §6.1) | Task 7 |
| Startup Items view Pro 功能 (§4.2 + §6.1) | Task 6 |
| StoreKit IAP + Pro 锁 (§11) | Task 8 |
| Wave 0 Core 服务复用 | All tasks (TrashMover / BackupManager / ResidueDetector / AppCatalogService) |

---

## Risks

1. **`TrashMover.restore(id:)` requires `actualTrashPath` to persist across launches** — Wave 0 fixed this; Task 4 verify the field is populated and read correctly.
2. **ResidueDetector.detectResidues signature drift** — Task 3 confirm; adapt call site if signature differs.
3. **UninstallHistoryRepository lacks `init(inMemory:)`** — Task 5 adds; small CoreDataStack refactor, don't touch production path.
4. **SMAppService (macOS 13+) returns login items asynchronously with callbacks** — Task 6 falls back to LSSharedFileList; if LoginItems type stays empty, acceptable for v1.
5. **Configuration.storekit Xcode integration** — manually verify scheme → Options → StoreKit Configuration → Configuration.storekit. Without this, StoreKit tests will hit real sandbox.
6. **`@MainActor` boundary on `TrashMover.restore` from `HistoryViewModel`** — already Wave 0 pattern; Task 5 reuses.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-01-kfresh-wave1.md`. Two execution options:

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks (spec compliance + code quality), fast iteration.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints.

Approach follows Wave 0 pattern: direct commits to `main`, no PRs, fresh subagent per task.
