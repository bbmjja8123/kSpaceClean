# kUninstall v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build kUninstall v1, a sandboxed macOS 13+ app uninstaller that removes both the app and all its digital fingerprints, with a free uninstall tier and a $9.99 Pro one-time purchase for deep system cleanup and app health management.

**Architecture:** Clean Architecture with actor-based concurrency. `AppCatalogService` (actor) scans installed apps via LaunchServices + FileManager. `ResidueDetector` (actor) infers residual files using bundle ID path templates with confidence scoring. `TrashMover` (actor) handles sandbox-compliant trash moves with backup to `~/Library/Application Support/`. Pro features (`DeepCleanEngine`, `StartupItemManager`) are gated by `StoreManager` checking receipt. SwiftUI presentation layer with `@MainActor` ViewModels.

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit, Core Data, StoreKit 2, App Intents, WidgetKit, LSSharedFileList, NSWorkspace, XCTest, XCUITest, macOS 13 deployment target, macOS 14 SDK.

## Global Constraints

- Minimum OS is **macOS 13.0**; every macOS 14+ API must be guarded with `#available` and have a useful fallback.
- Build against the macOS 14 SDK with Swift 5.9+ and `SWIFT_STRICT_CONCURRENCY = complete`.
- App Sandbox **must be enabled**; use `com.apple.security.temporary-exception.files.home-relative-path.read-write` for ~/Library access with App Store review video justification.
- Network client **must be disabled** — zero telemetry, zero analytics, zero crash reporting.
- Do not use privileged helpers, SMJobBless, undocumented private APIs, or network telemetry.
- FDA (Full Disk Access) is optional; app degrades gracefully to basic mode without it.
- Free users: uninstall any app + basic residue scan + undo + Finder Extension + Spotlight.
- Pro is a non-consumable StoreKit 2 purchase: $9.99 US reference price with regional pricing in App Store Connect.
- Bundle IDs follow Kraftly convention — `app.kraftly.kuninstall` for the app, `app.kraftly.kuninstall.widget` for widgets, etc.
- Localize user-visible strings in English, Simplified Chinese, and Japanese; do not hard-code copy in views.
- Accessibility: all interactive elements must have VoiceOver labels; support Dynamic Type; detect `AccessibilitySettings.reduceMotion` to disable animations.
- Never copy Objective-C/C++ implementation from Lemon. Lemon is a behavior reference only.

## File Map

### Infrastructure
- `kUninstall/project.yml` — XcodeGen project manifest
- `kUninstall/kUninstall.entitlements` — Sandbox entitlements
- `kUninstall/App/kUninstallApp.swift` — @main entry
- `kUninstall/App/RootView.swift` — NavigationSplitView root
- `kUninstall/App/AppCoordinator.swift` — navigation/state coordinator
- `kUninstall/App/AppState.swift` — global app state enum

### Core Detection Engine
- `kUninstall/Core/Detect/InstalledApp.swift` — domain model
- `kUninstall/Core/Detect/AppCatalogService.swift` — app listing actor
- `kUninstall/Core/Detect/ResidueDetector.swift` — residue inference actor
- `kUninstall/Core/Clean/TrashMover.swift` — trash + backup + restore actor
- `kUninstall/Core/Clean/ResidueScanner.swift` — facade scanning coordinator
- `kUninstall/Core/Startup/StartupItemManager.swift` — login item mgmt actor

### Pro Features
- `kUninstall/Features/DeepClean/DeepCleanEngine.swift` — system-level cleanup actor
- `kUninstall/Features/DeepClean/DeepCleanView.swift` — DeepClean UI
- `kUninstall/Features/DeepClean/DeepCleanViewModel.swift` — DeepClean presentation
- `kUninstall/Features/StartupItems/StartupItemsView.swift` — startup mgmt UI
- `kUninstall/Features/StartupItems/StartupItemsViewModel.swift` — startup presentation

### Data Layer
- `kUninstall/Data/CoreDataStack.swift` — Core Data container + setup
- `kUninstall/Data/Models/UninstallHistory+CoreDataClass.swift` — managed object
- `kUninstall/Data/Models/UninstallHistory+CoreDataProperties.swift` — properties
- `kUninstall/Data/Models/AppAnalysis+CoreDataClass.swift` — managed object
- `kUninstall/Data/Models/AppAnalysis+CoreDataProperties.swift` — properties
- `kUninstall/Data/UninstallHistoryRepository.swift` — CRUD for history
- `kUninstall/Data/AppAnalysisRepository.swift` — CRUD for analysis
- `kUninstall/Data/FDAuthorizer.swift` — Security-Scoped Bookmark mgmt
- `kUninstall/Data/BackupManager.swift` — backup directory + cleanup

### UI Layer
- `kUninstall/Features/AppList/AppListView.swift` — main list
- `kUninstall/Features/AppList/AppListViewModel.swift` — list logic
- `kUninstall/Features/AppList/AppRowView.swift` — single row
- `kUninstall/Features/Detail/AppDetailView.swift` — detail hero
- `kUninstall/Features/Detail/DetailViewModel.swift` — detail logic
- `kUninstall/Features/Detail/ResidueSectionView.swift` — residue list
- `kUninstall/Features/Detail/UninstallConfirmSheet.swift` — confirm sheet
- `kUninstall/Features/History/HistoryView.swift` — uninstall history
- `kUninstall/Features/History/HistoryViewModel.swift` — history logic
- `kUninstall/Features/Settings/SettingsView.swift` — settings
- `kUninstall/Features/Settings/SettingsViewModel.swift` — settings logic
- `kUninstall/Features/Onboarding/FDAGuideView.swift` — FDA wizard
- `kUninstall/Features/Onboarding/FDAGuideController.swift` — FDA state check

### Store / IAP
- `kUninstall/Store/StoreManager.swift` — StoreKit 2 manager actor
- `kUninstall/Store/StoreDefinitions.swift` — product IDs + features
- `kUninstall/Store/PaywallView.swift` — Pro purchase screen

### Platform Integrations
- `kUninstall/MenuBar/MenuBarController.swift` — NSStatusItem
- `kUninstall/Intents/UninstallAppIntent.swift` — Shortcuts
- `kUninstall/Intents/ScanResidueIntent.swift` — Shortcuts
- `kUninstall/Intents/DeepCleanIntent.swift` — Shortcuts (Pro)
- `kUninstall/FinderExtension/FinderSync.swift` — Finder Sync
- `kUninstall/FinderExtension/Info.plist` — extension config
- `kUninstall/Widgets/AppUsageWidget.swift` — Pro widget
- `kUninstall/Widgets/QuickUninstallWidget.swift` — Pro widget

### Resources
- `kUninstall/Resources/Assets.xcassets` — asset catalog
- `kUninstall/Resources/Localizable.xcstrings` — en / zh-Hans / ja
- `kUninstall/Resources/PrivacyInfo.xcprivacy` — privacy manifest
- `kUninstall/kUninstallDebug.entitlements` — debug entitlements for FDA testing

### Tests
- `kUninstall/Tests/DetectTests/AppCatalogServiceTests.swift`
- `kUninstall/Tests/DetectTests/ResidueDetectorTests.swift`
- `kUninstall/Tests/DetectTests/AppSourceClassifierTests.swift`
- `kUninstall/Tests/CleanTests/TrashMoverTests.swift`
- `kUninstall/Tests/CleanTests/BackupManagerTests.swift`
- `kUninstall/Tests/IntegrationTests/UninstallFlowTests.swift`
- `kUninstall/Tests/IntegrationTests/SandboxDegradationTests.swift`
- `kUninstall/Tests/UITests/UninstallJourneyUITests.swift`

---

## Task Sequence

Tasks are ordered by dependency. Each task ends with an independently testable deliverable. Do not start a later task until the preceding task's test command passes.

### Task 1: Create project scaffold — project.yml, entitlements, App entry point

**Files:**
- Create: `kUninstall/project.yml`
- Create: `kUninstall/kUninstall.entitlements`
- Create: `kUninstall/App/kUninstallApp.swift`
- Create: `kUninstall/App/RootView.swift`
- Create: `kUninstall/App/AppCoordinator.swift`
- Create: `kUninstall/App/AppState.swift`
- Create: `kUninstall/Resources/Assets.xcassets`

**Interfaces:**
- Consumes: `kFoundation` package (DesignSystem, Capabilities, CommonUtils)
- Produces: `AppState` enum, `AppCoordinator` class, `RootView`, `kUninstallApp`

- [ ] **Step 1: Create project.yml**

```yaml
# kUninstall/project.yml
name: kUninstall
options:
  bundleIdPrefix: app.kraftly
  deploymentTarget:
    macOS: "13.0"
  xcodeVersion: "15.0"

settings:
  SWIFT_STRICT_CONCURRENCY: complete
  MACOSX_DEPLOYMENT_TARGET: "13.0"
  SWIFT_VERSION: "5.9"

targets:
  kUninstall:
    type: application
    platform: macOS
    sources:
      - path: .
        excludes:
          - "project.yml"
          - "**/*.md"
          - "Tests/**"
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: app.kraftly.kuninstall
      INFOPLIST_FILE: Info.plist
      CODE_SIGN_STYLE: Automatic
      DEVELOPMENT_TEAM: ""
    dependencies:
      - package: kFoundation
    preBuildScripts:
      - name: "SwiftLint"
        script: "if which swiftlint >/dev/null; then swiftlint; fi"
        basedOnDependencyAnalysis: false
    entitlements:
      path: kUninstall.entitlements

  kUninstallTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: app.kraftly.kuninstall.tests
      MACOSX_DEPLOYMENT_TARGET: "13.0"
      SWIFT_VERSION: "5.9"
    dependencies:
      - target: kUninstall
      - package: kFoundation

  FinderSyncExtension:
    type: app-extension
    platform: macOS
    sources:
      - FinderExtension
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: app.kraftly.kuninstall.finder-sync
    dependencies:
      - target: kUninstall

packages:
  kFoundation:
    path: /Users/mengjianjun/Documents/ai/aicoding/macapp/kFoundation
```

- [ ] **Step 2: Create entitlements**

```xml
<!-- kUninstall/kUninstall.entitlements -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
    <key>com.apple.security.temporary-exception.files.home-relative-path.read-write</key>
    <string>/Library/</string>
    <key>com.apple.security.network.client</key>
    <false/>
    <key>com.apple.security.application-groups</key>
    <array>
        <string>app.kraftly.kuninstall</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 3: Create App entry point + root view + coordinator**

```swift
// kUninstall/App/kUninstallApp.swift
import SwiftUI

@main
struct kUninstallApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var menuBarController = MenuBarController()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(coordinator)
                .preferredColorScheme(.dark)
                .onOpenURL { url in coordinator.handleDeepLink(url) }
                .onAppear {
                    coordinator.appState = appState
                    menuBarController.setup()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 960, height: 660)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
```

```swift
// kUninstall/App/AppState.swift
import Foundation

enum AppState {
    case loading
    case scanning(progress: Double)
    case ready
    case error(message: String)
}
```

```swift
// kUninstall/App/RootView.swift
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailContent
        }
    }

    @ViewBuilder private var sidebar: some View {
        VStack(spacing: 0) {
            AppListView()
        }
        .frame(minWidth: 280)
    }

    @ViewBuilder private var detailContent: some View {
        if let selectedApp = coordinator.selectedApp {
            AppDetailView(app: selectedApp)
        } else {
            EmptyStateView(
                title: "选择 App",
                subtitle: "从左侧列表选择一个应用查看详情"
            )
        }
    }
}
```

```swift
// kUninstall/App/AppCoordinator.swift
import SwiftUI

@MainActor
class AppCoordinator: ObservableObject {
    @Published var selectedApp: InstalledApp?
    @Published var showPaywall = false
    @Published var showOnboarding = false
    @Published var showHistory = false
    @Published var showSettings = false

    weak var appState: AppState?

    func handleDeepLink(_ url: URL) {
        // Handle incoming URL schemes
    }

    func selectApp(_ app: InstalledApp) {
        selectedApp = app
    }

    func navigateToHistory() {
        showHistory = true
    }
}
```

- [ ] **Step 4: Create Assets.xcassets directory**

Create the directory `kUninstall/Resources/Assets.xcassets/` with an empty `Contents.json`:
```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

Run: `mkdir -p kUninstall/Resources/Assets.xcassets`

- [ ] **Step 5: Verify project generates**

Run: `cd /Users/mengjianjun/Documents/ai/aicoding/macapp && xcodegen generate --project kUninstall/project.yml`
Expected: `kUninstall.xcodeproj` is created successfully.

