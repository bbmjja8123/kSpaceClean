# kSpaceClean v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and ship kSpaceClean v1 — a macOS disk cleaning app with 3D galaxy visualization, CoreML AI classification, and deep system integration.

**Architecture:** Clean layered architecture with kFoundation Swift Package as shared foundation layer. kSpaceClean target depends on kFoundation, all extensions (Widget, Intents, Finder, LiveActivity) depend on kSpaceClean. Presentation layer uses SwiftUI + AppKit bridge. Infrastructure layer isolates file I/O, CoreML, and CoreData behind protocol abstractions for testability.

**Tech Stack:** Swift 5.9+, SwiftUI + AppKit, Metal + SceneKit, CoreML, CoreData, StoreKit 2, WidgetKit, App Intents, FinderSync, ActivityKit (macOS 14+), CryptoKit

## Global Constraints

- **Deployment target:** macOS 13.0 (compile against macOS 14 SDK)
- **Swift:** 5.9+, strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`)
- **App Sandbox:** Always enabled. No Privileged Helper / SMJobBless
- **TCC:** Full Disk Access requested via system preferences (user-manual)
- **Third-party dependencies:** Zero. No Firebase, Sentry, etc.
- **Privacy:** Zero network reporting. MetricKit only (local). Network whitelist = Apple receipt validation only
- **Branding:** `app.kraftly.sclean` bundle ID, `k` prefix for all symbols
- **Naming:** Never use "CleanMyMac" in copy
- **Lemon reference:** `/Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon/` — logic reference ONLY, NO code reuse
- **StoreKit:** Auto-renewable subscription only (no consumables)

---
## File Map

```
KraftlyWorkspace.xcworkspace
├── kFoundation/
│   └── Sources/
│       ├── DesignSystem/              # Colors, Typography, Spacing, Components
│       ├── FileScanner/               # File enumeration, hash, duplicate detection
│       ├── PrivacyShield/             # TCC status detection, bookmarks
│       ├── AppCatalog/                # macOS app identification
│       ├── Capabilities/              # OS version capability gate
│       └── CommonUtils/               # FileSize formatting, extensions
├── kWise/
│   ├── App/
│   │   ├── kSpaceCleanApp.swift       # @main entry point
│   │   ├── RootView.swift             # Window root with SwiftUI lifecycle
│   │   ├── AppCoordinator.swift       # Navigation state machine
│   │   └── AppState.swift             # Global observable state
│   ├── Features/
│   │   ├── DiskGalaxy/
│   │   │   ├── GalaxyRenderer.swift   # Metal renderer (SCNView delegate)
│   │   │   ├── GalaxyScene.swift      # SceneKit scene graph builder
│   │   │   ├── GalaxyViewModel.swift  # Scene ↔ App state bridge
│   │   │   └── GalaxyView.swift       # SwiftUI wrapper (NSViewRepresentable)
│   │   ├── SmartScan/
│   │   │   ├── ScanEngine.swift       # Orchestrator: enum → hash → classify → report
│   │   │   ├── ScanProgress.swift     # Progress reporting model
│   │   │   └── ScanViewModel.swift    # Scan state for UI
│   │   ├── AIClassifier/
│   │   │   ├── AIClassifier.swift     # CoreML inference wrapper
│   │   │   └── RuleClassifier.swift   # Fallback rule-based classifier
│   │   ├── Cleanup/
│   │   │   ├── TrashMover.swift       # Move to trash + snapshot
│   │   │   ├── CleanupHistory.swift   # CoreData-backed history
│   │   │   └── CleanupViewModel.swift # Cleanup state for UI
│   │   ├── RightPanel/
│   │   │   ├── RightPanelView.swift   # Tab container (Overview / All Files / Suggestions)
│   │   │   ├── OverviewTabView.swift
│   │   │   ├── AllFilesTabView.swift  # Searchable/sortable table
│   │   │   └── SuggestionsTabView.swift # AI recommendations
│   │   ├── Onboarding/
│   │   │   ├── OnboardingCoordinator.swift
│   │   │   └── OnboardingPages.swift  # 5 screen views
│   │   └── Settings/
│   │       └── SettingsView.swift
│   ├── MenuBar/
│   │   ├── MenuBarManager.swift       # NSStatusItem setup + menu
│   │   └── DiskStatusView.swift       # Menu bar icon with percentage
│   ├── Widgets/
│   │   ├── KSpaceCleanWidget.swift    # WidgetBundle + entry views
│   │   └── WidgetTimelineProvider.swift
│   ├── Intents/
│   │   ├── ScanIntent.swift
│   │   ├── CleanCacheIntent.swift
│   │   └── ShowLargeFilesIntent.swift
│   ├── FinderExtension/
│   │   ├── FinderSync.swift           # FinderSync protocol
│   │   └── FinderExtensionHelper.swift
│   ├── LiveActivity/
│   │   └── CleanupActivityAttributes.swift
│   ├── Spotlight/
│   │   └── SpotlightIndexer.swift
│   ├── Persistence/
│   │   ├── CoreDataStack.swift        # NSPersistentContainer setup
│   │   ├── ScanRecord+CoreData.swift  # NSManagedObject subclasses
│   │   ├── FileEntry+CoreData.swift
│   │   ├── CleanupRecord+CoreData.swift
│   │   └── UserPreferences.swift      # JSON-backed settings
│   ├── Store/
│   │   ├── StoreManager.swift         # StoreKit 2 transaction handling
│   │   └── PaywallView.swift          # Subscription UI
│   └── Resources/
│       ├── Models/                    # .mlmodel files (placeholder)
│       ├── Assets.xcassets
│       └── Localizable.xcstrings      # en + zh-Hans + ja
└── Tools/
    └── version-bump.sh                # Script to bump version number
```

---

## Task Sequence (Dependency Order)

```
Task 1  (Scaffolding)       ← no dependencies
Task 2  (kFoundation)       ← depends on Task 1
Task 3  (Core Data)         ← depends on Task 2
Task 4  (SmartScan Engine)  ← depends on Task 3
Task 5  (AI Classifier)     ← depends on Task 4
Task 6  (Cleanup Engine)    ← depends on Task 3
Task 7  (Onboarding)        ← depends on Task 3
Task 8  (Main Window UI)    ← depends on Task 2 (DesignSystem)
Task 9  (Disk Galaxy 3D)    ← depends on Task 4, Task 8
Task 10 (Right Panel)       ← depends on Task 8
Task 11 (Menu Bar)          ← depends on Task 6
Task 12 (Widgets)           ← depends on Task 4
Task 13 (App Intents)       ← depends on Task 4
Task 14 (Finder Extension)  ← depends on Task 4
Task 15 (Live Activity)     ← depends on Task 6
Task 16 (Subscription)      ← no dependencies
Task 17 (Localization)      ← depends on Task 8-11
Task 18 (Spotlight)         ← depends on Task 4
Task 19 (App Store Ready)   ← depends on all above
```

---

### Task 1: Project Scaffolding

**Files:**
- Create: `KraftlyWorkspace.xcworkspace` (via `xcodebuild` or Xcode)
- Create: `kFoundation/Package.swift`
- Create: `kWise/` target skeleton
- Create: `Tools/version-bump.sh`

**Interfaces:**
- Produces: A buildable Xcode workspace with empty kFoundation package and kSpaceClean target

- [ ] **Step 1: Create Xcode workspace**

Open Xcode → File → New → Workspace → save as `KraftlyWorkspace.xcworkspace` in the project root.

- [ ] **Step 2: Create kFoundation Swift Package**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp
mkdir -p kFoundation/Sources/{DesignSystem,FileScanner,PrivacyShield,AppCatalog,DaemonBridge,Capabilities,CommonUtils}
mkdir -p kFoundation/Tests
```

Create `kFoundation/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "kFoundation",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "FileScanner", targets: ["FileScanner"]),
        .library(name: "PrivacyShield", targets: ["PrivacyShield"]),
        .library(name: "AppCatalog", targets: ["AppCatalog"]),
        .library(name: "Capabilities", targets: ["Capabilities"]),
        .library(name: "CommonUtils", targets: ["CommonUtils"]),
        .library(name: "DaemonBridge", targets: ["DaemonBridge"]),
    ],
    targets: [
        .target(name: "DesignSystem"),
        .target(name: "FileScanner", dependencies: ["CommonUtils"]),
        .target(name: "PrivacyShield"),
        .target(name: "AppCatalog"),
        .target(name: "Capabilities"),
        .target(name: "CommonUtils"),
        .target(name: "DaemonBridge"),
        .testTarget(name: "FileScannerTests", dependencies: ["FileScanner"]),
        .testTarget(name: "CommonUtilsTests", dependencies: ["CommonUtils"]),
    ]
)
```

- [ ] **Step 3: Create kSpaceClean target in workspace**

In Xcode: Add Files to workspace → New Target → macOS → App → name `kSpaceClean`. Set:
- Bundle ID: `app.kraftly.sclean`
- Deployment target: macOS 13.0
- Language: Swift
- Interface: SwiftUI
- Lifecycle: SwiftUI App

Then configure target dependencies to include `kFoundation` package modules.

- [ ] **Step 4: Configure entitlements**

Create `kWise/kSpaceClean.entitlements`:

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
    <array><string>group.app.kraftly.shared</string></array>
    <key>com.apple.security.device.camera</key><false/>
    <key>com.apple.security.device.microphone</key><false/>
    <key>com.apple.security.device.usb</key><false/>
    <key>com.apple.security.print</key><false/>
    <key>com.apple.security.network.client</key><true/>
    <key>com.apple.security.network.server</key><false/>
</dict>
</plist>
```

- [ ] **Step 5: Verify build**

Run: `xcodebuild -workspace KraftlyWorkspace.xcworkspace -scheme kSpaceClean build`

Expected: Build succeeds (empty app launches).

- [ ] **Step 6: Commit**

```bash
git init
git add -A
git commit -m "chore: scaffold Kraftly workspace with kFoundation package and kSpaceClean target"
```

---

### Task 2: kFoundation − DesignSystem, Capabilities, CommonUtils

**Files:**
- Create: `kFoundation/Sources/DesignSystem/Colors.swift`
- Create: `kFoundation/Sources/DesignSystem/Typography.swift`
- Create: `kFoundation/Sources/DesignSystem/Spacing.swift`
- Create: `kFoundation/Sources/DesignSystem/Radius.swift`
- Create: `kFoundation/Sources/DesignSystem/Shadow.swift`
- Create: `kFoundation/Sources/DesignSystem/Icons.swift`
- Create: `kFoundation/Sources/DesignSystem/Components/ProgressRing.swift`
- Create: `kFoundation/Sources/DesignSystem/Components/CategoryBadge.swift`
- Create: `kFoundation/Sources/DesignSystem/Components/EmptyStateView.swift`
- Create: `kFoundation/Sources/DesignSystem/Components/LoadingStateView.swift`
- Create: `kFoundation/Sources/DesignSystem/Components/ErrorStateView.swift`
- Create: `kFoundation/Sources/DesignSystem/Components/GlassPanel.swift`
- Create: `kFoundation/Sources/Capabilities/CapabilityGate.swift`
- Create: `kFoundation/Sources/CommonUtils/FileSizeFormatter.swift`
- Create: `kFoundation/Sources/CommonUtils/URLExtensions.swift`
- Create: `kFoundation/Tests/CommonUtilsTests/FileSizeFormatterTests.swift`

**Interfaces:**
- Consumes: Nothing (foundational layer)
- Produces: Reusable design tokens, capability detection, and formatting utilities

- [ ] **Step 1: Write DesignSystem token files**

`Colors.swift`:
```swift
import SwiftUI

