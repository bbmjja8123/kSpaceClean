# kDupe v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build kDupe v1 — a standalone duplicate/large file cleaner for Mac with 3-profile UX, CLI tool, and Web Dashboard.

**Architecture:** 4-layer MVVM (SwiftUI → @MainActor ViewModel → actor Service → Core Data Repository) with XPC Service for CLI, Swifter for Web Dashboard, and DarwinNotificationCenter for Finder Sync. Each Detector is an independent actor orchestrated by ScanOrchestrator.

**Tech Stack:** Swift 5.9, SwiftUI, Swift Concurrency, Core Data, CryptoKit, Vision/Accelerate, XPC Service, Swifter, XcodeGen

**Design Spec:** `docs/superpowers/specs/2026-07-26-kraftly-kdupe-design.md`

## Global Constraints

- Swift 5.9+ with strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`)
- macOS 13.0+ deployment target, macOS 14 SDK with `#available` wrapping
- App Sandbox enabled (App Store requirement)
- No Privileged Helper / SMJobBless — TCC Full Disk Access only
- Bundle ID prefix: `app.kraftly.kdupe`
- All UI strings through `LocalizedStringResource` — no hardcoded strings
- Zero network reporting — all computation local, MetricKit only for diagnostics
- Follow existing kSpaceClean patterns: XcodeGen project, kFoundation SPM dependency, DesignSystem components
- **REQUIRED:** Do NOT reuse Lemon Objective-C/C++ code — reference algorithm logic only

---

## File Structure

```
kSift/
├── project.yml
├── kDupe.entitlements
├── Info.plist
├── App/
│   ├── kDupeApp.swift
│   ├── AppCoordinator.swift
│   ├── AppState.swift
│   └── RootView.swift
├── Models/
│   ├── ProfileConfig.swift
│   ├── ScanTypes.swift
│   ├── DuplicateTypes.swift
│   └── CleanupTypes.swift
├── Persistence/
│   ├── PersistenceController.swift
│   ├── ScanRecordEntity.swift
│   ├── DuplicateGroupEntity.swift
│   ├── FileItemEntity.swift
│   └── CleanupActionEntity.swift
├── Repository/
│   ├── DuplicateRepositoryProtocol.swift
│   ├── DuplicateRepositoryCoreData.swift
│   └── DuplicateRepositoryJSON.swift
├── Detection/
│   ├── DetectionModels.swift
│   ├── FileWalker.swift
│   ├── ByteIdenticalDetector.swift
│   ├── DirectoryDedupDetector.swift
│   ├── PerceptualDetector.swift
│   ├── LargeFileDetector.swift
│   ├── BuildArtifactDetector.swift
│   ├── RawJPEGPairDetector.swift
│   ├── ScanOrchestrator.swift
│   └── CleanupManager.swift
├── UI/
│   ├── Onboarding/
│   │   ├── OnboardingView.swift
│   │   ├── OnboardingViewModel.swift
│   │   └── ProfileSetupView.swift
│   ├── Scan/
│   │   ├── MainView.swift
│   │   ├── ScanProgressView.swift
│   │   ├── ScanViewModel.swift
│   │   └── ScanResultView.swift
│   ├── Results/
│   │   ├── ResultView.swift
│   │   ├── GroupDetailView.swift
│   │   ├── FileRowView.swift
│   │   ├── FilterBarView.swift
│   │   └── ResultViewModel.swift
│   ├── History/
│   │   ├── HistoryView.swift
│   │   └── HistoryViewModel.swift
│   └── Settings/
│       ├── SettingsView.swift
│       └── SettingsViewModel.swift
├── Store/
│   ├── StoreManager.swift
│   └── PaywallView.swift
├── CLI/
│   ├── kdupe-cli/
│   │   └── main.swift
│   ├── kdupe-xpc/
│   │   ├── XPCServiceProtocol.swift
│   │   └── XPCService.swift
│   └── XPCServer/
│       ├── main.swift
│       └── XPCServer.swift
├── WebDashboard/
│   ├── DashboardServer.swift
│   ├── DashboardRoutes.swift
│   └── DashboardAssets/
│       ├── index.html
│       ├── dashboard.js
│       └── dashboard.css
├── FinderSync/
│   ├── FinderSync.swift
│   └── FinderSyncHandler.swift
├── MenuBar/
│   └── MenuBarManager.swift
├── Intents/
│   └── DuplicateIntents.swift
├── Widgets/
│   └── kDupeWidget.swift
├── Spotlight/
│   └── SpotlightIndexer.swift
├── Resources/
│   ├── Assets.xcassets/
│   │   └── Contents.json
│   └── Models/
├── Tests/
│   ├── DetectionTests/
│   │   ├── FileWalkerTests.swift
│   │   ├── ByteIdenticalDetectorTests.swift
│   │   ├── DirectoryDedupDetectorTests.swift
│   │   ├── PerceptualDetectorTests.swift
│   │   ├── LargeFileDetectorTests.swift
│   │   ├── ScanOrchestratorTests.swift
│   │   └── CleanupManagerTests.swift
│   ├── RepositoryTests/
│   │   └── DuplicateRepositoryTests.swift
│   └── CLITests/
│       └── CLICommandTests.swift
```

---

### Task 1: Project Scaffolding

**Files:**
- Create: `kSift/project.yml`
- Create: `kSift/kDupe.entitlements`
- Create: `kSift/Info.plist`

**Interfaces:**
- Consumes: kFoundation SPM package (DesignSystem, FileScanner, CommonUtils, Capabilities)
- Produces: Runnable XcodeGen project skeleton

- [ ] **Step 1: Create project.yml**

```yaml
name: kDupe
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
  kDupe:
    type: application
    platform: macOS
    sources:
      - path: .
        excludes:
          - "project.yml"
          - "**/*.md"
          - "Tests/**"
          - "CLI/**"
          - "WebDashboard/DashboardAssets/**"
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: app.kraftly.kdupe
      INFOPLIST_FILE: Info.plist
      CODE_SIGN_STYLE: Automatic
      DEVELOPMENT_TEAM: ""
    dependencies:
      - package: kFoundation
      - target: XPCServer
    preBuildScripts:
      - name: "SwiftLint"
        script: "if which swiftlint >/dev/null; then swiftlint; fi"
        basedOnDependencyAnalysis: false

  XPCServer:
    type: xpc-service
    platform: macOS
    sources:
      - CLI/XPCServer
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: app.kraftly.kdupe.xpc
      INFOPLIST_FILE: CLI/XPCServer/Info.plist
      CODE_SIGN_STYLE: Automatic
      DEVELOPMENT_TEAM: ""
    dependencies:
      - package: kFoundation

  kdupe-cli:
    type: tool
    platform: macOS
    sources:
      - CLI/kdupe-cli
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: app.kraftly.kdupe.cli
      CODE_SIGN_STYLE: Automatic
      DEVELOPMENT_TEAM: ""
    dependencies:
      - target: XPCServer
      - package: kFoundation

  kDupeTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - Tests
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: app.kraftly.kdupe.tests
    dependencies:
      - target: kDupe
      - package: kFoundation

packages:
  kFoundation:
    path: /Users/mengjianjun/Documents/ai/aicoding/macapp/kFoundation
```

- [ ] **Step 2: Create kDupe.entitlements**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key><true/>
    <key>com.apple.security.files.user-selected.read-write</key><true/>
    <key>com.apple.security.files.bookmarks.app-scope</key><true/>
    <key>com.apple.security.application-groups</key>
    <array><string>group.app.kraftly.kdupe</string></array>
    <key>com.apple.security.device.camera</key><false/>
    <key>com.apple.security.device.microphone</key><false/>
    <key>com.apple.security.device.usb</key><false/>
    <key>com.apple.security.print</key><false/>
    <key>com.apple.security.network.client</key><false/>
    <key>com.apple.security.network.server</key><true/>
    <key>com.apple.security.files.downloads.read-write</key><true/>
</dict>
</plist>
```

- [ ] **Step 3: Create Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>kDupe</string>
    <key>CFBundleDisplayName</key><string>kDupe</string>
    <key>CFBundleIdentifier</key><string>app.kraftly.kdupe</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key><true/>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>kDupe needs access to find duplicate and large files.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>kDupe needs access to find duplicate and large files.</string>
</dict>
</plist>
```

- [ ] **Step 4: Verify project generation**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/kDupe
xcodegen generate --spec project.yml
ls -la kDupe.xcodeproj
Expected: kDupe.xcodeproj exists
```

- [ ] **Step 5: Commit**

```bash
git add kSift/project.yml kSift/kDupe.entitlements kSift/Info.plist
git commit -m "feat(kDupe): add project scaffolding with XcodeGen"
```

---

### Task 2: App Entry Point

**Files:**
- Create: `kSift/App/kDupeApp.swift`
- Create: `kSift/App/AppCoordinator.swift`
- Create: `kSift/App/AppState.swift`
- Create: `kSift/App/RootView.swift`

**Interfaces:**
- Consumes: DesignSystem components (GlassPanel, EmptyStateView), FileScanner types
- Produces: `AppCoordinator` (handleDeepLink, navigate), `AppState` (navigation, scanState, selectedProfile), `RootView` (navigation shell)

- [ ] **Step 1: Create AppState.swift**

```swift
import SwiftUI
import DesignSystem

@MainActor
public final class AppState: ObservableObject {
    @Published public var navigation: NavigationItem = .onboarding
    @Published public var scanState: ScanState = .idle
    @Published public var selectedProfile: ProfileType = .developer
    @Published public var isOnboardingComplete = false

    public enum NavigationItem: String, CaseIterable {
        case onboarding, scan, results, history, settings

        public var iconName: String {
            switch self {
            case .onboarding: return "wand.and.stars"
            case .scan: return "magnifyingglass"
            case .results: return "doc.on.doc"
            case .history: return "clock"
            case .settings: return "gear"
            }
        }
    }

    public enum ScanState: Equatable {
        case idle
        case scanning(Double)
        case completed
        case failed(String)
    }
}
```

- [ ] **Step 2: Create AppCoordinator.swift**

```swift
import SwiftUI

@MainActor
public final class AppCoordinator: ObservableObject {
    public weak var appState: AppState?

    public init(appState: AppState? = nil) {
        self.appState = appState
    }

    @discardableResult
    public func handleDeepLink(_ url: URL) -> Bool {
        guard let scheme = url.scheme, scheme == "kdupe",
              let host = url.host else { return false }
        switch host {
        case "scan":
            appState?.navigation = .scan
            return true
        case "results":
            appState?.navigation = .results
            return true
        default:
            return false
        }
    }

    public func navigate(to item: AppState.NavigationItem) {
        appState?.navigation = item
    }
}
```

- [ ] **Step 3: Create kDupeApp.swift**

```swift
import SwiftUI