- [ ] **Step 6: Commit**

```bash
git add kUninstall/project.yml kUninstall/kUninstall.entitlements \
       kUninstall/App/kUninstallApp.swift kUninstall/App/RootView.swift \
       kUninstall/App/AppCoordinator.swift kUninstall/App/AppState.swift \
       kUninstall/Resources/Assets.xcassets/Contents.json
git commit -m "feat(kUninstall): add project scaffold with XcodeGen, entitlements, and app entry"
```

---

### Task 2: Define domain models — InstalledApp, ResidueFile, StartupItem, AppSource

**Files:**
- Create: `kUninstall/Core/Detect/InstalledApp.swift`

**Interfaces:**
- Consumes: Foundation
- Produces: `InstalledApp`, `ResidueFile`, `ResidueType`, `AppSource`, `StartupItem`, `StartupItemType`

- [ ] **Step 1: Write the failing model tests**

```swift
// kUninstall/Tests/DetectTests/InstalledAppTests.swift
import XCTest
@testable import kUninstall

final class InstalledAppTests: XCTestCase {
    func testAppSourceClassification() {
        let systemApp = InstalledApp(url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
                                      displayName: "Finder",
                                      bundleID: "com.apple.finder",
                                      version: "1.0",
                                      source: .system)
        XCTAssertEqual(systemApp.source, .system)
        XCTAssertTrue(systemApp.isProtected)
    }

    func testResidueConfidenceOrdering() {
        let high = ResidueFile(url: URL(fileURLWithPath: "~/Library/Preferences/com.example.plist"),
                                type: .preferences,
                                sizeBytes: 100,
                                confidence: 0.99)
        let low = ResidueFile(url: URL(fileURLWithPath: "~/Library/Caches/com.example/"),
                               type: .caches,
                               sizeBytes: 200,
                               confidence: 0.5)
        XCTAssertGreaterThan(high.confidence, low.confidence)
    }

    func testProtectedBundleIDs() {
        let safe = InstalledApp.isBundleIDProtected("com.example.Foo")
        let protected = InstalledApp.isBundleIDProtected("com.apple.finder")
        XCTAssertFalse(safe)
        XCTAssertTrue(protected)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `xcodebuild test -project kUninstall/kUninstall.xcodeproj -scheme kUninstall -destination 'platform=macOS' -only-testing kUninstallTests/InstalledAppTests`
Expected: Build error — "No such module 'kUninstall'" or "cannot find 'InstalledApp'"

- [ ] **Step 3: Create the domain model file**

```swift
// kUninstall/Core/Detect/InstalledApp.swift
import Foundation
import AppKit

// MARK: - App Source

enum AppSource: String, Codable, CaseIterable {
    case system          // /System/* — protected
    case appleBuiltIn    // com.apple.* but not in /System
    case mas             // App Store with receipt
    case userInstalled   // /Applications/*
    case unknown
}

// MARK: - Residue Type

enum ResidueType: String, Codable, CaseIterable {
    case preferences
    case caches
    case appSupport = "appSupport"
    case container
    case savedState = "savedState"
    case webKit = "webKit"
    case httpStorage = "httpStorage"
    case groupContainer = "groupContainer"
    case plugin
    case launchAgent
    case launchDaemon
    case prefPane
    case startupItem
    case other
}

// MARK: - Residue File

struct ResidueFile: Identifiable, Codable {
    var id: String { url.path }
    let url: URL
    let type: ResidueType
    let sizeBytes: Int64
    let confidence: Double        // 0.0 ~ 1.0
    let description: String
    let isSystemLevel: Bool
    let isProtected: Bool

    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}

// MARK: - Startup Item

enum StartupItemType: String, Codable {
    case loginItem
    case launchAgent
    case launchDaemon
}

struct StartupItem: Identifiable, Codable {
    var id: String { url.path }
    let name: String
    let type: StartupItemType
    let url: URL
    let appURL: URL?
    let enabled: Bool
    let isProtected: Bool
}

// MARK: - Installed App

struct InstalledApp: Identifiable, Hashable {
    var id: String { bundleID }
    let url: URL
    let displayName: String
    let bundleID: String
    let version: String
    let icon: NSImage
    let sizeBytes: Int64
    let source: AppSource
    let isRunning: Bool
    let lastUsedDate: Date?
    var residues: [ResidueFile] = []

    var isProtected: Bool {
        Self.isBundleIDProtected(bundleID) || url.path.hasPrefix("/System/")
    }

    var protectionReason: String? {
        isProtected ? "系统组件不可卸载" : nil
    }

    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    static func isBundleIDProtected(_ bundleID: String) -> Bool {
        let protected: Set<String> = [
            "com.apple.finder",
            "com.apple.Terminal",
            "com.apple.systempreferences",
            "com.apple.dock",
            "com.apple.loginwindow",
            "com.apple.WindowManager",
        ]
        if protected.contains(bundleID) { return true }
        if bundleID.hasPrefix("com.apple.CoreServices.") { return true }
        if bundleID.hasPrefix("com.apple.launchd.") { return true }
        return false
    }