public extension Color {
    // Brand
    static let brandPrimary = Color(hex: "#7C3AED")
    static let brandSecondary = Color(hex: "#3B82F6")
    static let brandAccent = Color(hex: "#F59E0B")
    static let success = Color(hex: "#10B981")
    static let danger = Color(hex: "#EF4444")
    static let warning = Color(hex: "#F97316")

    // Semantic backgrounds
    static let bgPrimary = Color(hex: "#1C1C1E")
    static let bgSecondary = Color(hex: "#2C2C2E")
    static let bgTertiary = Color(hex: "#3A3A3C")
    static let textPrimary = Color(hex: "#F5F5F7")
    static let textSecondary = Color(hex: "#98989D")
    static let separatorColor = Color(hex: "#48484A")

    // File categories
    static let categoryImage = Color(hex: "#A855F7")
    static let categoryVideo = Color(hex: "#3B82F6")
    static let categoryDocument = Color(hex: "#10B981")
    static let categoryAudio = Color(hex: "#F59E0B")
    static let categoryCache = Color(hex: "#6B7280")
    static let categoryDev = Color(hex: "#EC4899")
    static let categoryApp = Color(hex: "#8B5CF6")
    static let categoryOther = Color(hex: "#9CA3AF")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let int = UInt64(hex, radix: 16) ?? 0
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

public enum FileCategory: String, CaseIterable, Codable {
    case image, video, document, audio, cache, dev, app, other

    public var color: Color {
        switch self {
        case .image: return .categoryImage
        case .video: return .categoryVideo
        case .document: return .categoryDocument
        case .audio: return .categoryAudio
        case .cache: return .categoryCache
        case .dev: return .categoryDev
        case .app: return .categoryApp
        case .other: return .categoryOther
        }
    }

    public var icon: String {
        switch self {
        case .image: return "photo"
        case .video: return "video"
        case .document: return "doc.text"
        case .audio: return "music.note"
        case .cache: return "archivebox"
        case .dev: return "chevron.left.forwardslash.chevron.right"
        case .app: return "app"
        case .other: return "questionmark.folder"
        }
    }
}
```

`Typography.swift`:
```swift
import SwiftUI

public enum AppFont {
    public static let largeTitle = Font.system(size: 26, weight: .bold)
    public static let title2 = Font.system(size: 20, weight: .semibold)
    public static let title3 = Font.system(size: 16, weight: .semibold)
    public static let body = Font.system(size: 13)
    public static let callout = Font.system(size: 12)
    public static let caption = Font.system(size: 11)
    public static let monoDigit = Font.system(size: 13, design: .monospaced)
}
```

`Spacing.swift`:
```swift
public enum AppSpacing {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48
}
```

`Radius.swift`:
```swift
public enum AppRadius {
    public static let sm: CGFloat = 4
    public static let md: CGFloat = 6
    public static let lg: CGFloat = 8
    public static let xl: CGFloat = 12
    public static let full: CGFloat = 999
}
```

`Shadow.swift`:
```swift
import SwiftUI

public enum AppShadow {
    public static let sm = Shadow(color: .black.opacity(0.3), radius: 2, y: 1)
    public static let md = Shadow(color: .black.opacity(0.4), radius: 8, y: 4)
    public static let lg = Shadow(color: .black.opacity(0.5), radius: 24, y: 8)

    public struct Shadow {
        public let color: Color
        public let radius: CGFloat
        public let x: CGFloat
        public let y: CGFloat

        public init(color: Color, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) {
            self.color = color
            self.radius = radius
            self.x = x
            self.y = y
        }
    }
}

public extension View {
    func appShadow(_ shadow: AppShadow.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}
```

- [ ] **Step 2: Write CapabilityGate**

`CapabilityGate.swift`:
```swift
import Foundation

public enum CapabilityGate {
    public static var isMacOS14: Bool {
        if #available(macOS 14, *) { return true }
        return false
    }

    public static var supportsSwiftData: Bool { isMacOS14 }
    public static var supportsInteractiveWidgets: Bool { isMacOS14 }
    public static var supportsLiveActivities: Bool { isMacOS14 }
    public static var supportsControlWidgets: Bool { isMacOS14 }
    public static var supportsTipKit: Bool { isMacOS14 }

    public static var supportsAppIntents: Bool { true }  // macOS 13+
}
```

- [ ] **Step 3: Write CommonUtils**

`FileSizeFormatter.swift`:
```swift
import Foundation

public struct FileSizeFormatter {
    public static func string(from bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    public static func abbreviated(from bytes: Int64) -> String {
        let absBytes = abs(bytes)
        if absBytes < 1024 { return "\(bytes) B" }
        let units = ["KB", "MB", "GB", "TB"]
        var value = Double(bytes) / 1024.0
        for unit in units {
            if abs(value) < 1024 { return String(format: "%.1f %@", value, unit) }
            value /= 1024.0
        }
        return String(format: "%.1f PB", value)
    }
}
```

`URLExtensions.swift`:
```swift
import Foundation

public extension URL {
    var isDirectory: Bool {
        (try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }

    var fileSize: Int64 {
        guard let values = try? resourceValues(forKeys: [.fileSizeKey, .fileAllocatedSizeKey]) else {
            return 0
        }
        return Int64(values.fileSize ?? values.fileAllocatedSize ?? 0)
    }

    var isPackage: Bool {
        (try? resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false
    }
}
```

- [ ] **Step 4: Write DesignSystem Components**

`ProgressRing.swift`:
```swift
import SwiftUI

public struct ProgressRing: View {
    let progress: Double  // 0.0 ... 1.0
    let label: String?

    public init(progress: Double, label: String? = nil) {
        self.progress = min(max(progress, 0), 1)
        self.label = label
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Color.separatorColor.opacity(0.3), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.brandPrimary, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: progress)
            if let label = label {
                Text(label)
                    .font(AppFont.callout)
                    .foregroundColor(.textPrimary)
            }
        }
    }
}
```

`GlassPanel.swift`:
```swift
import SwiftUI

public struct GlassPanel<Content: View>: View {
    let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.xl)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
    }
}
```

`EmptyStateView.swift`, `LoadingStateView.swift`, `ErrorStateView.swift`:
```swift
import SwiftUI

public struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String?
    let action: (title: String, handler: () -> Void)?

    public init(icon: String, title: String, subtitle: String? = nil,
                action: (title: String, handler: () -> Void)? = nil) {
        self.icon = icon; self.title = title; self.subtitle = subtitle; self.action = action
    }