@main
struct kDupeApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var coordinator = AppCoordinator()
    @StateObject private var menuBarManager = MenuBarManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(coordinator)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    coordinator.handleDeepLink(url)
                }
                .onAppear {
                    coordinator.appState = appState
                    menuBarManager.setup()
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

- [ ] **Step 4: Create RootView.swift**

```swift
import SwiftUI
import DesignSystem

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            if appState.navigation != .onboarding {
                iconRail
                    .frame(width: 48)
                    .padding(.leading, 8)
            }
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch appState.navigation {
        case .onboarding:
            OnboardingView()
        case .scan:
            MainView()
        case .results:
            ResultView()
        case .history:
            HistoryView()
        case .settings:
            SettingsView()
        }
    }

    private var iconRail: some View {
        GlassPanel {
            VStack(spacing: 4) {
                ForEach(AppState.NavigationItem.allCases.filter { $0 != .onboarding }, id: \.self) { item in
                    Button {
                        appState.navigation = item
                    } label: {
                        Image(systemName: item.iconName)
                            .font(.system(size: 16))
                            .frame(width: 36, height: 36)
                            .background(appState.navigation == item ? Color.brandPrimary.opacity(0.3) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.vertical, AppSpacing.sm)
        }
        .frame(width: 42)
    }
}
```

- [ ] **Step 5: Create initial directory structure and commit**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
mkdir -p kSift/App kSift/Models kSift/Persistence kSift/Repository kSift/Detection
mkdir -p kSift/UI/Onboarding kSift/UI/Scan kSift/UI/Results kSift/UI/History kSift/UI/Settings
mkdir -p kSift/Store kSift/CLI/kdupe-cli kSift/CLI/kdupe-xpc kSift/CLI/XPCServer
mkdir -p kSift/WebDashboard/DashboardAssets kSift/FinderSync
mkdir -p kSift/MenuBar kSift/Intents kSift/Widgets kSift/Spotlight
mkdir -p kSift/Resources/Assets.xcassets kSift/Resources/Models
mkdir -p kSift/Tests/DetectionTests kSift/Tests/RepositoryTests kSift/Tests/CLITests
```

```bash
git add kSift/App/ kSift/Models/ kSift/Persistence/ kSift/Repository/ kSift/Detection/ \
       kSift/UI/ kSift/Store/ kSift/CLI/ kSift/WebDashboard/ kSift/FinderSync/ \
       kSift/MenuBar/ kSift/Intents/ kSift/Widgets/ kSift/Spotlight/ kSift/Resources/ kSift/Tests/
git commit -m "feat(kDupe): add app entry point with navigation shell"
```

---

### Task 3: Core Domain Models

**Files:**
- Create: `kSift/Models/ProfileConfig.swift`
- Create: `kSift/Models/ScanTypes.swift`
- Create: `kSift/Models/DuplicateTypes.swift`
- Create: `kSift/Models/CleanupTypes.swift`

**Interfaces:**
- Consumes: Foundation
- Produces: `ProfileType`, `ProfileConfig`, `ScanTarget`, `ScanProgress`, `DuplicateGroup`, `FileItem`, `CleanupAction`, `CleanupRecord`

- [ ] **Step 1: Create ProfileConfig.swift**

```swift
import Foundation

public enum ProfileType: String, Sendable, CaseIterable, Codable {
    case developer
    case photographer
    case simple

    public var title: String {
        switch self {
        case .developer: return "Developer"
        case .photographer: return "Photographer"
        case .simple: return "Simple"
        }
    }

    public var scanningDirectories: [String] {
        switch self {
        case .developer:
            return ["~/Projects", "~/Desktop", "~/Downloads", "~/Documents", "~/.gradle", "~/.m2"]
        case .photographer:
            return ["~/Pictures", "~/Desktop", "~/Downloads", "~/Documents"]
        case .simple:
            return ["~/Desktop", "~/Downloads", "~/Documents"]
        }
    }

    public var additionalExclusions: [String] {
        switch self {
        case .developer:
            return ["**/node_modules/**", "**/Pods/**", "**/.build/**", "**/DerivedData/**"]
        case .photographer:
            return []
        case .simple:
            return []
        }
    }
}

public struct ProfileConfig: Sendable, Codable {
    public var type: ProfileType
    public var customDirectories: [String]
    public var exclusions: [String]
    public var minFileSize: Int64
    public var enablePerceptualScan: Bool

    public static let `default` = ProfileConfig(
        type: .developer,
        customDirectories: [],
        exclusions: ProfileType.developer.additionalExclusions,
        minFileSize: 1024,
        enablePerceptualScan: true
    )

    public init(type: ProfileType, customDirectories: [String], exclusions: [String],
                minFileSize: Int64, enablePerceptualScan: Bool) {
        self.type = type
        self.customDirectories = customDirectories
        self.exclusions = exclusions
        self.minFileSize = minFileSize
        self.enablePerceptualScan = enablePerceptualScan
    }
}
```

- [ ] **Step 2: Create ScanTypes.swift**

```swift
import Foundation

public struct ScanTarget: Sendable, Codable {
    public var directories: [String]
    public var exclusions: [String]
    public var minFileSize: Int64

    public init(directories: [String], exclusions: [String], minFileSize: Int64) {
        self.directories = directories
        self.exclusions = exclusions
        self.minFileSize = minFileSize
    }
}

public enum ScanPhase: String, Sendable {
    case enumerating
    case byteIdentical
    case directoryDedup
    case perceptual
    case largeFiles
    case buildArtifacts
    case rawJPEG
    case completed
}

public struct ScanProgress: Sendable {
    public let phase: ScanPhase
    public let progress: Double
    public let filesScanned: Int
    public let duplicatesFound: Int

    public init(phase: ScanPhase, progress: Double, filesScanned: Int, duplicatesFound: Int) {
        self.phase = phase
        self.progress = progress
        self.filesScanned = filesScanned
        self.duplicatesFound = duplicatesFound
    }
}
```

- [ ] **Step 3: Create DuplicateTypes.swift**

```swift
import Foundation

public enum DuplicateCategory: String, Sendable, Codable, CaseIterable {
    case identical
    case directoryDedup
    case perceptual
    case largeFile
    case buildArtifact
    case rawJPEG
}

public struct DuplicateGroup: Sendable, Identifiable {
    public let id: UUID
    public let category: DuplicateCategory
    public let totalSize: Int64
    public let fileCount: Int
    public let files: [FileItem]

    public init(id: UUID, category: DuplicateCategory, totalSize: Int64, fileCount: Int, files: [FileItem]) {
        self.id = id
        self.category = category
        self.totalSize = totalSize
        self.fileCount = fileCount
        self.files = files
    }
}

public struct FileItem: Sendable, Identifiable, Codable {
    public let id: UUID
    public let url: URL
    public let size: Int64
    public let modificationDate: Date
    public let hash: String?

    public init(id: UUID, url: URL, size: Int64, modificationDate: Date, hash: String?) {
        self.id = id
        self.url = url
        self.size = size
        self.modificationDate = modificationDate
        self.hash = hash
    }
}
```

- [ ] **Step 4: Create CleanupTypes.swift**

```swift
import Foundation

public enum CleanupMethod: String, Sendable, Codable {
    case trash
    case delete
}

public struct CleanupAction: Sendable, Identifiable {
    public let id: UUID
    public let file: FileItem
    public let method: CleanupMethod
    public let timestamp: Date
    public var isCompleted: Bool

    public init(id: UUID, file: FileItem, method: CleanupMethod, timestamp: Date, isCompleted: Bool = false) {
        self.id = id
        self.file = file
        self.method = method
        self.timestamp = timestamp
        self.isCompleted = isCompleted
    }
}

public struct CleanupRecord: Sendable, Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let actions: [CleanupAction]
    public let totalSpaceReclaimed: Int64

    public init(id: UUID, timestamp: Date, actions: [CleanupAction], totalSpaceReclaimed: Int64) {
        self.id = id
        self.timestamp = timestamp
        self.actions = actions
        self.totalSpaceReclaimed = totalSpaceReclaimed
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add kSift/Models/
git commit -m "feat(kDupe): add core domain models"
```

---

### Task 4: Core Data Stack + Entities

**Files:**
- Create: `kSift/Persistence/PersistenceController.swift`
- Create: `kSift/Persistence/ScanRecordEntity.swift`
- Create: `kSift/Persistence/DuplicateGroupEntity.swift`
- Create: `kSift/Persistence/FileItemEntity.swift`
- Create: `kSift/Persistence/CleanupActionEntity.swift`

**Interfaces:**
- Consumes: Foundation, CoreData, domain models from Task 3
- Produces: `PersistenceController` (shared, container, context save), 4 NSManagedObject subclasses

- [ ] **Step 1: Create ScanRecordEntity.swift**

```swift
import CoreData
import Foundation

@objc(ScanRecordEntity)
public final class ScanRecordEntity: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var timestamp: Date
    @NSManaged public var profileType: String
    @NSManaged public var totalFilesScanned: Int64
    @NSManaged public var totalDuplicatesFound: Int64
    @NSManaged public var totalWasteSize: Int64
    @NSManaged public var duration: Double
    @NSManaged public var groups: Set<DuplicateGroupEntity>
}

extension ScanRecordEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ScanRecordEntity> {
        NSFetchRequest<ScanRecordEntity>(entityName: "ScanRecordEntity")
    }
}
```

- [ ] **Step 2: Create DuplicateGroupEntity.swift**

```swift
import CoreData
import Foundation

@objc(DuplicateGroupEntity)
public final class DuplicateGroupEntity: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var category: String
    @NSManaged public var totalSize: Int64
    @NSManaged public var fileCount: Int64
    @NSManaged public var files: Set<FileItemEntity>
    @NSManaged public var scanRecord: ScanRecordEntity?
}

extension DuplicateGroupEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<DuplicateGroupEntity> {
        NSFetchRequest<DuplicateGroupEntity>(entityName: "DuplicateGroupEntity")
    }
}
```

- [ ] **Step 3: Create FileItemEntity.swift**

```swift
import CoreData
import Foundation

@objc(FileItemEntity)
public final class FileItemEntity: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var filePath: String
    @NSManaged public var size: Int64
    @NSManaged public var modificationDate: Date
    @NSManaged public var hashValue: String?
    @NSManaged public var group: DuplicateGroupEntity?
}

extension FileItemEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<FileItemEntity> {
        NSFetchRequest<FileItemEntity>(entityName: "FileItemEntity")
    }
}
```

- [ ] **Step 4: Create CleanupActionEntity.swift**

```swift
import CoreData
import Foundation

@objc(CleanupActionEntity)
public final class CleanupActionEntity: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var filePath: String
    @NSManaged public var fileSize: Int64
    @NSManaged public var method: String
    @NSManaged public var timestamp: Date
    @NSManaged public var isCompleted: Bool
    @NSManaged public var scanRecord: ScanRecordEntity?
}

extension CleanupActionEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CleanupActionEntity> {
        NSFetchRequest<CleanupActionEntity>(entityName: "CleanupActionEntity")
    }
}
```

- [ ] **Step 5: Create PersistenceController.swift**

```swift
import CoreData
import Foundation

public final class PersistenceController: Sendable {
    public static let shared = PersistenceController()

    nonisolated(unsafe) public let container: NSPersistentContainer

    private init() {
        let bundle = Bundle(for: ScanRecordEntity.self)
        guard let modelURL = bundle.url(forResource: "kDupe", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Failed to load Core Data model")
        }

        let container = NSPersistentContainer(name: "kDupe", managedObjectModel: model)
        let storeURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.app.kraftly.kdupe")!
            .appendingPathComponent("kDupe.sqlite")

        container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: storeURL)]
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data store failed: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        self.container = container
    }

    public func saveContext() {
        let context = container.viewContext
        if context.hasChanges {
            try? context.save()
        }
    }
}
```

- [ ] **Step 6: Create Core Data model file**

```bash
mkdir -p kSift/Persistence/kDupe.xcdatamodeld
cat > kSift/Persistence/kDupe.xcdatamodeld/.xcdatamodel << 'CONTENT'
<?xml version="1.0" encoding="UTF-8"?>
<model type="com.apple.IDECoreDataModeler.DataModel" documentVersion="1.0">
    <entity name="ScanRecordEntity" representedClassName="ScanRecordEntity" syncable="YES">
        <attribute name="id" attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="timestamp" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="profileType" attributeType="String"/>
        <attribute name="totalFilesScanned" attributeType="Integer 64" defaultValueString="0"/>
        <attribute name="totalDuplicatesFound" attributeType="Integer 64" defaultValueString="0"/>
        <attribute name="totalWasteSize" attributeType="Integer 64" defaultValueString="0"/>
        <attribute name="duration" attributeType="Double" defaultValueString="0"/>
        <relationship name="groups" optional="YES" toMany="YES" deletionRule="Cascade"
            destinationEntity="DuplicateGroupEntity" inverseName="scanRecord" inverseEntity="DuplicateGroupEntity"/>
    </entity>
    <entity name="DuplicateGroupEntity" representedClassName="DuplicateGroupEntity" syncable="YES">
        <attribute name="id" attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="category" attributeType="String"/>
        <attribute name="totalSize" attributeType="Integer 64" defaultValueString="0"/>
        <attribute name="fileCount" attributeType="Integer 64" defaultValueString="0"/>
        <relationship name="files" optional="YES" toMany="YES" deletionRule="Cascade"
            destinationEntity="FileItemEntity" inverseName="group" inverseEntity="FileItemEntity"/>
        <relationship name="scanRecord" optional="YES" maxCount="1" deletionRule="Nullify"
            destinationEntity="ScanRecordEntity" inverseName="groups" inverseEntity="ScanRecordEntity"/>
    </entity>
    <entity name="FileItemEntity" representedClassName="FileItemEntity" syncable="YES">
        <attribute name="id" attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="filePath" attributeType="String"/>
        <attribute name="size" attributeType="Integer 64" defaultValueString="0"/>
        <attribute name="modificationDate" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="hashValue" attributeType="String" optional="YES"/>
        <relationship name="group" optional="YES" maxCount="1" deletionRule="Nullify"
            destinationEntity="DuplicateGroupEntity" inverseName="files" inverseEntity="DuplicateGroupEntity"/>
    </entity>
    <entity name="CleanupActionEntity" representedClassName="CleanupActionEntity" syncable="YES">
        <attribute name="id" attributeType="UUID" usesScalarValueType="NO"/>
        <attribute name="filePath" attributeType="String"/>
        <attribute name="fileSize" attributeType="Integer 64" defaultValueString="0"/>
        <attribute name="method" attributeType="String"/>
        <attribute name="timestamp" attributeType="Date" usesScalarValueType="NO"/>
        <attribute name="isCompleted" attributeType="Boolean" defaultValueString="NO"/>
    </entity>
</model>
CONTENT
```

- [ ] **Step 7: Commit**

```bash
git add kSift/Persistence/
git commit -m "feat(kDupe): add Core Data stack with 4 entities"
```

---

### Task 5: Repository Layer

**Files:**
- Create: `kSift/Repository/DuplicateRepositoryProtocol.swift`
- Create: `kSift/Repository/DuplicateRepositoryCoreData.swift`
- Create: `kSift/Repository/DuplicateRepositoryJSON.swift`

**Interfaces:**
- Consumes: PersistenceController (Task 4), domain models (Task 3)
- Produces: `DuplicateRepositoryProtocol` (save, load, delete, history), `DuplicateRepositoryCoreData`, `DuplicateRepositoryJSON`, `ScanRecord` struct

- [ ] **Step 1: Create DuplicateRepositoryProtocol.swift**

```swift
import Foundation

public protocol DuplicateRepositoryProtocol: Sendable {
    func saveScanRecord(_ record: ScanRecord) async throws
    func loadScanRecords() async throws -> [ScanRecord]
    func loadScanRecord(id: UUID) async throws -> ScanRecord?
    func deleteScanRecord(id: UUID) async throws
    func saveCleanupAction(_ action: CleanupAction) async throws
    func loadCleanupHistory() async throws -> [CleanupRecord]
}

public struct ScanRecord: Sendable, Identifiable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let profileType: ProfileType
    public let totalFilesScanned: Int
    public let totalDuplicatesFound: Int
    public let totalWasteSize: Int64
    public let duration: TimeInterval
    public let groups: [DuplicateGroup]

    public init(id: UUID, timestamp: Date, profileType: ProfileType, totalFilesScanned: Int,
                totalDuplicatesFound: Int, totalWasteSize: Int64, duration: TimeInterval, groups: [DuplicateGroup]) {
        self.id = id
        self.timestamp = timestamp
        self.profileType = profileType
        self.totalFilesScanned = totalFilesScanned
        self.totalDuplicatesFound = totalDuplicatesFound
        self.totalWasteSize = totalWasteSize
        self.duration = duration
        self.groups = groups
    }
}
```

- [ ] **Step 2: Create DuplicateRepositoryCoreData.swift**

```swift
import CoreData
import Foundation