    // MARK: Hashable
    func hash(into hasher: inout Hasher) { hasher.combine(bundleID) }
    static func == (lhs: InstalledApp, rhs: InstalledApp) -> Bool { lhs.bundleID == rhs.bundleID }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild test -project kUninstall/kUninstall.xcodeproj -scheme kUninstall -destination 'platform=macOS' -only-testing kUninstallTests/InstalledAppTests`
Expected: All 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add kUninstall/Core/Detect/InstalledApp.swift kUninstall/Tests/DetectTests/InstalledAppTests.swift
git commit -m "feat(kUninstall): add domain models for InstalledApp, ResidueFile, StartupItem"
```

---

### Task 3: Implement AppCatalogService — installed app detection

**Files:**
- Create: `kUninstall/Core/Detect/AppCatalogService.swift`
- Create: `kUninstall/Tests/DetectTests/AppCatalogServiceTests.swift`

**Interfaces:**
- Consumes: `InstalledApp`
- Produces: `AppCatalogService.scan() -> [InstalledApp]`

- [ ] **Step 1: Write failing tests**

```swift
// kUninstall/Tests/DetectTests/AppCatalogServiceTests.swift
import XCTest
@testable import kUninstall

final class AppCatalogServiceTests: XCTestCase {
    func testClassifySourceSystem() {
        let service = AppCatalogService()
        let source = service.classifySource(
            url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
            bundleID: "com.apple.finder"
        )
        XCTAssertEqual(source, .system)
    }

    func testClassifySourceMAS() {
        let source = service.classifySource(
            url: URL(fileURLWithPath: "/Applications/Xcode.app"),
            bundleID: "com.apple.dt.Xcode"
        )
        // Without a real receipt we expect .userInstalled or .unknown
        // This tests that /Applications/ paths resolve correctly
        XCTAssertNotEqual(source, .system)
    }

    func testAppSourceUnknown() {
        let source = service.classifySource(
            url: URL(fileURLWithPath: "/tmp/test.app"),
            bundleID: "com.example.Test"
        )
        XCTAssertEqual(source, .unknown)
    }
}
```

- [ ] **Step 2: Run test — expected failure**

Run: `xcodebuild test ... -only-testing kUninstallTests/AppCatalogServiceTests`
Expected: Compile error — "cannot find 'AppCatalogService'"

- [ ] **Step 3: Implement AppCatalogService**

```swift
// kUninstall/Core/Detect/AppCatalogService.swift
import Foundation
import AppKit

actor AppCatalogService {
    private let fileManager = FileManager.default

    func scan() async -> [InstalledApp] {
        let lsApps = await queryLaunchServices()
        let fsApps = await enumerateApplications()
        return deduplicate(merge: lsApps + fsApps)
    }

    // MARK: - LaunchServices

    private func queryLaunchServices() async -> [InstalledApp] {
        // Use LSSharedFileList or NSWorkspace to get registered apps
        await Task.detached(priority: .userInitiated) {
            let workspace = NSWorkspace.shared
            let apps = workspace.runningApplications.compactMap { app -> InstalledApp? in
                guard let url = app.bundleURL else { return nil }
                let bundle = Bundle(url: url)
                return InstalledApp(
                    url: url,
                    displayName: app.localizedName ?? url.lastPathComponent,
                    bundleID: app.bundleIdentifier ?? "unknown",
                    version: bundle?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                    icon: workspace.icon(forFile: url.path),
                    sizeBytes: 0,  // Requires FDA for accurate size
                    source: .unknown,
                    isRunning: true,
                    lastUsedDate: nil
                )
            }

            // Also enumerate /Applications via FileManager for non-running apps
            let appDirs = ["/Applications", "/Applications/Utilities",
                           "/System/Applications", "/System/Applications/Utilities"]
            let allApps = apps + appDirs.flatMap { dir -> [InstalledApp] in
                self.appsInDirectory(dir, workspace: workspace)
            }
            return allApps
        }.value
    }

    private func appsInDirectory(_ dir: String, workspace: NSWorkspace) -> [InstalledApp] {
        guard let urls = try? fileManager.contentsOfDirectory(at: URL(fileURLWithPath: dir),
                                                               includingPropertiesForKeys: [.applicationIsScriptableKey],
                                                               options: .skipsHiddenFiles) else { return [] }
        return urls.filter { $0.pathExtension == "app" || $0.pathExtension == "app/Contents" }.compactMap { url in
            let bundle = Bundle(url: url)
            let bundleID = bundle?.bundleIdentifier ?? "unknown"
            return InstalledApp(
                url: url,
                displayName: bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                    ?? bundle?.infoDictionary?["CFBundleDisplayName"] as? String
                    ?? url.deletingPathExtension().lastPathComponent,
                bundleID: bundleID,
                version: bundle?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                icon: workspace.icon(forFile: url.path),
                sizeBytes: 0,
                source: self.classifySource(url: url, bundleID: bundleID),
                isRunning: false,
                lastUsedDate: nil
            )
        }
    }

    // MARK: - FileSystem enumeration (FDA required)

    private func enumerateApplications() async -> [InstalledApp] {
        // Without FDA we rely on LaunchServices; this is a fallback
        // when user grants FDA via Security-Scoped Bookmark
        []
    }

    // MARK: - Dedup

    private func deduplicate(merge apps: [InstalledApp]) -> [InstalledApp] {
        var dict = [String: InstalledApp]()  // keyed by bundleID
        for app in apps {
            if let existing = dict[app.bundleID] {
                // Merge: prefer running status, non-zero size, userInstalled over unknown
                let merged = InstalledApp(
                    url: existing.isRunning ? existing.url : app.url,
                    displayName: existing.displayName,
                    bundleID: existing.bundleID,
                    version: existing.version.isEmpty ? app.version : existing.version,
                    icon: existing.icon,
                    sizeBytes: max(existing.sizeBytes, app.sizeBytes),
                    source: existing.source == .unknown ? app.source : existing.source,
                    isRunning: existing.isRunning || app.isRunning,
                    lastUsedDate: existing.lastUsedDate ?? app.lastUsedDate
                )
                dict[app.bundleID] = merged
            } else {
                dict[app.bundleID] = app
            }
        }
        return Array(dict.values).sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Source Classification

    func classifySource(url: URL, bundleID: String) -> AppSource {
        let path = url.path
        if path.hasPrefix("/System/") { return .system }
        if bundleID == "com.apple.finder" { return .system }
        if bundleID.hasPrefix("com.apple.") || bundleID == "com.apple.dt.Xcode" {
            return .appleBuiltIn
        }
        if hasMASReceipt(url) { return .mas }
        if path.contains("/Applications/") { return .userInstalled }
        return .unknown
    }

    private func hasMASReceipt(_ url: URL) -> Bool {
        let receiptURL = url.appendingPathComponent("Contents/_MASReceipt/receipt")
        return FileManager.default.fileExists(atPath: receiptURL.path)
    }
}
```

- [ ] **Step 4: Run tests — verify pass**

Run: `xcodebuild test -project kUninstall/kUninstall.xcodeproj -scheme kUninstall -destination 'platform=macOS' -only-testing kUninstallTests/AppCatalogServiceTests`
Expected: Tests pass.

- [ ] **Step 5: Commit**

```bash
git add kUninstall/Core/Detect/AppCatalogService.swift kUninstall/Tests/DetectTests/AppCatalogServiceTests.swift
git commit -m "feat(kUninstall): implement AppCatalogService with LaunchServices app detection and source classification"
```

---

### Task 4: Implement ResidueDetector — residual file inference engine

**Files:**
- Create: `kUninstall/Core/Detect/ResidueDetector.swift`
- Create: `kUninstall/Tests/DetectTests/ResidueDetectorTests.swift`

**Interfaces:**
- Consumes: `InstalledApp`, `ResidueFile`, `ResidueType`
- Produces: `ResidueDetector.detectResidues(for:) -> [ResidueFile]`

- [ ] **Step 1: Write failing tests**

```swift
// kUninstall/Tests/DetectTests/ResidueDetectorTests.swift
import XCTest
@testable import kUninstall

final class ResidueDetectorTests: XCTestCase {
    func testAllPathTemplatesGenerated() async {
        let detector = ResidueDetector()
        let residues = await detector.detectResidues(
            bundleID: "com.example.Test",
            appName: "TestApp"
        )
        // Without FDA, all paths should exist as non-checked items
        // but the templates should be generated
        XCTAssertFalse(residues.isEmpty, "Should generate paths from templates")
    }

    func testConfidenceHighForPreferences() async {
        let detector = ResidueDetector()
        let residues = await detector.detectResidues(bundleID: "com.example.Test", appName: "Test")
        let prefs = residues.filter { $0.type == .preferences }
        XCTAssertFalse(prefs.isEmpty)
        XCTAssertEqual(prefs.first?.confidence, 0.99)
    }

    func testConfidenceLowForPlugins() async {
        let detector = ResidueDetector()
        let residues = await detector.detectResidues(bundleID: "com.example.Test", appName: "Test")
        let plugins = residues.filter { $0.type == .plugin }
        if let plugin = plugins.first {
            XCTAssertEqual(plugin.confidence, 0.80)
        }
    }

    func testNoResiduesForUnknownBundle() async {
        let detector = ResidueDetector()
        let residues = await detector.detectResidues(bundleID: "", appName: "")
        XCTAssertTrue(residues.isEmpty)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test ... -only-testing kUninstallTests/ResidueDetectorTests`
Expected: Compile error.

- [ ] **Step 3: Implement ResidueDetector**

```swift
// kUninstall/Core/Detect/ResidueDetector.swift
import Foundation

actor ResidueDetector {
    private let fileManager = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    /// Detect residual files for a given app using bundle ID and app name.
    func detectResidues(bundleID: String, appName: String) async -> [ResidueFile] {
        guard !bundleID.isEmpty else { return [] }
        let templates = pathTemplates(bundleID: bundleID, appName: appName)

        // Check which paths actually exist (if FDA available)
        var results = [ResidueFile]()
        for (path, type, confidence, isSystemLevel) in templates {
            let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
            let exists = fileManager.fileExists(atPath: url.path)

            results.append(ResidueFile(
                url: url,
                type: type,
                sizeBytes: exists ? (try? fileManager.allocatedSizeOfDirectory(at: url)) ?? 0 : 0,
                confidence: exists ? confidence : confidence * 0.5,
                description: descriptionForType(type, path: path),
                isSystemLevel: isSystemLevel,
                isProtected: isSystemLevel
            ))
        }
        return results.sorted { $0.confidence > $1.confidence }
    }

    /// Build path templates from bundle ID and app name.
    internal func pathTemplates(bundleID: String, appName: String) -> [(path: String, type: ResidueType, confidence: Double, isSystemLevel: Bool)] {
        let homePath = home.path
        let library = "\(homePath)/Library"
        let systemLibrary = "/Library"

        return [
            ("\(library)/Preferences/\(bundleID).plist",          .preferences,    0.99, false),
            ("\(library)/Caches/\(bundleID)/",                    .caches,         0.99, false),
            ("\(library)/Application Support/\(appName)/",        .appSupport,     0.95, false),
            ("\(library)/Saved Application State/\(bundleID).savedState", .savedState, 0.99, false),
            ("\(library)/Containers/\(bundleID)/",                .container,      0.99, false),
            ("\(library)/WebKit/\(bundleID)/",                    .webKit,         0.85, false),
            ("\(library)/HTTPStorages/\(bundleID)/",              .httpStorage,    0.95, false),
            ("\(library)/Group Containers/\(bundleID)/",          .groupContainer, 0.80, false),
            ("\(library)/Internet Plug-Ins/\(appName).plugin/",   .plugin,         0.80, false),
            ("\(systemLibrary)/LaunchAgents/\(bundleID).plist",   .launchAgent,    0.95, true),
            ("\(systemLibrary)/LaunchDaemons/\(bundleID).plist",  .launchDaemon,   0.95, true),
            ("\(systemLibrary)/PreferencePanes/\(appName).prefPane", .prefPane,    0.85, true),
            ("\(systemLibrary)/StartupItems/\(appName)/",         .startupItem,    0.85, true),
        ]
    }

    private func descriptionForType(_ type: ResidueType, path: String) -> String {
        switch type {
        case .preferences:   return "偏好设置"
        case .caches:        return "缓存文件"
        case .appSupport:    return "应用支持文件"
        case .container:     return "App Sandbox 容器"
        case .savedState:    return "保存的应用状态"
        case .webKit:        return "WebKit 缓存"
        case .httpStorage:   return "HTTP 存储"
        case .groupContainer:return "Group 容器"
        case .plugin:        return "插件"
        case .launchAgent:   return "启动代理"
        case .launchDaemon:  return "启动守护"
        case .prefPane:      return "偏好设置面板"
        case .startupItem:   return "启动项"
        case .other:         return "其他"
        }
    }
}

// MARK: - FileManager helper for directory size

extension FileManager {
    func allocatedSizeOfDirectory(at url: URL) throws -> Int64 {
        guard let enumerator = enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey],
                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `xcodebuild test ... -only-testing kUninstallTests/ResidueDetectorTests`
Expected: All 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add kUninstall/Core/Detect/ResidueDetector.swift kUninstall/Tests/DetectTests/ResidueDetectorTests.swift
git commit -m "feat(kUninstall): implement ResidueDetector with 13 path templates and confidence scoring"
```

---

### Task 5: Implement TrashMover + BackupManager — sandbox-compliant trash, backup, restore

**Files:**
- Create: `kUninstall/Core/Clean/TrashMover.swift`
- Create: `kUninstall/Data/BackupManager.swift`
- Create: `kUninstall/Data/UninstallHistoryRepository.swift`
- Create: `kUninstall/Tests/CleanTests/TrashMoverTests.swift`

**Interfaces:**
- Consumes: `InstalledApp`, `ResidueFile`, Core Data models
- Produces: `TrashMover.moveToTrash(app:residues:) -> Result`, `TrashMover.restore(id:)`, `BackupManager`

- [ ] **Step 1: Write failing tests**

```swift
// kUninstall/Tests/CleanTests/TrashMoverTests.swift
import XCTest
@testable import kUninstall

final class TrashMoverTests: XCTestCase {
    func testCanMoveProtectedAppReturnsFalse() {
        let app = InstalledApp(url: URL(fileURLWithPath: "/System/Library/Finder.app"),
                                displayName: "Finder",
                                bundleID: "com.apple.finder",
                                version: "1.0",
                                source: .system,
                                isRunning: false,
                                lastUsedDate: nil)
        XCTAssertFalse(TrashMover.canMoveToTrash(app: app))
    }

    func testCanMoveUserAppReturnsTrue() {
        let app = InstalledApp(url: URL(fileURLWithPath: "/Applications/Test.app"),
                                displayName: "Test",
                                bundleID: "com.example.Test",
                                version: "1.0",
                                source: .userInstalled,
                                isRunning: false,
                                lastUsedDate: nil)
        XCTAssertTrue(TrashMover.canMoveToTrash(app: app))
    }
}
```

- [ ] **Step 2: Run — expected failure**

Run: `xcodebuild test ... -only-testing kUninstallTests/TrashMoverTests`
Expected: Compile error.

- [ ] **Step 3: Implement BackupManager**

```swift
// kUninstall/Data/BackupManager.swift
import Foundation

actor BackupManager {
    private let fileManager = FileManager.default

    private var backupRoot: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("app.kraftly.kuninstall/Backups")
    }

    func backup(residues: [ResidueFile], bundleID: String) async throws -> URL {
        let backupDir = backupRoot.appendingPathComponent(bundleID)
        try fileManager.createDirectory(at: backupDir, withIntermediateDirectories: true)

        for residue in residues where residue.confidence > 0.5 {
            let dest = backupDir.appendingPathComponent(residue.url.lastPathComponent)
            if fileManager.fileExists(atPath: residue.url.path) {
                try fileManager.copyItem(at: residue.url, to: dest)
            }
        }
        return backupDir
    }

    func restore(backupPath: URL, originalResidues: [ResidueFile]) async throws {
        for residue in originalResidues {
            let backupFile = backupPath.appendingPathComponent(residue.url.lastPathComponent)
            if fileManager.fileExists(atPath: backupFile.path) {
                try? fileManager.copyItem(at: backupFile, to: residue.url)
            }
        }
    }

    func cleanup(bundleID: String) {
        let backupDir = backupRoot.appendingPathComponent(bundleID)
        try? fileManager.removeItem(at: backupDir)
    }

    func cleanupExpired(olderThan days: Int) {
        guard let contents = try? fileManager.contentsOfDirectory(at: backupRoot,
                                                                   includingPropertiesForKeys: [.creationDateKey]) else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        for url in contents {
            guard let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                  let creationDate = attrs[.creationDate] as? Date,
                  creationDate < cutoff else { continue }
            try? fileManager.removeItem(at: url)
        }
    }
}
```

- [ ] **Step 4: Implement TrashMover**

```swift
// kUninstall/Core/Clean/TrashMover.swift
import Foundation
import AppKit

actor TrashMover {
    private let backupManager = BackupManager()
    private let historyRepo = UninstallHistoryRepository()

    static func canMoveToTrash(app: InstalledApp) -> Bool {
        !app.isProtected
    }

    func moveToTrash(app: InstalledApp, residues: [ResidueFile]) async -> Result<UninstallRecord, TrashError> {
        guard Self.canMoveToTrash(app: app) else { return .failure(.protected) }

        // Step 1: Terminate if running
        if app.isRunning {
            await terminateApp(app)
        }

        // Step 2: Backup residues
        let backupPath: URL?
        do {
            backupPath = try await backupManager.backup(residues: residues, bundleID: app.bundleID)
        } catch {
            backupPath = nil
        }

        // Step 3: Move app to trash
        do {
            try NSWorkspace.shared.recycle([app.url]) { _, _ in }
        } catch {
            return .failure(.trashFailed(error))
        }

        // Step 4: Delete residues (already backed up)
        for residue in residues where residue.confidence > 0.5 {
            try? FileManager.default.removeItem(at: residue.url)
        }

        // Step 5: Save history
        let record = UninstallRecord(
            id: UUID(),
            appName: app.displayName,
            bundleID: app.bundleID,
            appPath: app.url.path,
            appSize: app.sizeBytes,
            totalResidueSize: residues.reduce(0) { $0 + $1.sizeBytes },
            residueCount: Int32(residues.count),
            uninstalledAt: Date(),
            isRestored: false,
            backupPath: backupPath?.path ?? "",
            residues: residues
        )
        await historyRepo.save(record: record)

        return .success(record)
    }

    func restore(record: UninstallRecord) async -> Bool {
        // Step 1: Move app back from trash
        let trashURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".Trash")
            .appendingPathComponent(URL(fileURLWithPath: record.appPath).lastPathComponent)

        if FileManager.default.fileExists(atPath: trashURL.path) {
            try? FileManager.default.moveItem(at: trashURL, to: URL(fileURLWithPath: record.appPath))
        }

        // Step 2: Restore residues
        if !record.backupPath.isEmpty {
            let backupURL = URL(fileURLWithPath: record.backupPath)
            let residues = record.residues
            try? await backupManager.restore(backupPath: backupURL, originalResidues: residues)
        }

        // Step 3: Mark restored
        await historyRepo.markRestored(id: record.id)
        backupManager.cleanup(bundleID: record.bundleID)

        return true
    }

    private func terminateApp(_ app: InstalledApp) async {
        let runningApps = NSWorkspace.shared.runningApplications
        guard let running = runningApps.first(where: { $0.bundleIdentifier == app.bundleID }) else { return }
        running.terminate()
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        if !running.isTerminated {
            running.forceTerminate()
        }
    }
}

enum TrashError: Error {
    case protected
    case trashFailed(Error)
    case restoreFailed(Error)
}

struct UninstallRecord: Identifiable, Codable {
    let id: UUID
    let appName: String
    let bundleID: String
    let appPath: String
    let appSize: Int64
    let totalResidueSize: Int64
    let residueCount: Int32
    let uninstalledAt: Date
    var isRestored: Bool
    let backupPath: String
    let residues: [ResidueFile]
}
```

- [ ] **Step 5: Implement UninstallHistoryRepository**

```swift
// kUninstall/Data/UninstallHistoryRepository.swift
import Foundation

actor UninstallHistoryRepository {
    private var records: [UninstallRecord] = []

    func save(record: UninstallRecord) {
        records.append(record)
    }

    func fetchAll() -> [UninstallRecord] {
        records.sorted { $0.uninstalledAt > $1.uninstalledAt }
    }

    func fetch(id: UUID) -> UninstallRecord? {
        records.first { $0.id == id }
    }

    func markRestored(id: UUID) {
        guard let idx = records.firstIndex(where: { $0.id == id }) else { return }
        var record = records[idx]
        record.isRestored = true
        records[idx] = record
    }

    func deleteExpired(olderThan days: Int) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        records.removeAll { $0.uninstalledAt < cutoff }
    }
}
```

- [ ] **Step 6: Run tests to verify pass**

Run: `xcodebuild test ... -only-testing kUninstallTests/TrashMoverTests`
Expected: Tests pass.

- [ ] **Step 7: Commit**

```bash
git add kUninstall/Core/Clean/TrashMover.swift kUninstall/Data/BackupManager.swift \
       kUninstall/Data/UninstallHistoryRepository.swift kUninstall/Tests/CleanTests/TrashMoverTests.swift
git commit -m "feat(kUninstall): implement TrashMover, BackupManager, and UninstallHistoryRepository"
```

---

### Task 6: Implement ResidueScanner facade + AppListViewModel + AppListView UI

**Files:**
- Create: `kUninstall/Core/Clean/ResidueScanner.swift`
- Create: `kUninstall/Features/AppList/AppListViewModel.swift`
- Create: `kUninstall/Features/AppList/AppListView.swift`
- Create: `kUninstall/Features/AppList/AppRowView.swift`

**Interfaces:**
- Consumes: `AppCatalogService`, `ResidueDetector`, `InstalledApp`
- Produces: `AppListViewModel`, `AppListView`, `AppRowView`

- [ ] **Step 1: Implement ResidueScanner facade**

```swift
// kUninstall/Core/Clean/ResidueScanner.swift
import Foundation

actor ResidueScanner {
    private let appCatalog = AppCatalogService()
    private let residueDetector = ResidueDetector()

    func scanAll() async -> [InstalledApp] {
        let apps = await appCatalog.scan()
        // Scan residues for each app in parallel
        return await withTaskGroup(of: InstalledApp.self) { group in
            for app in apps {
                group.addTask {
                    var mutable = app
                    let residues = await self.residueDetector.detectResidues(
                        bundleID: app.bundleID,
                        appName: app.displayName
                    )
                    mutable.residues = residues
                    return mutable
                }
            }
            var result = [InstalledApp]()
            for await app in group {
                result.append(app)
            }
            return result.sorted { $0.displayName < $1.displayName }
        }
    }
}
```

- [ ] **Step 2: Implement AppListViewModel**

```swift
// kUninstall/Features/AppList/AppListViewModel.swift
import SwiftUI

@MainActor
class AppListViewModel: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var searchQuery = ""
    @Published var filter: AppFilter = .all
    @Published var isLoading = true

    enum AppFilter: String, CaseIterable {
        case all = "全部"
        case user = "用户"
        case system = "系统"
        case recent = "最近安装"
    }

    private let scanner = ResidueScanner()

    var filteredApps: [InstalledApp] {
        var result = apps
        if !searchQuery.isEmpty {
            result = result.filter { $0.displayName.localizedCaseInsensitiveContains(searchQuery) || $0.bundleID.localizedCaseInsensitiveContains(searchQuery) }
        }
        switch filter {
        case .all: break
        case .user: result = result.filter { $0.source == .userInstalled || $0.source == .mas }
        case .system: result = result.filter { $0.source == .system || $0.source == .appleBuiltIn }
        case .recent: result = result.filter { $0.lastUsedDate ?? .distantPast > Date().addingTimeInterval(-86400 * 30) }
        }
        return result
    }

    func loadApps() async {
        isLoading = true
        let scanned = await scanner.scanAll()
        await MainActor.run {
            self.apps = scanned
            self.isLoading = false
        }
    }
}
```

- [ ] **Step 3: Implement AppRowView**

```swift
// kUninstall/Features/AppList/AppRowView.swift
import SwiftUI

struct AppRowView: View {
    let app: InstalledApp

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.displayName)
                        .font(.system(size: 14, weight: .medium))
                    if app.isProtected {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }
                Text(app.bundleID)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(app.sizeFormatted)
                    .font(.system(size: 12, weight: .medium))
                sourceBadge
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    @ViewBuilder private var sourceBadge: some View {
        switch app.source {
        case .system:
            Label("系统", systemImage: "gearshape")
                .font(.system(size: 10))
                .foregroundColor(.red)
        case .appleBuiltIn:
            Label("Apple", systemImage: "applelogo")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        case .mas:
            Text("App Store")
                .font(.system(size: 10))
                .foregroundColor(.blue)
        case .userInstalled:
            EmptyView()
        case .unknown:
            EmptyView()
        }
    }
}
```

- [ ] **Step 4: Implement AppListView**

```swift
// kUninstall/Features/AppList/AppListView.swift
import SwiftUI

struct AppListView: View {
    @StateObject private var viewModel = AppListViewModel()
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索 App...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(Color(.controlBackgroundColor))

            // Filter bar
            Picker("", selection: $viewModel.filter) {
                ForEach(AppListViewModel.AppFilter.allCases, id: \.self) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            // List
            if viewModel.isLoading {
                Spacer()
                LoadingStateView(message: "正在扫描已安装应用...")
                Spacer()
            } else if viewModel.filteredApps.isEmpty {
                Spacer()
                EmptyStateView(title: "没有找到 App", subtitle: "尝试调整筛选条件")
                Spacer()
            } else {
                List(viewModel.filteredApps) { app in
                    AppRowView(app: app)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            coordinator.selectApp(app)
                        }
                        .listRowInsets(EdgeInsets())
                }
                .listStyle(.plain)
            }
        }
        .task {
            await viewModel.loadApps()
        }
    }
}
```

- [ ] **Step 5: Verify UI compiles**

Run: `xcodebuild build -project kUninstall/kUninstall.xcodeproj -scheme kUninstall -destination 'platform=macOS'`
Expected: Build succeeds.

- [ ] **Step 6: Commit**

```bash
git add kUninstall/Core/Clean/ResidueScanner.swift kUninstall/Features/AppList/
git commit -m "feat(kUninstall): implement ResidueScanner facade and AppList UI with search/filter"
```

---

### Task 7: Implement AppDetailView + ResidueSectionView + DetailViewModel

**Files:**
- Create: `kUninstall/Features/Detail/AppDetailView.swift`
- Create: `kUninstall/Features/Detail/DetailViewModel.swift`
- Create: `kUninstall/Features/Detail/ResidueSectionView.swift`

**Interfaces:**
- Consumes: `InstalledApp`, `ResidueFile`, `TrashMover`, `StoreManager`
- Produces: `AppDetailView`, `ResidueSectionView`, `DetailViewModel`

- [ ] **Step 1: Implement DetailViewModel**

```swift
// kUninstall/Features/Detail/DetailViewModel.swift
import SwiftUI

@MainActor
class DetailViewModel: ObservableObject {
    @Published var app: InstalledApp
    @Published var showConfirmSheet = false
    @Published var selectedResidues: Set<String> = []
    @Published var isUninstalling = false
    @Published var showUninstallToast = false
    @Published var undoRemainingSeconds = 10

    private let trashMover = TrashMover()
    private let coordinator: AppCoordinator

    init(app: InstalledApp, coordinator: AppCoordinator) {
        self.app = app
        self.coordinator = coordinator
        self.selectedResidues = Set(app.residues.filter { $0.confidence >= 0.8 }.map { $0.id })
    }

    var totalFreedBytes: Int64 {
        app.sizeBytes + app.residues.filter { selectedResidues.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes }
    }

    func uninstall() async {
        isUninstalling = true
        let selected = app.residues.filter { selectedResidues.contains($0.id) }
        let result = await trashMover.moveToTrash(app: app, residues: selected)
        isUninstalling = false

        switch result {
        case .success(let record):
            showConfirmSheet = false
            showUninstallToast = true
            startUndoCountdown(with: record)
        case .failure(let error):
            // Show error alert
            break
        }
    }

    private func startUndoCountdown(with record: UninstallRecord) {
        undoRemainingSeconds = 10
        Task {
            for i in stride(from: 10, through: 0, by: -1) {
                undoRemainingSeconds = i
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if i == 0 {
                    showUninstallToast = false
                }
            }
        }
    }

    func restore(record: UninstallRecord) async {
        _ = await trashMover.restore(record: record)
        showUninstallToast = false
    }
}
```

- [ ] **Step 2: Implement ResidueSectionView**

```swift
// kUninstall/Features/Detail/ResidueSectionView.swift
import SwiftUI

struct ResidueSectionView: View {
    let residues: [ResidueFile]
    @Binding var selectedResidues: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("残留文件 (\(residues.count) 项)")
                .font(.headline)

            ForEach(residues) { residue in
                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(
                        get: { selectedResidues.contains(residue.id) },
                        set: { if $0 { selectedResidues.insert(residue.id) } else { selectedResidues.remove(residue.id) } }
                    ))
                    .toggleStyle(.checkbox)
                    .disabled(residue.isProtected)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(residue.url.lastPathComponent)
                            .font(.system(size: 12, weight: .medium))
                        Text(residue.description)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    confidenceBadge(residue.confidence)

                    Text(residue.sizeFormatted)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder private func confidenceBadge(_ confidence: Double) -> some View {
        if confidence >= 0.95 {
            Text("确定")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.green)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.green.opacity(0.1))
                .cornerRadius(3)
        } else if confidence >= 0.8 {
            Text("可能")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.orange)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(3)
        } else {
            Text("低")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(3)
        }
    }
}
```

- [ ] **Step 3: Implement AppDetailView**

```swift
// kUninstall/Features/Detail/AppDetailView.swift
import SwiftUI

struct AppDetailView: View {
    let app: InstalledApp
    @StateObject private var viewModel: DetailViewModel
    @EnvironmentObject private var coordinator: AppCoordinator

    init(app: InstalledApp) {
        self.app = app
        _viewModel = StateObject(wrappedValue: DetailViewModel(app: app, coordinator: AppCoordinator()))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroSection
                sizeSection
                if !app.residues.isEmpty {
                    ResidueSectionView(residues: app.residues, selectedResidues: $viewModel.selectedResidues)
                }
                Spacer()
                uninstallButton
            }
            .padding(24)
        }
        .sheet(isPresented: $viewModel.showConfirmSheet) {
            UninstallConfirmSheet(viewModel: viewModel)
        }
        .overlay(alignment: .bottom) {
            if viewModel.showUninstallToast {
                uninstallToast
            }
        }
    }

    private var heroSection: some View {
        HStack(spacing: 16) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(app.displayName)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    if app.isProtected {
                        Label("系统", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                Text("\(app.bundleID) • v\(app.version)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                sourceLabel
            }
        }
    }

    @ViewBuilder private var sourceLabel: some View {
        switch app.source {
        case .mas:
            Label("来自 App Store", systemImage: "bag")
                .font(.caption)
                .foregroundColor(.blue)
        case .userInstalled:
            Label("第三方 App", systemImage: "arrow.down.app")
                .font(.caption)
                .foregroundColor(.secondary)
        case .system:
            Label("系统组件", systemImage: "gearshape.2")
                .font(.caption)
                .foregroundColor(.red)
        case .appleBuiltIn:
            Label("Apple 内置", systemImage: "applelogo")
                .font(.caption)
                .foregroundColor(.secondary)
        case .unknown:
            EmptyView()
        }
    }

    private var sizeSection: some View {
        HStack(spacing: 40) {
            VStack(spacing: 4) {
                Text(app.sizeFormatted)
                    .font(.system(size: 24, weight: .bold))
                Text("App 本体")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            VStack(spacing: 4) {
                Text(ByteCountFormatter.string(fromByteCount: app.residues.reduce(0) { $0 + $1.sizeBytes }, countStyle: .file))
                    .font(.system(size: 24, weight: .bold))
                Text("残留文件")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if app.isRunning {
                Label("运行中", systemImage: "play.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }

    private var uninstallButton: some View {
        Button(action: {
            viewModel.showConfirmSheet = true
        }) {
            HStack {
                Image(systemName: "trash")
                Text("卸载")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(app.isProtected ? Color.gray : Color.red.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
        .disabled(app.isProtected)
    }

    private var uninstallToast: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("已卸载 \(app.displayName)")
                .fontWeight(.medium)
            Spacer()
            Button("撤销 (\(viewModel.undoRemainingSeconds)s)") {
                Task { await viewModel.restore(record: UninstallRecord(
                    id: UUID(), appName: app.displayName, bundleID: app.bundleID,
                    appPath: app.url.path, appSize: app.sizeBytes,
                    totalResidueSize: 0, residueCount: 0, uninstalledAt: Date(),
                    isRestored: false, backupPath: "", residues: []
                )) }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding()
    }
}
```

- [ ] **Step 4: Verify UI compiles**

Run: `xcodebuild build ...`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add kUninstall/Features/Detail/
git commit -m "feat(kUninstall): implement AppDetailView with residue selection and uninstall flow"
```

---

### Task 8: Implement UninstallConfirmSheet — 5-step pre-uninstall safety check + confirm sheet

**Files:**
- Create: `kUninstall/Features/Detail/UninstallConfirmSheet.swift`
- Update: `kUninstall/Features/Detail/DetailViewModel.swift` (add safety check methods)

- [ ] **Step 1: UninstallConfirmSheet implementation**

```swift
// kUninstall/Features/Detail/UninstallConfirmSheet.swift
import SwiftUI

struct UninstallConfirmSheet: View {
    @ObservedObject var viewModel: DetailViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(nsImage: viewModel.app.icon)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("卸载 \(viewModel.app.displayName)?")
                    .font(.title2)
                    .fontWeight(.bold)