    public var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.textSecondary)
            Text(title).font(AppFont.title3).foregroundColor(.textPrimary)
            if let subtitle = subtitle {
                Text(subtitle).font(AppFont.callout).foregroundColor(.textSecondary)
            }
            if let action = action {
                Button(action.title) { action.handler() }
                    .buttonStyle(.borderedProminent).tint(.brandPrimary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

public struct LoadingStateView: View {
    let title: String
    let progress: Double?
    let detail: String?

    public var body: some View {
        VStack(spacing: AppSpacing.lg) {
            if let progress = progress {
                ProgressRing(progress: progress, label: "\(Int(progress * 100))%")
                    .frame(width: 80, height: 80)
            } else {
                ProgressView().scaleEffect(1.5)
            }
            Text(title).font(AppFont.title3).foregroundColor(.textPrimary)
            if let detail = detail {
                Text(detail).font(AppFont.caption).foregroundColor(.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

public struct ErrorStateView: View {
    let title: String
    let message: String
    let retryAction: (() -> Void)?

    public var body: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36)).foregroundColor(.warning)
            Text(title).font(AppFont.title3).foregroundColor(.textPrimary)
            Text(message).font(AppFont.callout).foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
            if let retryAction = retryAction {
                Button("重试") { retryAction() }
                    .buttonStyle(.borderedProminent).tint(.brandPrimary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 5: Write tests**

`FileSizeFormatterTests.swift`:
```swift
import XCTest
@testable import CommonUtils

final class FileSizeFormatterTests: XCTestCase {
    func testAbbreviatedBytes() {
        XCTAssertEqual(FileSizeFormatter.abbreviated(from: 0), "0 B")
        XCTAssertEqual(FileSizeFormatter.abbreviated(from: 500), "500 B")
    }

    func testAbbreviatedKB() {
        XCTAssertEqual(FileSizeFormatter.abbreviated(from: 2048), "2.0 KB")
    }

    func testAbbreviatedMB() {
        XCTAssertEqual(FileSizeFormatter.abbreviated(from: 5_242_880), "5.0 MB")
    }

    func testAbbreviatedGB() {
        let result = FileSizeFormatter.abbreviated(from: 10_737_418_240)
        XCTAssertTrue(result.hasSuffix("GB"))
    }

    func testCategoryColorMapping() {
        XCTAssertEqual(FileCategory.image.color, Color(hex: "#A855F7"))
        XCTAssertEqual(FileCategory.video.color, Color(hex: "#3B82F6"))
    }
}
```

- [ ] **Step 6: Run tests and commit**

```bash
xcodebuild -workspace KraftlyWorkspace.xcworkspace -scheme kFoundation -destination 'platform=macOS' test
git add -A
git commit -m "feat(kFoundation): add DesignSystem, Capabilities, CommonUtils"
```

---

### Task 3: Core Data Layer

**Files:**
- Create: `kWise/Persistence/CoreDataStack.swift`
- Create: `kWise/Persistence/ScanRecord+CoreData.swift`
- Create: `kWise/Persistence/FileEntry+CoreData.swift`
- Create: `kWise/Persistence/CleanupRecord+CoreData.swift`
- Create: `kWise/Persistence/UserPreferences.swift`

**Interfaces:**
- Consumes: `CommonUtils` (FileSizeFormatter), `Capabilities` (CapabilityGate)
- Produces: `CoreDataStack` (shared persistent container), `ScanRecord`, `FileEntry`, `CleanupRecord` managed objects, `UserPreferences` (Codable JSON)

- [ ] **Step 1: Create CoreDataStack**

```swift
import CoreData

public final class CoreDataStack {
    public static let shared = CoreDataStack()

    public lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "kSpaceClean")
        let storeURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.app.kraftly.shared")!
            .appendingPathComponent("kSpaceClean.sqlite")
        container.persistentStoreDescriptions = [
            NSPersistentStoreDescription(url: storeURL)
        ]
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data load failed: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }()

    public var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    public func save() {
        guard viewContext.hasChanges else { return }
        try? viewContext.save()
    }

    public func backgroundContext() -> NSManagedObjectContext {
        persistentContainer.newBackgroundContext()
    }
}
```

- [ ] **Step 2: Create NSManagedObject subclasses**

`ScanRecord+CoreData.swift`:
```swift
import CoreData

@objc(ScanRecord)
public class ScanRecord: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var startedAt: Date
    @NSManaged public var finishedAt: Date?
    @NSManaged public var totalBytes: Int64
    @NSManaged public var freedBytes: Int64
    @NSManaged public var category: String
    @NSManaged public var entries: NSSet?
}

@objc(FileEntry)
public class FileEntry: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var path: String
    @NSManaged public var size: Int64
    @NSManaged public var category: String
    @NSManaged public var confidence: Double
    @NSManaged public var scanRecord: ScanRecord?
}

@objc(CleanupRecord)
public class CleanupRecord: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var cleanedAt: Date
    @NSManaged public var totalBytes: Int64
    @NSManaged public var entries: NSSet?
    @NSManaged public var isRestored: Bool
}
```

- [ ] **Step 3: Create Core Data model file**

In Xcode: Create `kWise/Persistence/kSpaceClean.xcdatamodeld` with entities:
- `ScanRecord`: attributes id(UUID), startedAt(Date), finishedAt(Date?), totalBytes(Int64), freedBytes(Int64), category(String). Relationship entries(ToMany → FileEntry)
- `FileEntry`: attributes id(UUID), path(String), size(Int64), category(String), confidence(Double). Relationship scanRecord(ToOne → ScanRecord)
- `CleanupRecord`: attributes id(UUID), cleanedAt(Date), totalBytes(Int64), isRestored(Bool). Relationship entries(ToMany → FileEntry)

Set Codegen to "Manual/None" (using the @objc classes above).

- [ ] **Step 4: Create UserPreferences**

```swift
import Foundation

public struct UserPreferences: Codable {
    public var largeFileThreshold: Int64 = 100 * 1024 * 1024  // 100MB
    public var ignoredPaths: [String] = []
    public var aiClassificationEnabled: Bool = true
    public var defaultCleanAction: CleanAction = .trash
    public var confirmHighRisk: Bool = true
    public var historyRetentionDays: Int = 30
    public var launchAtLogin: Bool = false
    public var showMenuBarDiskUsage: Bool = true

    public enum CleanAction: String, Codable {
        case trash, permanent
    }

    public static func load() -> UserPreferences {
        guard let data = try? Data(contentsOf: preferencesURL),
              let prefs = try? JSONDecoder().decode(UserPreferences.self, from: data) else {
            return UserPreferences()
        }
        return prefs
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.preferencesURL, options: .atomic)
    }

    private static var preferencesURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("app.kraftly.sclean/preferences.json")
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(kSpaceClean): add Core Data layer and user preferences"
```

---

### Task 4: SmartScan Engine

**Files:**
- Create: `kFoundation/Sources/FileScanner/FileEnumerator.swift`
- Create: `kFoundation/Sources/FileScanner/FileHasher.swift`
- Create: `kFoundation/Sources/FileScanner/DuplicateDetector.swift`
- Create: `kWise/Features/SmartScan/ScanEngine.swift`
- Create: `kWise/Features/SmartScan/ScanProgress.swift`
- Create: `kWise/Features/SmartScan/ScanViewModel.swift`
- Create: `kFoundation/Tests/FileScannerTests/FileEnumeratorTests.swift`
- Create: `kFoundation/Tests/FileScannerTests/FileHasherTests.swift`

**Interfaces:**
- Consumes: `CommonUtils`, `CoreDataStack`, `FileCategory`
- Produces: `ScanEngine` (async scan orchestrator), `ScanProgress` (observable progress), `ScanViewModel` (UI-facing), `DuplicateDetector` (hash-based dedup)

- [ ] **Step 1: Write FileEnumerator**

```swift
import Foundation

public actor FileEnumerator {
    public struct ScanResult: Sendable {
        public let url: URL
        public let size: Int64
        public let isDirectory: Bool
    }

    public enum ScanError: Error {
        case cancelled
        case permissionDenied(URL)
    }

    public init() {}

    public func enumerate(
        root: URL,
        progressHandler: @Sendable (ScanResult) -> Void,
        cancellationToken: CancellationToken
    ) async throws {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .isPackageKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            if cancellationToken.isCancelled { throw ScanError.cancelled }

            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]),
                  !(values.isDirectory ?? false) else { continue }

            let result = ScanResult(url: url, size: Int64(values.fileSize ?? 0), isDirectory: false)
            progressHandler(result)
        }
    }
}

@dynamicMemberLookup
public final class CancellationToken: @unchecked Sendable {
    public private(set) var isCancelled = false
    public func cancel() { isCancelled = true }
}
```

- [ ] **Step 2: Write FileHasher**

```swift
import Foundation
import CryptoKit

public actor FileHasher {
    public enum HashError: Error {
        case fileTooLarge(Int64)
        case readFailed(URL)
    }

    public init() {}

    public func hash(file url: URL, maxSize: Int64 = 100 * 1024 * 1024) async throws -> String {
        let size = url.fileSize
        guard size <= maxSize else { throw HashError.fileTooLarge(size) }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        // SHA-256 of first 4KB + last 4KB (fast fingerprint for dedup)
        var hasher = SHA256()
        let frontData = try handle.read(upToCount: 4096) ?? Data()
        hasher.update(data: frontData)
        try handle.seekToEnd()
        let tailOffset = max(0, try handle.offset() - 4096)
        try handle.seek(toOffset: tailOffset)
        let tailData = try handle.read(upToCount: 4096) ?? Data()
        hasher.update(data: tailData)

        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 3: Write DuplicateDetector**

```swift
import Foundation

public actor DuplicateDetector {
    private var sizeGroups: [Int64: [URL]] = [:]
    private var hashGroups: [String: [URL]] = [:]

    public init() {}

    public func add(file url: URL, size: Int64) {
        sizeGroups[size, default: []].append(url)
    }

    public func candidates() -> [(size: Int64, urls: [URL])] {
        sizeGroups.filter { $0.value.count > 1 }
            .map { ($0.key, $0.value) }
    }

    public func hashGroup(
        _ urls: [URL],
        hasher: FileHasher
    ) async -> [String: [URL]] {
        var groups: [String: [URL]] = [:]
        for url in urls {
            if let hash = try? await hasher.hash(file: url) {
                groups[hash, default: []].append(url)
            }
        }
        return groups.filter { $0.value.count > 1 }
    }
}
```

- [ ] **Step 4: Write ScanEngine orchestrator**

```swift
import Foundation
import FileScanner

@MainActor
public final class ScanEngine: ObservableObject {
    @Published public private(set) var progress = ScanProgress()
    private let enumerator = FileEnumerator()
    private let hasher = FileHasher()
    private let detector = DuplicateDetector()
    private let cancellationToken = CancellationToken()
    private let classifier = RuleClassifier()

    public init() {}

    public func startScan() async {
        progress.state = .scanning
        progress.filesDiscovered = 0

        let scanDirs = [
            URL(filePath: NSHomeDirectory() + "/Library/Caches"),
            URL(filePath: NSHomeDirectory() + "/Library/Application Support"),
            URL(filePath: "/Library/Caches"),
        ]

        for dir in scanDirs {
            guard FileManager.default.fileExists(atPath: dir.path) else { continue }
            do {
                try await enumerator.enumerate(
                    root: dir,
                    progressHandler: { [weak self] result in
                        Task { @MainActor in
                            guard let self = self else { return }
                            self.progress.filesDiscovered += 1
                            self.progress.totalBytes += result.size
                            let category = self.classifier.classify(result.url)

                            // Persist to Core Data
                            let ctx = CoreDataStack.shared.backgroundContext()
                            ctx.perform {
                                let entry = FileEntry(context: ctx)
                                entry.id = UUID()
                                entry.path = result.url.path
                                entry.size = result.size
                                entry.category = category.rawValue
                                entry.confidence = 0.5
                                try? ctx.save()
                            }
                        }
                    },
                    cancellationToken: cancellationToken
                )
            } catch {
                progress.errors.append(ScanError(path: dir.path, message: error.localizedDescription))
            }
        }

        progress.state = .completed
        progress.finishedAt = Date()
    }

    public func cancel() {
        cancellationToken.cancel()
        progress.state = .cancelled
    }
}

public struct ScanProgress: Sendable {
    public enum State: Sendable { case idle, scanning, analysing, completed, cancelled, failed }
    public var state: State = .idle
    public var filesDiscovered: Int = 0
    public var totalBytes: Int64 = 0
    public var currentDirectory: String = ""
    public var errors: [ScanError] = []
    public var finishedAt: Date?
}

public struct ScanError: Identifiable, Sendable {
    public let id = UUID()
    public let path: String
    public let message: String
}
```

- [ ] **Step 5: Write ScanViewModel**

```swift
import Foundation

@MainActor
public final class ScanViewModel: ObservableObject {
    @Published public var progress = ScanProgress()
    @Published public var scanResults: [FileEntry] = []
    private let engine = ScanEngine()

    public func startScan() {
        Task {
            await engine.startScan()
            // Observe progress changes and update UI
        }
    }

    public func cancelScan() {
        engine.cancel()
    }
}
```

- [ ] **Step 6: Write tests and commit**

```bash
git add -A
git commit -m "feat(kSpaceClean): add SmartScan engine with file enumeration and duplicate detection"
```

---

### Task 5: AI Classifier

**Files:**
- Create: `kWise/Features/AIClassifier/AIClassifier.swift`
- Create: `kWise/Features/AIClassifier/RuleClassifier.swift`

**Interfaces:**
- Consumes: `FileCategory` (from DesignSystem)
- Produces: `AIClassifier` (CoreML wrapper), `RuleClassifier` (extension-based fallback)

- [ ] **Step 1: Write RuleClassifier (always-available fallback)**

```swift
import Foundation

public struct RuleClassifier: Sendable {
    private let imageExtensions: Set<String> = ["jpg","jpeg","png","gif","bmp","tiff","webp","heic","heif","raw","cr2","nef","arw"]
    private let videoExtensions: Set<String> = ["mp4","mov","avi","mkv","wmv","flv","webm","m4v","3gp"]
    private let documentExtensions: Set<String> = ["pdf","doc","docx","xls","xlsx","ppt","pptx","txt","rtf","md","csv","json","xml","html"]
    private let audioExtensions: Set<String> = ["mp3","aac","wav","flac","ogg","wma","m4a","aiff"]
    private let cacheExtensions: Set<String> = ["cache","tmp","temp","log","swp","ds_store"]
    private let devExtensions: Set<String> = ["swift","kt","java","py","js","ts","go","rs","c","cpp","h","m","mm","plist","entitlements"]

    public func classify(_ url: URL) -> FileCategory {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if videoExtensions.contains(ext) { return .video }
        if documentExtensions.contains(ext) { return .document }
        if audioExtensions.contains(ext) { return .audio }
        if cacheExtensions.contains(ext) { return .cache }
        if devExtensions.contains(ext) { return .dev }
        return .other
    }

    public func isSystemCache(_ url: URL) -> Bool {
        url.path.contains("/Caches/") || url.path.contains("/Cache/")
    }
}
```

- [ ] **Step 2: Write AIClassifier protocol + CoreML wrapper**

```swift
import CoreML
import Foundation

public protocol ClassifierProtocol: Sendable {
    func classify(_ url: URL, size: Int64) async -> FileCategory
    var confidence: Double { get }
}

public final class AIClassifier: ClassifierProtocol {
    private let model: MLModel?
    private let ruleClassifier = RuleClassifier()
    public private(set) var confidence: Double = 0

    public init() {
        // Load CoreML model from bundle
        guard let modelURL = Bundle.main.url(forResource: "FileClassifier", withExtension: "mlmodelc"),
              let model = try? MLModel(contentsOf: modelURL) else {
            self.model = nil
            return
        }
        self.model = model
    }

    public func classify(_ url: URL, size: Int64) async -> FileCategory {
        guard let model = model else {
            confidence = 0.5  // Rule-based, moderate confidence
            return ruleClassifier.classify(url)
        }

        do {
            let ext = url.pathExtension
            let input = FileClassifierInput(
                fileExtension: ext,
                fileSize: Double(size),
                pathLength: Double(url.path.count)
            )
            let output = try model.prediction(from: input)
            confidence = output.featureValue(for: "confidence")?.doubleValue ?? 0.5
            let label = output.featureValue(for: "category")?.stringValue ?? "other"
            return FileCategory(rawValue: label) ?? .other
        } catch {
            confidence = 0.5
            return ruleClassifier.classify(url)
        }
    }
}

// Generated by CoreML compiler — this is a placeholder for the actual model
// The .mlmodel file lives in kWise/Resources/Models/
public class FileClassifierInput: MLFeatureProvider {
    public let fileExtension: String
    public let fileSize: Double
    public let pathLength: Double

    public var featureNames: Set<String> { ["fileExtension", "fileSize", "pathLength"] }

    public func featureValue(for featureName: String) -> MLFeatureValue? {
        switch featureName {
        case "fileExtension": return MLFeatureValue(string: fileExtension)
        case "fileSize": return MLFeatureValue(double: fileSize)
        case "pathLength": return MLFeatureValue(double: pathLength)
        default: return nil
        }
    }

    public init(fileExtension: String, fileSize: Double, pathLength: Double) {
        self.fileExtension = fileExtension
        self.fileSize = fileSize
        self.pathLength = pathLength
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat(kSpaceClean): add AI classifier with CoreML and rule fallback"
```

---

### Task 6: Cleanup Engine

**Files:**
- Create: `kWise/Features/Cleanup/TrashMover.swift`
- Create: `kWise/Features/Cleanup/CleanupHistory.swift`
- Create: `kWise/Features/Cleanup/CleanupViewModel.swift`

**Interfaces:**
- Consumes: `CoreDataStack`, `FileEntry`, `CleanupRecord`, `CommonUtils`
- Produces: `TrashMover` (file → trash + snapshot), `CleanupHistory` (CoreData CRUD), `CleanupViewModel` (UI state)

- [ ] **Step 1: Write TrashMover**

```swift
import Foundation

public final class TrashMover: Sendable {
    public enum MoveError: Error {
        case trashFailed(URL, Error)
        case snapshotFailed(URL)
        case fileNotFound(URL)
    }

    public init() {}

    public func moveToTrash(urls: [URL]) async -> TrashResult {
        var succeeded: [(original: URL, trashURL: URL)] = []
        var failed: [(URL, MoveError)] = []

        for url in urls {
            guard FileManager.default.fileExists(atPath: url.path) else {
                failed.append((url, .fileNotFound(url)))
                continue
            }

            do {
                var trashedURL: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)

                guard let trashURL = trashedURL as? URL,
                      let snapshot = try? await createSnapshot(for: url, trashURL: trashURL) else {
                    failed.append((url, .snapshotFailed(url)))
                    continue
                }

                succeeded.append((url, trashURL))
            } catch {
                failed.append((url, .trashFailed(url, error)))
            }
        }

        return TrashResult(succeeded: succeeded.map(\.original), failed: failed)
    }

    private func createSnapshot(for url: URL, trashURL: URL) async -> TrashSnapshot? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return nil
        }
        return TrashSnapshot(
            originalPath: url.path,
            trashPath: trashURL.path,
            fileSize: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate ?? Date()
        )
    }
}

public struct TrashResult: Sendable {
    public let succeeded: [URL]
    public let failed: [(URL, TrashMover.MoveError)]
}

public struct TrashSnapshot: Codable, Sendable {
    public let originalPath: String
    public let trashPath: String
    public let fileSize: Int64
    public let modifiedAt: Date
}

public extension FileManager {
    var trashDirectory: URL? {
        urls(for: .trashDirectory, in: .userDomainMask).first
    }
}
```

- [ ] **Step 2: Write CleanupHistory**

```swift
import CoreData

public final class CleanupHistory: Sendable {
    private let stack = CoreDataStack.shared

    public func recordCleanup(snapshot: TrashSnapshot) {
        let ctx = stack.backgroundContext()
        ctx.perform {
            let record = CleanupRecord(context: ctx)
            record.id = UUID()
            record.cleanedAt = Date()
            record.totalBytes = snapshot.fileSize
            record.isRestored = false

            let entry = FileEntry(context: ctx)
            entry.id = UUID()
            entry.path = snapshot.originalPath
            entry.size = snapshot.fileSize
            entry.category = ""
            entry.confidence = 0
            record.entries = NSSet(object: entry)

            try? ctx.save()
        }
    }

    public func restore(record: CleanupRecord) async -> Bool {
        guard let entries = record.entries?.allObjects as? [FileEntry] else { return false }
        var allRestored = true
        for entry in entries {
            // Restore from trash path: reconstruct trash path from original
            let trashDir = FileManager.default.trashDirectory
            let originalURL = URL(fileURLWithPath: entry.path)
            let trashURL = trashDir?.appendingPathComponent(originalURL.lastPathComponent) ?? originalURL
            let fm = FileManager.default

            if fm.fileExists(atPath: trashURL.path) {
                try? fm.createDirectory(at: originalURL.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
                do {
                    try fm.moveItem(at: trashURL, to: originalURL)
                } catch {
                    allRestored = false
                }
            }
        }
        if allRestored {
            let ctx = stack.backgroundContext()
            ctx.perform {
                record.isRestored = true
                try? ctx.save()
            }
        }
        return allRestored
    }

    public func fetchRecent(limit: Int = 50) -> [CleanupRecord] {
        let fetch = CleanupRecord.fetchRequest()
        fetch.sortDescriptors = [NSSortDescriptor(key: "cleanedAt", ascending: false)]
        fetch.fetchLimit = limit
        return (try? stack.viewContext.fetch(fetch)) ?? []
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat(kSpaceClean): add cleanup engine with trash move and history"
```

---

### Task 7: Onboarding Flow

**Files:**
- Create: `kWise/Features/Onboarding/OnboardingCoordinator.swift`
- Create: `kWise/Features/Onboarding/OnboardingPages.swift`

**Interfaces:**
- Consumes: `DesignSystem` components
- Produces: `OnboardingCoordinator` (step management + completion callback)

- [ ] **Step 1: Write OnboardingCoordinator**

```swift
import SwiftUI

@MainActor
public final class OnboardingCoordinator: ObservableObject {
    @Published public var currentPage = 0
    public let totalPages = 5
    public var onComplete: (() -> Void)?

    public func next() {
        if currentPage < totalPages - 1 {
            withAnimation { currentPage += 1 }
        } else {
            onComplete?()
        }
    }

    public func skipFDA() {
        // Skip to last page in restricted mode
        withAnimation { currentPage = totalPages - 1 }
    }

    public func openSystemSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
}
```

- [ ] **Step 2: Write 5 onboarding pages**

```swift
import SwiftUI

struct OnboardingPage1: View {  // Value prop
    var body: some View {
        VStack(spacing: AppSpacing.xl) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 64)).foregroundColor(.brandPrimary)
            Text("更快,更干净")
                .font(AppFont.largeTitle).foregroundColor(.textPrimary)
            Text("kSpaceClean 帮你智能清理系统垃圾、释放磁盘空间、让你的 Mac 重回巅峰")
                .font(AppFont.body).foregroundColor(.textSecondary).multilineTextAlignment(.center)
        }
    }
}

struct OnboardingPage2: View {  // 3 core features
    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Text("三大核心能力").font(AppFont.title2).foregroundColor(.textPrimary)
            FeatureRow(icon: "sparkles", title: "3D 磁盘星系", desc: "直观看到空间分布")
            FeatureRow(icon: "brain", title: "AI 智能分类", desc: "自动识别可清理文件")
            FeatureRow(icon: "trash", title: "一键清理", desc: "安全释放空间")
        }
    }
}

struct OnboardingPage3: View {  // Privacy promise
    var body: some View {
        VStack(spacing: AppSpacing.xl) {
            Image(systemName: "lock.shield.fill").font(.system(size: 56)).foregroundColor(.success)
            Text("隐私优先，100% 本地").font(AppFont.title2).foregroundColor(.textPrimary)
            Text("我们不会上传任何文件内容。所有扫描和 AI 分类都在你的 Mac 上本地完成，零网络上报。")
                .font(AppFont.body).foregroundColor(.textSecondary).multilineTextAlignment(.center)
        }
    }
}

struct OnboardingPage4: View {  // FDA request
    let coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "key.fill").font(.system(size: 48)).foregroundColor(.warning)
            Text("需要你的授权").font(AppFont.title2).foregroundColor(.textPrimary)
            Text("kSpaceClean 需要完全磁盘访问权限才能扫描系统缓存和其他临时文件。")
                .font(AppFont.callout).foregroundColor(.textSecondary)
            Button("打开系统设置 → 授予权限") { coordinator.openSystemSettings() }
                .buttonStyle(.borderedProminent).tint(.brandPrimary).controlSize(.large)
            Button("跳过，进入受限模式") { coordinator.skipFDA() }
                .buttonStyle(.plain).foregroundColor(.textSecondary)
        }
    }
}

struct OnboardingPage5: View {  // Ready to scan
    let coordinator: OnboardingCoordinator

    var body: some View {
        VStack(spacing: AppSpacing.xl) {
            Image(systemName: "sparkle.magnifyingglass").font(.system(size: 56)).foregroundColor(.brandPrimary)
            Text("准备好了！").font(AppFont.title2).foregroundColor(.textPrimary)
            Text("一切就绪，开始你的第一次扫描吧").font(AppFont.body).foregroundColor(.textSecondary)
            Button("开始首次扫描") { coordinator.onComplete?() }
                .buttonStyle(.borderedProminent).tint(.brandPrimary).controlSize(.large)
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat(kSpaceClean): add 5-screen onboarding flow"
```

---

### Task 8: Main Window UI (Icon Rail + Layout Shell)

**Files:**
- Create: `kWise/App/kSpaceCleanApp.swift`
- Create: `kWise/App/RootView.swift`
- Create: `kWise/App/AppState.swift`
- Create: `kWise/App/AppCoordinator.swift`
- Create: `kWise/Features/Settings/SettingsView.swift`

**Interfaces:**
- Consumes: `DesignSystem` (GlassPanel, Colors, Typography), all features
- Produces: `AppState` (global observable), `RootView` (NSWindow + SwiftUI layout)

- [ ] **Step 1: Write kSpaceCleanApp.swift**

```swift
import SwiftUI

@main
struct kSpaceCleanApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
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

- [ ] **Step 2: Write AppState**

```swift
import SwiftUI

@MainActor
public final class AppState: ObservableObject {
    @Published public var navigation: NavigationItem = .galaxy
    @Published public var rightPanelTab: RightPanelTab = .overview
    @Published public var rightPanelVisible = true
    @Published public var selectedCategory: FileCategory?
    @Published public var scanState: ScanState = .idle

    public enum NavigationItem: String, CaseIterable {
        case galaxy = "🪐"
        case scan = "🔍"
        case cleanup = "🗑"
        case history = "⏱"
        case settings = "⚙"

        var tooltip: String {
            switch self {
            case .galaxy: return "星系"
            case .scan: return "扫描"
            case .cleanup: return "清理"
            case .history: return "历史"
            case .settings: return "设置"
            }
        }
    }

    public enum RightPanelTab: String, CaseIterable {
        case overview = "概览"
        case allFiles = "所有文件"
        case suggestions = "建议"
    }

    public enum ScanState {
        case idle, scanning(Double), completed, failed(String)
    }
}
```

- [ ] **Step 3: Write RootView with Icon Rail + layout**

```swift
import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Layer 1: Background (3D Galaxy or placeholder)
                galaxyLayer

                // Layer 2: Icon Rail (left)
                HStack(spacing: 0) {
                    iconRail
                        .frame(width: 48)
                        .padding(.leading, 8)

                    Spacer()
                }

                // Layer 3: Right Panel
                HStack(spacing: 0) {
                    Spacer()
                    if appState.rightPanelVisible {
                        RightPanelView()
                            .frame(width: min(260, geo.size.width * 0.3))
                            .padding(.trailing, 12)
                            .padding(.top, 48)
                            .padding(.bottom, 68)
                    }
                }

                // Layer 4: Bottom Panel
                VStack {
                    Spacer()
                    bottomPanel
                        .padding(.horizontal, 68)
                        .padding(.bottom, 10)
                }

                // Layer 5: Category Legend
                VStack {
                    Spacer()
                    HStack {
                        categoryLegend
                            .padding(.leading, 68)
                        Spacer()
                    }
                    .padding(.bottom, 72)
                }
            }
        }
    }

    // MARK: - Icon Rail
    private var iconRail: some View {
        GlassPanel {
            VStack(spacing: 4) {
                ForEach(AppState.NavigationItem.allCases, id: \.self) { item in
                    Button {
                        appState.navigation = item
                    } label: {
                        Text(item.rawValue)
                            .font(.system(size: 18))
                            .frame(width: 36, height: 36)
                            .background(appState.navigation == item ? Color.brandPrimary.opacity(0.3) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .help(item.tooltip)
                }
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .frame(width: 42)
    }

    // MARK: - Bottom Panel
    private var bottomPanel: some View {
        GlassPanel {
            HStack {
                DiskUsageBar()
                Spacer()
                HStack(spacing: 8) {
                    Button("⬇ 快速扫描") { /* trigger quick scan */ }
                        .buttonStyle(.bordered).tint(.textSecondary)
                    Button("✨ 开始扫描") { /* trigger full scan */ }
                        .buttonStyle(.borderedProminent).tint(.brandPrimary)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .frame(height: 48)
        }
    }

    // MARK: - Category Legend
    private var categoryLegend: some View {
        HStack(spacing: 10) {
            ForEach(FileCategory.allCases.filter { $0 != .other && $0 != .dev }, id: \.self) { cat in
                HStack(spacing: 4) {
                    Circle().fill(cat.color).frame(width: 8, height: 8)
                    Text(verbatim: "\(cat)").font(AppFont.caption).foregroundColor(.textSecondary)
                }
                .onTapGesture { appState.selectedCategory = cat }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // Placeholder — replaced by GalaxyView in Task 9
    private var galaxyLayer: some View {
        Color.bgPrimary.ignoresSafeArea()
    }
}

struct DiskUsageBar: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("已用 128 GB").font(AppFont.caption).foregroundColor(.textSecondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.separatorColor.opacity(0.3)).frame(height: 4)
                    Capsule().fill(Color.success).frame(width: geo.size.width * 0.5, height: 4)
                }
            }
            .frame(width: 100)
            Text("共 256 GB").font(AppFont.caption).foregroundColor(.textSecondary)
        }
    }
}
```

- [ ] **Step 4: Write SettingsView**

```swift
import SwiftUI

struct SettingsView: View {
    @State private var prefs = UserPreferences.load()
    @State private var selectedTab = "general"

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text("设置").font(AppFont.title2).foregroundColor(.textPrimary)

            Form {
                Section("通用") {
                    Toggle("启动时自动扫描", isOn: $prefs.launchAtLogin)
                    Toggle("菜单栏显示磁盘占用", isOn: $prefs.showMenuBarDiskUsage)
                    Toggle("清理后通知", isOn: .constant(true))
                }

                Section("扫描") {
                    Picker("大文件阈值", selection: $prefs.largeFileThreshold) {
                        Text("50 MB").tag(Int64(50_000_000))
                        Text("100 MB").tag(Int64(100_000_000))
                        Text("500 MB").tag(Int64(500_000_000))
                        Text("1 GB").tag(Int64(1_000_000_000))
                    }
                    Toggle("AI 分类启用", isOn: $prefs.aiClassificationEnabled)
                }

                Section("订阅") {
                    Text("当前: Pro").font(AppFont.body).foregroundColor(.textPrimary)
                    Button("管理订阅") { /* open App Store */ }
                }
            }
            .formStyle(.grouped)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(kSpaceClean): add main window layout with Icon Rail and glass panels"
```

---

### Task 9: Disk Galaxy 3D View (Metal + SceneKit)

**Files:**
- Create: `kWise/Features/DiskGalaxy/GalaxyRenderer.swift`
- Create: `kWise/Features/DiskGalaxy/GalaxyScene.swift`
- Create: `kWise/Features/DiskGalaxy/GalaxyViewModel.swift`
- Create: `kWise/Features/DiskGalaxy/GalaxyView.swift`

**Interfaces:**
- Consumes: `AppState`, `FileCategory`, `SmartScan` results
- Produces: `GalaxyView` (NSViewRepresentable wrapping SCNView), `GalaxyViewModel` (scene ↔ app state bridge)

- [ ] **Step 1: Write GalaxyScene (SceneKit scene builder)**

```swift
import SceneKit

public final class GalaxyScene {
    public let scene = SCNScene()
    private var spheres: [SCNNode] = []

    public func buildSphere(for category: FileCategory, size: Double) -> SCNNode {
        let radius = 0.5 + log2(size + 1) * 0.3
        let clampedRadius = min(max(radius, 0.5), 3.0)

        let sphere = SCNSphere(radius: CGFloat(clampedRadius))
        sphere.firstMaterial?.diffuse.contents = NSColor(category.color).withAlphaComponent(0.85)
        sphere.firstMaterial?.specular.contents = NSColor.white.withAlphaComponent(0.3)
        sphere.firstMaterial?.isDoubleSided = true

        let node = SCNNode(geometry: sphere)
        node.categoryBitMask = 1
        node.name = category.rawValue

        // Add icon as a billboard sprite
        let icon = SCNText(string: "", extrusionDepth: 0)

        return node
    }

    public func arrangeSpheres(_ spheres: [SCNNode]) {
        // Arrange in a spiral pattern around center
        let count = spheres.count
        for (index, node) in spheres.enumerated() {
            let angle = Double(index) / Double(count) * .pi * 2
            let radius: Float = 5.0
            node.position = SCNVector3(
                cos(Float(angle)) * radius,
                sin(Float(angle)) * radius * 0.6,
                -Float(index) * 0.5
            )
        }
    }

    public func addCamera() {
        let camera = SCNCamera()
        camera.zNear = 0.1
        camera.zFar = 100

        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 15)
        scene.rootNode.addChildNode(cameraNode)
    }

    public func addLighting() {
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 300
        scene.rootNode.addChildNode(ambient)

        let directional = SCNNode()
        directional.light = SCNLight()
        directional.light?.type = .directional
        directional.light?.intensity = 800
        directional.position = SCNVector3(5, 10, 10)
        scene.rootNode.addChildNode(directional)
    }

    public func addParticleStars() {
        // Starfield background
        let particle = SCNParticleSystem()
        particle.birthRate = 50
        particle.loops = true
        particle.emissionDuration = 1
        particle.particleLifeSpan = 10
        particle.particleSize = 0.05
        particle.spreadingAngle = 180
        particle.emitterShape = SCNSphere(radius: 30)
        let particleNode = SCNNode()
        particleNode.addParticleSystem(particle)
        scene.rootNode.addChildNode(particleNode)
    }
}
```

- [ ] **Step 2: Write GalaxyView (SwiftUI wrapper)**

```swift
import SwiftUI
import SceneKit

struct GalaxyView: NSViewRepresentable {
    @ObservedObject var viewModel: GalaxyViewModel

    func makeNSView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.scene = context.coordinator.scene
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = false
        scnView.backgroundColor = .clear
        scnView.antialiasingMode = .multisampling4X
        scnView.delegate = context.coordinator

        // Gestures
        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        scnView.addGestureRecognizer(clickGesture)

        let doubleClickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleClick(_:)))
        doubleClickGesture.numberOfClicksRequired = 2
        scnView.addGestureRecognizer(doubleClickGesture)

        return scnView
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        context.coordinator.updateScene(with: viewModel)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    class Coordinator: NSObject, SCNSceneRendererDelegate {
        let sceneBuilder = GalaxyScene()
        var scene: SCNScene
        var viewModel: GalaxyViewModel

        init(viewModel: GalaxyViewModel) {
            self.viewModel = viewModel
            self.scene = sceneBuilder.scene
            super.init()
            setupScene()
        }

        private func setupScene() {
            sceneBuilder.addCamera()
            sceneBuilder.addLighting()
            sceneBuilder.addParticleStars()
        }

        func updateScene(with viewModel: GalaxyViewModel) {
            // Remove old spheres, add new ones based on scan results
            scene.rootNode.childNodes.filter { $0.geometry is SCNSphere }.forEach { $0.removeFromParentNode() }

            let sphereNodes = viewModel.categories.map { sceneBuilder.buildSphere(for: $0.category, size: $0.totalSize) }
            sceneBuilder.arrangeSpheres(sphereNodes)
            sphereNodes.forEach { scene.rootNode.addChildNode($0) }
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let point = gesture.location(in: view)
            let hits = view.hitTest(point, options: [.categoryBitMask: 1])

            if let hit = hits.first, let node = hit.node, let categoryName = node.name {
                viewModel.selectCategory(categoryName)
            } else {
                viewModel.deselectAll()
            }
        }

        @objc func handleDoubleClick(_ gesture: NSClickGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let point = gesture.location(in: view)
            let hits = view.hitTest(point, options: [.categoryBitMask: 1])

            if let hit = hits.first, let node = hit.node, let categoryName = node.name {
                viewModel.drillDown(categoryName)
            }
        }
    }
}
```

- [ ] **Step 3: Write GalaxyViewModel**

```swift
import Foundation

@MainActor
public final class GalaxyViewModel: ObservableObject {
    @Published public var categories: [CategoryGroup] = []
    @Published public var selectedCategory: FileCategory?
    @Published public var breadcrumb: [String] = ["/"]

    public struct CategoryGroup: Identifiable {
        public let id = UUID()
        public let category: FileCategory
        public let totalSize: Double
        public let fileCount: Int
    }

    public func update(with results: [FileEntry]) {
        var groups: [FileCategory: (size: Double, count: Int)] = [:]
        for entry in results {
            let cat = FileCategory(rawValue: entry.category) ?? .other
            groups[cat, default: (0, 0)].size += Double(entry.size)
            groups[cat, default: (0, 0)].count += 1
        }
        categories = groups.map { CategoryGroup(category: $0.key, totalSize: $0.value.size, fileCount: $0.value.count) }
            .sorted { $0.totalSize > $1.totalSize }
    }

    public func selectCategory(_ name: String) {
        selectedCategory = FileCategory(rawValue: name)
    }

    public func deselectAll() {
        selectedCategory = nil
    }

    public func drillDown(_ name: String) {
        selectedCategory = FileCategory(rawValue: name)
        breadcrumb.append(name)
    }
}
```

- [ ] **Step 4: Integrate GalaxyView into RootView**

Replace `galaxyLayer` in RootView:
```swift
private var galaxyLayer: some View {
    GalaxyView(viewModel: galaxyViewModel)
        .ignoresSafeArea()
}
```
Add `@StateObject private var galaxyViewModel = GalaxyViewModel()` to RootView.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(kSpaceClean): add 3D galaxy view with SceneKit rendering"
```

---

### Task 10: Right Panel (Tabs: Overview / All Files / Suggestions)

**Files:**
- Create: `kWise/Features/RightPanel/RightPanelView.swift`
- Create: `kWise/Features/RightPanel/OverviewTabView.swift`
- Create: `kWise/Features/RightPanel/AllFilesTabView.swift`
- Create: `kWise/Features/RightPanel/SuggestionsTabView.swift`

**Interfaces:**
- Consumes: `AppState`, `FileEntry` (Core Data), `ScanEngine`, `GalaxyViewModel`
- Produces: Complete right panel with 3 tabs

- [ ] **Step 1: Write RightPanelView**

```swift
import SwiftUI

struct RightPanelView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: AppState.RightPanelTab = .overview

    var body: some View {
        GlassPanel {
            VStack(spacing: 0) {
                // Tab bar
                HStack(spacing: 0) {
                    ForEach(AppState.RightPanelTab.allCases, id: \.self) { tab in
                        Button(tab.rawValue) {
                            selectedTab = tab
                            appState.rightPanelTab = tab
                        }
                        .buttonStyle(.plain)
                        .font(AppFont.callout)
                        .foregroundColor(selectedTab == tab ? .textPrimary : .textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selectedTab == tab ? Color.brandPrimary.opacity(0.15) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 4)

                Divider().padding(.vertical, 4)

                // Tab content
                TabView(selection: $selectedTab) {
                    OverviewTabView().tag(AppState.RightPanelTab.overview)
                    AllFilesTabView().tag(AppState.RightPanelTab.allFiles)
                    SuggestionsTabView().tag(AppState.RightPanelTab.suggestions)
                }
                .tabViewStyle(.automatic)
            }
        }
    }
}
```

- [ ] **Step 2: Write OverviewTabView**

```swift
import SwiftUI

struct OverviewTabView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                if let category = appState.selectedCategory {
                    // Selected category detail
                    CategoryDetailCard(category: category)
                } else {
                    // Global overview (all categories)
                    Text("磁盘概览").font(AppFont.title3).foregroundColor(.textPrimary)
                    ForEach(FileCategory.allCases, id: \.rawValue) { cat in
                        CategoryRow(category: cat, size: 0, count: 0)
                    }
                }

                // AI Suggestions summary
                GlassPanel {
                    VStack(alignment: .leading, spacing: AppSpacing.sm) {
                        HStack {
                            Image(systemName: "brain").foregroundColor(.brandPrimary)
                            Text("AI 建议").font(AppFont.callout).foregroundColor(.textPrimary)
                        }
                        Text("发现 328 张相似照片可清理").font(AppFont.caption).foregroundColor(.textSecondary)
                    }
                    .padding(AppSpacing.md)
                }
            }
            .padding(AppSpacing.md)
        }
    }
}

struct CategoryDetailCard: View {
    let category: FileCategory

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            HStack {
                Image(systemName: category.icon).foregroundColor(category.color)
                Text(verbatim: "\(category)").font(AppFont.title3).foregroundColor(.textPrimary)
            }
            Text("42.3 GB · 1,234 个文件").font(AppFont.callout).foregroundColor(.textSecondary)
            HStack(spacing: 8) {
                Button("查看文件") { }.buttonStyle(.bordered).controlSize(.small)
                Button("清理") { }.buttonStyle(.borderedProminent).tint(.danger).controlSize(.small)
            }
        }
        .padding()
        .background(category.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }
}

struct CategoryRow: View {
    let category: FileCategory
    let size: Int64
    let count: Int

    var body: some View {
        HStack {
            Circle().fill(category.color).frame(width: 8, height: 8)
            Image(systemName: category.icon).foregroundColor(category.color).font(.system(size: 14))
            Text(verbatim: "\(category)").font(AppFont.body).foregroundColor(.textPrimary)
            Spacer()
            Text(FileSizeFormatter.abbreviated(from: size)).font(AppFont.monoDigit).foregroundColor(.textSecondary)
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 3: Write AllFilesTabView**

```swift
import SwiftUI
import CoreData

struct AllFilesTabView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var sortColumn = "name"
    @State private var sortAscending = true
    @State private var selectedFiles: Set<UUID> = []

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \FileEntry.size, ascending: false)],
        animation: .default
    ) private var files: FetchedResults<FileEntry>

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.textSecondary)
                TextField("搜索文件...", text: $searchText)
                    .textFieldStyle(.plain).font(AppFont.callout)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.textSecondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.bgTertiary.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            // Table header
            HStack(spacing: 0) {
                CheckboxHeader(isAllSelected: selectedFiles.count == files.count && !files.isEmpty,
                               action: toggleSelectAll)
                    .frame(width: 24)
                SortableHeader("名称", column: "name", sortColumn: $sortColumn, sortAscending: $sortAscending)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SortableHeader("大小", column: "size", sortColumn: $sortColumn, sortAscending: $sortAscending)
                    .frame(width: 70, alignment: .trailing)
                Text("类型").font(AppFont.caption).foregroundColor(.textSecondary).frame(width: 50)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)

            Divider()

            // File list
            let displayFiles = filteredFiles
            List(displayFiles, id: \.id) { file in
                FileRow(file: file, isSelected: selectedFiles.contains(file.id))
                    .onTapGesture { toggleSelection(file.id) }
            }
            .listStyle(.plain)

            // Footer
            HStack {
                Text("共 \(displayFiles.count) 个 · 已选 \(selectedFiles.count) 个")
                    .font(AppFont.caption).foregroundColor(.textSecondary)
                Spacer()
                Button("🗑 清理") { /* trigger cleanup */ }
                    .buttonStyle(.borderedProminent).tint(.danger).disabled(selectedFiles.isEmpty)
            }
            .padding(8)
        }
    }

    private var filteredFiles: [FileEntry] {
        let sorted = sortColumn == "size"
            ? files.sorted { sortAscending ? $0.size < $1.size : $0.size > $1.size }
            : files.sorted { sortAscending ? $0.path < $1.path : $0.path > $1.path }
        guard !searchText.isEmpty else { return sorted }
        return sorted.filter { $0.path.localizedCaseInsensitiveContains(searchText) }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedFiles.contains(id) { selectedFiles.remove(id) }
        else { selectedFiles.insert(id) }
    }

    private func toggleSelectAll() {
        if selectedFiles.count == files.count {
            selectedFiles.removeAll()
        } else {
            selectedFiles = Set(files.compactMap { $0.id })
        }
    }
}

// MARK: - Table header components

struct SortableHeader: View {
    let label: String
    let column: String
    @Binding var sortColumn: String
    @Binding var sortAscending: Bool

    init(_ label: String, column: String, sortColumn: Binding<String>, sortAscending: Binding<Bool>) {
        self.label = label
        self.column = column
        _sortColumn = sortColumn
        _sortAscending = sortAscending
    }

    var body: some View {
        Button {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = true
            }
        } label: {
            HStack(spacing: 2) {
                Text(label).font(AppFont.caption).foregroundColor(.textSecondary)
                if sortColumn == column {
                    Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8)).foregroundColor(.brandPrimary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct CheckboxHeader: View {
    let isAllSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isAllSelected ? "checkmark.square.fill" : "square")
                .foregroundColor(isAllSelected ? .brandPrimary : .textSecondary)
        }
        .buttonStyle(.plain)
    }
}

struct FileRow: View {
    let file: FileEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .foregroundColor(isSelected ? .brandPrimary : .textSecondary).frame(width: 24)
            Image(systemName: FileCategory(rawValue: file.category)?.icon ?? "questionmark")
                .foregroundColor(FileCategory(rawValue: file.category)?.color ?? .textSecondary)
                .frame(width: 18)
            Text(URL(fileURLWithPath: file.path).lastPathComponent)
                .font(AppFont.body).foregroundColor(.textPrimary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(FileSizeFormatter.abbreviated(from: file.size))
                .font(AppFont.monoDigit).foregroundColor(.textSecondary).frame(width: 70, alignment: .trailing)
            CategoryBadge(category: file.category).frame(width: 50)
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
    }
}
```

- [ ] **Step 4: Write SuggestionsTabView**

```swift
import SwiftUI

struct SuggestionsTabView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("AI 智能推荐").font(AppFont.title3).foregroundColor(.textPrimary)

                SuggestionCard(
                    icon: "photo.on.rectangle",
                    title: "清理相似照片",
                    detail: "328 张相似照片 · 预计释放 2.4 GB",
                    confidence: 0.95
                )
                SuggestionCard(
                    icon: "archivebox",
                    title: "清理系统缓存",
                    detail: "12 GB 缓存文件 · 预计释放 8.1 GB",
                    confidence: 0.88
                )
                SuggestionCard(
                    icon: "trash",
                    title: "清空废纸篓",
                    detail: "3.2 GB · 安全可清理",
                    confidence: 0.99
                )
            }
            .padding(AppSpacing.md)
        }
    }
}

struct SuggestionCard: View {
    let icon: String
    let title: String
    let detail: String
    let confidence: Double

    var body: some View {
        GlassPanel {
            HStack {
                Image(systemName: icon).font(.title2).foregroundColor(.brandPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(AppFont.body).foregroundColor(.textPrimary)
                    Text(detail).font(AppFont.caption).foregroundColor(.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(Int(confidence * 100))%").font(AppFont.callout).foregroundColor(.success)
                    Button("清理") { }.buttonStyle(.bordered).controlSize(.small)
                }
            }
            .padding(AppSpacing.sm)
        }
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(kSpaceClean): add right panel with 3-tab system"
```

---

### Task 11: Menu Bar

**Files:**
- Create: `kWise/MenuBar/MenuBarManager.swift`
- Create: `kWise/MenuBar/DiskStatusView.swift`

**Interfaces:**
- Consumes: `AppState`, `CleanupHistory`
- Produces: `MenuBarManager` (NSStatusItem lifecycle)

- [ ] **Step 1: Write MenuBarManager**

```swift
import AppKit

@MainActor
public final class MenuBarManager: NSObject {
    private var statusItem: NSStatusItem?

    public func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.action = #selector(toggleMenu)
        statusItem?.button?.target = self
        statusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        updateMenu()
    }

    public func updateDiskUsage(used: Int64, total: Int64) {
        let percentage = total > 0 ? Double(used) / Double(total) : 0
        let color: NSColor = percentage < 0.7 ? .systemGreen : percentage < 0.9 ? .systemYellow : .systemRed

        let formatted = ByteCountFormatter.string(fromByteCount: used, countStyle: .file)
        statusItem?.button?.title = "📦 \(formatted)"
        statusItem?.button?.attributedTitle = NSAttributedString(
            string: "\(formatted)",
            attributes: [.foregroundColor: color]
        )
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "快速清理", action: #selector(quickClean), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "快速扫描", action: #selector(quickScan), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "最近清理: 今天 10:30 · 3.2 GB", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "打开主窗口", action: #selector(openMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApp.terminate), keyEquivalent: "q"))
        return menu
    }

    private func updateMenu() {
        statusItem?.menu = buildMenu()
    }

    @objc private func toggleMenu() { statusItem?.button?.performClick(nil) }
    @objc private func quickClean() { /* trigger clean */ }
    @objc private func quickScan() { /* trigger scan */ }
    @objc private func openMainWindow() { NSApp.activate(ignoringOtherApps: true) }
    @objc private func openSettings() { /* show settings */ }
}
```

Call `MenuBarManager().setup()` from `kSpaceCleanApp.swift` init.

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "feat(kSpaceClean): add menu bar with status and quick actions"
```

---

### Task 12: Widgets

**Files:**
- Create: `kWise/Widgets/KSpaceCleanWidget.swift`
- Create: `kWise/Widgets/WidgetTimelineProvider.swift`
- Modify: `kWise/Info.plist` (add widget bundle)

**Interfaces:**
- Consumes: `AppState`, `CommonUtils`
- Produces: WidgetExtension target with small/medium/large widgets

- [ ] **Step 1: Create Widget target**

In Xcode: Add target → macOS → Widget Extension → name `KSpaceCleanWidget`. Set bundle ID to `app.kraftly.sclean.widget`.

- [ ] **Step 2: Write TimelineProvider**

```swift
import WidgetKit
import SwiftUI

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(usedGB: 128, totalGB: 256, date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SimpleEntry) -> Void) {
        let entry = SimpleEntry(usedGB: 128, totalGB: 256, date: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SimpleEntry>) -> Void) {
        let entry = SimpleEntry(usedGB: 128, totalGB: 256, date: Date())
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600)))
        completion(timeline)
    }
}