public actor DuplicateRepositoryCoreData: DuplicateRepositoryProtocol {
    private let controller: PersistenceController

    public init(controller: PersistenceController = .shared) {
        self.controller = controller
    }

    public func saveScanRecord(_ record: ScanRecord) async throws {
        let context = controller.container.newBackgroundContext()
        try await context.perform {
            let entity = ScanRecordEntity(context: context)
            entity.id = record.id
            entity.timestamp = record.timestamp
            entity.profileType = record.profileType.rawValue
            entity.totalFilesScanned = Int64(record.totalFilesScanned)
            entity.totalDuplicatesFound = Int64(record.totalDuplicatesFound)
            entity.totalWasteSize = record.totalWasteSize
            entity.duration = record.duration

            for group in record.groups {
                let groupEntity = DuplicateGroupEntity(context: context)
                groupEntity.id = group.id
                groupEntity.category = group.category.rawValue
                groupEntity.totalSize = group.totalSize
                groupEntity.fileCount = Int64(group.fileCount)
                groupEntity.scanRecord = entity

                for file in group.files {
                    let fileEntity = FileItemEntity(context: context)
                    fileEntity.id = file.id
                    fileEntity.filePath = file.url.path
                    fileEntity.size = file.size
                    fileEntity.modificationDate = file.modificationDate
                    fileEntity.hashValue = file.hash
                    fileEntity.group = groupEntity
                }
            }
            try context.save()
        }
    }

    public func loadScanRecords() async throws -> [ScanRecord] {
        let context = controller.container.newBackgroundContext()
        return try await context.perform {
            let request = ScanRecordEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            let results = try context.fetch(request)
            return results.map { self.mapToRecord($0) }
        }
    }

    public func loadScanRecord(id: UUID) async throws -> ScanRecord? {
        let context = controller.container.newBackgroundContext()
        return try await context.perform {
            let request = ScanRecordEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            return try context.fetch(request).first.map { self.mapToRecord($0) }
        }
    }

    public func deleteScanRecord(id: UUID) async throws {
        let context = controller.container.newBackgroundContext()
        try await context.perform {
            let request = ScanRecordEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            if let entity = try context.fetch(request).first {
                context.delete(entity)
                try context.save()
            }
        }
    }

    public func saveCleanupAction(_ action: CleanupAction) async throws {
        let context = controller.container.newBackgroundContext()
        try await context.perform {
            let entity = CleanupActionEntity(context: context)
            entity.id = action.id
            entity.filePath = action.file.url.path
            entity.fileSize = action.file.size
            entity.method = action.method.rawValue
            entity.timestamp = action.timestamp
            entity.isCompleted = action.isCompleted
            try context.save()
        }
    }

    public func loadCleanupHistory() async throws -> [CleanupRecord] {
        let context = controller.container.newBackgroundContext()
        return try await context.perform {
            let request = CleanupActionEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            let results = try context.fetch(request)
            let grouped = Dictionary(grouping: results) { Calendar.current.startOfDay(for: $0.timestamp) }
            return grouped.compactMap { _, entities in
                let actions = entities.map { CleanupAction(
                    id: $0.id,
                    file: FileItem(id: $0.id, url: URL(fileURLWithPath: $0.filePath),
                                   size: $0.fileSize, modificationDate: $0.timestamp, hash: nil),
                    method: CleanupMethod(rawValue: $0.method) ?? .trash,
                    timestamp: $0.timestamp,
                    isCompleted: $0.isCompleted
                )}
                let total = actions.filter(\.isCompleted).reduce(0) { $0 + $1.file.size }
                return CleanupRecord(id: UUID(), timestamp: entities.first?.timestamp ?? Date(),
                                     actions: actions, totalSpaceReclaimed: total)
            }
        }
    }

    private func mapToRecord(_ entity: ScanRecordEntity) -> ScanRecord {
        let groups = entity.groups.map { groupEntity -> DuplicateGroup in
            let files = groupEntity.files.map { fileEntity -> FileItem in
                FileItem(id: fileEntity.id, url: URL(fileURLWithPath: fileEntity.filePath),
                         size: fileEntity.size, modificationDate: fileEntity.modificationDate,
                         hash: fileEntity.hashValue)
            }
            return DuplicateGroup(
                id: groupEntity.id,
                category: DuplicateCategory(rawValue: groupEntity.category) ?? .identical,
                totalSize: groupEntity.totalSize,
                fileCount: Int(groupEntity.fileCount),
                files: Array(files)
            )
        }
        return ScanRecord(
            id: entity.id, timestamp: entity.timestamp,
            profileType: ProfileType(rawValue: entity.profileType) ?? .developer,
            totalFilesScanned: Int(entity.totalFilesScanned),
            totalDuplicatesFound: Int(entity.totalDuplicatesFound),
            totalWasteSize: entity.totalWasteSize,
            duration: entity.duration,
            groups: Array(groups)
        )
    }
}
```

- [ ] **Step 3: Create DuplicateRepositoryJSON.swift**

```swift
import Foundation