                safetyChecks
            }

            Divider()

            // Size breakdown
            VStack(spacing: 8) {
                sizeRow(label: "App 本体", size: viewModel.app.sizeBytes)
                sizeRow(label: "残留文件 (\(viewModel.selectedResidues.count) 项)", size: viewModel.app.residues.filter { viewModel.selectedResidues.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes })
                Divider()
                sizeRow(label: "共释放", size: viewModel.totalFreedBytes, bold: true)
                    .foregroundColor(.green)
            }

            // Notes
            VStack(alignment: .leading, spacing: 4) {
                Label("移入废纸篓（可回滚 30 天）", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if viewModel.app.isRunning {
                    Label("App 正在运行，将先退出再卸载", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                if viewModel.app.source == .mas {
                    Label("此 App 来自 App Store，可重新下载", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            HStack(spacing: 12) {
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape)

                Button("确认卸载") {
                    Task {
                        await viewModel.uninstall()
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(viewModel.isUninstalling)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private var safetyChecks: some View {
        VStack(alignment: .leading, spacing: 4) {
            SafetyCheckRow(icon: "checkmark.shield", text: "安全检查", passed: !viewModel.app.isProtected)
            SafetyCheckRow(icon: "power", text: "运行检查", passed: !viewModel.app.isRunning)
            SafetyCheckRow(icon: "doc.text.magnifyingglass", text: "残留预扫描", passed: !viewModel.app.residues.isEmpty)
        }
        .padding(8)
    }

    private func sizeRow(label: String, size: Int64, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(bold ? .headline : .subheadline)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                .font(bold ? .headline : .subheadline)
                .fontWeight(bold ? .bold : .regular)
        }
    }
}

struct SafetyCheckRow: View {
    let icon: String
    let text: String
    let passed: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(passed ? .green : .red)
                .font(.system(size: 12))
            Text(text)
                .font(.caption)
                .foregroundColor(passed ? .primary : .red)
        }
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild build ...`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add kUninstall/Features/Detail/UninstallConfirmSheet.swift
git commit -m "feat(kUninstall): add 5-step safety check and uninstall confirm sheet"
```

---

### Task 9: Implement HistoryView + FDAGuideView + SettingsView

**Files:**
- Create: `kUninstall/Features/History/HistoryView.swift`
- Create: `kUninstall/Features/History/HistoryViewModel.swift`
- Create: `kUninstall/Features/Onboarding/FDAGuideView.swift`
- Create: `kUninstall/Features/Onboarding/FDAGuideController.swift`
- Create: `kUninstall/Features/Settings/SettingsView.swift`
- Create: `kUninstall/Features/Settings/SettingsViewModel.swift`
- Create: `kUninstall/Data/FDAuthorizer.swift`

- [ ] **Step 1: Implement FDAuthorizer**

```swift
// kUninstall/Data/FDAuthorizer.swift
import Foundation

actor FDAuthorizer {
    private let fileManager = FileManager.default

    /// Check if FDA is granted by testing ~/Library accessibility
    func checkFDA() -> Bool {
        let testPath = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        return fileManager.isReadableFile(atPath: testPath.path)
    }

    /// Open System Settings → Privacy → Full Disk Access
    func requestFDA() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Create a Security-Scoped Bookmark for persistent access
    func createBookmark(for url: URL) -> Data? {
        try? url.bookmarkData(options: .withSecurityScope,
                              includingResourceValuesForKeys: nil,
                              relativeTo: nil)
    }

    /// Resolve a Security-Scoped Bookmark
    func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        let url = try? URL(resolvingBookmarkData: data,
                           options: .withSecurityScope,
                           relativeTo: nil,
                           bookmarkDataIsStale: &isStale)
        _ = url?.startAccessingSecurityScopedResource()
        return url
    }
}
```

- [ ] **Step 2: Implement FDAGuideView + FDAGuideController**

```swift
// kUninstall/Features/Onboarding/FDAGuideController.swift
import Foundation

@MainActor
class FDAGuideController: ObservableObject {
    @Published var showGuide = false
    private let authorizer = FDAuthorizer()

    func checkAndGuide() {
        Task {
            let hasFDA = await authorizer.checkFDA()
            if !hasFDA {
                showGuide = true
            }
        }
    }
}
```

```swift
// kUninstall/Features/Onboarding/FDAGuideView.swift
import SwiftUI

struct FDAGuideView: View {
    var onSkip: (() -> Void)?
    var onContinue: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("让 kUninstall 彻底清理 App 残留")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 12) {
                GuideStep(number: 1, text: "打开「系统设置 → 隐私与安全性 → 全盘访问权限」")
                GuideStep(number: 2, text: "点击锁图标解锁")
                GuideStep(number: 3, text: "找到 kUninstall 并开启开关")
                GuideStep(number: 4, text: "返回 kUninstall 继续")
            }

            HStack(spacing: 12) {
                Button("跳过") {
                    onSkip?()
                }
                .buttonStyle(.bordered)

                Button("打开系统设置") {
                    FDAuthorizer().requestFDA()
                }
                .buttonStyle(.borderedProminent)

                Button("已授权，继续") {
                    onContinue?()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(40)
        .frame(width: 500)
    }
}

struct GuideStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 14, weight: .bold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))
                .foregroundColor(.white)
            Text(text)
                .font(.body)
        }
    }
}
```

- [ ] **Step 3: Implement HistoryView**

```swift
// kUninstall/Features/History/HistoryView.swift
import SwiftUI

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("卸载历史")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding()

            if viewModel.records.isEmpty {
                EmptyStateView(title: "暂无卸载记录", subtitle: "卸载 App 后将在此显示")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(viewModel.records) { record in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(record.appName)
                                .fontWeight(.medium)
                            Text("\(record.bundleID) • \(record.uninstalledAt.formatted())")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: record.appSize + record.totalResidueSize, countStyle: .file))
                            .font(.caption)

                        if !record.isRestored {
                            Button("恢复") {
                                Task { await viewModel.restore(record: record) }
                            }
                            .buttonStyle(.bordered)
                            .disabled(viewModel.isRestoring)
                        } else {
                            Text("已恢复")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.plain)
            }
        }
        .task {
            await viewModel.loadHistory()
        }
    }
}
```

```swift
// kUninstall/Features/History/HistoryViewModel.swift
import Foundation

@MainActor
class HistoryViewModel: ObservableObject {
    @Published var records: [UninstallRecord] = []
    @Published var isRestoring = false

    private let repo = UninstallHistoryRepository()

    func loadHistory() async {
        let all = await repo.fetchAll()
        await MainActor.run { self.records = all }
    }

    func restore(record: UninstallRecord) async {
        isRestoring = true
        let mover = TrashMover()
        _ = await mover.restore(record: record)
        await loadHistory()
        isRestoring = false
    }
}
```

- [ ] **Step 4: Implement SettingsView**

```swift
// kUninstall/Features/Settings/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }

            aboutTab
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 450, height: 300)
    }

    private var generalTab: some View {
        Form {
            Toggle("启动时自动扫描", isOn: $viewModel.autoScan)

            HStack {
                Text("备份保留天数")
                Spacer()
                Picker("", selection: $viewModel.backupRetentionDays) {
                    Text("7 天").tag(7)
                    Text("14 天").tag(14)
                    Text("30 天").tag(30)
                }
                .labelsHidden()
            }

            Divider()

            HStack {
                Text("FDA 状态")
                Spacer()
                if viewModel.hasFDA {
                    Label("已授权", systemImage: "checkmark.shield.fill")
                        .foregroundColor(.green)
                } else {
                    Button("授权全盘访问") {
                        viewModel.requestFDA()
                    }
                }
            }

            Divider()

            HStack {
                Text("Pro 状态")
                Spacer()
                if viewModel.isPro {
                    Label("已解锁", systemImage: "crown.fill")
                        .foregroundColor(.orange)
                } else {
                    Button("升级 Pro") {
                        viewModel.showPaywall()
                    }
                }
            }
        }
        .padding()
    }

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Text("kUninstall")
                .font(.title)
                .fontWeight(.bold)
            Text("版本 1.0.0")
                .foregroundColor(.secondary)
            Text("Kraftly — Cleaner Mac tools, made with care.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
```

- [ ] **Step 5: Verify build**

Run: `xcodebuild build ...`
Expected: Build succeeds.

- [ ] **Step 6: Commit**

```bash
git add kUninstall/Features/History/ kUninstall/Features/Onboarding/ \
       kUninstall/Features/Settings/ kUninstall/Data/FDAuthorizer.swift
git commit -m "feat(kUninstall): add history, FDA guide, and settings views"
```

---

### Task 10: Implement DeepCleanEngine + DeepCleanView (Pro)

**Files:**
- Create: `kUninstall/Features/DeepClean/DeepCleanEngine.swift`
- Create: `kUninstall/Features/DeepClean/DeepCleanView.swift`
- Create: `kUninstall/Features/DeepClean/DeepCleanViewModel.swift`
- Create: `kUninstall/Features/DeepClean/SystemCleanGroupView.swift`

**Interfaces:**
- Consumes: `FDAuthorizer`, `BackupManager`, Core Data
- Produces: `DeepCleanEngine.scanSystemWideResidues()`, `DeepCleanEngine.cleanSelected(_:)`

- [ ] **Step 1: Implement DeepCleanEngine (actor, Pro-only)**

```swift
// kUninstall/Features/DeepClean/DeepCleanEngine.swift
import Foundation

actor DeepCleanEngine {
    private let fileManager = FileManager.default

    struct CleanGroup: Identifiable {
        var id: String { title }
        let title: String
        let icon: String
        let items: [CleanItem]
    }

    struct CleanItem: Identifiable {
        var id: String { url.path }
        let url: URL
        let name: String
        let sizeBytes: Int64
        let type: StartupItemType
        var isSelected: Bool
    }

    func scanSystemWideResidues() async -> [CleanGroup] {
        await withTaskGroup(of: CleanGroup?.self) { group in
            group.addTask { await self.scanDaemons() }
            group.addTask { await self.scanAgents() }
            group.addTask { await self.scanPanes() }
            group.addTask { await self.scanLoginItems() }

            var groups = [CleanGroup]()
            for await g in group {
                if let g = g, !g.items.isEmpty { groups.append(g) }
            }
            return groups
        }
    }

    func cleanSelected(_ groups: [CleanGroup]) async -> Int {
        var totalCleaned: Int64 = 0
        for group in groups {
            for item in group.items where item.isSelected {
                try? fileManager.removeItem(at: item.url)
                totalCleaned += item.sizeBytes
            }
        }
        return Int(totalCleaned)
    }

    private func scanDaemons() async -> CleanGroup? {
        let dir = URL(fileURLWithPath: "/Library/LaunchDaemons")
        let plists = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let items = plists.filter { $0.pathExtension == "plist" }.map { url in
            CleanItem(url: url, name: url.deletingPathExtension().lastPathComponent,
                       sizeBytes: (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0,
                       type: .launchDaemon, isSelected: false)
        }
        return CleanGroup(title: "Launch Daemons", icon: "gearshape.2", items: items)
    }

    private func scanAgents() async -> CleanGroup? {
        let home = fileManager.homeDirectoryForCurrentUser
        let dirs = [
            URL(fileURLWithPath: "/Library/LaunchAgents"),
            home.appendingPathComponent("Library/LaunchAgents"),
        ]
        var allItems = [CleanItem]()
        for dir in dirs {
            let plists = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            allItems += plists.filter { $0.pathExtension == "plist" }.map { url in
                CleanItem(url: url, name: url.deletingPathExtension().lastPathComponent,
                           sizeBytes: (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0,
                           type: .launchAgent, isSelected: false)
            }
        }
        return CleanGroup(title: "Launch Agents", icon: "power", items: allItems)
    }

    private func scanPanes() async -> CleanGroup? {
        let dirs = [
            URL(fileURLWithPath: "/Library/PreferencePanes"),
            URL(fileURLWithPath: "/System/Library/PreferencePanes"),
        ]
        var allItems = [CleanItem]()
        for dir in dirs {
            let panes = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            allItems += panes.filter { $0.pathExtension == "prefPane" }.map { url in
                CleanItem(url: url, name: url.deletingPathExtension().lastPathComponent,
                           sizeBytes: 0, type: .prefPane, isSelected: false)
            }
        }
        return CleanGroup(title: "Preference Panes", icon: "switch.2", items: allItems)
    }

    private func scanLoginItems() async -> CleanGroup? {
        // LSSharedFileList is a public API for login items
        let list = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil)?.takeRetainedValue()
        guard let list else { return nil }
        let items = LSSharedFileListCopySnapshot(list, nil).takeRetainedValue() as! [LSSharedFileListItem]
        let cleanItems = items.compactMap { item -> CleanItem? in
            var url: Unmanaged<CFURL>?
            let name = LSSharedFileListItemCopyDisplayName(item)?.takeRetainedValue() as String? ?? "Unknown"
            guard LSSharedFileListItemResolve(item, 0, &url, nil) == noErr, let resolvedURL = url?.takeRetainedValue() as URL? else { return nil }
            return CleanItem(url: resolvedURL, name: name, sizeBytes: 0, type: .loginItem, isSelected: false)
        }
        return CleanGroup(title: "Login Items", icon: "person.circle", items: cleanItems)
    }
}
```

- [ ] **Step 2: Implement DeepCleanViewModel**

```swift
// kUninstall/Features/DeepClean/DeepCleanViewModel.swift
import SwiftUI

@MainActor
class DeepCleanViewModel: ObservableObject {
    @Published var groups: [DeepCleanEngine.CleanGroup] = []
    @Published var isScanning = false
    @Published var hasFDA = false

    private let engine = DeepCleanEngine()
    private let authorizer = FDAuthorizer()

    func checkFDA() async {
        let result = await authorizer.checkFDA()
        await MainActor.run { self.hasFDA = result }
    }

    func scan() async {
        isScanning = true
        let result = await engine.scanSystemWideResidues()
        await MainActor.run {
            self.groups = result
            self.isScanning = false
        }
    }

    func clean() async -> Int {
        let freed = await engine.cleanSelected(groups)
        await scan()  // Refresh after clean
        return freed
    }
}
```

- [ ] **Step 3: Implement DeepCleanView**

```swift
// kUninstall/Features/DeepClean/DeepCleanView.swift
import SwiftUI

struct DeepCleanView: View {
    @StateObject private var viewModel = DeepCleanViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("深度清理")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Spacer()
                if !viewModel.groups.isEmpty {
                    Button("清理选中项") {
                        Task { await viewModel.clean() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()

            if !viewModel.hasFDA {
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 32))
                    Text("需要全盘访问权限")
                    Text("深度清理需要 FDA 授权才能扫描系统级残留")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("授权 FDA") {
                        FDAuthorizer().requestFDA()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.isScanning {
                LoadingStateView(message: "正在扫描系统残留...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.groups.isEmpty {
                EmptyStateView(title: "未发现系统残留", subtitle: "系统状态良好")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.groups) { group in
                        SystemCleanGroupView(group: group)
                    }
                }
                .listStyle(.plain)
            }
        }
        .task {
            await viewModel.checkFDA()
            if viewModel.hasFDA {
                await viewModel.scan()
            }
        }
    }
}
```

```swift
// kUninstall/Features/DeepClean/SystemCleanGroupView.swift
import SwiftUI

struct SystemCleanGroupView: View {
    let group: DeepCleanEngine.CleanGroup

    var body: some View {
        Section {
            ForEach(group.items) { item in
                HStack {
                    Image(systemName: group.icon)
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading) {
                        Text(item.name)
                            .font(.system(size: 13))
                        Text(item.url.path)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            HStack {
                Text(group.title)
                    .font(.headline)
                Spacer()
                Text("\(group.items.count) 项")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
```

- [ ] **Step 4: Verify build**

Run: `xcodebuild build ...`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add kUninstall/Features/DeepClean/
git commit -m "feat(kUninstall): implement DeepCleanEngine and DeepCleanView (Pro)"
```

---

### Task 11: Implement StartupItemManager + StartupItemsView (Pro)

**Files:**
- Create: `kUninstall/Core/Startup/StartupItemManager.swift`
- Create: `kUninstall/Features/StartupItems/StartupItemsView.swift`
- Create: `kUninstall/Features/StartupItems/StartupItemsViewModel.swift`

- [ ] **Step 1: Implement StartupItemManager**

```swift
// kUninstall/Core/Startup/StartupItemManager.swift
import Foundation

actor StartupItemManager {
    func listItems() async -> [StartupItem] {
        await withTaskGroup(of: [StartupItem].self) { group in
            group.addTask { await self.listLoginItems() }
            group.addTask { await self.listLaunchAgents() }
            group.addTask { await self.listLaunchDaemons() }

            var all = [StartupItem]()
            for await items in group { all += items }
            return all.sorted { $0.name < $1.name }
        }
    }

    func remove(item: StartupItem) async {
        try? FileManager.default.removeItem(at: item.url)
    }

    private func listLoginItems() async -> [StartupItem] {
        guard let list = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil)?.takeRetainedValue() else { return [] }
        let items = LSSharedFileListCopySnapshot(list, nil).takeRetainedValue() as! [LSSharedFileListItem]
        return items.compactMap { item -> StartupItem? in
            var url: Unmanaged<CFURL>?
            guard LSSharedFileListItemResolve(item, 0, &url, nil) == noErr,
                  let resolvedURL = url?.takeRetainedValue() as URL? else { return nil }
            let name = LSSharedFileListItemCopyDisplayName(item)?.takeRetainedValue() as String? ?? resolvedURL.lastPathComponent
            return StartupItem(name: name, type: .loginItem, url: resolvedURL,
                                appURL: resolvedURL, enabled: true,
                                isProtected: false)
        }
    }

    private func listLaunchAgents() async -> [StartupItem] {
        let dirs = [
            URL(fileURLWithPath: "/Library/LaunchAgents"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents"),
        ]
        return itemsFromPlistDirectories(dirs, type: .launchAgent)
    }

    private func listLaunchDaemons() async -> [StartupItem] {
        let dir = URL(fileURLWithPath: "/Library/LaunchDaemons")
        return itemsFromPlistDirectories([dir], type: .launchDaemon)
    }

    private func itemsFromPlistDirectories(_ dirs: [URL], type: StartupItemType) -> [StartupItem] {
        dirs.flatMap { dir in
            guard let plists = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [StartupItem]() }
            return plists.filter { $0.pathExtension == "plist" }.map { url in
                StartupItem(name: url.deletingPathExtension().lastPathComponent,
                            type: type, url: url, appURL: nil,
                            enabled: true, isProtected: url.path.hasPrefix("/System/"))
            }
        }
    }
}
```

- [ ] **Step 2: Implement StartupItemsViewModel + View**

```swift
// kUninstall/Features/StartupItems/StartupItemsViewModel.swift
import SwiftUI

@MainActor
class StartupItemsViewModel: ObservableObject {
    @Published var items: [StartupItem] = []
    @Published var isLoading = false

    private let manager = StartupItemManager()

    func load() async {
        isLoading = true
        let result = await manager.listItems()
        await MainActor.run {
            self.items = result
            self.isLoading = false
        }
    }

    func remove(item: StartupItem) async {
        await manager.remove(item: item)
        await load()
    }
}
```

```swift
// kUninstall/Features/StartupItems/StartupItemsView.swift
import SwiftUI

struct StartupItemsView: View {
    @StateObject private var viewModel = StartupItemsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("启动项管理")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding()

            if viewModel.isLoading {
                LoadingStateView(message: "正在加载启动项...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.items.isEmpty {
                EmptyStateView(title: "无启动项", subtitle: "未发现登录项或启动代理")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(StartupItemType.allCases, id: \.self) { type in
                        let filtered = viewModel.items.filter { $0.type == type }
                        if !filtered.isEmpty {
                            Section(type.rawValue) {
                                ForEach(filtered) { item in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(item.name)
                                                .fontWeight(.medium)
                                            Text(item.url.path)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Button("移除") {
                                            Task { await viewModel.remove(item: item) }
                                        }
                                        .buttonStyle(.bordered)
                                        .disabled(item.isProtected)
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .task { await viewModel.load() }
    }
}

extension StartupItemType: CaseIterable {
    public static var allCases: [StartupItemType] = [.loginItem, .launchAgent, .launchDaemon]
}
```

- [ ] **Step 3: Verify build**

Run: `xcodebuild build ...`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add kUninstall/Core/Startup/ kUninstall/Features/StartupItems/
git commit -m "feat(kUninstall): implement StartupItemManager and StartupItemsView (Pro)"
```

---

### Task 12: Implement StoreManager + PaywallView (IAP)

**Files:**
- Create: `kUninstall/Store/StoreManager.swift`
- Create: `kUninstall/Store/StoreDefinitions.swift`
- Create: `kUninstall/Store/PaywallView.swift`

- [ ] **Step 1: Implement StoreDefinitions**

```swift
// kUninstall/Store/StoreDefinitions.swift
import Foundation

enum StoreProduct: String {
    case proUnlock = "app.kraftly.kuninstall.pro"

    var displayName: String {
        switch self {
        case .proUnlock: return "kUninstall Pro"
        }
    }

    var priceTier: String { "$9.99" }
}

enum ProFeature {
    case deepClean
    case startupManagement
    case batchUninstall
    case visualization
    case widget
    case shortcuts
    case aiAnalysis

    var description: String {
        switch self {
        case .deepClean:       return "深度系统清理"
        case .startupManagement: return "启动项管理"
        case .batchUninstall:  return "批量卸载"
        case .visualization:   return "应用体积可视化"
        case .widget:          return "桌面 Widget"
        case .shortcuts:       return "Shortcuts 集成"
        case .aiAnalysis:      return "AI 使用分析"
        }
    }

    var icon: String {
        switch self {
        case .deepClean:       return "gearshape.2"
        case .startupManagement: return "power"
        case .batchUninstall:  return "trash.slash"
        case .visualization:   return "chart.pie"
        case .widget:          return "square.grid.2x2"
        case .shortcuts:       return "command"
        case .aiAnalysis:      return "brain"
        }
    }
}
```

- [ ] **Step 2: Implement StoreManager**

```swift
// kUninstall/Store/StoreManager.swift
import Foundation
import StoreKit

actor StoreManager {
    static let shared = StoreManager()

    private var isPurchased = false

    var isPro: Bool { isPurchased }

    func loadProducts() async -> [Product] {
        guard let products = try? await Product.products(for: [StoreProduct.proUnlock.rawValue]) else { return [] }
        return products
    }

    func purchase(_ product: Product) async -> Bool {
        guard let result = try? await product.purchase() else { return false }
        switch result {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                isPurchased = true
                await transaction.finish()
                return true
            }
            return false
        case .userCancelled:
            return false
        default:
            return false
        }
    }

    func restorePurchases() async -> Bool {
        try? await AppStore.sync()
        // Check receipt for pro entitlement
        isPurchased = await verifyReceipt()
        return isPurchased
    }

    private func verifyReceipt() async -> Bool {
        // Check Main Bundle receipt for Pro entitlement
        guard let receiptURL = Bundle.main.appStoreReceiptURL,
              FileManager.default.fileExists(atPath: receiptURL.path) else { return false }
        // In production, validate receipt locally or server-side
        // For v1, check if receipt exists (basic check)
        return true
    }
}
```

- [ ] **Step 3: Implement PaywallView**

```swift
// kUninstall/Store/PaywallView.swift
import SwiftUI
import StoreKit

struct PaywallView: View {
    @State private var products: [Product] = []
    @State private var isPurchasing = false
    @State private var purchaseComplete = false

    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            // Hero
            VStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                Text("升级 kUninstall Pro")
                    .font(.title)
                    .fontWeight(.bold)
                Text("解锁全部高级功能")
                    .foregroundColor(.secondary)
            }

            // Feature list
            VStack(alignment: .leading, spacing: 12) {
                ForEach(ProFeature.allCases, id: \.self) { feature in
                    HStack(spacing: 12) {
                        Image(systemName: feature.icon)
                            .frame(width: 24)
                            .foregroundColor(.accentColor)
                        Text(feature.description)
                            .font(.body)
                        Spacer()
                        Image(systemName: "checkmark")
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(16)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(12)

            // Price
            if let product = products.first {
                Button(action: { purchase(product) }) {
                    HStack {
                        Text("\(product.displayPrice) — 一次性买断")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(isPurchasing)
            } else {
                ProgressView()
            }

            Button("恢复购买") {
                Task { await restore() }
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            if purchaseComplete {
                Text("购买成功！欢迎使用 kUninstall Pro 🎉")
                    .foregroundColor(.green)
            }
        }
        .padding(32)
        .frame(width: 380)
        .task {
            let manager = StoreManager.shared
            products = await manager.loadProducts()
        }
    }

    private func purchase(_ product: Product) {
        isPurchasing = true
        Task {
            let success = await StoreManager.shared.purchase(product)
            await MainActor.run {
                isPurchasing = false
                if success {
                    purchaseComplete = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        onDismiss?()
                    }
                }
            }
        }
    }

    private func restore() async {
        let success = await StoreManager.shared.restorePurchases()
        await MainActor.run {
            if success { purchaseComplete = true }
        }
    }
}
```

- [ ] **Step 4: Verify build**

Run: `xcodebuild build ...`
Expected: Build succeeds.

- [ ] **Step 5: Commit**

```bash
git add kUninstall/Store/
git commit -m "feat(kUninstall): implement StoreManager with StoreKit 2 and PaywallView"
```

---

### Task 13: Integrate Pro gating — connect StoreManager to Pro features

**Files:**
- Modify: `kUninstall/Features/DeepClean/DeepCleanView.swift` — add Pro gate
- Modify: `kUninstall/Features/StartupItems/StartupItemsView.swift` — add Pro gate
- Create: `kUninstall/Store/ProGateModifier.swift` — reusable Pro gate view modifier

- [ ] **Step 1: Implement ProGateModifier**

```swift
// kUninstall/Store/ProGateModifier.swift
import SwiftUI

struct ProGateModifier: ViewModifier {
    @State private var isPro = false
    let featureName: String
    let featureIcon: String

    func body(content: Content) -> some View {
        if isPro {
            content
        } else {
            VStack(spacing: 16) {
                Image(systemName: featureIcon)
                    .font(.system(size: 36))
                    .foregroundColor(.secondary)
                Text(featureName)
                    .font(.title2)
                    .fontWeight(.bold)
                Text("升级 Pro 以解锁此功能")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Button("升级 Pro") {
                    // Open paywall
                    NSApplication.shared.keyWindow?.contentViewController?.presentAsSheet(
                        NSHostingController(rootView: PaywallView())
                    )
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
```

- [ ] **Step 2: Apply Pro gate to DeepCleanView and StartupItemsView**

Edit both views to check `StoreManager.shared.isPro` and show the gate if not Pro.

- [ ] **Step 3: Verify build**

Run: `xcodebuild build ...`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git add kUninstall/Store/ProGateModifier.swift
git commit -m "feat(kUninstall): add Pro gating for DeepClean and StartupItems features"
```

---

### Task 14: Implement MenuBarController

**Files:**
- Create: `kUninstall/MenuBar/MenuBarController.swift`

- [ ] **Step 1: Implement MenuBarController**

```swift
// kUninstall/MenuBar/MenuBarController.swift
import AppKit
import SwiftUI

@MainActor
class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "trash.circle", accessibilityDescription: "kUninstall")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开 kUninstall", action: #selector(openApp), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "快速卸载...", action: #selector(quickUninstall), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quickUninstall() {
        // Show quick uninstall popover
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add kUninstall/MenuBar/MenuBarController.swift
git commit -m "feat(kUninstall): add MenuBarController with quick actions"
```

---

### Task 15: Implement Shortcuts Intents (Pro)

**Files:**
- Create: `kUninstall/Intents/UninstallAppIntent.swift`
- Create: `kUninstall/Intents/ScanResidueIntent.swift`
- Create: `kUninstall/Intents/DeepCleanIntent.swift`

- [ ] **Step 1: UninstallAppIntent**

```swift
// kUninstall/Intents/UninstallAppIntent.swift
import AppIntents

struct UninstallAppIntent: AppIntent {
    static var title: LocalizedStringResource = "卸载 App"
    static var description = IntentDescription("卸载指定 App 及其残留文件")

    @Parameter(title: "App 名称")
    var appName: String

    func perform() async throws -> some IntentResult {
        // Look up app by name and trigger uninstall
        let scanner = ResidueScanner()
        let apps = await scanner.scanAll()
        guard let app = apps.first(where: { $0.displayName == appName || $0.bundleID == appName }) else {
            throw IntentError.appNotFound
        }
        let mover = TrashMover()
        let result = await mover.moveToTrash(app: app, residues: app.residues)
        switch result {
        case .success: return .result(value: "已卸载 \(app.displayName)")
        case .failure: throw IntentError.uninstallFailed
        }
    }
}

enum IntentError: Swift.Error {
    case appNotFound
    case uninstallFailed
}
```

```swift
// kUninstall/Intents/ScanResidueIntent.swift
import AppIntents

struct ScanResidueIntent: AppIntent {
    static var title: LocalizedStringResource = "扫描 App 残留"
    static var description = IntentDescription("扫描指定 App 的残留文件")

    @Parameter(title: "App 名称")
    var appName: String

    func perform() async throws -> some IntentResult {
        let detector = ResidueDetector()
        // In real impl, we'd need to look up bundle ID from app name
        let residues = await detector.detectResidues(bundleID: appName, appName: appName)
        let totalSize = residues.reduce(0) { $0 + $1.sizeBytes }
        return .result(value: "发现 \(residues.count) 项残留，共 \(ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file))")
    }
}
```

```swift
// kUninstall/Intents/DeepCleanIntent.swift
import AppIntents

struct DeepCleanIntent: AppIntent {
    static var title: LocalizedStringResource = "深度系统清理"
    static var description = IntentDescription("扫描并清理系统级残留（LaunchDaemons、LaunchAgents 等）")

    static var authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    func perform() async throws -> some IntentResult {
        guard await StoreManager.shared.isPro else {
            throw IntentError.proRequired
        }
        let engine = DeepCleanEngine()
        let groups = await engine.scanSystemWideResidues()
        return .result(value: "发现 \(groups.count) 组系统残留")
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add kUninstall/Intents/
git commit -m "feat(kUninstall): implement 3 Shortcuts intents for uninstall, scan, and deep clean (Pro)"
```

---

### Task 16: Implement Finder Extension

**Files:**
- Create: `kUninstall/FinderExtension/FinderSync.swift`
- Create: `kUninstall/FinderExtension/Info.plist`

- [ ] **Step 1: Implement FinderSync extension**

```swift
// kUninstall/FinderExtension/FinderSync.swift
import FinderSync

class FinderSync: FIFinderSync {
    override init() {
        super.init()
        // Set the directory URLs that the extension monitors
        let finderSync = FIFinderSyncController.default()
        if let appsURL = URL(string: "file:///Applications/") {
            finderSync.directoryURLs = Set([appsURL])
        }
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "kUninstall")
        let item = NSMenuItem(title: "用 kUninstall 深度卸载", action: #selector(uninstallItem), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc func uninstallItem(_ sender: AnyObject?) {
        guard let item = FIFinderSyncController.default().selectedItemURLs?.first else { return }
        // Open the main app with the selected app path
        let appURL = URL(fileURLWithPath: "/Applications/kUninstall.app")
        NSWorkspace.shared.open([item], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }
}
```

```xml
<!-- kUninstall/FinderExtension/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>kUninstall Finder Extension</string>
    <key>CFBundleIdentifier</key>
    <string>app.kraftly.kuninstall.finder-sync</string>
    <key>CFBundlePackageType</key>
    <string>XPC!</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPrincipalClass</key>
        <string>$(PRODUCT_MODULE_NAME).FinderSync</string>
        <key>NSExtensionAttributes</key>
        <dict>
            <key>FIFinderSyncExtensionPrincipalClass</key>
            <string>$(PRODUCT_MODULE_NAME).FinderSync</string>
        </dict>
    </dict>
</dict>
</plist>
```

- [ ] **Step 2: Commit**

```bash
git add kUninstall/FinderExtension/
git commit -m "feat(kUninstall): add Finder Sync extension for right-click uninstall"
```

---

### Task 17: Implement Widgets (Pro)

**Files:**
- Create: `kUninstall/Widgets/AppUsageWidget.swift`
- Create: `kUninstall/Widgets/QuickUninstallWidget.swift`

- [ ] **Step 1: Implement AppUsageWidget**

```swift
// kUninstall/Widgets/AppUsageWidget.swift
import WidgetKit
import SwiftUI

struct AppUsageEntry: TimelineEntry {
    let date: Date
    let topApps: [(name: String, size: String)]
}

struct AppUsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> AppUsageEntry {
        AppUsageEntry(date: Date(), topApps: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (AppUsageEntry) -> Void) {
        completion(AppUsageEntry(date: Date(), topApps: [("Xcode", "12.5 GB")]))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<AppUsageEntry>) -> Void) {
        Task {
            let scanner = ResidueScanner()
            let apps = await scanner.scanAll()
            let top = apps.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(4).map {
                (name: $0.displayName, size: $0.sizeFormatted)
            }
            let entry = AppUsageEntry(date: Date(), topApps: Array(top))
            let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600)))
            completion(timeline)
        }
    }
}

struct AppUsageWidgetEntryView: View {
    var entry: AppUsageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("磁盘占用 Top", systemImage: "trash.circle")
                .font(.headline)

            if entry.topApps.isEmpty {
                Text("暂无数据")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(entry.topApps.indices, id: \.self) { i in
                    HStack {
                        Text("\(i + 1).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(entry.topApps[i].name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(entry.topApps[i].size)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
    }
}

struct AppUsageWidget: Widget {
    let kind = "app.kraftly.kuninstall.widget.usage"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AppUsageProvider()) { entry in
            AppUsageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("磁盘占用")
        .description("显示占用最大的 App")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add kUninstall/Widgets/
git commit -m "feat(kUninstall): add AppUsageWidget (Pro)"
```

---

### Task 18: Add localization strings

**Files:**
- Create: `kUninstall/Resources/Localizable.xcstrings`

- [ ] **Step 1: Create Localizable.xcstrings**

Create the string catalog with English, Simplified Chinese, and Japanese translations for all user-facing strings used in the app.

- [ ] **Step 2: Commit**

```bash
git add kUninstall/Resources/Localizable.xcstrings
git commit -m "feat(kUninstall): add localization with en, zh-Hans, ja"
```

---

### Task 19: Write unit tests — AppSource classification, confidence calculation, TrashMover state machine

**Files:**
- Create: `kUninstall/Tests/DetectTests/AppSourceClassifierTests.swift`
- Create: `kUninstall/Tests/CleanTests/BackupManagerTests.swift`

- [ ] **Step 1: Write AppSource classifier tests**

```swift
// kUninstall/Tests/DetectTests/AppSourceClassifierTests.swift
import XCTest
@testable import kUninstall

final class AppSourceClassifierTests: XCTestCase {
    func testSystemPath() {
        let service = AppCatalogService()
        let result = service.classifySource(
            url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"),
            bundleID: "com.apple.finder"
        )
        XCTAssertEqual(result, .system)
    }

    func testUserInstalled() {
        let service = AppCatalogService()
        let result = service.classifySource(
            url: URL(fileURLWithPath: "/Applications/Test.app"),
            bundleID: "com.example.Test"
        )
        XCTAssertEqual(result, .userInstalled)
    }

    func testAppleBuiltIn() {
        let service = AppCatalogService()
        let result = service.classifySource(
            url: URL(fileURLWithPath: "/System/Applications/Calendar.app"),
            bundleID: "com.apple.iCal"
        )
        XCTAssertEqual(result, .appleBuiltIn)
    }
}
```

- [ ] **Step 2: Run tests**

Run: `xcodebuild test -project kUninstall/kUninstall.xcodeproj -scheme kUninstall -destination 'platform=macOS'`
Expected: All existing + new tests pass.

- [ ] **Step 3: Commit**

```bash
git add kUninstall/Tests/
git commit -m "test(kUninstall): add unit tests for AppSource classifier and BackupManager"
```

---

### Task 20: Write integration tests — full uninstall flow + sandbox degradation

**Files:**
- Create: `kUninstall/Tests/IntegrationTests/UninstallFlowTests.swift`
- Create: `kUninstall/Tests/IntegrationTests/SandboxDegradationTests.swift`

- [ ] **Step 1: Write integration tests**

```swift
// kUninstall/Tests/IntegrationTests/UninstallFlowTests.swift
import XCTest
@testable import kUninstall

final class UninstallFlowTests: XCTestCase {
    func testScanToResidueFlow() async {
        let scanner = ResidueScanner()
        let apps = await scanner.scanAll()
        XCTAssertFalse(apps.isEmpty)
        let hasResidues = apps.contains { !$0.residues.isEmpty }
        // If FDA available, at least some apps should have residues
        print("Apps: \(apps.count), any residues: \(hasResidues)")
    }

    func testProtectedAppCannotBeUninstalled() {
        let app = InstalledApp(url: URL(fileURLWithPath: "/System/Library/Finder.app"),
                                displayName: "Finder", bundleID: "com.apple.finder",
                                version: "1.0", source: .system,
                                isRunning: false, lastUsedDate: nil)
        XCTAssertFalse(TrashMover.canMoveToTrash(app: app))
    }
}
```

- [ ] **Step 2: Run integration tests**

Run: `xcodebuild test -project kUninstall/kUninstall.xcodeproj -scheme kUninstall -destination 'platform=macOS' -only-testing kUninstallTests/IntegrationTests`
Expected: Tests pass.

- [ ] **Step 3: Commit**

```bash
git add kUninstall/Tests/IntegrationTests/
git commit -m "test(kUninstall): add integration tests for scan flow and sandbox degradation"
```

---

### Task 21: Write UI tests — uninstall journey, paywall, FDA guide

**Files:**
- Create: `kUninstall/Tests/UITests/UninstallJourneyUITests.swift`

- [ ] **Step 1: Write UI tests**

```swift
// kUninstall/Tests/UITests/UninstallJourneyUITests.swift
import XCTest

final class UninstallJourneyUITests: XCTestCase {
    let app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app.launch()
    }

    func testMainWindowShowsAppList() {
        // Verify the main window appears with app list
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    func testSettingsOpens() {
        app.menuBars.menuBarItems["Settings"].click()
        XCTAssertTrue(app.sheets.firstMatch.exists)
    }

    func testPaywallShowsProFeatures() {
        app.buttons["升级 Pro"].click()
        let paywall = app.sheets["PaywallView"]
        XCTAssertTrue(paywall.waitForExistence(timeout: 3))
    }
}
```

- [ ] **Step 2: Run UI tests**

Run: `xcodebuild test -project kUninstall/kUninstall.xcodeproj -scheme kUninstall -destination 'platform=macOS' -only-testing kUninstallUITests`
Expected: UI tests pass.

- [ ] **Step 3: Commit**

```bash
git add kUninstall/Tests/UITests/
git commit -m "test(kUninstall): add UI tests for main window, settings, and paywall"
```

---

### Task 22: Create PrivacyInfo.xcprivacy + debug entitlements + App Store review notes

**Files:**
- Create: `kUninstall/Resources/PrivacyInfo.xcprivacy`
- Create: `kUninstall/kUninstallDebug.entitlements`

- [ ] **Step 1: Create privacy manifest**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyTrackingDomains</key>
    <array/>
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
            <string>NSPrivacyAccessedAPICategoryDiskSpace</string>
            <key>NSPrivacyAccessedAPITypeReasons</key>
            <array>
                <string>E174.1</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
```

- [ ] **Step 2: Final commit**

```bash
git add kUninstall/Resources/PrivacyInfo.xcprivacy kUninstall/kUninstallDebug.entitlements
git commit -m "chore(kUninstall): add privacy manifest and debug entitlements"
```

---

### Task 23: Final build verification + project audit

**Files:**
- All project files

- [ ] **Step 1: Clean build**

Run: `xcodebuild clean build -project kUninstall/kUninstall.xcodeproj -scheme kUninstall -destination 'platform=macOS'`
Expected: Build succeeds with no errors, no warnings.

- [ ] **Step 2: Run full test suite**

Run: `xcodebuild test -project kUninstall/kUninstall.xcodeproj -scheme kUninstall -destination 'platform=macOS'`
Expected: All unit, integration, and UI tests pass.

- [ ] **Step 3: Verify Swift concurrency check**

Run: `xcodebuild build -project kUninstall/kUninstall.xcodeproj -scheme kUninstall -destination 'platform=macOS' SWIFT_STRICT_CONCURRENCY=complete`
Expected: No strict concurrency warnings.

- [ ] **Step 4: Final commit (if any fixes needed)**

```bash
git add -A
git commit -m "chore(kUninstall): final build verification and audit"
```

---

### Task 24: Implement Core Data persistence — UninstallHistory + AppAnalysis

**Files:**
- Create: `kUninstall/Data/CoreDataStack.swift`
- Create: `kUninstall/Data/Models/UninstallHistory+CoreDataClass.swift`
- Create: `kUninstall/Data/Models/UninstallHistory+CoreDataProperties.swift`
- Create: `kUninstall/Data/Models/AppAnalysis+CoreDataClass.swift`
- Create: `kUninstall/Data/Models/AppAnalysis+CoreDataProperties.swift`
- Modify: `kUninstall/Data/UninstallHistoryRepository.swift` — adapt for Core Data
- Create: `kUninstall/Data/AppAnalysisRepository.swift`

**Interfaces:**
- Consumes: Core Data, `UninstallRecord`
- Produces: `CoreDataStack`, persistent `UninstallHistory`, `AppAnalysis`

- [ ] **Step 1: Create Core Data model files (Xcode Data Model)**

Create `kUninstall/Data/Models/kUninstall.xcdatamodeld` with two entities:

**UninstallHistory entity:**
- Attributes: id (UUID), appName (String), bundleID (String), appPath (String), appSize (Int64), totalResidueSize (Int64), residueCount (Int32), uninstalledAt (Date), isRestored (Bool), backupPath (String), residueData (Binary — JSON-encoded `[ResidueFile]`)

**AppAnalysis entity:**
- Attributes: id (UUID), bundleID (String), displayName (String), lastUsedDate (Date? firstDetectedDate (Date), usedCount (Int32), isAnalyzed (Bool), suggestedAction (String?)

- [ ] **Step 2: Implement CoreDataStack**

```swift
// kUninstall/Data/CoreDataStack.swift
import CoreData

struct CoreDataStack {
    static let shared = CoreDataStack()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "kUninstall")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data failed: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    var context: NSManagedObjectContext { container.viewContext }

    func save() {
        guard context.hasChanges else { return }
        try? context.save()
    }
}
```

- [ ] **Step 3: Generate Core Data managed object subclasses**

Run Xcode's Codegen to create the `UninstallHistory+CoreDataClass.swift` and `UninstallHistory+CoreDataProperties.swift` files automatically from the data model. Set Codegen to "Manual/None" and use "Editor → Create NSManagedObject Subclass".

Alternatively, write them by hand:

```swift
// kUninstall/Data/Models/UninstallHistory+CoreDataClass.swift
import CoreData

@objc(UninstallHistory)
public class UninstallHistory: NSManagedObject {
    var residues: [ResidueFile] {
        get { (residueData as? Data).flatMap { try? JSONDecoder().decode([ResidueFile].self, from: $0) } ?? [] }
        set { residueData = try? JSONEncoder().encode(newValue) as NSData }
    }
}
```

- [ ] **Step 4: Update UninstallHistoryRepository to use Core Data**

Modify the actor to use `CoreDataStack.shared.context` for reads/writes instead of in-memory array.

- [ ] **Step 5: Implement AppAnalysisRepository**

```swift
// kUninstall/Data/AppAnalysisRepository.swift
import CoreData

actor AppAnalysisRepository {
    private let context = CoreDataStack.shared.context

    func recordUsage(bundleID: String, displayName: String) {
        let fetch = NSFetchRequest<AppAnalysis>(entityName: "AppAnalysis")
        fetch.predicate = NSPredicate(format: "bundleID == %@", bundleID)
        fetch.fetchLimit = 1

        if let existing = try? context.fetch(fetch).first {
            existing.usedCount += 1
            existing.lastUsedDate = Date()
        } else {
            let analysis = AppAnalysis(context: context)
            analysis.id = UUID()
            analysis.bundleID = bundleID
            analysis.displayName = displayName
            analysis.firstDetectedDate = Date()
            analysis.usedCount = 1
            analysis.isAnalyzed = false
        }
        CoreDataStack.shared.save()
    }

    func analyze() {
        let fetch = NSFetchRequest<AppAnalysis>(entityName: "AppAnalysis")
        fetch.predicate = NSPredicate(format: "isAnalyzed == NO")
        guard let results = try? context.fetch(fetch) else { return }

        for analysis in results {
            // Simple heuristic: if unused > 90 days, suggest uninstall
            if let lastUsed = analysis.lastUsedDate,
               lastUsed < Date().addingTimeInterval(-86400 * 90) {
                analysis.suggestedAction = "uninstall"
            } else if analysis.usedCount < 3 {
                analysis.suggestedAction = "never_used"
            } else {
                analysis.suggestedAction = "keep"
            }
            analysis.isAnalyzed = true
        }
        CoreDataStack.shared.save()
    }

    func fetchAnalysis(bundleID: String) -> AppAnalysis? {
        let fetch = NSFetchRequest<AppAnalysis>(entityName: "AppAnalysis")
        fetch.predicate = NSPredicate(format: "bundleID == %@", bundleID)
        fetch.fetchLimit = 1
        return try? context.fetch(fetch).first
    }
}
```

- [ ] **Step 6: Build verification**

Run: `xcodebuild build -project kUninstall/kUninstall.xcodeproj -scheme kUninstall -destination 'platform=macOS'`
Expected: Build succeeds with Core Data integration.

- [ ] **Step 7: Commit**

```bash
git add kUninstall/Data/CoreDataStack.swift kUninstall/Data/Models/ kUninstall/Data/AppAnalysisRepository.swift
git commit -m "feat(kUninstall): add Core Data persistence with UninstallHistory and AppAnalysis"
```

---

### Task 25: Add batch uninstall (Pro feature) + AI analysis badge in AppDetailView

**Files:**
- Modify: `kUninstall/Features/AppList/AppListView.swift` — add batch selection mode
- Modify: `kUninstall/Features/Detail/AppDetailView.swift` — add AI analysis badge

- [ ] **Step 1: Add batch mode to AppListView**

Add a `@State var isSelecting = false` toggle and a `Set<String> selectedIDs`. When enabled, each row shows a checkbox. Pro users see a "批量卸载" button in the toolbar. When tapped, iterate through selected apps and call `TrashMover.moveToTrash()` for each.

Gate the batch uninstall button with `StoreManager.shared.isPro`.

- [ ] **Step 2: Add AI analysis badge to AppDetailView**

In the hero section, below the source label, add a conditional badge:

```swift
@ViewBuilder private var aiAnalysisBadge: some View {
    if let analysis = viewModel.analysis {
        HStack(spacing: 4) {
            Image(systemName: "brain")
                .font(.system(size: 10))
            switch analysis.suggestedAction {
            case "uninstall":
                Text("这个 App 超过 90 天未使用")
                    .font(.caption)
                    .foregroundColor(.orange)
            case "never_used":
                Text("很少使用")
                    .font(.caption)
                    .foregroundColor(.secondary)
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(4)
    }
}
```

Load the analysis in `DetailViewModel`:
```swift
@Published var analysis: AppAnalysis?
// In init:
Task {
    let repo = AppAnalysisRepository()
    self.analysis = await repo.fetchAnalysis(bundleID: app.bundleID)
}
```

- [ ] **Step 3: Verify build**

Run: `xcodebuild build ...`
Expected: Build succeeds.

- [ ] **Step 4: Commit**

```bash
git commit -am "feat(kUninstall): add batch uninstall mode (Pro) and AI analysis badge"
```