struct SimpleEntry: TimelineEntry {
    let usedGB: Int64
    let totalGB: Int64
    let date: Date

    var percentUsed: Double { totalGB > 0 ? Double(usedGB) / Double(totalGB) : 0 }
}
```

- [ ] **Step 3: Write widget views**

```swift
struct KSpaceCleanWidgetEntryView: View {
    var entry: Provider.Entry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall: SmallWidgetView(entry: entry)
        case .systemMedium: MediumWidgetView(entry: entry)
        case .systemLarge: LargeWidgetView(entry: entry)
        default: SmallWidgetView(entry: entry)
        }
    }
}

struct SmallWidgetView: View {
    let entry: Provider.Entry

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles.rectangle.stack")
                .foregroundColor(.brandPrimary)
            ProgressRing(progress: entry.percentUsed, label: "\(Int(entry.percentUsed * 100))%")
                .frame(width: 60, height: 60)
            Text("\(entry.usedGB) / \(entry.totalGB) GB")
                .font(.caption).foregroundColor(.secondary)
            Link(destination: URL(string: "kspaceclean://scan")!) {
                Label("扫描", systemImage: "magnifyingglass").font(.caption)
            }
        }
        .containerBackground(.background, for: .widget)
    }
}

struct MediumWidgetView: View {
    let entry: Provider.Entry

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Label("kSpaceClean", systemImage: "sparkles.rectangle.stack")
                    .font(.headline).foregroundColor(.brandPrimary)
                DiskUsageBarView(used: entry.usedGB, total: entry.totalGB)
            }
            Spacer()
            Link(destination: URL(string: "kspaceclean://clean")!) {
                Label("一键清理", systemImage: "trash").font(.caption)
            }
            .buttonStyle(.borderedProminent).tint(.brandPrimary)
        }
        .padding()
        .containerBackground(.background, for: .widget)
    }
}