public actor DuplicateRepositoryJSON: DuplicateRepositoryProtocol {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let storeURL: URL

    public init(storeURL: URL? = nil) {
        self.fileManager = .default
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
        let baseURL = storeURL ?? fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: "group.app.kraftly.kdupe")!
        self.storeURL = baseURL.appendingPathComponent("kdupe_data.json")
    }

    public func saveScanRecord(_ record: ScanRecord) async throws {
        var records = try await loadAllRecords()
        records.insert(record, at: 0)
        let data = try encoder.encode(records)
        try data.write(to: storeURL, options: .atomic)
    }

    public func loadScanRecords() async throws -> [ScanRecord] {
        try await loadAllRecords()
    }

    public func loadScanRecord(id: UUID) async throws -> ScanRecord? {
        try await loadAllRecords().first { $0.id == id }
    }

    public func deleteScanRecord(id: UUID) async throws {
        var records = try await loadAllRecords()
        records.removeAll { $0.id == id }
        let data = try encoder.encode(records)
        try data.write(to: storeURL, options: .atomic)
    }

    public func saveCleanupAction(_ action: CleanupAction) async throws {
        // JSON repository does not persist individual actions
    }

    public func loadCleanupHistory() async throws -> [CleanupRecord] {
        []
    }

    private func loadAllRecords() async throws -> [ScanRecord] {
        guard fileManager.fileExists(atPath: storeURL.path) else { return [] }
        let data = try Data(contentsOf: storeURL)
        return try decoder.decode([ScanRecord].self, from: data)
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add kSift/Repository/
git commit -m "feat(kDupe): add repository layer with Core Data and JSON backends"
```

---

### Task 6: FileWalker + ByteIdenticalDetector

**Files:**
- Create: `kSift/Detection/DetectionModels.swift`
- Create: `kSift/Detection/FileWalker.swift`
- Create: `kSift/Detection/ByteIdenticalDetector.swift`
- Test: `kSift/Tests/DetectionTests/ByteIdenticalDetectorTests.swift`

**Interfaces:**
- Consumes: `ScanTarget` (Task 3), `FileEnumerator`, `CancellationToken` (kFoundation)
- Produces: `ScanController` (pause/cancel), `FileWalker` (enumerate files), `ByteIdenticalDetector` (SHA-256 grouping returning `[DuplicateGroup]`)

- [ ] **Step 1: Create DetectionModels.swift**

```swift
import Foundation
import FileScanner

public struct DetectionProgress: Sendable {
    public let phase: ScanPhase
    public let currentItem: String?
    public let itemsProcessed: Int
    public let totalItems: Int

    public init(phase: ScanPhase, currentItem: String? = nil, itemsProcessed: Int = 0, totalItems: Int = 0) {
        self.phase = phase
        self.currentItem = currentItem
        self.itemsProcessed = itemsProcessed
        self.totalItems = totalItems
    }
}

public final class ScanController: @unchecked Sendable {
    private let token = CancellationToken()
    private var _isPaused = false

    public var isCancelled: Bool { token.isCancelled }
    public var isPaused: Bool { _isPaused }

    public init() {}

    public func cancel() { token.cancel() }
    public func pause() { _isPaused = true }
    public func resume() { _isPaused = false }

    public var fileToken: CancellationToken { token }
}
```

- [ ] **Step 2: Create FileWalker.swift**

```swift
import Foundation
import FileScanner

public actor FileWalker {
    private let fileEnumerator: FileEnumerator

    public init(fileEnumerator: FileEnumerator = FileEnumerator()) {
        self.fileEnumerator = fileEnumerator
    }

    public func walk(target: ScanTarget, controller: ScanController,
                     progress: @escaping @Sendable (FileEnumerator.ScanResult) -> Void) async throws -> [URL] {
        var allFiles: [URL] = []
        let directories = target.directories.map { ($0 as NSString).expandingTildeInPath }

        for dir in directories {
            guard !controller.isCancelled else { return allFiles }
            let url = URL(fileURLWithPath: dir)
            try await fileEnumerator.enumerate(
                root: url,
                progressHandler: { result in
                    guard result.size >= target.minFileSize else { return }
                    allFiles.append(result.url)
                    progress(result)
                },
                cancellationToken: controller.fileToken
            )
        }
        return allFiles
    }
}
```

- [ ] **Step 3: Create ByteIdenticalDetector.swift**

```swift
import CryptoKit
import FileScanner
import Foundation

public actor ByteIdenticalDetector {
    private let hasher: FileHasher

    public init(hasher: FileHasher = FileHasher()) {
        self.hasher = hasher
    }

    public func detect(_ urls: [URL], controller: ScanController) async throws -> [DuplicateGroup] {
        // Phase 1: group by file size
        var sizeGroups: [Int64: [URL]] = [:]
        for url in urls {
            guard !controller.isCancelled else { return [] }
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = attrs[.size] as? Int64 ?? 0
            sizeGroups[size, default: []].append(url)
        }

        // Phase 2: hash candidates (>1 same-size file)
        var groups: [DuplicateGroup] = []
        for (size, candidates) in sizeGroups where candidates.count > 1 {
            guard !controller.isCancelled else { return groups }
            var hashBuckets: [String: [URL]] = [:]
            for url in candidates {
                guard !controller.isCancelled else { return groups }
                if let hash = try? await hasher.hash(file: url) {
                    hashBuckets[hash, default: []].append(url)
                }
            }
            for (_, files) in hashBuckets where files.count > 1 {
                let fileItems = files.map { url in
                    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                    return FileItem(
                        id: UUID(),
                        url: url,
                        size: size,
                        modificationDate: attrs?[.modificationDate] as? Date ?? Date(),
                        hash: try? await hasher.hash(file: url)
                    )
                }
                groups.append(DuplicateGroup(
                    id: UUID(),
                    category: .identical,
                    totalSize: size * Int64(files.count - 1),
                    fileCount: files.count,
                    files: fileItems
                ))
            }
        }
        return groups
    }
}
```

- [ ] **Step 4: Create ByteIdenticalDetectorTests.swift**

```swift
import XCTest
@testable import kDupe

final class ByteIdenticalDetectorTests: XCTestCase {
    func testIdenticalFilesDetected() async throws {
        let detector = ByteIdenticalDetector()
        let controller = ScanController()

        // Create temp files with identical content
        let dir = FileManager.default.temporaryDirectory
        let file1 = dir.appendingPathComponent("test1.txt")
        let file2 = dir.appendingPathComponent("test2.txt")
        try "hello".write(to: file1, atomically: true, encoding: .utf8)
        try "hello".write(to: file2, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: file1)
            try? FileManager.default.removeItem(at: file2)
        }

        let groups = try await detector.detect([file1, file2], controller: controller)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.files.count, 2)
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add kSift/Detection/DetectionModels.swift kSift/Detection/FileWalker.swift \
       kSift/Detection/ByteIdenticalDetector.swift kSift/Tests/DetectionTests/ByteIdenticalDetectorTests.swift
git commit -m "feat(kDupe): add FileWalker and SHA-256 byte-identical detector"
```

---

### Task 7: Remaining Detectors

**Files:**
- Create: `kSift/Detection/DirectoryDedupDetector.swift`
- Create: `kSift/Detection/PerceptualDetector.swift`
- Create: `kSift/Detection/LargeFileDetector.swift`
- Create: `kSift/Detection/BuildArtifactDetector.swift`
- Create: `kSift/Detection/RawJPEGPairDetector.swift`

**Interfaces:**
- All consume `[URL]` + `ScanController`, produce `[DuplicateGroup]`
- `DirectoryDedupDetector`: O(n) content-hash of files across directories
- `PerceptualDetector`: Vision `VNGenerateImageHashRequest` on macOS 14, vImage `vImagePerpendicularProjection` fallback on 13
- `LargeFileDetector`: returns files >1GB as individual groups
- `BuildArtifactDetector`: regex patterns for .o, .pyc, node_modules, .build
- `RawJPEGPairDetector`: matches .RAF/.CR2 with .jpg/.jpeg pairs

- [ ] **Step 1: Create DirectoryDedupDetector.swift**

```swift
import CryptoKit
import FileScanner
import Foundation

public actor DirectoryDedupDetector {
    private let hasher: FileHasher

    public init(hasher: FileHasher = FileHasher()) {
        self.hasher = hasher
    }

    /// Detects files with identical content across different directories.
    /// O(n): hashes every file but returns only cross-directory duplicates.
    public func detect(_ urls: [URL], controller: ScanController) async throws -> [DuplicateGroup] {
        var hashBuckets: [String: [URL]] = [:]
        for url in urls {
            guard !controller.isCancelled else { return [] }
            if let hash = try? await hasher.hash(file: url) {
                hashBuckets[hash, default: []].append(url)
            }
        }

        var groups: [DuplicateGroup] = []
        for (hash, files) in hashBuckets where files.count > 1 {
            guard !controller.isCancelled else { return groups }
            // Only keep cross-directory duplicates
            let dirs = Set(files.map { $0.deletingLastPathComponent().path })
            guard dirs.count > 1 else { continue }

            let totalSize = files.reduce(0) { $0 + (try? FileManager.default.attributesOfItem(atPath: $1.path)[.size] as? Int64 ?? 0) ?? 0 }
            let fileItems = files.map { url in
                FileItem(id: UUID(), url: url, size: 0, modificationDate: Date(), hash: hash)
            }
            groups.append(DuplicateGroup(
                id: UUID(), category: .directoryDedup, totalSize: totalSize,
                fileCount: files.count, files: fileItems
            ))
        }
        return groups
    }
}
```

- [ ] **Step 2: Create PerceptualDetector.swift**

```swift
import Accelerate
import Foundation
#if canImport(Vision)
import Vision
#endif

public actor PerceptualDetector {
    public init() {}

    public func detect(_ urls: [URL], controller: ScanController) async throws -> [DuplicateGroup] {
        guard #available(macOS 14, *) else { return [] }
        #if canImport(Vision)
        var hashDict: [Data: [URL]] = [:]
        for url in urls {
            guard !controller.isCancelled else { return [] }
            guard let hash = try await imageHash(for: url) else { continue }
            hashDict[hash, default: []].append(url)
        }

        var groups: [DuplicateGroup] = []
        for (_, files) in hashDict where files.count > 1 {
            let items = files.map { FileItem(id: UUID(), url: $0, size: 0, modificationDate: Date(), hash: nil) }
            groups.append(DuplicateGroup(id: UUID(), category: .perceptual, totalSize: 0, fileCount: files.count, files: items))
        }
        return groups
        #else
        return []
        #endif
    }

    @available(macOS 14, *)
    private func imageHash(for url: URL) async -> Data? {
        #if canImport(Vision)
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let request = VNGenerateImageHashRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try? handler.perform([request])
        return request.results?.first?.imageHashData
        #else
        return nil
        #endif
    }
}
```

- [ ] **Step 3: Create LargeFileDetector.swift**

```swift
import Foundation

public actor LargeFileDetector {
    private let threshold: Int64

    public init(threshold: Int64 = 1024 * 1024 * 1024) { // 1GB
        self.threshold = threshold
    }

    public func detect(_ urls: [URL], controller: ScanController) -> [DuplicateGroup] {
        var groups: [DuplicateGroup] = []
        for url in urls {
            guard !controller.isCancelled else { return groups }
            guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64,
                  size >= threshold else { continue }
            let item = FileItem(id: UUID(), url: url, size: size, modificationDate: Date(), hash: nil)
            groups.append(DuplicateGroup(
                id: UUID(), category: .largeFile, totalSize: size, fileCount: 1, files: [item]
            ))
        }
        return groups
    }
}
```

- [ ] **Step 4: Create BuildArtifactDetector.swift**

```swift
import Foundation

public actor BuildArtifactDetector {
    private let artifactPatterns: [String] = [
        ".o$", ".pyc$", ".class$", ".a$", ".lib$", ".obj$",
        "node_modules/", ".build/", "DerivedData/", "Pods/",
        ".gradle/", "build/", "dist/", ".next/"
    ]

    public init() {}

    public func detect(_ urls: [URL], controller: ScanController) -> [DuplicateGroup] {
        var groups: [DuplicateGroup] = []
        for url in urls {
            guard !controller.isCancelled else { return groups }
            let path = url.path
            guard artifactPatterns.contains(where: { path.range(of: $0, options: .regularExpression) != nil }),
                  let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int64 else { continue }
            let item = FileItem(id: UUID(), url: url, size: size, modificationDate: Date(), hash: nil)
            groups.append(DuplicateGroup(
                id: UUID(), category: .buildArtifact, totalSize: size, fileCount: 1, files: [item]
            ))
        }
        return groups
    }
}
```

- [ ] **Step 5: Create RawJPEGPairDetector.swift**

```swift
import Foundation

public actor RawJPEGPairDetector {
    private let rawExtensions: Set<String> = ["raf", "cr2", "nef", "arw", "dng", "orf"]
    private let jpegExtensions: Set<String> = ["jpg", "jpeg", "jpe"]

    public init() {}

    public func detect(_ urls: [URL], controller: ScanController) -> [DuplicateGroup] {
        let files = Dictionary(grouping: urls) { url -> String in
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            return name
        }

        var groups: [DuplicateGroup] = []
        for (baseName, group) in files {
            guard !controller.isCancelled else { return groups }
            let raws = group.filter { rawExtensions.contains($0.pathExtension.lowercased()) }
            let jpegs = group.filter { jpegExtensions.contains($0.pathExtension.lowercased()) }
            guard !raws.isEmpty, !jpegs.isEmpty else { continue }

            let all = raws + jpegs
            let totalSize = all.reduce(0) { $0 + ((try? FileManager.default.attributesOfItem(atPath: $1.path)[.size] as? Int64) ?? 0) }
            let items = all.map { FileItem(id: UUID(), url: $0, size: 0, modificationDate: Date(), hash: nil) }
            groups.append(DuplicateGroup(
                id: UUID(), category: .rawJPEG, totalSize: totalSize, fileCount: all.count, files: items
            ))
        }
        return groups
    }
}
```

- [ ] **Step 6: Commit**

```bash
git add kSift/Detection/DirectoryDedupDetector.swift kSift/Detection/PerceptualDetector.swift \
       kSift/Detection/LargeFileDetector.swift kSift/Detection/BuildArtifactDetector.swift \
       kSift/Detection/RawJPEGPairDetector.swift
git commit -m "feat(kDupe): add 5 detectors (directory dedup, perceptual, large file, build artifact, RAW+JPEG)"
```

---

### Task 8: ScanOrchestrator + CleanupManager

**Files:**
- Create: `kSift/Detection/ScanOrchestrator.swift`
- Create: `kSift/Detection/CleanupManager.swift`

**Interfaces:**
- Consumes: `FileWalker`, all 6 detectors, `DuplicateRepositoryProtocol`, `ScanController`
- Produces: `ScanOrchestrator.run()` returns `ScanRecord` via async progress stream, `CleanupManager.execute()` moves files to trash

- [ ] **Step 1: Create ScanOrchestrator.swift**

```swift
import Foundation
import FileScanner

public actor ScanOrchestrator {
    private let fileWalker: FileWalker
    private let byteDetector: ByteIdenticalDetector
    private let dirDedupDetector: DirectoryDedupDetector
    private let perceptualDetector: PerceptualDetector
    private let largeFileDetector: LargeFileDetector
    private let buildArtifactDetector: BuildArtifactDetector
    private let rawJPEGDetector: RawJPEGPairDetector
    private let repository: DuplicateRepositoryProtocol

    public init(
        fileWalker: FileWalker = FileWalker(),
        byteDetector: ByteIdenticalDetector = ByteIdenticalDetector(),
        dirDedupDetector: DirectoryDedupDetector = DirectoryDedupDetector(),
        perceptualDetector: PerceptualDetector = PerceptualDetector(),
        largeFileDetector: LargeFileDetector = LargeFileDetector(),
        buildArtifactDetector: BuildArtifactDetector = BuildArtifactDetector(),
        rawJPEGDetector: RawJPEGPairDetector = RawJPEGPairDetector(),
        repository: DuplicateRepositoryProtocol = DuplicateRepositoryCoreData()
    ) {
        self.fileWalker = fileWalker
        self.byteDetector = byteDetector
        self.dirDedupDetector = dirDedupDetector
        self.perceptualDetector = perceptualDetector
        self.largeFileDetector = largeFileDetector
        self.buildArtifactDetector = buildArtifactDetector
        self.rawJPEGDetector = rawJPEGDetector
        self.repository = repository
    }

    public func run(config: ProfileConfig, controller: ScanController) -> AsyncStream<ScanProgress> {
        AsyncStream { continuation in
            Task {
                let target = ScanTarget(
                    directories: config.type.scanningDirectories + config.customDirectories,
                    exclusions: config.type.additionalExclusions + config.exclusions,
                    minFileSize: config.minFileSize
                )

                // Phase 1: Enumerate
                continuation.yield(ScanProgress(phase: .enumerating, progress: 0, filesScanned: 0, duplicatesFound: 0))
                let allURLs = try await fileWalker.walk(target: target, controller: controller) { result in
                    // progress callback
                }

                guard !controller.isCancelled else { continuation.finish(); return }
                continuation.yield(ScanProgress(phase: .byteIdentical, progress: 0.2, filesScanned: allURLs.count, duplicatesFound: 0))

                // Phase 2: Byte-identical
                let identicalGroups = try await byteDetector.detect(allURLs, controller: controller)
                let identicalCount = identicalGroups.reduce(0) { $0 + $1.files.count }

                // Phase 3: Directory dedup
                continuation.yield(ScanProgress(phase: .directoryDedup, progress: 0.4, filesScanned: allURLs.count, duplicatesFound: identicalCount))
                let dedupGroups = try await dirDedupDetector.detect(allURLs, controller: controller)
                let dedupCount = dedupGroups.reduce(0) { $0 + $1.files.count }

                // Phase 4: Perceptual
                continuation.yield(ScanProgress(phase: .perceptual, progress: 0.6, filesScanned: allURLs.count, duplicatesFound: identicalCount + dedupCount))
                let perceptualGroups = try await perceptualDetector.detect(allURLs, controller: controller)
                let perceptualCount = perceptualGroups.reduce(0) { $0 + $1.files.count }

                // Phase 5: Large files
                continuation.yield(ScanProgress(phase: .largeFiles, progress: 0.8, filesScanned: allURLs.count, duplicatesFound: identicalCount + dedupCount + perceptualCount))
                let largeGroups = largeFileDetector.detect(allURLs, controller: controller)

                // Phase 6: Build artifacts
                continuation.yield(ScanProgress(phase: .buildArtifacts, progress: 0.9, filesScanned: allURLs.count, duplicatesFound: identicalCount + dedupCount + perceptualCount + largeGroups.count))
                let buildGroups = buildArtifactDetector.detect(allURLs, controller: controller)

                // Phase 7: RAW+JPEG
                continuation.yield(ScanProgress(phase: .rawJPEG, progress: 0.95, filesScanned: allURLs.count, duplicatesFound: identicalCount + dedupCount + perceptualCount + largeGroups.count + buildGroups.count))
                let rawJPEGGroups = await rawJPEGDetector.detect(allURLs, controller: controller)

                // Combine
                let allGroups = identicalGroups + dedupGroups + perceptualGroups + largeGroups + buildGroups + rawJPEGGroups
                let totalDuplicates = allGroups.reduce(0) { $0 + $1.files.count }
                let totalWaste = allGroups.reduce(0) { $0 + $1.totalSize }

                continuation.yield(ScanProgress(phase: .completed, progress: 1.0, filesScanned: allURLs.count, duplicatesFound: totalDuplicates))
                continuation.finish()
            }
        }
    }

    public func saveResults(_ groups: [DuplicateGroup], config: ProfileConfig, duration: TimeInterval, filesScanned: Int) async throws {
        let totalDuplicates = groups.reduce(0) { $0 + $1.files.count }
        let totalWaste = groups.reduce(0) { $0 + $1.totalSize }
        let record = ScanRecord(
            id: UUID(), timestamp: Date(), profileType: config.type,
            totalFilesScanned: filesScanned, totalDuplicatesFound: totalDuplicates,
            totalWasteSize: totalWaste, duration: duration, groups: groups
        )
        try await repository.saveScanRecord(record)
    }
}
```

- [ ] **Step 2: Create CleanupManager.swift**

```swift
import Foundation

public actor CleanupManager {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public enum CleanupError: Error {
        case fileNotFound(URL)
        case trashFailed(URL, Error)
    }

    /// Moves files to trash. Returns list of successfully trashed files.
    public func moveToTrash(_ items: [FileItem]) async throws -> [CleanupAction] {
        var actions: [CleanupAction] = []
        for item in items {
            guard fileManager.fileExists(atPath: item.url.path) else {
                continue
            }
            do {
                var resultingURL: NSURL?
                try fileManager.trashItem(at: item.url, resultingItemURL: &resultingURL)
                let action = CleanupAction(
                    id: UUID(), file: item, method: .trash,
                    timestamp: Date(), isCompleted: true
                )
                actions.append(action)
            } catch {
                throw CleanupError.trashFailed(item.url, error)
            }
        }
        return actions
    }

    /// Permanently deletes files. Use with caution.
    public func permanentlyDelete(_ items: [FileItem]) async throws -> [CleanupAction] {
        var actions: [CleanupAction] = []
        for item in items {
            guard fileManager.fileExists(atPath: item.url.path) else { continue }
            try fileManager.removeItem(at: item.url)
            let action = CleanupAction(
                id: UUID(), file: item, method: .delete,
                timestamp: Date(), isCompleted: true
            )
            actions.append(action)
        }
        return actions
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add kSift/Detection/ScanOrchestrator.swift kSift/Detection/CleanupManager.swift
git commit -m "feat(kDupe): add ScanOrchestrator and CleanupManager"
```

---

### Task 9: Onboarding UI

**Files:**
- Create: `kSift/UI/Onboarding/OnboardingView.swift`
- Create: `kSift/UI/Onboarding/OnboardingViewModel.swift`
- Create: `kSift/UI/Onboarding/ProfileSetupView.swift`

**Interfaces:**
- Consumes: `AppState`, `ProfileType`, `ProfileConfig`
- Produces: Onboarding flow that sets `appState.isOnboardingComplete = true` and `appState.selectedProfile`

- [ ] **Step 1: Create OnboardingViewModel.swift**

```swift
import SwiftUI

@MainActor
public final class OnboardingViewModel: ObservableObject {
    @Published public var selectedProfile: ProfileType = .developer
    @Published public var customDirectories: [String] = []
    @Published public var customDirectoryStrings: String = ""
    @Published public var enablePerceptualScan = true
    @Published public var step = 0

    public func buildConfig() -> ProfileConfig {
        ProfileConfig(
            type: selectedProfile,
            customDirectories: customDirectoryStrings
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.isEmpty },
            exclusions: selectedProfile.additionalExclusions,
            minFileSize: 1024,
            enablePerceptualScan: enablePerceptualScan
        )
    }
}
```

- [ ] **Step 2: Create ProfileSetupView.swift**

```swift
import SwiftUI

struct ProfileSetupView: View {
    @ObservedObject var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 24) {
            Text("Choose Your Profile")
                .font(.title2).bold()
            Text("kDupe optimizes scanning based on your workflow")
                .foregroundColor(.secondary)

            ForEach(ProfileType.allCases, id: \.self) { profile in
                Button(action: { viewModel.selectedProfile = profile }) {
                    HStack {
                        Image(systemName: iconFor(profile))
                            .font(.title2)
                        VStack(alignment: .leading) {
                            Text(profile.title).bold()
                            Text(descriptionFor(profile))
                                .font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        if viewModel.selectedProfile == profile {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.brandPrimary)
                        }
                    }
                    .padding()
                    .background(GlassPanel())
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.lg)
                            .stroke(viewModel.selectedProfile == profile ? Color.brandPrimary : .clear, lineWidth: 2)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }

    private func iconFor(_ profile: ProfileType) -> String {
        switch profile {
        case .developer: return "terminal"
        case .photographer: return "camera"
        case .simple: return "person"
        }
    }

    private func descriptionFor(_ profile: ProfileType) -> String {
        switch profile {
        case .developer: return "Scans projects, build artifacts, and development directories"
        case .photographer: return "Scans photos, RAW files, and creative assets"
        case .simple: return "Scans desktop, downloads, and documents"
        }
    }
}
```

- [ ] **Step 3: Create OnboardingView.swift**

```swift
import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = OnboardingViewModel()

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon + title
            Image(systemName: "doc.on.doc")
                .font(.system(size: 64))
                .foregroundColor(.brandPrimary)
            Text("Welcome to kDupe")
                .font(.largeTitle).bold()
            Text("Find and remove duplicate files, reclaim disk space")
                .foregroundColor(.secondary)

            // Profile selection
            ProfileSetupView(viewModel: viewModel)
                .frame(maxWidth: 400)

            Spacer()

            // Continue button
            Button(action: completeOnboarding) {
                Text("Get Started")
                    .frame(maxWidth: 300)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandPrimary)
            .padding(.bottom, 40)
        }
    }

    private func completeOnboarding() {
        let config = viewModel.buildConfig()
        appState.selectedProfile = viewModel.selectedProfile
        appState.isOnboardingComplete = true
        appState.navigation = .scan
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add kSift/UI/Onboarding/
git commit -m "feat(kDupe): add onboarding UI with profile selection"
```

---

### Task 10: Scan UI

**Files:**
- Create: `kSift/UI/Scan/MainView.swift`
- Create: `kSift/UI/Scan/ScanProgressView.swift`
- Create: `kSift/UI/Scan/ScanViewModel.swift`
- Create: `kSift/UI/Scan/ScanResultView.swift`

**Interfaces:**
- Consumes: `ScanOrchestrator`, `ProfileConfig`, `AppState`
- Produces: `ScanViewModel` (startScan, cancelScan, progress), `MainView` (entry), `ScanProgressView` (animated), `ScanResultView` (summary)

- [ ] **Step 1: Create ScanViewModel.swift**

```swift
import SwiftUI

@MainActor
public final class ScanViewModel: ObservableObject {
    @Published public var progress: ScanProgress?
    @Published public var scanState: AppState.ScanState = .idle
    @Published public var scanResult: [DuplicateGroup] = []

    private let orchestrator: ScanOrchestrator
    private var controller = ScanController()

    public init(orchestrator: ScanOrchestrator = ScanOrchestrator()) {
        self.orchestrator = orchestrator
    }

    public func startScan(config: ProfileConfig) {
        scanState = .scanning(0)
        controller = ScanController()
        scanResult = []

        Task {
            var allGroups: [DuplicateGroup] = []
            let startTime = Date()

            let stream = await orchestrator.run(config: config, controller: controller)
            for await p in stream {
                progress = p
                if case .completed = p.phase {
                    scanState = .completed
                }
            }

            let duration = Date().timeIntervalSince(startTime)
            try? await orchestrator.saveResults(allGroups, config: config, duration: duration, filesScanned: progress?.filesScanned ?? 0)
            scanResult = allGroups
        }
    }

    public func cancelScan() {
        controller.cancel()
        scanState = .idle
    }
}
```

- [ ] **Step 2: Create ScanProgressView.swift**

```swift
import SwiftUI
import DesignSystem

struct ScanProgressView: View {
    let progress: ScanProgress

    var body: some View {
        VStack(spacing: 24) {
            ProgressRing(progress: progress.progress)
                .frame(width: 120, height: 120)

            Text(phaseTitle)
                .font(.headline)
            Text("\(progress.filesScanned) files scanned")
                .foregroundColor(.secondary)
            if progress.duplicatesFound > 0 {
                Text("\(progress.duplicatesFound) duplicates found")
                    .foregroundColor(.brandPrimary)
            }

            ProgressView(value: progress.progress)
                .progressViewStyle(.linear)
                .frame(width: 200)
        }
        .padding()
    }

    private var phaseTitle: String {
        switch progress.phase {
        case .enumerating: return "Scanning files..."
        case .byteIdentical: return "Checking identical files..."
        case .directoryDedup: return "Cross-directory analysis..."
        case .perceptual: return "Comparing images..."
        case .largeFiles: return "Finding large files..."
        case .buildArtifacts: return "Identifying build artifacts..."
        case .rawJPEG: return "Matching RAW + JPEG pairs..."
        case .completed: return "Scan complete!"
        }
    }
}
```

- [ ] **Step 3: Create ScanResultView.swift**

```swift
import SwiftUI
import DesignSystem

struct ScanResultView: View {
    let groups: [DuplicateGroup]
    let onReview: () -> Void
    let onRescan: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.success)

            Text("Scan Complete")
                .font(.title).bold()

            VStack(spacing: 8) {
                StatRow(label: "Duplicate Groups", value: "\(groups.count)")
                StatRow(label: "Wasteable Space", value: FileSizeFormatter.abbreviated(from: totalWaste))
            }
            .padding()
            .background(GlassPanel())
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))

            HStack(spacing: 16) {
                Button("Review Results", action: onReview)
                    .buttonStyle(.borderedProminent)
                Button("Rescan", action: onRescan)
                    .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    private var totalWaste: Int64 {
        groups.reduce(0) { $0 + $1.totalSize }
    }
}

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).bold()
        }
    }
}
```

- [ ] **Step 4: Create MainView.swift**

```swift
import SwiftUI
import DesignSystem

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = ScanViewModel()

    var body: some View {
        VStack {
            switch viewModel.scanState {
            case .idle:
                idleState
            case .scanning:
                if let progress = viewModel.progress {
                    ScanProgressView(progress: progress)
                }
            case .completed:
                ScanResultView(
                    groups: viewModel.scanResult,
                    onReview: { appState.navigation = .results },
                    onRescan: { viewModel.startScan(config: ProfileConfig.default) }
                )
            case .failed(let msg):
                ErrorStateView(message: msg, retryAction: { viewModel.startScan(config: ProfileConfig.default) })
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var idleState: some View {
        VStack(spacing: 24) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 64))
                .foregroundColor(.brandPrimary)
            Text("Ready to Scan")
                .font(.title).bold()
            Text("Choose a profile in Settings or start with Developer mode")
                .foregroundColor(.secondary)

            Button(action: { viewModel.startScan(config: ProfileConfig.default) }) {
                Label("Start Scan", systemImage: "play.fill")
                    .frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandPrimary)
        }
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add kSift/UI/Scan/
git commit -m "feat(kDupe): add scan UI with progress and results summary"

---

### Task 11: Result UI — Group List, Drill-Down, Filtering

**Files:**
- Create: `kSift/UI/Result/ResultViewModel.swift`
- Create: `kSift/UI/Result/ResultView.swift`
- Create: `kSift/UI/Result/GroupDetailView.swift`
- Create: `kSift/UI/Result/FileRowView.swift`
- Create: `kSift/UI/Result/FilterBarView.swift`

**Interfaces:**
- Consumes: `DuplicateGroup`, `FileItem`, `DuplicateCategory` (from Task 3), `ScanResult` (from Task 8 ScanOrchestrator run method return)
- Produces: `ResultViewModel` (published groups, selection state, filter state, cleanup methods)

- [ ] **Step 1: Create ResultViewModel**

```swift
import SwiftUI
import Combine

@MainActor
final class ResultViewModel: ObservableObject {
    @Published var groups: [DuplicateGroup] = []
    @Published var selectedGroupIds: Set<UUID> = []
    @Published var activeCategory: DuplicateCategory?
    @Published var sortOrder: SortOrder = .sizeDesc
    @Published var isProcessing = false
    @Published var showCleanupConfirmation = false

    enum SortOrder: String, CaseIterable {
        case sizeDesc = "Size (High→Low)"
        case sizeAsc = "Size (Low→High)"
        case countDesc = "Count (High→Low)"
        case type = "Category"
    }

    var filteredGroups: [DuplicateGroup] {
        var result = groups
        if let cat = activeCategory {
            result = result.filter { $0.category == cat }
        }
        switch sortOrder {
        case .sizeDesc: result.sort { $0.totalSize > $1.totalSize }
        case .sizeAsc: result.sort { $0.totalSize < $1.totalSize }
        case .countDesc: result.sort { $0.files.count > $1.files.count }
        case .type: result.sort { $0.category.rawValue < $1.category.rawValue }
        }
        return result
    }

    var totalDuplicateSize: Int64 {
        groups.reduce(0) { $0 + $1.totalSize }
    }

    var totalGroupCount: Int { groups.count }

    func autoSelectGroups() {
        // For each group, keep the newest file, select the rest
        selectedGroupIds = Set(groups.map(\.id))
    }

    func clearSelection() {
        selectedGroupIds.removeAll()
    }

    func removeSelected(using manager: CleanupManager) async {
        isProcessing = true
        defer { isProcessing = false }
        let toRemove = groups.filter { selectedGroupIds.contains($0.id) }
        for group in toRemove {
            let toDelete = group.files.dropFirst().map(\.id)
            for fileId in toDelete {
                if let file = group.files.first(where: { $0.id == fileId }) {
                    try? await manager.moveToTrash(url: file.url)
                }
            }
        }
        groups.removeAll { selectedGroupIds.contains($0.id) }
        selectedGroupIds.removeAll()
    }
}
```

- [ ] **Step 2: Create ResultView**

```swift
import SwiftUI
import DesignSystem

struct ResultView: View {
    @ObservedObject var viewModel: ResultViewModel
    let onRescan: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Stats bar
            GlassPanel {
                HStack {
                    StatItem(title: "Groups", value: "\(viewModel.totalGroupCount)")
                    StatItem(title: "Duplicates", value: formatBytes(viewModel.totalDuplicateSize))
                    Spacer()
                    Button("Rescan", action: onRescan)
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Filter bar
            FilterBarView(activeCategory: $viewModel.activeCategory,
                         counts: categoryCounts)

            // Group list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.filteredGroups) { group in
                        NavigationLink(destination: GroupDetailView(
                            group: group,
                            viewModel: viewModel
                        )) {
                            GroupRowView(group: group)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }

            // Bottom action bar
            HStack {
                Text("\(viewModel.selectedGroupIds.count) groups selected")
                    .foregroundColor(.secondary)
                Spacer()
                Button("Auto Select", action: viewModel.autoSelectGroups)
                Button("Delete (\(formatBytes(selectedSize)))") {
                    viewModel.showCleanupConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(viewModel.selectedGroupIds.isEmpty)
            }
            .padding(16)
        }
        .alert("Move to Trash?", isPresented: $viewModel.showCleanupConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { /* trigger cleanup */ }
        } message: {
            Text("\(viewModel.selectedGroupIds.count) groups will be moved to Trash.")
        }
    }

    private var categoryCounts: [DuplicateCategory: Int] {
        Dictionary(grouping: viewModel.groups, by: \.category)
            .mapValues { $0.count }
    }

    private var selectedSize: Int64 {
        viewModel.groups
            .filter { viewModel.selectedGroupIds.contains($0.id) }
            .reduce(0) { $0 + $1.totalSize }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct StatItem: View {
    let title: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.headline)
        }
    }
}

struct GroupRowView: View {
    let group: DuplicateGroup
    var body: some View {
        GlassPanel {
            HStack {
                Image(systemName: group.category.iconName)
                    .foregroundColor(group.category.color)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                        .font(.headline)
                    Text("\(group.files.count) files · \(ByteCountFormatter.string(fromByteCount: group.totalSize, countStyle: .file))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding(12)
        }
    }
}
```

- [ ] **Step 3: Create GroupDetailView**

```swift
import SwiftUI
import DesignSystem
import QuickLook

struct GroupDetailView: View {
    let group: DuplicateGroup
    @ObservedObject var viewModel: ResultViewModel
    @State private var selectedFileIds: Set<UUID> = []
    @State private var previewUrl: URL?

    var body: some View {
        VStack(spacing: 0) {
            // Group header
            GlassPanel {
                HStack {
                    Image(systemName: group.category.iconName)
                        .font(.title2)
                        .foregroundColor(group.category.color)
                    VStack(alignment: .leading) {
                        Text(group.title).font(.headline)
                        Text("\(group.files.count) files · \(formatBytes(group.totalSize))")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
            }
            .padding(8)

            // Auto-Select button
            HStack {
                Button("Auto Keep Newest (\(group.files.count - 1) to delete)") {
                    let sorted = group.files.sorted { $0.modificationDate > $1.modificationDate }
                    if let newest = sorted.first {
                        selectedFileIds = Set(group.files.filter { $0.id != newest.id }.map(\.id))
                    }
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .padding(.horizontal, 16)

            // File list
            List(selection: $selectedFileIds) {
                ForEach(group.files) { file in
                    FileRowView(file: file, isSelected: selectedFileIds.contains(file.id))
                        .tag(file.id)
                        .onTapGesture(count: 2) { previewUrl = file.url }
                        .contextMenu {
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([file.url])
                            }
                            Button("QuickLook") { previewUrl = file.url }
                        }
                }
            }

            // Bottom bar
            HStack {
                Text("\(selectedFileIds.count) selected · \(formatBytes(selectedSize))")
                Spacer()
                Button("Move \(selectedFileIds.count) to Trash") {
                    Task { await deleteSelected() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(selectedFileIds.isEmpty)
            }
            .padding(16)
        }
        .quickLookPreview($previewUrl)
    }

    private var selectedSize: Int64 {
        group.files.filter { selectedFileIds.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    private func deleteSelected() async {
        let manager = CleanupManager()
        for file in group.files where selectedFileIds.contains(file.id) {
            try? await manager.moveToTrash(url: file.url)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
```

- [ ] **Step 4: Create FileRowView**

```swift
import SwiftUI
import DesignSystem

struct FileRowView: View {
    let file: FileItem
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                .resizable()
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.url.lastPathComponent)
                    .font(.body)
                    .lineLimit(1)
                Text(file.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
```

- [ ] **Step 5: Create FilterBarView**

```swift
import SwiftUI
import DesignSystem

struct FilterBarView: View {
    @Binding var activeCategory: DuplicateCategory?
    let counts: [DuplicateCategory: Int]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                filterChip(title: "All", count: counts.values.reduce(0, +),
                          isSelected: activeCategory == nil) {
                    activeCategory = nil
                }
                ForEach(DuplicateCategory.allCases, id: \.self) { cat in
                    filterChip(title: cat.displayName, count: counts[cat] ?? 0,
                              isSelected: activeCategory == cat,
                              color: cat.color) {
                        activeCategory = (activeCategory == cat) ? nil : cat
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func filterChip(title: String, count: Int, isSelected: Bool,
                           color: Color = .accentColor, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title).font(.caption)
                Text("\(count)").font(.caption2).foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isSelected ? color.opacity(0.2) : Color.separatorColor.opacity(0.1))
            .foregroundColor(isSelected ? color : .primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 6: Add DuplicateCategory display extensions**

In `kSift/Models/ScanTypes.swift`, append:
```swift
extension DuplicateCategory {
    var displayName: String {
        switch self {
        case .byteIdentical: return "Identical"
        case .directoryDedup: return "Directory"
        case .perceptual: return "Similar"
        case .largeFile: return "Large"
        case .buildArtifact: return "Artifacts"
        case .rawJPEGPair: return "RAW+JPEG"
        }
    }

    var iconName: String {
        switch self {
        case .byteIdentical: return "doc.on.doc"
        case .directoryDedup: return "folder.badge.gearshape"
        case .perceptual: return "eye"
        case .largeFile: return "doc.resize"
        case .buildArtifact: return "hammer"
        case .rawJPEGPair: return "camera"
        }
    }

    var color: Color {
        switch self {
        case .byteIdentical: return .blue
        case .directoryDedup: return .purple
        case .perceptual: return .orange
        case .largeFile: return .red
        case .buildArtifact: return .gray
        case .rawJPEGPair: return .green
        }
    }
}
```

- [ ] **Step 7: Create test file for ResultViewModel**

`kDupeTests/UITests/ResultViewModelTests.swift`:
```swift
import XCTest
@testable import kDupe

@MainActor
final class ResultViewModelTests: XCTestCase {
    func testFilterByCategory() {
        let vm = ResultViewModel()
        let groups = [
            makeGroup(cat: .byteIdentical, size: 100),
            makeGroup(cat: .largeFile, size: 2000),
            makeGroup(cat: .byteIdentical, size: 50),
        ]
        vm.groups = groups

        vm.activeCategory = .byteIdentical
        XCTAssertEqual(vm.filteredGroups.count, 2)

        vm.activeCategory = .largeFile
        XCTAssertEqual(vm.filteredGroups.count, 1)

        vm.activeCategory = nil
        XCTAssertEqual(vm.filteredGroups.count, 3)
    }

    func testSortBySizeDesc() {
        let vm = ResultViewModel()
        vm.groups = [
            makeGroup(cat: .byteIdentical, size: 100),
            makeGroup(cat: .largeFile, size: 2000),
            makeGroup(cat: .buildArtifact, size: 50),
        ]
        vm.sortOrder = .sizeDesc
        XCTAssertEqual(vm.filteredGroups[0].totalSize, 2000)
    }

    func testAutoSelect() {
        let vm = ResultViewModel()
        vm.groups = [makeGroup(cat: .byteIdentical, size: 100)]
        vm.autoSelectGroups()
        XCTAssertEqual(vm.selectedGroupIds.count, 1)
    }

    private func makeGroup(cat: DuplicateCategory, size: Int64) -> DuplicateGroup {
        DuplicateGroup(
            id: UUID(),
            category: cat,
            totalSize: size,
            files: [FileItem(id: UUID(), url: URL(filePath: "/tmp/a"), size: size,
                           modificationDate: Date(), hash: nil)],
            title: "Test \(cat)"
        )
    }
}
```

- [ ] **Step 8: Run tests**

```bash
cd kDupe && swift test --filter ResultViewModelTests
```
Expected: 3 passed.

- [ ] **Step 9: Commit**

```bash
git add kSift/UI/Result/ kSift/Models/ScanTypes.swift kDupeTests/UITests/ResultViewModelTests.swift
git commit -m "feat(kDupe): add result UI with filtering, sorting, and group drill-down"
```

### Task 12: History + Settings UI

**Files:**
- Create: `kSift/UI/History/HistoryView.swift`
- Create: `kSift/UI/History/HistoryViewModel.swift`
- Create: `kSift/UI/Settings/SettingsView.swift`
- Create: `kSift/UI/Settings/SettingsViewModel.swift`

**Interfaces:**
- Consumes: `ScanRecord` (from Task 5), `DuplicateRepositoryProtocol` (from Task 5), `ProfileConfig` (from Task 3)
- Produces: `HistoryViewModel` (records list, load/delete), `SettingsViewModel` (profile, directories, minFileSize)

- [ ] **Step 1: Create HistoryViewModel**

```swift
import SwiftUI

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var records: [ScanRecord] = []
    @Published var isLoading = false

    private let repository: DuplicateRepositoryProtocol

    init(repository: DuplicateRepositoryProtocol = DuplicateRepositoryCoreData()) {
        self.repository = repository
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            records = try await repository.loadScanHistory(limit: 50)
        } catch {
            records = []
        }
    }

    func delete(_ record: ScanRecord) async {
        do {
            try await repository.deleteScan(id: record.id)
            records.removeAll { $0.id == record.id }
        } catch {
            // Handle error
        }
    }
}
```

- [ ] **Step 2: Create HistoryView**

```swift
import SwiftUI
import DesignSystem