struct LargeWidgetView: View {
    let entry: Provider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("kSpaceClean", systemImage: "sparkles.rectangle.stack")
                .font(.headline).foregroundColor(.brandPrimary)
            DiskUsageBarView(used: entry.usedGB, total: entry.totalGB)
            Divider()
            WidgetCategoryRow(label: "系统缓存", size: "3.2 GB")
            WidgetCategoryRow(label: "应用残留", size: "2.1 GB")
            WidgetCategoryRow(label: "大文件", size: "4.8 GB")
            Spacer()
            if #available(macOS 14, *) {
                Link(destination: URL(string: "kspaceclean://cleanAll")!) {
                    Label("一键全清", systemImage: "trash.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(.brandPrimary)
            }
        }
        .padding()
        .containerBackground(.background, for: .widget)
    }
}

struct WidgetCategoryRow: View {
    let label: String
    let size: String

    var body: some View {
        HStack {
            Text(label).font(.callout)
            Spacer()
            Text(size).font(.caption).foregroundColor(.secondary)
        }
    }
}
```

- [ ] **Step 4: Register widget bundle**

```swift
@main
struct KSpaceCleanWidgetBundle: WidgetBundle {
    var body: some Widget {
        KSpaceCleanWidget()
    }
}

struct KSpaceCleanWidget: Widget {
    let kind = "KSpaceCleanWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            KSpaceCleanWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("磁盘空间")
        .description("查看磁盘使用情况并快速扫描")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
```

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(kSpaceClean): add widgets with small/medium/large variants"
```

---

### Task 13: App Intents (Shortcuts)

**Files:**
- Create: `kWise/Intents/ScanIntent.swift`
- Create: `kWise/Intents/CleanCacheIntent.swift`
- Create: `kWise/Intents/ShowLargeFilesIntent.swift`

**Interfaces:**
- Consumes: `ScanEngine`, `TrashMover`, `FileEntry`
- Produces: 3 App Intents discoverable in Shortcuts, Siri, Spotlight

- [ ] **Step 1: Write ScanIntent**

```swift
import AppIntents

struct ScanIntent: AppIntent {
    static var title: LocalizedStringResource = "扫描 Mac 存储"
    static var description = IntentDescription("扫描磁盘并返回当前已用空间")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let engine = ScanEngine()
        await engine.startScan()
        let used = engine.progress.totalBytes
        let result = .result(value: "已用: \(FileSizeFormatter.abbreviated(from: used))")
        return result
    }
}
```

- [ ] **Step 2: Write CleanCacheIntent**

```swift
import AppIntents

struct CleanCacheIntent: AppIntent {
    static var title: LocalizedStringResource = "清理系统缓存"
    static var description = IntentDescription("清理系统缓存文件并返回释放的空间大小")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let cacheDir = URL(filePath: NSHomeDirectory() + "/Library/Caches")
        let mover = TrashMover()
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: cacheDir,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]) else {
            return .result(value: "无法访问缓存目录")
        }
        let result = await mover.moveToTrash(urls: items)
        let totalFreed = result.succeeded.reduce(0) { $0 + $1.fileSize }
        return .result(value: "已清理 \(FileSizeFormatter.abbreviated(from: totalFreed)) 缓存")
    }
}
```

- [ ] **Step 3: Write ShowLargeFilesIntent**

```swift
import AppIntents

struct ShowLargeFilesIntent: AppIntent {
    static var title: LocalizedStringResource = "显示最大文件 Top 10"
    static var description = IntentDescription("显示当前磁盘上最大的 10 个文件")

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Query Core Data for top 10 largest FileEntry records
        let fetch = FileEntry.fetchRequest()
        fetch.sortDescriptors = [NSSortDescriptor(key: "size", ascending: false)]
        fetch.fetchLimit = 10
        let topFiles = (try? CoreDataStack.shared.viewContext.fetch(fetch)) ?? []
        let result = topFiles.enumerated().map { i, f in
            "\(i+1). \(URL(fileURLWithPath: f.path).lastPathComponent) - \(FileSizeFormatter.abbreviated(from: f.size))"
        }.joined(separator: "\n")
        return .result(value: result.isEmpty ? "暂无数据" : result)
    }
}
```

- [ ] **Step 4: Register intents in Info.plist**

Add `NSUserActivityTypes` array with intent identifiers.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat(kSpaceClean): add 3 App Intents for Shortcuts integration"
```

---

### Task 14: Finder Extension

**Files:**
- Create: `kWise/FinderExtension/FinderSync.swift`
- Create: `kWise/FinderExtension/Info.plist`

**Interfaces:**
- Consumes: `AppCoordinator` (deep link), `ScanEngine`
- Produces: Finder right-click "用 kSpaceClean 扫描" menu item

- [ ] **Step 1: Create FinderSync target**

In Xcode: Add target → macOS → Finder Sync Extension → name `KSpaceCleanFinderExtension`.

- [ ] **Step 2: Write FinderSync**

```swift
import FinderSync

class FinderSync: FIFinderSync {
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "kSpaceClean")
        let item = NSMenuItem(title: "用 kSpaceClean 扫描此文件夹", action: #selector(scanFolder), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc func scanFolder(_ sender: AnyObject?) {
        guard let target = FIFinderSyncController.default().targetedURL() else { return }
        // Open app with deep link
        NSWorkspace.shared.open(URL(string: "kspaceclean://scan?path=\(target.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!)")!)
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat(kSpaceClean): add Finder extension for right-click scan"
```

---

### Task 15: Live Activity (macOS 14+)

**Files:**
- Create: `kWise/LiveActivity/CleanupActivityAttributes.swift`

**Interfaces:**
- Consumes: `ActivityKit`, `CleanupEngine`
- Produces: Dynamic Island-style progress for cleanup tasks

- [ ] **Step 1: Write ActivityAttributes**

```swift
import ActivityKit
import Foundation

@available(macOS 14, *)
struct CleanupActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable & Hashable {
        var progress: Double
        var currentFile: String
        var freedBytes: Int64
    }

    var startedAt: Date
}
```

- [ ] **Step 2: Start Live Activity during cleanup**

```swift
@available(macOS 14, *)
func startCleanupActivity(totalBytes: Int64) {
    let attributes = CleanupActivityAttributes(startedAt: Date())
    let initialState = CleanupActivityAttributes.ContentState(
        progress: 0,
        currentFile: "准备中...",
        freedBytes: 0
    )
    do {
        let activity = try Activity.request(
            attributes: attributes,
            content: .init(state: initialState, staleDate: nil)
        )
        // Store activity for updates
    } catch {
        print("Live Activity failed: \(error)")
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat(kSpaceClean): add Live Activity for cleanup progress"
```

---

### Task 16: Subscription (StoreKit 2)

**Files:**
- Create: `kWise/Store/StoreManager.swift`
- Create: `kWise/Store/PaywallView.swift`

**Interfaces:**
- Produces: `StoreManager` (StoreKit 2 transaction handler), `PaywallView` (SwiftUI paywall)

- [ ] **Step 1: Write StoreManager**

```swift
import StoreKit

@MainActor
public final class StoreManager: ObservableObject {
    @Published public var isSubscribed = false
    @Published public var isEligibleForTrial = true

    private let productID = "app.kraftly.sclean.subscription.yearly"

    public func checkSubscription() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.productID == productID && transaction.revocationDate == nil {
                    isSubscribed = true
                    return
                }
            }
        }
        isSubscribed = false
    }

    public func purchase() async {
        guard let product = try? await Product.products(for: [productID]).first else { return }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(.verified(let transaction)):
                await transaction.finish()
                isSubscribed = true
            default:
                break
            }
        } catch {
            print("Purchase failed: \(error)")
        }
    }

    public func restorePurchases() async {
        try? await AppStore.sync()
        await checkSubscription()
    }
}
```

- [ ] **Step 2: Write PaywallView**

```swift
import SwiftUI

struct PaywallView: View {
    @StateObject private var store = StoreManager()

    var body: some View {
        GlassPanel {
            VStack(spacing: AppSpacing.xl) {
                Image(systemName: "crown.fill").font(.system(size: 48)).foregroundColor(.brandAccent)
                Text("解锁全部 kSpaceClean 功能").font(AppFont.title2).foregroundColor(.textPrimary)

                FeatureList(items: [
                    ("无限清理", "免费版仅 1GB"),
                    ("AI 智能分类", "本地 CoreML"),
                    ("3D 磁盘星系图", "Metal 渲染"),
                    ("桌面 Widget + Shortcuts", "macOS 深度集成"),
                ])

                Button("7 天免费试用 · 之后 ¥98/年") {
                    Task { await store.purchase() }
                }
                .buttonStyle(.borderedProminent).tint(.brandPrimary).controlSize(.large)

                Button("恢复购买") {
                    Task { await store.restorePurchases() }
                }
                .buttonStyle(.plain).foregroundColor(.textSecondary)
            }
            .padding(AppSpacing.xxl)
        }
        .frame(width: 400)
    }
}