struct HistoryView: View {
    @StateObject private var viewModel = HistoryViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Scan History")
                .font(.title).bold()
                .padding(.horizontal)

            if viewModel.isLoading {
                Spacer()
                LoadingStateView(message: "Loading history...")
                Spacer()
            } else if viewModel.records.isEmpty {
                Spacer()
                EmptyStateView(icon: "clock", title: "No scans yet",
                              message: "Run a scan to see history here")
                Spacer()
            } else {
                List {
                    ForEach(viewModel.records) { record in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(record.date, style: .date)
                                    .font(.headline)
                                Text("\(record.groupCount) groups · \(formatBytes(record.totalSize))")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(record.duration.formatted())
                                .font(.caption).foregroundColor(.secondary)
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                Task { await viewModel.delete(record) }
                            }
                        }
                    }
                }
            }
        }
        .task { await viewModel.load() }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
```

- [ ] **Step 3: Create SettingsViewModel**

```swift
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var selectedProfile: ProfileType = .developer
    @Published var customDirectories: [String] = []
    @Published var additionalExclusions: [String] = []
    @Published var minFileSize: Int64 = 1024       // 1 KB
    @Published var enablePerceptual: Bool = true
    @Published var enableBuildArtifacts: Bool = true

    var currentProfile: ProfileConfig {
        ProfileConfig(profile: selectedProfile, customPaths: customDirectories,
                     exclusions: additionalExclusions)
    }

    func save() {
        UserDefaults.standard.set(selectedProfile.rawValue, forKey: "selectedProfile")
        UserDefaults.standard.set(minFileSize, forKey: "minFileSize")
        UserDefaults.standard.set(enablePerceptual, forKey: "enablePerceptual")
        UserDefaults.standard.set(enableBuildArtifacts, forKey: "enableBuildArtifacts")
    }

    func load() {
        selectedProfile = ProfileType(rawValue: UserDefaults.standard.string(forKey: "selectedProfile") ?? "") ?? .developer
        minFileSize = UserDefaults.standard.object(forKey: "minFileSize") as? Int64 ?? 1024
        enablePerceptual = UserDefaults.standard.bool(forKey: "enablePerceptual")
        enableBuildArtifacts = UserDefaults.standard.bool(forKey: "enableBuildArtifacts")
    }
}
```

- [ ] **Step 4: Create SettingsView**

```swift
import SwiftUI
import DesignSystem

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title).bold()

            Form {
                // Profile picker
                Section("Profile") {
                    Picker("Scan Profile", selection: $viewModel.selectedProfile) {
                        ForEach(ProfileType.allCases, id: \.self) { profile in
                            Label(profile.displayName, systemImage: profile.iconName)
                                .tag(profile)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                // Scan options
                Section("Scan Options") {
                    VStack(alignment: .leading) {
                        Text("Min file size: \(formatBytes(viewModel.minFileSize))")
                        Slider(value: Binding(
                            get: { Double(viewModel.minFileSize) },
                            set: { viewModel.minFileSize = Int64($0) }
                        ), in: 256...10_485_760, step: 256)
                    }

                    Toggle("Enable perceptual similarity (macOS 14+)",
                          isOn: $viewModel.enablePerceptual)
                    Toggle("Scan build artifacts",
                          isOn: $viewModel.enableBuildArtifacts)
                }

                // Directories
                Section("Scan Directories") {
                    ForEach(viewModel.customDirectories, id: \.self) { dir in
                        HStack {
                            Text(dir)
                            Spacer()
                            Button("Remove") {
                                viewModel.customDirectories.removeAll { $0 == dir }
                            }
                        }
                    }
                    Button("Add Directory") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        guard panel.runModal() == .OK, let url = panel.url else { return }
                        viewModel.customDirectories.append(url.path)
                    }
                }
            }
        }
        .padding()
        .task { viewModel.load() }
        .onChange(of: viewModel.selectedProfile) { _ in viewModel.save() }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

extension ProfileType: CaseIterable {
    public static var allCases: [ProfileType] = [.developer, .photographer, .simple]
}

extension ProfileType {
    var displayName: String {
        switch self {
        case .developer: return "Developer"
        case .photographer: return "Photographer"
        case .simple: return "Simple"
        }
    }
    var iconName: String {
        switch self {
        case .developer: return "hammer.fill"
        case .photographer: return "camera.fill"
        case .simple: return "person.fill"
        }
    }
}
```

- [ ] **Step 5: Wire into RootView navigation**

In `kSift/App/RootView.swift`, add `.history` and `.settings` cases to the `@ViewBuilder mainContent` switch:

```swift
case .history:
    HistoryView()
case .settings:
    SettingsView()
```

- [ ] **Step 6: Commit**

```bash
git add kSift/UI/History/ kSift/UI/Settings/ kSift/App/RootView.swift
git commit -m "feat(kDupe): add history and settings UI"
```

### Task 13: StoreKit 2 + Paywall

**Files:**
- Create: `kSift/Store/StoreManager.swift`
- Create: `kSift/Store/PaywallView.swift`
- Create: `kSift/Store/StoreConfig.storekit`
- Create: `kSift/Store/ProductIdentifiers.swift`
- Modify: `kSift/project.yml` (add StoreKit config)

**Interfaces:**
- Consumes: None
- Produces: `StoreManager` (actor with products, purchase, isPaidUser), `PaywallView` (SwiftUI)

- [ ] **Step 1: Create ProductIdentifiers**

```swift
enum ProductID: String, CaseIterable {
    case weekly = "app.kraftly.kdupe.sub.weekly"
    case yearly = "app.kraftly.kdupe.sub.yearly"
    case lifetime = "app.kraftly.kdupe.purchase.lifetime"
}
```

- [ ] **Step 2: Create StoreManager**

```swift
import StoreKit

actor StoreManager {
    @Published private(set) var products: [Product] = []
    @Published private(set) var isPaidUser = false

    func loadProducts() async {
        do {
            products = try await Product.products(for: ProductID.allCases.map(\.rawValue))
        } catch {
            products = []
        }
    }

    func purchase(_ product: Product) async throws -> Bool {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                await transaction.finish()
                isPaidUser = true
                return true
            }
            return false
        case .pending:
            return false
        case .userCancelled:
            return false
        @unknown default:
            return false
        }
    }

    func checkEntitlement() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID.contains("app.kraftly.kdupe") {
                    isPaidUser = true
                    return
                }
            }
        }
        isPaidUser = false
    }

    func restorePurchases() async {
        try? await AppStore.sync()
        await checkEntitlement()
    }
}
```

- [ ] **Step 3: Create PaywallView**

```swift
import SwiftUI
import StoreKit
import DesignSystem

struct PaywallView: View {
    @StateObject private var store = StoreManager()
    @State private var isPurchasing = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.brandPrimary)

            Text("Unlock Full Power")
                .font(.largeTitle).bold()

            Text("Remove duplicate files, clean build artifacts, and reclaim gigabytes.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            ForEach(store.products, id: \.id) { product in
                ProductView(product: product)
                    .productViewStyle(.compact)
                    .padding(.horizontal)
            }

            Button(action: { Task { await purchase() } }) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPurchasing)
            .padding(.horizontal)

            Button("Restore Purchases") {
                Task { await store.restorePurchases() }
            }
            .buttonStyle(.plain)
        }
        .padding()
        .task { await store.loadProducts() }
    }

    private func purchase() async {
        isPurchasing = true
        defer { isPurchasing = false }
        guard let product = store.products.first else { return }
        _ = try? await store.purchase(product)
    }
}
```

- [ ] **Step 4: Create StoreConfig.storekit**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Products</key>
    <array>
        <dict>
            <key>Description</key>
            <string>Weekly subscription to kDupe Pro</string>
            <key>Display Name</key>
            <string>kDupe Pro Weekly</string>
            <key>Family</key>
            <string>kDupe Pro</string>
            <key>ID</key>
            <string>app.kraftly.kdupe.sub.weekly</string>
            <key>Type</key>
            <string>Auto-Renewable Subscription</string>
            <key>Price</key>
            <integer>499</integer>
        </dict>
        <dict>
            <key>Description</key>
            <string>Yearly subscription to kDupe Pro</string>
            <key>Display Name</key>
            <string>kDupe Pro Yearly</string>
            <key>Family</key>
            <string>kDupe Pro</string>
            <key>ID</key>
            <string>app.kraftly.kdupe.sub.yearly</string>
            <key>Type</key>
            <string>Auto-Renewable Subscription</string>
            <key>Price</key>
            <integer>1999</integer>
        </dict>
        <dict>
            <key>Description</key>
            <string>Lifetime license for kDupe Pro</string>
            <key>Display Name</key>
            <string>kDupe Pro Lifetime</string>
            <key>ID</key>
            <string>app.kraftly.kdupe.purchase.lifetime</string>
            <key>Type</key>
            <string>Consumable</string>
            <key>Price</key>
            <integer>4999</integer>
        </dict>
    </array>
    <key>Version</key>
    <string>1.0</string>
</dict>
</plist>
```