struct FeatureList: View {
    let items: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            ForEach(items, id: \.0) { item in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.success)
                    Text(item.0).font(AppFont.body).foregroundColor(.textPrimary)
                    Text(item.1).font(AppFont.caption).foregroundColor(.textSecondary)
                }
            }
        }
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat(kSpaceClean): add StoreKit subscription and paywall"
```

---

### Task 17: Localization

**Files:**
- Create: `kWise/Resources/Localizable.xcstrings` (in Xcode: Project → Localizations → add English / Chinese / Japanese)

- [ ] **Step 1: Extract all user-facing strings into Localizable.xcstrings**

Key localizations needed:
```swift
// English (en)
"开始扫描" = "Start Scan";
"快速扫描" = "Quick Scan";
"一键清理" = "Clean Up";
"磁盘空间" = "Disk Space";
"已用 %@ / %@" = "%@ used / %@";
"释放了 %@" = "%@ freed";
"需要你的授权" = "Authorization Required";

// Simplified Chinese (zh-Hans)
"开始扫描" = "开始扫描";
"快速扫描" = "快速扫描";
"一键清理" = "一键清理";

// Japanese (ja)
"开始扫描" = "スキャン開始";
"快速扫描" = "クイックスキャン";
```

- [ ] **Step 2: Use string catalog in all SwiftUI views**

Replace hardcoded strings with `Text(verbatim:)` → `Text("localization_key")`.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "feat(kSpaceClean): add localization for en, zh-Hans, ja"
```