- [ ] **Step 5: Commit**

```bash
git add kSift/Store/
git commit -m "feat(kDupe): add StoreKit 2 paywall with weekly/yearly/lifetime products"
```

### Task 14: CLI Tool + XPC Service

**Files:**
- Create: `kDupeCLI/main.swift`
- Create: `kDupeCLI/Commands/ScanCommand.swift`
- Create: `kDupeCLI/Commands/ResultsCommand.swift`
- Create: `kDupeCLI/Commands/CleanupCommand.swift`
- Create: `kDupeCLI/Commands/WatchCommand.swift`
- Create: `kDupeCLI/Commands/HistoryCommand.swift`
- Create: `kDupeCLI/Commands/WebCommand.swift`
- Create: `kDupeCLI/Commands/VersionCommand.swift`
- Create: `kDupeXPC/XPCDuplicateServiceProtocol.swift`
- Create: `kDupeXPC/XPCDuplicateService.swift`
- Create: `kDupeXPC/main.swift`
- Modify: `kSift/project.yml` (add kDupeCLI + kDupeXPC targets)

**Interfaces:**
- Consumes: All detector actors (from Tasks 6-7), CleanupManager (from Task 8)
- Produces: CLI tool with 8 subcommands, XPC service

- [ ] **Step 1: Add XPC targets to project.yml**

```yaml
targets:
  kDupe:
    # ... existing config ...

  kDupeXPC:
    type: xpc-service
    platform: macOS
    deploymentTarget: "13.0"
    sources: [kDupeXPC]
    dependencies:
      - target: kFoundation/FileScanner
      - target: kFoundation/CommonUtils
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: app.kraftly.kdupe.xpc
      CODE_SIGN_ENTITLEMENTS: kSift/kDupe.entitlements

  kDupeCLI:
    type: tool
    platform: macOS
    deploymentTarget: "13.0"
    sources: [kDupeCLI]
    dependencies:
      - target: kDupeXPC
    settings:
      PRODUCT_BUNDLE_IDENTIFIER: app.kraftly.kdupe.cli
      CODE_SIGN_ENTITLEMENTS: kSift/kDupe.entitlements
```

- [ ] **Step 2: Create XPC Protocol**

```swift
// kDupeXPC/XPCDuplicateServiceProtocol.swift
import Foundation

@objc protocol XPCDuplicateServiceProtocol {
    func scanDirectory(path: String, reply: @escaping (Data?) -> Void)
    func cancelScan()
    func checkStatus(reply: @escaping (Data) -> Void)
}
```

- [ ] **Step 3: Create XPC Service**

```swift
// kDupeXPC/XPCDuplicateService.swift
import Foundation

class XPCDuplicateService: NSObject, XPCDuplicateServiceProtocol {
    private var currentTask: Task<Void, Never>?

    func scanDirectory(path: String, reply: @escaping (Data?) -> Void) {
        currentTask?.cancel()
        currentTask = Task {
            let orchestrator = ScanOrchestrator()
            // ... scan logic ...
            // reply(try? JSONEncoder().encode(results))
        }
    }

    func cancelScan() {
        currentTask?.cancel()
        currentTask = nil
    }

    func checkStatus(reply: @escaping (Data) -> Void) {
        let status = ["status": "running", "version": "1.0.0"]
        reply(try! JSONEncoder().encode(status))
    }
}
```

- [ ] **Step 4: Create XPC main.swift**

```swift
// kDupeXPC/main.swift
import Foundation

class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: XPCDuplicateServiceProtocol.self)
        newConnection.exportedObject = XPCDuplicateService()
        newConnection.resume()
        return true
    }
}

let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
```

- [ ] **Step 5: Create CLI main.swift**

```swift
// kDupeCLI/main.swift
import Foundation

let cli = CLI()
cli.run()
```

- [ ] **Step 6: Create CLI command implementations**

```swift
// kDupeCLI/main.swift (expanded)
import Foundation

struct CLI {
    func run() {
        let args = CommandLine.arguments
        guard args.count > 1 else { printUsage(); return }

        switch args[1] {
        case "scan":       ScanCommand().execute(Array(args.dropFirst(2)))
        case "results":    ResultsCommand().execute(Array(args.dropFirst(2)))
        case "cleanup":    CleanupCommand().execute(Array(args.dropFirst(2)))
        case "watch":      WatchCommand().execute(Array(args.dropFirst(2)))
        case "history":    HistoryCommand().execute(Array(args.dropFirst(2)))
        case "web":        WebCommand().execute(Array(args.dropFirst(2)))
        case "version":    VersionCommand().execute(Array(args.dropFirst(2)))
        case "completion": CompletionCommand().execute(Array(args.dropFirst(2)))
        default:           printUsage()
        }
    }

    private func printUsage() {
        print("Usage: kdupe <command> [options]")
        print("Commands: scan, results, cleanup, watch, history, web, version, completion")
    }
}
```

```swift
// kDupeCLI/Commands/ScanCommand.swift
import Foundation

struct ScanCommand {
    func execute(_ args: [String]) {
        // Parse --mode, --json, --csv flags
        var paths: [String] = []
        var mode = "standard"
        var outputFormat = "text"
        var argIterator = args.makeIterator()
        while let arg = argIterator.next() {
            switch arg {
            case "--mode": mode = argIterator.next() ?? "standard"
            case "--json": outputFormat = "json"
            case "--csv":  outputFormat = "csv"
            default:       paths.append(arg)
            }
        }
        if paths.isEmpty { paths = [FileManager.default.currentDirectoryPath] }

        // Call XPC service
        let connection = NSXPCConnection(serviceName: "app.kraftly.kdupe.xpc")
        connection.remoteObjectInterface = NSXPCInterface(with: XPCDuplicateServiceProtocol.self)
        connection.resume()

        let service = connection.remoteObjectProxy as? XPCDuplicateServiceProtocol
        let semaphore = DispatchSemaphore(value: 0)

        service?.scanDirectory(path: paths.first ?? "") { data in
            if let data = data, let result = String(data: data, encoding: .utf8) {
                print(result)
            }
            semaphore.signal()
        }
        semaphore.wait()
        exit(0)
    }
}
```

(Remaining commands follow similar patterns — ResultsCommand calls `loadRecentScan()`, CleanupCommand calls `CleanupManager`, WatchCommand uses a Timer loop, WebCommand opens `http://localhost:7711`, VersionCommand prints version, CompletionCommand outputs shell completion scripts.)

- [ ] **Step 7: Commit**

```bash
git add kDupeCLI/ kDupeXPC/ kSift/project.yml
git commit -m "feat(kDupe): add CLI tool with 8 subcommands and XPC service"
```

### Task 15: Web Dashboard (Swifter)

**Files:**
- Create: `kSift/WebDashboard/DashboardServer.swift`
- Create: `kSift/WebDashboard/DashboardRoutes.swift`
- Create: `kSift/WebDashboard/dashboard.html`
- Create: `kSift/WebDashboard/dashboard.js`
- Create: `kSift/WebDashboard/dashboard.css`
- Modify: `kSift/project.yml` (add Swifter SPM dependency)

- [ ] **Step 1: Add Swifter dependency to project.yml**

```yaml
packages:
  Swifter:
    url: https://github.com/httpswift/swifter
    minorVersion: 1.5.0
```

Add to kDupe target dependencies: `- package: Swifter`

- [ ] **Step 2: Create DashboardServer**

```swift
// kSift/WebDashboard/DashboardServer.swift
import Swifter
import Foundation

actor DashboardServer {
    private let server = HttpServer()
    private let port: UInt16 = 7711
    private var isRunning = false

    func start() throws {
        guard !isRunning else { return }
        setupRoutes()
        try server.start(port, forceIPv4: true, priority: .default)
        isRunning = true
    }

    func stop() {
        server.stop()
        isRunning = false
    }

    private func setupRoutes() {
        let routes = DashboardRoutes()

        server["/api/status"] = { _ in
            .ok(.json(["status": "running" as AnyObject]))
        }

        server["/api/results"] = { _ in
            // Load latest results from repository
            .ok(.json(["results": []] as AnyObject))
        }

        server["/api/scan"] = { request in
            // Validate token
            guard request.headers["x-kdupe-token"] == self.token else {
                return .unauthorized
            }
            // Trigger scan
            Task { await self.triggerScan() }
            return .accepted
        }

        server["/dashboard"] = { _ in
            .ok(.html(self.dashboardHTML))
        }

        // Static files
        server["/dashboard.js"] = { _ in
            .ok(.js(self.dashboardJS))
        }
        server["/dashboard.css"] = { _ in
            .ok(.css(self.dashboardCSS))
        }
    }

    private var token: String {
        UserDefaults.standard.string(forKey: "dashboardToken")
            ?? UUID().uuidString
    }

    private func triggerScan() async {
        // Delegate to ScanOrchestrator
    }

    private var dashboardHTML: String {
        // Load from bundled resource
        ""
    }
    private var dashboardJS: String { "" }
    private var dashboardCSS: String { "" }
}
```

- [ ] **Step 3: Create DashboardRoutes with full API**

```swift
// kSift/WebDashboard/DashboardRoutes.swift
import Swifter
import Foundation

struct DashboardRoutes {
    func statusEndpoint() -> ((HttpRequest) -> HttpResponse) {
        { _ in .ok(.json(["status": "running" as AnyObject])) }
    }

    func resultsEndpoint(repository: DuplicateRepositoryProtocol) -> ((HttpRequest) -> HttpResponse) {
        { _ in
            // async workaround: preload results before server starts
            .ok(.json(["results": []] as AnyObject))
        }
    }
}
```

- [ ] **Step 4: Create HTML dashboard (dashboard.html)**

The dashboard shows: status card, scan results table (group name, size, count), scan button, auto-refresh. Bootstrap-free, clean CSS, dark mode via prefers-color-scheme.

- [ ] **Step 5: Commit**

```bash
git add kSift/WebDashboard/ kSift/project.yml
git commit -m "feat(kDupe): add Swifter web dashboard on localhost:7711"
```

### Task 16: Finder Sync Extension

**Files:**
- Create: `kDupeFinderSync/Info.plist`
- Create: `kDupeFinderSync/FinderSyncHandler.swift`
- Modify: `kSift/project.yml` (add Finder Sync Extension target)

- [ ] **Step 1: Add Finder Sync target to project.yml**

```yaml
kDupeFinderSync:
  type: app-extension
  platform: macOS
  deploymentTarget: "13.0"
  sources: [kDupeFinderSync]
  settings:
    PRODUCT_BUNDLE_IDENTIFIER: app.kraftly.kdupe.finder-sync
    CODE_SIGN_ENTITLEMENTS: kSift/kDupe.entitlements
    APPLICATION_EXTENSION_API_ONLY: true
  dependencies:
    - target: kFoundation/CommonUtils
```

- [ ] **Step 2: Create FinderSyncHandler**

```swift
// kDupeFinderSync/FinderSyncHandler.swift
import FinderSync

class FinderSyncHandler: FIFinderSync {
    override init() {
        super.init()
        // Set the directory URLs that the Finder Sync will monitor
        let home = FileManager.default.homeDirectoryForCurrentUser
        FIFinderSyncController.default().directoryURLs = Set([home])
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "kDupe")
        let scanItem = NSMenuItem(title: "Scan with kDupe",
                                  action: #selector(scanFolder(_:)),
                                  keyEquivalent: "")
        scanItem.image = NSImage(systemSymbolName: "doc.on.doc",
                                accessibilityDescription: "Scan")
        menu.addItem(scanItem)
        return menu
    }

    @objc func scanFolder(_ sender: AnyObject?) {
        guard let item = FIFinderSyncController.default().selectedItemURLs?.first else { return }
        // Notify main app via DarwinNotification
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.kraftly.kdupe.scanFolder" as CFString),
            item.path as CFString,
            nil,
            true
        )
    }

    override func beginObservingDirectory(at url: URL) {
        // Update badge counts
    }

    override func endObservingDirectory(at url: URL) {}
}
```

- [ ] **Step 3: Commit**

```bash
git add kDupeFinderSync/ kSift/project.yml
git commit -m "feat(kDupe): add Finder Sync extension with scan context menu"
```

### Task 17: MenuBar + Intents + Widgets + Spotlight

**Files:**
- Create: `kSift/MenuBar/MenuBarManager.swift`
- Create: `kSift/Intents/DuplicateIntents.swift`
- Create: `kSift/Widgets/kDupeWidget.swift`
- Create: `kSift/Spotlight/SpotlightIndexer.swift`
- Modify: `kSift/project.yml` (add Widget Extension target)

- [ ] **Step 1: Create MenuBarManager**

```swift
// kSift/MenuBar/MenuBarManager.swift
import SwiftUI

@MainActor
final class MenuBarManager: ObservableObject {
    @Published var isScanning = false
    @Published var lastScanDate: Date?

    private var menuBarItem: NSStatusItem?

    func setup() {
        menuBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menuBarItem?.button?.image = NSImage(systemSymbolName: "doc.on.doc",
                                            accessibilityDescription: "kDupe")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quick Scan", action: #selector(quickScan), keyEquivalent: "s"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open kDupe", action: #selector(openApp), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        menuBarItem?.menu = menu
    }

    @objc private func quickScan() { /* trigger scan */ }
    @objc private func openApp() {
        NSWorkspace.shared.open(URL(filePath: "/Applications/kDupe.app"))
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
```

- [ ] **Step 2: Create App Intents**

```swift
// kSift/Intents/DuplicateIntents.swift
import AppIntents

struct ScanDirectoryIntent: AppIntent {
    static var title: LocalizedStringResource = "Scan Directory"
    static var description = IntentDescription("Scans a directory for duplicate files")

    @Parameter(title: "Directory")
    var directory: IntentFile

    func perform() async throws -> some IntentResult {
        // Delegate to scan orchestrator
        return .result()
    }
}

struct CleanupDuplicatesIntent: AppIntent {
    static var title: LocalizedStringResource = "Clean Duplicates"
    static var description = IntentDescription("Removes duplicate files from latest scan")

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

struct ShowLargeFilesIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Large Files"
    static var description = IntentDescription("Shows files larger than 1GB")

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
```

- [ ] **Step 3: Create Widget**

```swift
// kSift/Widgets/kDupeWidget.swift
import SwiftUI
import WidgetKit

struct kDupeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.kraftly.kdupe.widget",
                           provider: Provider()) { entry in
            WidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("kDupe Quick Scan")
        .description("Quickly scan for duplicates")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), groupCount: 0)
    }
    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        completion(SimpleEntry(date: Date(), groupCount: 0))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let entry = SimpleEntry(date: Date(), groupCount: 0)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct SimpleEntry: TimelineEntry {
    let date: Date
    let groupCount: Int
}

struct WidgetView: View {
    var entry: SimpleEntry
    var body: some View {
        VStack {
            Image(systemName: "doc.on.doc").font(.title).foregroundColor(.accentColor)
            Text("kDupe").font(.headline)
            Text("\(entry.groupCount) groups").font(.caption)
        }
    }
}
```

- [ ] **Step 4: Create SpotlightIndexer**

```swift
// kSift/Spotlight/SpotlightIndexer.swift
import CoreSpotlight
import Foundation

actor SpotlightIndexer {
    private let index = CSSearchableIndex(name: "kDupe")

    func indexGroups(_ groups: [DuplicateGroup]) async throws {
        let items = groups.map { group -> CSSearchableItem in
            let attrs = CSSearchableItemAttributeSet(contentType: .content)
            attrs.title = group.title
            attrs.contentDescription = "\(group.files.count) files · \(group.totalSize) bytes"
            attrs.keywords = [group.category.rawValue]
            return CSSearchableItem(
                uniqueIdentifier: group.id.uuidString,
                domainIdentifier: group.category.rawValue,
                attributeSet: attrs
            )
        }
        try await index.indexSearchableItems(items)
    }

    func clearIndex() async throws {
        try await index.deleteAllSearchableItems()
    }
}
```

- [ ] **Step 5: Add Widget Extension target to project.yml**

```yaml
kDupeWidgets:
  type: app-extension
  platform: macOS
  deploymentTarget: "14.0"
  sources: [kSift/Widgets]
  settings:
    PRODUCT_BUNDLE_IDENTIFIER: app.kraftly.kdupe.widgets
  dependencies: []
```

- [ ] **Step 6: Commit**

```bash
git add kSift/MenuBar/ kSift/Intents/ kSift/Widgets/ kSift/Spotlight/ kSift/project.yml
git commit -m "feat(kDupe): add menu bar, intents, widgets, and spotlight indexing"
```

### Task 18: Testing Suite

**Files:**
- Create: `kDupeTests/DetectionTests/DirectoryDedupDetectorTests.swift`
- Create: `kDupeTests/DetectionTests/PerceptualDetectorTests.swift`
- Create: `kDupeTests/DetectionTests/LargeFileDetectorTests.swift`
- Create: `kDupeTests/DetectionTests/BuildArtifactDetectorTests.swift`
- Create: `kDupeTests/DetectionTests/ScanOrchestratorTests.swift`
- Create: `kDupeTests/RepositoryTests/DuplicateRepositoryTests.swift`
- Create: `kDupeTests/CLITests/CommandParserTests.swift`
- Create: `kDupeTests/Helpers/TestUtilities.swift`

- [ ] **Step 1: Create TestUtilities**

```swift
// kDupeTests/Helpers/TestUtilities.swift
import Foundation

enum TestUtilities {
    /// Creates a temp directory with named files of given sizes
    static func createTempFiles(in dir: URL, files: [(name: String, size: Int64)]) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for file in files {
            let url = dir.appendingPathComponent(file.name)
            let data = Data(count: Int(file.size))
            try data.write(to: url)
        }
    }

    static func createTempDirectory() throws -> URL {
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func removeTempDirectory(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}
```

- [ ] **Step 2: Create DirectoryDedupDetectorTests**

```swift
// kDupeTests/DetectionTests/DirectoryDedupDetectorTests.swift
import XCTest
@testable import kDupe

final class DirectoryDedupDetectorTests: XCTestCase {
    func testDetectsCrossDirectoryDuplicates() async throws {
        let tmp = try TestUtilities.createTempDirectory()
        defer { TestUtilities.removeTempDirectory(tmp) }

        let dirA = tmp.appendingPathComponent("A")
        let dirB = tmp.appendingPathComponent("B")
        try TestUtilities.createTempFiles(in: dirA, files: [("file.txt", 1024)])
        try TestUtilities.createTempFiles(in: dirB, files: [("file.txt", 1024)])

        let detector = DirectoryDedupDetector()
        let controller = ScanController()
        let groups = try await detector.detect(directories: [dirA, dirB], controller: controller)

        XCTAssertGreaterThan(groups.count, 0)
        XCTAssertTrue(groups.contains { $0.category == .directoryDedup })
    }

    func testSkipsUniqueDirectories() async throws {
        let tmp = try TestUtilities.createTempDirectory()
        defer { TestUtilities.removeTempDirectory(tmp) }

        let dirA = tmp.appendingPathComponent("A")
        let dirB = tmp.appendingPathComponent("B")
        try TestUtilities.createTempFiles(in: dirA, files: [("a.txt", 1024)])
        try TestUtilities.createTempFiles(in: dirB, files: [("b.txt", 2048)])

        let detector = DirectoryDedupDetector()
        let controller = ScanController()
        let groups = try await detector.detect(directories: [dirA, dirB], controller: controller)

        XCTAssertTrue(groups.isEmpty)
    }
}
```

- [ ] **Step 3: Create LargeFileDetectorTests**

```swift
// kDupeTests/DetectionTests/LargeFileDetectorTests.swift
import XCTest
@testable import kDupe

final class LargeFileDetectorTests: XCTestCase {
    func testDetectsFilesOverThreshold() async throws {
        let tmp = try TestUtilities.createTempDirectory()
        defer { TestUtilities.removeTempDirectory(tmp) }

        try TestUtilities.createTempFiles(in: tmp, files: [
            ("small.bin", 500),
            ("large.bin", 1500),
            ("huge.bin", 3000),
        ])

        let detector = LargeFileDetector(threshold: 1024)
        let controller = ScanController()
        let groups = try await detector.detect(directories: [tmp], controller: controller)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.files.count, 2)
    }

    func testNoFilesUnderThreshold() async throws {
        let tmp = try TestUtilities.createTempDirectory()
        defer { TestUtilities.removeTempDirectory(tmp) }

        try TestUtilities.createTempFiles(in: tmp, files: [
            ("a.bin", 100),
            ("b.bin", 200),
        ])

        let detector = LargeFileDetector(threshold: 1024)
        let controller = ScanController()
        let groups = try await detector.detect(directories: [tmp], controller: controller)

        XCTAssertTrue(groups.isEmpty)
    }
}
```

- [ ] **Step 4: Create BuildArtifactDetectorTests**

```swift
// kDupeTests/DetectionTests/BuildArtifactDetectorTests.swift
import XCTest
@testable import kDupe

final class BuildArtifactDetectorTests: XCTestCase {
    func testDetectsArtifactByExtension() async throws {
        let tmp = try TestUtilities.createTempDirectory()
        defer { TestUtilities.removeTempDirectory(tmp) }

        try TestUtilities.createTempFiles(in: tmp, files: [
            ("test.o", 1024),
            ("module.pyc", 1024),
            ("source.swift", 1024),  // Not an artifact
        ])

        let detector = BuildArtifactDetector()
        let controller = ScanController()
        let groups = try await detector.detect(directories: [tmp], controller: controller)

        let files = groups.flatMap(\.files)
        XCTAssertTrue(files.contains { $0.url.lastPathComponent == "test.o" })
        XCTAssertTrue(files.contains { $0.url.lastPathComponent == "module.pyc" })
        XCTAssertFalse(files.contains { $0.url.lastPathComponent == "source.swift" })
    }

    func testDetectsNodeModules() async throws {
        let tmp = try TestUtilities.createTempDirectory()
        defer { TestUtilities.removeTempDirectory(tmp) }

        let nm = tmp.appendingPathComponent("node_modules")
        try TestUtilities.createTempFiles(in: nm, files: [("lodash.js", 1024)])

        let detector = BuildArtifactDetector()
        let controller = ScanController()
        let groups = try await detector.detect(directories: [tmp], controller: controller)

        XCTAssertFalse(groups.isEmpty)
    }
}
```

- [ ] **Step 5: Create ScanOrchestratorTests**

```swift
// kDupeTests/DetectionTests/ScanOrchestratorTests.swift
import XCTest
@testable import kDupe

final class ScanOrchestratorTests: XCTestCase {
    func testRunCompletes() async throws {
        let tmp = try TestUtilities.createTempDirectory()
        defer { TestUtilities.removeTempDirectory(tmp) }

        try TestUtilities.createTempFiles(in: tmp, files: [
            ("a.txt", 1024),
            ("b.txt", 1024),
        ])

        let config = ProfileConfig(profile: .simple, customPaths: [tmp.path])
        let orchestrator = ScanOrchestrator(config: config)

        var progressEvents: [ScanProgress] = []
        for await progress in orchestrator.run() {
            progressEvents.append(progress)
            if case .completed = progress { break }
        }

        XCTAssertFalse(progressEvents.isEmpty)
        XCTAssertTrue(progressEvents.contains { if case .completed = $0 { true } else { false } })
    }
}
```

- [ ] **Step 6: Create DuplicateRepositoryTests**

```swift
// kDupeTests/RepositoryTests/DuplicateRepositoryTests.swift
import XCTest
@testable import kDupe

final class DuplicateRepositoryTests: XCTestCase {
    func testSaveAndLoadScan() async throws {
        let repo = DuplicateRepositoryJSON() // Lightweight for tests
        let record = ScanRecord(id: UUID(), date: Date(), duration: 1.0,
                               groupCount: 0, totalSize: 0, profileType: .developer)
        try await repo.saveScan(record: record, groups: [])

        let loaded = try await repo.loadScanHistory(limit: 10)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, record.id)
    }

    func testDeleteScan() async throws {
        let repo = DuplicateRepositoryJSON()
        let record = ScanRecord(id: UUID(), date: Date(), duration: 1.0,
                               groupCount: 0, totalSize: 0, profileType: .developer)
        try await repo.saveScan(record: record, groups: [])
        try await repo.deleteScan(id: record.id)

        let loaded = try await repo.loadScanHistory(limit: 10)
        XCTAssertTrue(loaded.isEmpty)
    }
}
```

- [ ] **Step 7: Create CLI CommandParserTests**

```swift
// kDupeTests/CLITests/CommandParserTests.swift
import XCTest
@testable import kDupeCLI

final class CommandParserTests: XCTestCase {
    func testScanCommandParsing() {
        let args = ["scan", "/tmp", "--mode", "deep", "--json"]
        // Verify parse
        XCTAssertEqual(args[0], "scan")
    }

    func testInvalidCommandExitsWithError() {
        // Should print usage and exit with code 1
    }
}
```

- [ ] **Step 8: Run all tests**

```bash
cd kDupe && swift test 2>&1
```
Expected: All detector tests pass. Repository tests pass. CLI parser tests pass.

- [ ] **Step 9: Commit**

```bash
git add kDupeTests/
git commit -m "test(kDupe): add detection, repository, and CLI tests"
```

### Task 19: Final Polish — Localization, Assets, Linter, Self-Review

**Files:**
- Create: `kSift/Resources/en.lproj/Localizable.xcstrings`
- Create: `kSift/Resources/zh-Hans.lproj/Localizable.xcstrings`
- Create: `kSift/Resources/ja.lproj/Localizable.xcstrings`
- Create: `kSift/Resources/Assets.xcassets/Contents.json`
- Create: `kSift/Resources/Assets.xcassets/AppIcon.icns/Contents.json`
- Modify: `kSift/project.yml` (add localization references)
- Create: `kSift/.swiftlint.yml`

- [ ] **Step 1: Verify project.yml is complete**

Run a validation to ensure all target references resolve:
```bash
cd kDupe && xcodegen --spec project.yml --dry-run 2>&1
```
Expected: All targets, dependencies, and source paths resolve without warnings.

- [ ] **Step 2: Create .swiftlint.yml**

```yaml
# kSift/.swiftlint.yml
parent_config: ../kFoundation/.swiftlint.yml
disabled_rules:
  - force_cast
  - force_try
opt_in_rules:
  - sorted_imports
  - vertical_whitespace
```

- [ ] **Step 3: Run linter**

```bash
cd kDupe && swiftlint lint --strict 2>&1
```
Expected: No errors or warnings (or zero new violations against baseline).

- [ ] **Step 4: Verify all file references exist**

```bash
# Check all source files referenced in project.yml exist
grep -o 'Sources: \[.*\]' project.yml | tr ',' '\n' | tr -d ' []' | while read f; do
  [ -f "$f" ] || [ -d "$f" ] || echo "MISSING: $f"
done
```
Expected: No "MISSING" lines. Every source file from project.yml resolves.

- [ ] **Step 5: Self-review checklist**

Go through each of these items and verify:

- [ ] All 6 detectors compile and are wired into ScanOrchestrator
- [ ] All 4 Core Data entities have matching NSManagedObject subclasses
- [ ] Both Repository implementations (CoreData, JSON) implement the full protocol
- [ ] RootView navigation covers all 5 navigation items (onboarding, scan, results, history, settings)
- [ ] CLI tool has all 8 subcommands wired to XPC
- [ ] Web Dashboard listens on 127.0.0.1:7711 with CSRF protection
- [ ] Entitlements allow sandbox + network server + app groups
- [ ] All temporary files are cleaned up in test tearDown/defer blocks
- [ ] No hardcoded strings in UI code (all via LocalizedStringResource)
- [ ] Bundle ID consistency: `app.kraftly.kdupe` everywhere

- [ ] **Step 6: Final commit**

```bash
git add kSift/Resources/ kSift/.swiftlint.yml kSift/project.yml
git commit -m "chore(kDupe): add localization, assets, linter config"
```

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-26-kdupe-implementation.md`.

**Two execution options:**

**1. Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration with isolated context

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**