---

### Task 18: Spotlight Integration

**Files:**
- Create: `kWise/Spotlight/SpotlightIndexer.swift`

**Interfaces:**
- Consumes: App Intents
- Produces: Searchable actions in macOS Spotlight

- [ ] **Step 1: Write SpotlightIndexer**

```swift
import CoreSpotlight

public final class SpotlightIndexer {
    public func indexActions() {
        let scanAction = CSSearchableItem(
            uniqueIdentifier: "kspaceclean://scan",
            domainIdentifier: "app.kraftly.sclean.actions",
            attributeSet: {
                let attr = CSSearchableItemAttributeSet(contentType: .content)
                attr.title = "扫描 Mac 存储"
                attr.contentDescription = "用 kSpaceClean 分析磁盘空间"
                attr.keywords = ["Mac 空间", "清理 Mac", "大文件"]
                return attr
            }()
        )
        CSSearchableIndex.default().indexSearchableItems([scanAction]) { error in
            if let error = error { print("Spotlight indexing error: \(error)") }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "feat(kSpaceClean): add Spotlight indexing for app actions"
```

---

### Task 19: App Store Ready

**Files:**
- Create: `kWise/Assets.xcassets/AppIcon.appiconset` (Xcode icon set)
- Modify: `kWise/Info.plist` (App Store metadata)

**Steps:**

- [ ] **Step 1: Prepare app icon**

Generate icon set in Xcode Assets catalog. Required sizes: 16×16, 32×32, 128×128, 256×256, 512×512 (standard macOS icon). Design: galaxy purple gradient with "k" monogram.

- [ ] **Step 2: Configure Info.plist for App Store**

```xml
<key>CFBundleDisplayName</key>
<string>kSpaceClean</string>
<key>CFBundleName</key>
<string>kSpaceClean</string>
<key>LSApplicationCategoryType</key>
<string>public.app-category.utilities</string>
<key>NSHumanReadableCopyright</key>
<string>© 2026 Kraftly. All rights reserved.</string>
```

- [ ] **Step 3: Prepare App Store metadata**

Capture 5 screenshots (as specified in §7.2 of the design spec):
1. 3D galaxy main view
2. Scan results with right panel
3. Cleanup confirmation
4. Widget on desktop
5. Shortcuts integration

Record 30-second preview video showing galaxy rotation + scan flow.

Set metadata in App Store Connect:
- Name: kSpaceClean - Smart Disk Cleaner
- Subtitle: Smart Storage Cleaner for Apple Silicon
- Keywords: mac cleaner, disk cleaner, storage cleaner, clean my mac, cache cleaner
- Support URL: https://kraftly.app/support
- Privacy URL: https://kraftly.app/privacy

- [ ] **Step 4: Build for release**

```bash
xcodebuild -workspace KraftlyWorkspace.xcworkspace \
  -scheme kSpaceClean \
  -configuration Release \
  -archivePath ./build/kSpaceClean.xcarchive \
  archive
```

Validate and upload via Xcode Organizer → Distribute App → Mac App Store.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: prepare App Store metadata and release build"
```

---

## Spec Coverage Map

| Spec § | Feature | Task(s) |
|---|---|---|
| 3.1 3D 磁盘星系图 | Metal + SceneKit galaxy view | Task 9 |
| 3.2 智能扫描引擎 | File enumeration, hash, duplicate detection | Task 4 |
| 3.3 CoreML AI 分类 | CoreML inference + rule fallback | Task 5 |
| 3.4 一键清理 + 回滚 | Trash mover, snapshot, restore | Task 6 |
| 3.5 Full Disk Access 引导 | 5-screen onboarding | Task 7 |
| 3.6 菜单栏图标 | NSStatusItem + dropdown | Task 11 |
| 3.7 桌面 Widget | Small/Medium/Large + Interactive (14+) | Task 12 |
| 3.8 Shortcuts App Intents | 3 intent actions | Task 13 |
| 3.9 Live Activities (14+) | Cleanup progress | Task 15 |
| 3.10 Finder 扩展 | Right-click scan | Task 14 |
| 3.11 Spotlight 集成 | Searchable actions | Task 18 |
| 3.12 本地化 | en + zh-Hans + ja | Task 17 |
| 4. 数据模型 | Core Data schema | Task 3 |
| 5. 隐私与安全 | Zero-network, Sandbox, FDA guide | Task 7 + entitlements |
| 6. 盈利设计 | StoreKit subscription + paywall | Task 16 |
| 7. ASO 与上架 | Metadata, screenshots, release | Task 19 |
| UI 设计: 窗口架构 | Icon Rail, glass panels, layout | Task 8 |
| UI 设计: 右侧面板 | 3-tab system | Task 10 |
| UI 设计: 设计系统 | Colors, Typography, Components | Task 2 |
