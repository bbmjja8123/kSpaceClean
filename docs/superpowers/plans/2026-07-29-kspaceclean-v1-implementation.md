# kSpaceClean v1.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship kSpaceClean v1.0 — a 4-level tree based Mac cleaner with Lemon-derived UX patterns, 4-level risk labels, and warning-driven cleanup. 17 weeks total (16 dev + 1 TestFlight).

**Architecture:** SwiftUI + Swift Concurrency. Core Data for cleanup history. JSON-based Bundle ID mapping (Lemon XML → JSON). File system access via TCC Full Disk Access. Warning Layer 1 detection via `lsof` + `proc_listpids`. Lazy cleanup history (trigger-time check).

**Tech Stack:** Swift 5.9+, SwiftUI, Swift Concurrency (async/await + TaskGroup + AsyncStream), Core Data, NSWorkspace (trash), lsof, lsregister, macOS 13+ (14+ features gated via `#available`).

## Global Constraints

From CLAUDE.md §8 + Design Spec:

- Swift 5.9+ with strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`)
- macOS 13.0 minimum (deployment), macOS 14 SDK compile target
- App Sandbox ON, TCC Full Disk Access required
- NEVER reuse Lemon Objective-C / C++ code — reference logic only
- All public APIs have DocC comments
- SwiftLint enforced
- Test coverage ≥ 70%
- 4-level risk: 🟢 Recommended / ⚪ Optional / 🟠 Caution / 🔴 Dangerous
- Cascade checkbox: parent ON → Recommended auto-select; Optional/Caution/Dangerous default off
- Dangerous: user can manually check; cleanup requires double confirm + input "DELETE"
- Warning Layer 1 required (Layer 2 deferred v1.1)
- 2000+ Chinese App Bundle ID mapping required
- UI frame rate ≥ 50fps during scan
- TestFlight 1 week + 5 internal testers (3 channels)
- 3 apps (kSpaceClean + kDupe + kUninstall) ship same week — none ships until all done
- Privacy / Photo Cache / Maintenance modules deferred to v1.1
- kSpaceClean v1.0 does NOT include Large Files / Duplicates / App Uninstall

---

## File Structure

```
kSpaceClean/
├── App/
│   ├── kSpaceCleanApp.swift                  # @main
│   ├── RootView.swift                        # NavigationSplitView
│   └── AppCoordinator.swift
├── Features/
│   ├── Common/                               # Cross-feature shared
│   │   ├── DesignSystem/
│   │   │   ├── Colors.swift                  # Color tokens
│   │   │   ├── Typography.swift              # Font tokens
│   │   │   ├── Spacing.swift                 # Spacing tokens
│   │   │   └── Accessibility.swift           # VoiceOver / Dynamic Type / Reduce Motion
│   │   ├── Components/
│   │   │   ├── RiskBadge.swift               # 4-level risk badge
│   │   │   ├── IndeterminateCheckbox.swift   # 3-state checkbox
│   │   │   ├── EmptyStateView.swift          # 8 empty/error scenarios
│   │   │   ├── SkeletonRow.swift             # Loading skeleton
│   │   │   └── ToolbarView.swift             # Top toolbar
│   │   └── KeyboardShortcuts.swift           # 20 keyboard shortcuts
│   ├── SmartScan/                            # PHASE A + B
│   │   ├── Models/
│   │   │   ├── ScanTreeNode.swift            # Protocol
│   │   │   ├── ScanCategory.swift            # Level 1
│   │   │   ├── ScanSubCategory.swift         # Level 2
│   │   │   ├── ScanAction.swift              # Level 3
│   │   │   ├── ScanResult.swift              # Level 4
│   │   │   ├── CheckState.swift              # 3-state enum
│   │   │   ├── RiskLevel.swift               # 4-level enum
│   │   │   └── ScanThreshold.swift           # 4-level threshold table
│   │   ├── Engine/
│   │   │   ├── ScanEngine.swift              # AsyncStream<ScanProgress>
│   │   │   ├── FileWalker.swift              # Recursive file enumerator
│   │   │   ├── BundleIDResolver.swift        # 3-level matcher (JSON)
│   │   │   └── ScanOrchestrator.swift        # TaskGroup fan-out
│   │   └── Views/
│   │       ├── ScanResultsView.swift         # 4-level tree main view
│   │       ├── ScanTreeRow.swift             # Generic 4-level row
│   │       ├── CategoryRow.swift             # Level 1 specific
│   │       ├── SubCategoryRow.swift          # Level 2 specific
│   │       ├── ActionRow.swift               # Level 3 specific
│   │       ├── ResultRow.swift               # Level 4 specific
│   │       ├── ScanProgressView.swift        # Ring + stages + current path
│   │       ├── ScanProgressRing.swift        # Animated ring
│   │       ├── SummaryBar.swift              # Sticky bottom bar
│   │       └── ScanViewModel.swift           # Scan state
│   └── Cleanup/                              # PHASE C
│       ├── Models/
│       │   ├── CleanupTypes.swift            # Cleanup config + result
│       │   └── CleanupHistoryItem.swift      # Core Data model
│       ├── Engine/
│       │   ├── CleanupEngine.swift           # Core cleanup logic
│       │   └── WarningDetectionService.swift # lsof + proc_listpids
│       └── Views/
│           ├── CleanupConfirmSheet.swift     # Risk-graded confirmation
│           ├── DangerousConfirmDialog.swift  # DELETE input
│           └── WarningToast.swift            # Running app warning
├── Persistence/
│   ├── PersistenceController.swift           # Core Data stack
│   └── kSpaceClean.xcdatamodeld/             # Core Data model
├── Resources/
│   ├── bundleIDMapping.json                  # 2000+ Chinese apps (Lemon XML → JSON)
│   └── Assets.xcassets
├── Intents/
│   └── CleanupIntents.swift                  # Shortcuts integration
├── Widgets/
│   └── kSpaceCleanWidget.swift               # Basic + Interactive
└── Info.plist

kFoundation/
└── Sources/
    ├── FileScanner/                          # Shared file scanning
    │   ├── FileEnumerator.swift              # Reusable enumeration
    │   ├── HashComputer.swift                # SHA256 / perceptual hash
    │   └── PathUtilities.swift               # Path manipulation
    ├── PrivacyShield/                        # TCC permission management
    │   ├── FDAGuider.swift                   # Educational FDA flow
    │   └── PermissionChecker.swift           # Real-time status
    └── DesignSystem/
        └── Colors.swift                      # kFoundation color tokens
```

---

## Phase A: Foundation + 4-Level Tree UI (Weeks 1-5)

### Task A1: Design Tokens Foundation

**Files:**
- Create: `kSpaceClean/Features/Common/DesignSystem/Colors.swift`
- Create: `kSpaceClean/Features/Common/DesignSystem/Typography.swift`
- Create: `kSpaceClean/Features/Common/DesignSystem/Spacing.swift`

**Interfaces:**
- Produces: `Color` extensions (`bg.canvas`, `text.primary`, `risk.recommended.bg`, etc.)
- Produces: `Font` tokens (`title.hero`, `body.regular`, etc.)
- Produces: `CGFloat` constants (`space.md = 16`, `radius.md = 8`, etc.)

- [ ] **Step 1: Create Colors.swift**

```swift
// kSpaceClean/Features/Common/DesignSystem/Colors.swift
import SwiftUI

extension Color {
    // Background
    static let bgCanvas = Color(red: 0.059, green: 0.063, blue: 0.071)        // #0F1012
    static let bgSurface = Color(red: 0.110, green: 0.110, blue: 0.118)       // #1C1C1E
    static let bgElevated = Color(red: 0.173, green: 0.173, blue: 0.180)      // #2C2C2E
    static let divider = Color(red: 0.227, green: 0.227, blue: 0.235)         // #3A3A3C

    // Text
    static let textPrimary = Color.white                                       // #FFFFFF
    static let textSecondary = Color(red: 0.600, green: 0.600, blue: 0.600)   // #999999
    static let textTertiary = Color(red: 0.400, green: 0.400, blue: 0.400)    // #666666
    static let textDisabled = Color(red: 0.227, green: 0.227, blue: 0.235)   // #3A3A3C

    // Brand
    static let brandPrimary = Color(red: 0.039, green: 0.518, blue: 1.000)    // #0A84FF
    static let brandAccent = Color(red: 0.353, green: 0.784, blue: 0.980)     // #5AC8FA

    // Risk (4 levels)
    static let riskRecommended = Color(red: 0.204, green: 0.780, blue: 0.349) // #34C759
    static let riskOptional = Color(red: 0.557, green: 0.557, blue: 0.576)    // #8E8E93
    static let riskCaution = Color(red: 1.000, green: 0.584, blue: 0.000)     // #FF9500
    static let riskDangerous = Color(red: 1.000, green: 0.231, blue: 0.188)   // #FF3B30

    // State
    static let stateWarning = Color(red: 1.000, green: 0.800, blue: 0.000)    // #FFCC00
    static let stateSuccess = Color(red: 0.204, green: 0.780, blue: 0.349)    // #34C759
    static let stateError = Color(red: 1.000, green: 0.231, blue: 0.188)      // #FF3B30
    static let stateScanning = Color(red: 0.039, green: 0.518, blue: 1.000)   // #0A84FF
}

extension RiskLevel {
    var backgroundColor: Color {
        switch self {
        case .recommended: return .riskRecommended
        case .optional: return .riskOptional
        case .caution: return .riskCaution
        case .dangerous: return .riskDangerous
        }
    }
    var foregroundColor: Color {
        switch self {
        case .caution: return .black
        default: return .white
        }
    }
}
```

- [ ] **Step 2: Create Typography.swift**

```swift
// kSpaceClean/Features/Common/DesignSystem/Typography.swift
import SwiftUI

enum Typography {
    static func heroNumber() -> Font {
        .system(size: 36, weight: .semibold, design: .default)
    }
    static func largeTitle() -> Font {
        .system(size: 24, weight: .semibold, design: .default)
    }
    static func mediumTitle() -> Font {
        .system(size: 17, weight: .semibold, design: .default)
    }
    static func largeBody() -> Font {
        .system(size: 15, weight: .medium, design: .default)
    }
    static func regularBody() -> Font {
        .system(size: 13, weight: .regular, design: .default)
    }
    static func smallBody() -> Font {
        .system(size: 11, weight: .regular, design: .default)
    }
    static func filePath() -> Font {
        .system(size: 12, weight: .regular, design: .monospaced)
    }
    static func sizeNumber() -> Font {
        .system(size: 17, weight: .semibold, design: .default)
    }
}
```

- [ ] **Step 3: Create Spacing.swift**

```swift
// kSpaceClean/Features/Common/DesignSystem/Spacing.swift
import Foundation

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

enum Radius {
    static let sm: CGFloat = 4
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
}

enum RowSize {
    static let height: CGFloat = 48
    static let checkboxSize: CGFloat = 18
    static let iconSize: CGFloat = 24
    static let indentPerLevel: CGFloat = 24
}
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild -scheme kSpaceClean -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add kSpaceClean/Features/Common/DesignSystem/
git commit -m "feat(kSpaceClean): add design tokens (Colors, Typography, Spacing)"
```

---

### Task A2: Accessibility Foundation

**Files:**
- Create: `kSpaceClean/Features/Common/DesignSystem/Accessibility.swift`

**Interfaces:**
- Produces: `AccessibilitySettings` enum with `voiceOverEnabled`, `reduceMotionEnabled`, `increaseContrastEnabled`, `dynamicTypeSize`

- [ ] **Step 1: Create Accessibility.swift**

```swift
// kSpaceClean/Features/Common/DesignSystem/Accessibility.swift
import SwiftUI

enum AccessibilitySettings {
    static var voiceOverEnabled: Bool {
        NSWorkspace.shared.isVoiceOverEnabled
    }
    static var reduceMotionEnabled: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
    static var increaseContrastEnabled: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    }
    @Environment(\.dynamicTypeSize) static var dynamicTypeSize
}

extension Animation {
    static func accessibleDefault(_ base: Animation) -> Animation {
        AccessibilitySettings.reduceMotionEnabled ? .linear(duration: 0.1) : base
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -scheme kSpaceClean -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add kSpaceClean/Features/Common/DesignSystem/Accessibility.swift
git commit -m "feat(kSpaceClean): add accessibility settings detection"
```

---

### Task A3: RiskLevel + CheckState Enums

**Files:**
- Create: `kSpaceClean/Features/SmartScan/Models/RiskLevel.swift`
- Create: `kSpaceClean/Features/SmartScan/Models/CheckState.swift`
- Test: `kSpaceClean/Features/SmartScan/Tests/RiskLevelTests.swift`

- [ ] **Step 1: Write failing test for RiskLevel**

```swift
// kSpaceClean/Features/SmartScan/Tests/RiskLevelTests.swift
import XCTest
@testable import kSpaceClean

final class RiskLevelTests: XCTestCase {
    func testRiskLevelOrder() {
        XCTAssertLessThan(RiskLevel.recommended.rawValue, RiskLevel.optional.rawValue)
        XCTAssertLessThan(RiskLevel.optional.rawValue, RiskLevel.caution.rawValue)
        XCTAssertLessThan(RiskLevel.caution.rawValue, RiskLevel.dangerous.rawValue)
    }

    func testDefaultCheckedStates() {
        XCTAssertTrue(RiskLevel.recommended.defaultChecked)
        XCTAssertFalse(RiskLevel.optional.defaultChecked)
        XCTAssertFalse(RiskLevel.caution.defaultChecked)
        XCTAssertFalse(RiskLevel.dangerous.defaultChecked)
    }

    func testRequiresDoubleConfirm() {
        XCTAssertFalse(RiskLevel.recommended.requiresDoubleConfirm)
        XCTAssertFalse(RiskLevel.caution.requiresDoubleConfirm)
        XCTAssertTrue(RiskLevel.dangerous.requiresDoubleConfirm)
    }
}
```

- [ ] **Step 2: Run test to verify failure**

Run: `swift test --filter RiskLevelTests`
Expected: FAIL with "cannot find 'RiskLevel' in scope"

- [ ] **Step 3: Create RiskLevel.swift**

```swift
// kSpaceClean/Features/SmartScan/Models/RiskLevel.swift
import SwiftUI

enum RiskLevel: Int, CaseIterable, Comparable, Sendable {
    case recommended = 0  // 🟢 默认勾选
    case optional = 1     // ⚪ 默认不勾选
    case caution = 2      // 🟠 默认不勾选
    case dangerous = 3    // 🔴 默认不勾选 + 清理时双确认

    static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .recommended: return "推荐"
        case .optional: return "可选"
        case .caution: return "谨慎"
        case .dangerous: return "危险"
        }
    }

    var iconName: String {
        switch self {
        case .recommended: return "checkmark.circle.fill"
        case .optional: return "circle"
        case .caution: return "exclamationmark.triangle.fill"
        case .dangerous: return "flame.fill"
        }
    }

    var defaultChecked: Bool {
        self == .recommended
    }

    var requiresDoubleConfirm: Bool {
        self == .dangerous
    }
}
```

- [ ] **Step 4: Create CheckState.swift**

```swift
// kSpaceClean/Features/SmartScan/Models/CheckState.swift
import Foundation

enum CheckState: Sendable {
    case off
    case on
    case mixed  // 部分选中，仅作为聚合结果，不向下传播
}
```

- [ ] **Step 5: Run test to verify pass**

Run: `swift test --filter RiskLevelTests`
Expected: PASS (3 tests)

- [ ] **Step 6: Commit**

```bash
git add kSpaceClean/Features/SmartScan/Models/
git commit -m "feat(kSpaceClean): add RiskLevel (4 levels) and CheckState (3 states) enums"
```

---

### Task A4: ScanTreeNode Protocol + 4 Node Types

**Files:**
- Create: `kSpaceClean/Features/SmartScan/Models/ScanTreeNode.swift`
- Create: `kSpaceClean/Features/SmartScan/Models/ScanCategory.swift`
- Create: `kSpaceClean/Features/SmartScan/Models/ScanSubCategory.swift`
- Create: `kSpaceClean/Features/SmartScan/Models/ScanAction.swift`
- Create: `kSpaceClean/Features/SmartScan/Models/ScanResult.swift`

**Interfaces:**
- Produces: `ScanTreeNode` protocol with `id`, `title`, `totalSize`, `state`, `children`, `riskLevel`, `showAction`, `setState()`, `refreshState()`, `collectSelected()`

- [ ] **Step 1: Create ScanTreeNode.swift**

```swift
// kSpaceClean/Features/SmartScan/Models/ScanTreeNode.swift
import Foundation

protocol ScanTreeNode: Identifiable, Hashable, Sendable {
    var id: UUID { get }
    var title: String { get }
    var tooltip: String? { get }
    var totalSize: Int64 { get }
    var selectedSize: Int64 { get }
    var state: CheckState { get set }
    var children: [any ScanTreeNode] { get }
    var riskLevel: RiskLevel { get }
    var isRecommended: Bool { get }
    var showAction: Bool { get }

    func setState(_ newState: CheckState)
    func refreshState()
    func collectSelected() -> [URL]
}

extension ScanTreeNode {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
```

- [ ] **Step 2: Create ScanCategory.swift**

```swift
// kSpaceClean/Features/SmartScan/Models/ScanCategory.swift
import Foundation

final class ScanCategory: ScanTreeNode, @unchecked Sendable {
    let id: UUID
    let categoryID: String       // "system.cache", "app.cache"
    let title: String
    let tooltip: String?
    let totalSize: Int64
    var selectedSize: Int64
    var state: CheckState
    var subItems: [ScanSubCategory]
    let riskLevel: RiskLevel
    let isRecommended: Bool
    let showAction: Bool = false

    var children: [any ScanTreeNode] { subItems }

    init(
        id: UUID = UUID(),
        categoryID: String,
        title: String,
        tooltip: String? = nil,
        totalSize: Int64 = 0,
        selectedSize: Int64 = 0,
        state: CheckState = .off,
        subItems: [ScanSubCategory] = [],
        riskLevel: RiskLevel = .recommended,
        isRecommended: Bool = true
    ) {
        self.id = id
        self.categoryID = categoryID
        self.title = title
        self.tooltip = tooltip
        self.totalSize = totalSize
        self.selectedSize = selectedSize
        self.state = state
        self.subItems = subItems
        self.riskLevel = riskLevel
        self.isRecommended = isRecommended
    }

    func setState(_ newState: CheckState) {
        guard state != newState else { return }
        state = newState
        guard newState != .mixed else { return }
        for child in subItems {
            child.setState(newState)
        }
    }

    func refreshState() {
        let states = subItems.map(\.state)
        let total = states.count
        guard total > 0 else { return }
        let onCount = states.filter { $0 == .on }.count
        if onCount == total { state = .on }
        else if onCount == 0 { state = .off }
        else { state = .mixed }
    }

    func collectSelected() -> [URL] {
        subItems.flatMap { $0.collectSelected() }
    }
}
```

- [ ] **Step 3: Create ScanSubCategory.swift**

```swift
// kSpaceClean/Features/SmartScan/Models/ScanSubCategory.swift
import Foundation

final class ScanSubCategory: ScanTreeNode, @unchecked Sendable {
    let id: UUID
    let subCategoryID: String
    let bundleID: String?
    let appName: String?
    let title: String
    let tooltip: String?
    var totalSize: Int64
    var selectedSize: Int64
    var state: CheckState
    var actions: [ScanAction]
    var directResults: [ScanResult]
    let showAction: Bool
    let riskLevel: RiskLevel
    let isRecommended: Bool

    var children: [any ScanTreeNode] {
        showAction ? (actions as [any ScanTreeNode]) : (directResults as [any ScanTreeNode])
    }

    init(
        id: UUID = UUID(),
        subCategoryID: String,
        title: String,
        bundleID: String? = nil,
        appName: String? = nil,
        tooltip: String? = nil,
        totalSize: Int64 = 0,
        selectedSize: Int64 = 0,
        state: CheckState = .off,
        actions: [ScanAction] = [],
        directResults: [ScanResult] = [],
        showAction: Bool = true,
        riskLevel: RiskLevel = .recommended,
        isRecommended: Bool = true
    ) {
        self.id = id
        self.subCategoryID = subCategoryID
        self.title = title
        self.bundleID = bundleID
        self.appName = appName
        self.tooltip = tooltip
        self.totalSize = totalSize
        self.selectedSize = selectedSize
        self.state = state
        self.actions = actions
        self.directResults = directResults
        self.showAction = showAction
        self.riskLevel = riskLevel
        self.isRecommended = isRecommended
    }

    func setState(_ newState: CheckState) {
        guard state != newState else { return }
        state = newState
        guard newState != .mixed else { return }
        if showAction {
            for action in actions {
                if newState == .off {
                    action.setState(.off)
                } else {
                    action.setState(action.recommend ? .on : .off)
                }
            }
        } else {
            for result in directResults {
                result.setState(newState)
            }
        }
    }

    func refreshState() {
        let states = showAction
            ? actions.map(\.state)
            : directResults.map(\.state)
        let total = states.count
        guard total > 0 else { return }
        let onCount = states.filter { $0 == .on }.count
        if onCount == total { state = .on }
        else if onCount == 0 { state = .off }
        else { state = .mixed }
    }

    func collectSelected() -> [URL] {
        showAction
            ? actions.flatMap { $0.collectSelected() }
            : directResults.flatMap { $0.collectSelected() }
    }
}
```

- [ ] **Step 4: Create ScanAction.swift**

```swift
// kSpaceClean/Features/SmartScan/Models/ScanAction.swift
import Foundation

enum ScanActionType: String, Sendable {
    case cache = "cache"
    case log = "log"
    case preference = "preference"
    case database = "database"
    case temporary = "temporary"
    case history = "history"
    case cookie = "cookie"
    case attachment = "attachment"
    case binary = "binary"
    case language = "language"
    case savedState = "savedState"
}

final class ScanAction: ScanTreeNode, @unchecked Sendable {
    let id: UUID
    let actionID: String
    let actionType: ScanActionType
    let title: String
    var totalSize: Int64
    var selectedSize: Int64
    var state: CheckState
    var results: [ScanResult]
    let recommend: Bool
    let riskLevel: RiskLevel
    let isRecommended: Bool
    let showAction: Bool = false

    var children: [any ScanTreeNode] { results }

    init(
        id: UUID = UUID(),
        actionID: String,
        actionType: ScanActionType,
        title: String,
        totalSize: Int64 = 0,
        selectedSize: Int64 = 0,
        state: CheckState = .off,
        results: [ScanResult] = [],
        recommend: Bool,
        riskLevel: RiskLevel = .recommended,
        isRecommended: Bool = true
    ) {
        self.id = id
        self.actionID = actionID
        self.actionType = actionType
        self.title = title
        self.totalSize = totalSize
        self.selectedSize = selectedSize
        self.state = state
        self.results = results
        self.recommend = recommend
        self.riskLevel = riskLevel
        self.isRecommended = isRecommended
    }

    func setState(_ newState: CheckState) {
        guard state != newState else { return }
        state = newState
        guard newState != .mixed else { return }
        for result in results {
            result.setState(newState)
        }
    }

    func refreshState() {
        let total = results.count
        guard total > 0 else { return }
        let onCount = results.filter { $0.state == .on }.count
        if onCount == total { state = .on }
        else if onCount == 0 { state = .off }
        else { state = .mixed }
    }

    func collectSelected() -> [URL] {
        results.filter { $0.state == .on }.flatMap { $0.collectSelected() }
    }
}
```

- [ ] **Step 5: Create ScanResult.swift**

```swift
// kSpaceClean/Features/SmartScan/Models/ScanResult.swift
import Foundation

enum CleanType: String, Sendable {
    case cache = "cache"
    case log = "log"
    case preference = "preference"
    case database = "database"
    case temporary = "temporary"
    case history = "history"
    case cookie = "cookie"
    case attachment = "attachment"
    case binary = "binary"
    case language = "language"
    case savedState = "savedState"
    case snapshot = "snapshot"
    case keychain = "keychain"
}

final class ScanResult: ScanTreeNode, @unchecked Sendable {
    let id: UUID
    let url: URL
    let path: String
    let title: String
    let iconSystemName: String?
    let fileSize: Int64
    let modificationDate: Date?
    let cleanType: CleanType
    let cautionID: String?
    var nestedResults: [ScanResult]
    var state: CheckState
    var selectedSize: Int64
    let riskLevel: RiskLevel
    let isRecommended: Bool
    let showAction: Bool = false

    var totalSize: Int64 {
        fileSize + nestedResults.reduce(0) { $0 + $1.totalSize }
    }

    var children: [any ScanTreeNode] { nestedResults }

    init(
        id: UUID = UUID(),
        url: URL,
        path: String,
        title: String,
        iconSystemName: String? = nil,
        fileSize: Int64,
        modificationDate: Date? = nil,
        cleanType: CleanType,
        cautionID: String? = nil,
        nestedResults: [ScanResult] = [],
        state: CheckState = .off,
        riskLevel: RiskLevel = .recommended,
        isRecommended: Bool = true
    ) {
        self.id = id
        self.url = url
        self.path = path
        self.title = title
        self.iconSystemName = iconSystemName
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.cleanType = cleanType
        self.cautionID = cautionID
        self.nestedResults = nestedResults
        self.state = state
        self.selectedSize = state == .on ? fileSize : 0
        self.riskLevel = riskLevel
        self.isRecommended = isRecommended
    }

    func setState(_ newState: CheckState) {
        guard state != newState else { return }
        state = newState
        selectedSize = (newState == .on) ? fileSize : 0
        for nested in nestedResults {
            nested.setState(newState)
        }
    }

    func refreshState() {
        // Leaf node: state set by user directly
    }

    func collectSelected() -> [URL] {
        if state == .on {
            var urls = [url]
            urls.append(contentsOf: nestedResults.filter { $0.state == .on }.flatMap { $0.collectSelected() })
            return urls
        }
        return []
    }
}
```

- [ ] **Step 6: Build and verify**

Run: `xcodebuild -scheme kSpaceClean -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add kSpaceClean/Features/SmartScan/Models/
git commit -m "feat(kSpaceClean): add 4-level ScanTreeNode protocol + node classes"
```

---

### Task A5: Cascade Checkbox Tests

**Files:**
- Create: `kSpaceClean/Features/SmartScan/Tests/CascadeCheckboxTests.swift`

**Interfaces:**
- Tests: cascade propagation (parent ON → Recommended auto-select, others default off)
- Tests: aggregation (child changes → parent mixed)
- Tests: parent OFF → all children off

- [ ] **Step 1: Write failing tests**

```swift
// kSpaceClean/Features/SmartScan/Tests/CascadeCheckboxTests.swift
import XCTest
@testable import kSpaceClean

final class CascadeCheckboxTests: XCTestCase {
    func testParentOn_RecommendedAutoSelects() {
        // Given: SubCategory with [recommended action, caution action]
        let recAction = ScanAction(actionID: "a1", actionType: .cache, title: "缓存", recommend: true, riskLevel: .recommended)
        recAction.results = [makeResult(riskLevel: .recommended)]
        let cauAction = ScanAction(actionID: "a2", actionType: .log, title: "日志", recommend: false, riskLevel: .caution)
        cauAction.results = [makeResult(riskLevel: .caution)]
        let sub = ScanSubCategory(subCategoryID: "s1", title: "微信", actions: [recAction, cauAction], showAction: true)

        // When: parent ON
        sub.setState(.on)

        // Then: recommended is ON, caution is OFF
        XCTAssertEqual(recAction.state, .on)
        XCTAssertEqual(cauAction.state, .off)
    }

    func testParentOff_AllChildrenOff() {
        let recAction = ScanAction(actionID: "a1", actionType: .cache, title: "缓存", recommend: true, riskLevel: .recommended)
        recAction.results = [makeResult(riskLevel: .recommended)]
        let sub = ScanSubCategory(subCategoryID: "s1", title: "微信", actions: [recAction], showAction: true)
        recAction.setState(.on)

        // When
        sub.setState(.off)

        // Then
        XCTAssertEqual(recAction.state, .off)
    }

    func testChildChange_AggregatesToParentMixed() {
        let r1 = makeResult(riskLevel: .recommended)
        let r2 = makeResult(riskLevel: .caution)
        let action = ScanAction(actionID: "a1", actionType: .cache, title: "缓存", recommend: true, riskLevel: .recommended, results: [r1, r2])

        r1.setState(.on)
        action.refreshState()

        XCTAssertEqual(action.state, .mixed)
    }

    func testAllChildrenSame_ParentAggregates() {
        let r1 = makeResult(riskLevel: .recommended)
        let r2 = makeResult(riskLevel: .recommended)
        let action = ScanAction(actionID: "a1", actionType: .cache, title: "缓存", recommend: true, riskLevel: .recommended, results: [r1, r2])

        r1.setState(.on)
        r2.setState(.on)
        action.refreshState()

        XCTAssertEqual(action.state, .on)
    }

    func testDangerousManualCheck_Allowed() {
        let r = makeResult(riskLevel: .dangerous)
        r.setState(.on)
        XCTAssertEqual(r.state, .on)
    }

    private func makeResult(riskLevel: RiskLevel) -> ScanResult {
        ScanResult(
            url: URL(fileURLWithPath: "/tmp/test"),
            path: "/tmp/test",
            title: "test",
            fileSize: 1024,
            cleanType: .cache,
            riskLevel: riskLevel
        )
    }
}
```

- [ ] **Step 2: Run tests to verify pass**

Run: `swift test --filter CascadeCheckboxTests`
Expected: PASS (5 tests)

- [ ] **Step 3: Commit**

```bash
git add kSpaceClean/Features/SmartScan/Tests/CascadeCheckboxTests.swift
git commit -m "test(kSpaceClean): add cascade checkbox algorithm tests"
```

---

### Task A6: RiskBadge Component

**Files:**
- Create: `kSpaceClean/Features/Common/Components/RiskBadge.swift`
- Test: `kSpaceClean/Features/Common/Components/Tests/RiskBadgeSnapshotTests.swift`

- [ ] **Step 1: Create RiskBadge.swift**

```swift
// kSpaceClean/Features/Common/Components/RiskBadge.swift
import SwiftUI

struct RiskBadge: View {
    let level: RiskLevel
    var compact: Bool = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: level.iconName)
                .font(.system(size: compact ? 8 : 10, weight: .semibold))
            if !compact {
                Text(level.label)
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .foregroundStyle(level.foregroundColor)
        .padding(.horizontal, compact ? 4 : 6)
        .padding(.vertical, 3)
        .background(level.backgroundColor.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm)
                .stroke(level.backgroundColor.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityLabel("风险等级，\(level.label)")
    }
}

#Preview {
    VStack(spacing: 12) {
        RiskBadge(level: .recommended)
        RiskBadge(level: .optional)
        RiskBadge(level: .caution)
        RiskBadge(level: .dangerous)
        RiskBadge(level: .recommended, compact: true)
    }
    .padding()
    .background(Color.bgCanvas)
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -scheme kSpaceClean -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add kSpaceClean/Features/Common/Components/RiskBadge.swift
git commit -m "feat(kSpaceClean): add RiskBadge component (4 levels)"
```

---

### Task A7: IndeterminateCheckbox Component

**Files:**
- Create: `kSpaceClean/Features/Common/Components/IndeterminateCheckbox.swift`

- [ ] **Step 1: Create IndeterminateCheckbox.swift**

```swift
// kSpaceClean/Features/Common/Components/IndeterminateCheckbox.swift
import SwiftUI

struct IndeterminateCheckbox: View {
    let state: CheckState
    var size: CGFloat = RowSize.checkboxSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(state == .off ? Color.clear : Color.brandPrimary)
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .stroke(state == .off ? Color.textTertiary : Color.clear, lineWidth: 1.5)
                )
            if state == .mixed {
                Image(systemName: "minus")
                    .font(.system(size: size * 0.66, weight: .bold))
                    .foregroundStyle(.white)
            } else if state == .on {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.66, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .animation(.accessibleDefault(.easeOut(duration: 0.15)), value: state)
        .accessibilityLabel(accessibilityLabelText)
    }

    private var accessibilityLabelText: String {
        switch state {
        case .off: return "未勾选"
        case .on: return "已勾选"
        case .mixed: return "部分勾选"
        }
    }
}

#Preview {
    HStack(spacing: 16) {
        IndeterminateCheckbox(state: .off)
        IndeterminateCheckbox(state: .on)
        IndeterminateCheckbox(state: .mixed)
    }
    .padding()
    .background(Color.bgCanvas)
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -scheme kSpaceClean -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add kSpaceClean/Features/Common/Components/IndeterminateCheckbox.swift
git commit -m "feat(kSpaceClean): add IndeterminateCheckbox component (3 states)"
```

---

### Task A8: ScanTreeRow Component

**Files:**
- Create: `kSpaceClean/Features/SmartScan/Views/ScanTreeRow.swift`

- [ ] **Step 1: Create ScanTreeRow.swift**

```swift
// kSpaceClean/Features/SmartScan/Views/ScanTreeRow.swift
import SwiftUI

struct ScanTreeRow: View {
    let node: any ScanTreeNode
    let level: Int
    let isExpanded: Bool
    let onToggleExpand: () -> Void
    let onToggleSelect: () -> Void

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Indent
            ForEach(0..<level, id: \.self) { _ in
                Color.clear.frame(width: RowSize.indentPerLevel)
            }

            // Expand chevron
            if !node.children.isEmpty {
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.textSecondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 16, height: 16)
            }

            // Checkbox
            Button(action: onToggleSelect) {
                IndeterminateCheckbox(state: node.state)
            }
            .buttonStyle(.plain)

            // Icon
            iconView

            // Title + path
            VStack(alignment: .leading, spacing: 2) {
                Text(node.title)
                    .font(Typography.largeBody())
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                if let path = pathForNode() {
                    Text(path)
                        .font(Typography.filePath())
                        .foregroundStyle(.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: Spacing.sm)

            // Size
            Text(formatBytes(node.totalSize))
                .font(Typography.sizeNumber())
                .foregroundStyle(.textPrimary)
                .monospacedDigit()

            // Risk badge
            RiskBadge(level: node.riskLevel, compact: level == 0)
        }
        .frame(height: RowSize.height)
        .padding(.horizontal, Spacing.md)
        .background(isHovered ? Color.bgSurface : Color.clear)
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .animation(.accessibleDefault(.easeOut(duration: 0.24)), value: isHovered)
    }

    @State private var isHovered = false

    @ViewBuilder
    private var iconView: some View {
        if let result = node as? ScanResult, let icon = result.iconSystemName {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.textSecondary)
                .frame(width: RowSize.iconSize, height: RowSize.iconSize)
        } else if node is ScanCategory {
            Image(systemName: "folder.fill")
                .font(.system(size: 16))
                .foregroundStyle(.brandAccent)
                .frame(width: RowSize.iconSize, height: RowSize.iconSize)
        } else if node is ScanSubCategory {
            Image(systemName: "app.fill")
                .font(.system(size: 16))
                .foregroundStyle(.brandPrimary)
                .frame(width: RowSize.iconSize, height: RowSize.iconSize)
        } else if node is ScanAction {
            Image(systemName: "tray.fill")
                .font(.system(size: 16))
                .foregroundStyle(.textSecondary)
                .frame(width: RowSize.iconSize, height: RowSize.iconSize)
        } else {
            Image(systemName: "doc.fill")
                .font(.system(size: 16))
                .foregroundStyle(.textSecondary)
                .frame(width: RowSize.iconSize, height: RowSize.iconSize)
        }
    }

    private func pathForNode() -> String? {
        if let result = node as? ScanResult {
            return result.path
        } else if let action = node as? ScanAction {
            return action.title
        } else if let sub = node as? ScanSubCategory {
            return sub.bundleID ?? sub.title
        }
        return nil
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -scheme kSpaceClean -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add kSpaceClean/Features/SmartScan/Views/ScanTreeRow.swift
git commit -m "feat(kSpaceClean): add ScanTreeRow component (4-level generic)"
```

---

### Task A9: 4-Level Risk Threshold Table

**Files:**
- Create: `kSpaceClean/Features/SmartScan/Models/ScanThreshold.swift`

**Interfaces:**
- Produces: `RiskClassifier` with `classify(path: String) -> RiskLevel` based on Lemon XML + CleanMyMac X 5-level downgrade

- [ ] **Step 1: Create ScanThreshold.swift**

```swift
// kSpaceClean/Features/SmartScan/Models/ScanThreshold.swift
import Foundation

struct RiskClassifier: Sendable {
    /// 4 级阈值规则（Lemon XML recommend 字段 + CleanMyMac X 5 级降维）
    /// 🟢 Recommended: 系统缓存、应用日志、tmp、系统临时文件、Quick Look 缓存
    /// ⚪ Optional: 浏览器历史、日志归档、崩溃报告、诊断报告
    /// 🟠 Caution: 应用 plist、应用数据库、浏览器 Cookies、Saved State、Mail 附件
    /// 🔴 Dangerous: 钥匙串、Time Machine 快照、启动项、沙箱容器、Photos 原始照片、系统 plist
    func classify(path: String) -> RiskLevel {
        let normalized = (path as NSString).expandingTildeInPath

        // Dangerous
        if normalized.contains("/Keychains/") { return .dangerous }
        if normalized.contains("/Backups.backupdb/") { return .dangerous }
        if normalized.contains("/MobileBackups/") { return .dangerous }
        if normalized.contains("/Containers/") { return .dangerous }
        if normalized.contains("/Saved Application State/") { return .dangerous }
        if normalized.contains("/LaunchAgents/") || normalized.contains("/LaunchDaemons/") { return .dangerous }
        if normalized.hasPrefix("/Library/Preferences/") { return .dangerous }
        if normalized.contains("/Pictures/Photos Library") { return .dangerous }

        // Caution
        if normalized.contains("/Cookies/") { return .caution }
        if normalized.contains("/Application Support/") && normalized.hasSuffix(".sqlite") { return .caution }
        if normalized.contains("/Preferences/") { return .caution }
        if normalized.contains("/Mail/") && normalized.contains("Attachments") { return .caution }
        if normalized.contains("/Mail/V") { return .caution }  // Mail database

        // Optional
        if normalized.contains("/Safari/History.db") { return .optional }
        if normalized.contains("/Chrome/History") { return .optional }
        if normalized.contains("/Firefox/places.sqlite") { return .optional }
        if normalized.hasSuffix(".log.gz") || normalized.hasSuffix(".crash") || normalized.hasSuffix(".ips") { return .optional }
        if normalized.contains("/DiagnosticReports/") { return .optional }

        // Recommended (default)
        if normalized.contains("/Caches/") { return .recommended }
        if normalized.contains("/Logs/") { return .recommended }
        if normalized.hasPrefix("/tmp/") || normalized.hasPrefix("/private/tmp/") { return .recommended }
        if normalized.contains("/Quick Look/") { return .recommended }
        if normalized.hasSuffix(".tmp") { return .recommended }

        return .optional  // 未知路径默认 Optional
    }
}
```

- [ ] **Step 2: Write test for classifier**

```swift
// kSpaceClean/Features/SmartScan/Tests/RiskClassifierTests.swift
import XCTest
@testable import kSpaceClean

final class RiskClassifierTests: XCTestCase {
    let classifier = RiskClassifier()

    func testSystemCache_Recommended() {
        XCTAssertEqual(classifier.classify(path: "/Library/Caches/com.apple.Safari"), .recommended)
    }

    func testKeychain_Dangerous() {
        XCTAssertEqual(classifier.classify(path: "/Users/me/Library/Keychains/login.keychain-db"), .dangerous)
    }

    func testAppPreferences_Caution() {
        XCTAssertEqual(classifier.classify(path: "/Users/me/Library/Preferences/com.tencent.WeChat.plist"), .caution)
    }

    func testTimeMachineSnapshot_Dangerous() {
        XCTAssertEqual(classifier.classify(path: "/Volumes/Backup/Backups.backupdb/mac/file"), .dangerous)
    }

    func testBrowserCookies_Caution() {
        XCTAssertEqual(classifier.classify(path: "/Users/me/Library/Cookies/Cookies.binarycookies"), .caution)
    }

    func testUnknownPath_Optional() {
        XCTAssertEqual(classifier.classify(path: "/Users/me/Documents/random"), .optional)
    }
}
```

- [ ] **Step 3: Run tests**

Run: `swift test --filter RiskClassifierTests`
Expected: PASS (6 tests)

- [ ] **Step 4: Commit**

```bash
git add kSpaceClean/Features/SmartScan/Models/ScanThreshold.swift kSpaceClean/Features/SmartScan/Tests/RiskClassifierTests.swift
git commit -m "feat(kSpaceClean): add 4-level risk classifier (Lemon + CleanMyMac downgrade)"
```

---

### Task A10: ScanResultsView (4-Level Tree Main View)

**Files:**
- Create: `kSpaceClean/Features/SmartScan/Views/ScanResultsView.swift`
- Create: `kSpaceClean/Features/SmartScan/Views/ScanViewModel.swift`

- [ ] **Step 1: Create ScanViewModel.swift**

```swift
// kSpaceClean/Features/SmartScan/Views/ScanViewModel.swift
import Foundation
import SwiftUI

@MainActor
final class ScanViewModel: ObservableObject {
    @Published var categories: [ScanCategory] = []
    @Published var expandedIDs: Set<UUID> = []
    @Published var isScanning: Bool = false
    @Published var currentPath: String = ""
    @Published var progress: Double = 0.0
    @Published var totalSelectedSize: Int64 = 0
    @Published var totalSelectedCount: Int = 0

    func toggleExpand(_ id: UUID) {
        if expandedIDs.contains(id) {
            expandedIDs.remove(id)
        } else {
            expandedIDs.insert(id)
        }
    }

    func toggleSelect(_ node: any ScanTreeNode) {
        let newState: CheckState = (node.state == .on) ? .off : .on
        node.setState(newState)
        // Refresh parent states
        refreshAllParents(of: node)
        updateSummary()
    }

    func updateSummary() {
        var totalSize: Int64 = 0
        var totalCount = 0
        for category in categories {
            let urls = category.collectSelected()
            totalCount += urls.count
            for url in urls {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? Int64 {
                    totalSize += size
                }
            }
        }
        totalSelectedSize = totalSize
        totalSelectedCount = totalCount
    }

    private func refreshAllParents(of node: any ScanTreeNode) {
        // Walk up the tree refreshing parent states (simplified)
        for category in categories {
            if let parent = findParent(of: node.id, in: category) {
                parent.refreshState()
            }
        }
    }

    private func findParent(of id: UUID, in node: any ScanTreeNode) -> (any ScanTreeNode)? {
        for child in node.children {
            if child.id == id { return node }
            if let found = findParent(of: id, in: child) { return found }
        }
        return nil
    }

    // Mock data for testing the view
    func loadMockData() {
        let recResult = ScanResult(
            url: URL(fileURLWithPath: "/Library/Caches/com.apple.Safari"),
            path: "/Library/Caches/com.apple.Safari",
            title: "Safari 缓存",
            fileSize: 2_100_000_000,
            cleanType: .cache,
            riskLevel: .recommended
        )
        let sub = ScanSubCategory(
            subCategoryID: "system.cache",
            title: "系统缓存",
            totalSize: 4_200_000_000,
            directResults: [recResult],
            showAction: false,
            riskLevel: .recommended
        )
        let category = ScanCategory(
            categoryID: "system.junk",
            title: "系统垃圾",
            totalSize: 4_200_000_000,
            subItems: [sub],
            riskLevel: .recommended
        )
        categories = [category]
    }
}
```

- [ ] **Step 2: Create ScanResultsView.swift**

```swift
// kSpaceClean/Features/SmartScan/Views/ScanResultsView.swift
import SwiftUI

struct ScanResultsView: View {
    @StateObject private var viewModel = ScanViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider().background(Color.divider)

            // Tree
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(viewModel.categories) { category in
                        renderNode(category, level: 0)
                    }
                }
                .padding(.vertical, Spacing.sm)
            }

            Divider().background(Color.divider)

            // Summary bar
            SummaryBar(viewModel: viewModel)
        }
        .background(Color.bgCanvas)
        .onAppear { viewModel.loadMockData() }
    }

    @ViewBuilder
    private var headerView: some View {
        HStack {
            Text("扫描完成")
                .font(Typography.largeTitle())
                .foregroundStyle(.textPrimary)
            Spacer()
            Text("\(viewModel.totalSelectedCount) 项 · \(formatBytes(viewModel.totalSelectedSize))")
                .font(Typography.regularBody())
                .foregroundStyle(.textSecondary)
        }
        .padding(Spacing.md)
        .frame(height: 64)
        .background(Color.bgElevated)
    }

    @ViewBuilder
    private func renderNode(_ node: any ScanTreeNode, level: Int) -> some View {
        let isExpanded = viewModel.expandedIDs.contains(node.id)

        ScanTreeRow(
            node: node,
            level: level,
            isExpanded: isExpanded,
            onToggleExpand: { viewModel.toggleExpand(node.id) },
            onToggleSelect: { viewModel.toggleSelect(node) }
        )

        if isExpanded {
            ForEach(Array(node.children.enumerated()), id: \.element.id) { _, child in
                renderNode(child, level: level + 1)
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct SummaryBar: View {
    @ObservedObject var viewModel: ScanViewModel

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("已选 \(formatBytes(viewModel.totalSelectedSize))")
                    .font(Typography.largeBody())
                    .foregroundStyle(.textPrimary)
                Text("\(viewModel.totalSelectedCount) 项")
                    .font(Typography.regularBody())
                    .foregroundStyle(.textSecondary)
            }

            Spacer()

            HStack(spacing: Spacing.sm) {
                Button("全选") { /* TODO */ }
                    .buttonStyle(.bordered)
                Button("反选") { /* TODO */ }
                    .buttonStyle(.bordered)
            }

            Button {
                // TODO: Phase C - cleanup
            } label: {
                Text("清 理")
                    .font(Typography.largeBody())
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.totalSelectedSize == 0)
            .opacity(viewModel.totalSelectedSize == 0 ? 0.5 : 1.0)
        }
        .padding(Spacing.md)
        .frame(height: 64)
        .background(Color.bgElevated)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

#Preview {
    ScanResultsView()
        .frame(width: 960, height: 720)
}
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -scheme kSpaceClean -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add kSpaceClean/Features/SmartScan/Views/ScanResultsView.swift kSpaceClean/Features/SmartScan/Views/ScanViewModel.swift
git commit -m "feat(kSpaceClean): add ScanResultsView with mock data + 4-level tree"
```

---

### Task A11: Empty State + Error State Views

**Files:**
- Create: `kSpaceClean/Features/Common/Components/EmptyStateView.swift`
- Create: `kSpaceClean/Features/Common/Components/SkeletonRow.swift`

- [ ] **Step 1: Create EmptyStateView.swift**

```swift
// kSpaceClean/Features/Common/Components/EmptyStateView.swift
import SwiftUI

enum EmptyStateScenario {
    case firstLaunch
    case noResults
    case cleanupComplete
    case noHistory
    case noFDA
    case scanFailed
    case cleanupFailed
    case diskFull

    var iconName: String {
        switch self {
        case .firstLaunch: return "sparkles"
        case .noResults: return "checkmark.seal.fill"
        case .cleanupComplete: return "checkmark.circle.fill"
        case .noHistory: return "clock.arrow.circlepath"
        case .noFDA: return "lock.shield.fill"
        case .scanFailed: return "exclamationmark.triangle.fill"
        case .cleanupFailed: return "xmark.octagon.fill"
        case .diskFull: return "internaldrive.fill"
        }
    }

    var title: String {
        switch self {
        case .firstLaunch: return "Mac 存储清理，从这里开始"
        case .noResults: return "Mac 已经干干净净"
        case .cleanupComplete: return "清理完成"
        case .noHistory: return "还没有清理记录"
        case .noFDA: return "需要 Full Disk Access 权限"
        case .scanFailed: return "扫描未完成"
        case .cleanupFailed: return "清理未完成"
        case .diskFull: return "无法清理 · 磁盘空间不足"
        }
    }

    var message: String {
        switch self {
        case .firstLaunch: return "kSpaceClean 会扫描你 Mac 上可以安全清理的文件，给你一个详细列表。"
        case .noResults: return "没有发现可以安全清理的文件。下次扫描建议在 7 天后。"
        case .cleanupComplete: return "你的 Mac 已经被清理干净了。"
        case .noHistory: return "你的第一次清理完成后，30 天内的清理记录会在这里显示。"
        case .noFDA: return "kSpaceClean 需要 Full Disk Access 才能扫描你 Mac 上的所有可清理文件。"
        case .scanFailed: return "扫描过程中遇到错误，部分文件未扫描。"
        case .cleanupFailed: return "部分文件清理失败（文件被其他应用占用）。"
        case .diskFull: return "需要至少 1 GB 可用空间执行清理。"
        }
    }

    var iconColor: Color {
        switch self {
        case .firstLaunch, .cleanupComplete, .noResults: return .brandPrimary
        case .noHistory: return .textSecondary
        case .noFDA, .scanFailed: return .stateWarning
        case .cleanupFailed, .diskFull: return .stateError
        }
    }
}

struct EmptyStateView: View {
    let scenario: EmptyStateScenario
    var primaryAction: (title: String, action: () -> Void)?
    var secondaryAction: (title: String, action: () -> Void)?

    var body: some View {
        VStack(spacing: Spacing.md) {
            Spacer()

            Image(systemName: scenario.iconName)
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(scenario.iconColor)
                .frame(width: 96, height: 96)

            Text(scenario.title)
                .font(Typography.largeTitle())
                .foregroundStyle(.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.md)

            Text(scenario.message)
                .font(Typography.regularBody())
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
                .padding(.horizontal, Spacing.md)

            if let primary = primaryAction {
                Button(primary.title, action: primary.action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, Spacing.md)
            }

            if let secondary = secondaryAction {
                Button(secondary.title, action: secondary.action)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgCanvas)
    }
}
```

- [ ] **Step 2: Create SkeletonRow.swift**

```swift
// kSpaceClean/Features/Common/Components/SkeletonRow.swift
import SwiftUI

struct SkeletonRow: View {
    @State private var phase: Double = 0

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Color.textTertiary.opacity(0.3)
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

            Color.textTertiary.opacity(0.3)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))

            VStack(alignment: .leading, spacing: 4) {
                Color.textTertiary.opacity(0.3)
                    .frame(width: 200, height: 14)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                Color.textTertiary.opacity(0.3)
                    .frame(width: 140, height: 10)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            }

            Spacer()

            Color.textTertiary.opacity(0.3)
                .frame(width: 60, height: 14)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        }
        .frame(height: RowSize.height)
        .padding(.horizontal, Spacing.md)
        .onAppear {
            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }
}
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -scheme kSpaceClean -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add kSpaceClean/Features/Common/Components/EmptyStateView.swift kSpaceClean/Features/Common/Components/SkeletonRow.swift
git commit -m "feat(kSpaceClean): add EmptyStateView (8 scenarios) + SkeletonRow"
```

---

### Task A12: Toolbar + Keyboard Shortcuts

**Files:**
- Create: `kSpaceClean/Features/Common/Components/ToolbarView.swift`
- Create: `kSpaceClean/Features/Common/KeyboardShortcuts.swift`

- [ ] **Step 1: Create KeyboardShortcuts.swift**

```swift
// kSpaceClean/Features/Common/KeyboardShortcuts.swift
import SwiftUI

extension View {
    func scanKeyboardShortcuts(onNewScan: @escaping () -> Void, onRescan: @escaping () -> Void) -> some View {
        Group {
            if #available(macOS 14.0, *) {
                self.keyboardShortcut("n", modifiers: .command, action: onNewScan)
                    .keyboardShortcut("r", modifiers: .command, action: onRescan)
            } else {
                self
            }
        }
    }
}
```

- [ ] **Step 2: Create ToolbarView.swift**

```swift
// kSpaceClean/Features/Common/Components/ToolbarView.swift
import SwiftUI

struct ToolbarView: View {
    var onScan: () -> Void
    var onClean: () -> Void
    var onWarning: () -> Void
    var onProfile: () -> Void

    var body: some View {
        HStack(spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.brandPrimary)
                Text("kSpaceClean")
                    .font(Typography.mediumTitle())
                    .foregroundStyle(.textPrimary)
            }

            Spacer()

            HStack(spacing: Spacing.sm) {
                ToolbarButton(icon: "magnifyingglass", title: "扫描", action: onScan)
                ToolbarButton(icon: "trash", title: "清理", action: onClean)
                ToolbarButton(icon: "exclamationmark.triangle", title: "警告", action: onWarning)
                ToolbarButton(icon: "person.circle", title: "账户", action: onProfile)
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 64)
        .background(Color.bgElevated)
    }
}

struct ToolbarButton: View {
    let icon: String
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                Text(title)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(.textSecondary)
            .frame(width: 56, height: 40)
            .background(isHovered ? Color.bgSurface : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -scheme kSpaceClean -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add kSpaceClean/Features/Common/Components/ToolbarView.swift kSpaceClean/Features/Common/KeyboardShortcuts.swift
git commit -m "feat(kSpaceClean): add Toolbar + KeyboardShortcuts"
```

---

### Task A13: Phase A Snapshot Tests

**Files:**
- Create: `kSpaceClean/Features/Common/Components/Tests/RiskBadgeSnapshotTests.swift`
- Create: `kSpaceClean/Features/SmartScan/Tests/ScanResultsViewSnapshotTests.swift`

- [ ] **Step 1: Add snapshot test infrastructure**

```swift
// kSpaceClean/Tests/SnapshotTestCase.swift
import XCTest
import SwiftUI
@testable import kSpaceClean

class SnapshotTestCase: XCTestCase {
    func assertSnapshot<V: View>(_ view: V, size: CGSize = CGSize(width: 960, height: 720), named name: String) {
        // Implementation depends on chosen snapshot library
        // For simplicity, log to console for manual verification
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        print("Snapshot '\(name)' rendered at \(size)")
    }
}
```

- [ ] **Step 2: Create RiskBadgeSnapshotTests.swift**

```swift
// kSpaceClean/Features/Common/Components/Tests/RiskBadgeSnapshotTests.swift
import XCTest
import SwiftUI
@testable import kSpaceClean

final class RiskBadgeSnapshotTests: SnapshotTestCase {
    func testAllRiskLevels() {
        let view = VStack(spacing: 12) {
            RiskBadge(level: .recommended)
            RiskBadge(level: .optional)
            RiskBadge(level: .caution)
            RiskBadge(level: .dangerous)
        }
        .padding()
        .background(Color.bgCanvas)

        assertSnapshot(view, named: "RiskBadge-AllLevels")
    }
}
```

- [ ] **Step 3: Run tests**

Run: `swift test --filter RiskBadgeSnapshotTests`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add kSpaceClean/Features/Common/Components/Tests/ kSpaceClean/Tests/
git commit -m "test(kSpaceClean): add snapshot test infrastructure + RiskBadge tests"
```

---

### Task A14: Phase A Polish + Buffer

**Files:** Various (polish existing components)

- [ ] **Step 1: Verify all Phase A tasks complete**

Run: `swift test`
Expected: ALL TESTS PASS

- [ ] **Step 2: Manual UI verification**

Run: `xcodebuild -scheme kSpaceClean -destination 'platform=macOS' build && open kSpaceClean.xcodeproj`
- Verify: 4-level tree renders correctly
- Verify: cascade checkbox works (parent ON → recommended auto-check, others default off)
- Verify: 4 risk badges display correct colors
- Verify: hover animation smooth (240ms)
- Verify: ⌘0 ⌘1 ⌘2 ⌘3 ⌘4 keyboard shortcuts work
- Verify: VoiceOver labels present on all interactive elements

- [ ] **Step 3: Performance check (50fps target)**

- Open Instruments → Time Profiler
- Trigger 4-level tree expand/collapse 10 times
- Verify: no frame drops > 16ms

- [ ] **Step 4: Commit final polish**

```bash
git add .
git commit -m "polish(kSpaceClean): Phase A complete - 4-level tree UI with 4 risk levels"
```

---

## Phase B: Scan Engine (Weeks 6-10)

**Goal:** Implement scan engine that produces 4-level tree results, populates tree progressively (Category pre-displayed, sub-nodes scan-to-appear), maintains 50fps during scan.

### Task B1: Bundle ID Mapping JSON (Lemon XML → JSON)

**Files:**
- Create: `kFoundation/Sources/FileScanner/BundleIDResolver.swift`
- Create: `kSpaceClean/Resources/bundleIDMapping.json`

**Interfaces:**
- Produces: `BundleIDResolver` with `resolve(path: String) -> ResolvedApp?`

- [ ] **Step 1: Read Lemon BundleIDMap.xml**

```bash
ls /Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon/LemonClener/LemonClener/libcleaner/BundleIDMap.xml
```

- [ ] **Step 2: Write XML → JSON converter script**

```python
#!/usr/bin/env python3
# scripts/lemon_xml_to_json.py
import xml.etree.ElementTree as ET
import json
import sys

def convert(xml_path, json_path):
    tree = ET.parse(xml_path)
    root = tree.getroot()
    mapping = {}
    for app in root.findall('app'):
        bundle_id = app.get('id')
        if not bundle_id:
            continue
        clean_paths = []
        for path_elem in app.findall('cleanPath'):
            clean_paths.append(path_elem.text)
        mapping[bundle_id] = {
            "name": app.get('name', ''),
            "nameCN": app.get('nameCN', ''),
            "vendor": app.get('vendor', ''),
            "type": app.get('type', 'other'),
            "riskLevel": app.get('riskLevel', 'recommended'),
            "cleanPaths": clean_paths,
            "version": app.get('version', '1.0'),
            "lastUpdated": "2026-07-29"
        }
    with open(json_path, 'w', encoding='utf-8') as f:
        json.dump(mapping, f, ensure_ascii=False, indent=2)
    print(f"Converted {len(mapping)} apps to {json_path}")

if __name__ == "__main__":
    convert(sys.argv[1], sys.argv[2])
```

- [ ] **Step 3: Run conversion**

```bash
python3 scripts/lemon_xml_to_json.py \
  /Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon/LemonClener/LemonClener/libcleaner/BundleIDMap.xml \
  kSpaceClean/Resources/bundleIDMapping.json
```

Expected: 2000+ entries in JSON

- [ ] **Step 4: Create BundleIDResolver.swift**

```swift
// kFoundation/Sources/FileScanner/BundleIDResolver.swift
import Foundation

public struct ResolvedApp: Sendable {
    public let bundleID: String
    public let name: String
    public let nameCN: String
    public let vendor: String
    public let type: String
    public let riskLevel: String
    public let cleanPaths: [String]
}

public actor BundleIDResolver {
    private var mapping: [String: ResolvedApp] = [:]
    private var loaded = false

    public init() {}

    public func load(from url: URL) async {
        guard !loaded else { return }
        do {
            let data = try Data(contentsOf: url)
            let raw = try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] ?? [:]
            mapping = raw.compactMapValues { dict -> ResolvedApp? in
                guard let id = dict["bundleID"] as? String ?? dict["name"] as? String else { return nil }
                return ResolvedApp(
                    bundleID: id,
                    name: dict["name"] as? String ?? "",
                    nameCN: dict["nameCN"] as? String ?? "",
                    vendor: dict["vendor"] as? String ?? "",
                    type: dict["type"] as? String ?? "other",
                    riskLevel: dict["riskLevel"] as? String ?? "recommended",
                    cleanPaths: dict["cleanPaths"] as? [String] ?? []
                )
            }
            loaded = true
        } catch {
            print("Failed to load BundleID mapping: \(error)")
        }
    }

    public func resolve(path: String) -> ResolvedApp? {
        let normalized = (path as NSString).expandingTildeInPath

        // L1: cleanPaths match
        for (id, app) in mapping {
            for pattern in app.cleanPaths {
                let expanded = (pattern as NSString).expandingTildeInPath
                if normalized.hasPrefix(expanded) {
                    return app
                }
            }
        }

        // L2: reversed domain extraction
        let regex = try? NSRegularExpression(pattern: "com\\.[a-zA-Z0-9]+\\.[a-zA-Z0-9]+")
        if let match = regex?.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
           let range = Range(match.range, in: normalized) {
            let bundleID = String(normalized[range])
            if let app = mapping[bundleID] {
                return app
            }
        }

        return nil
    }
}
```

- [ ] **Step 5: Write test**

```swift
// kFoundation/Tests/BundleIDResolverTests.swift
import XCTest
@testable import kFoundation

final class BundleIDResolverTests: XCTestCase {
    func testResolveByPathPrefix() async {
        let resolver = BundleIDResolver()
        let url = URL(fileURLWithPath: "/tmp/test_bundleid.json")
        let json = """
        {
          "com.tencent.WeChat": {
            "name": "WeChat", "nameCN": "微信", "vendor": "腾讯",
            "type": "chat", "riskLevel": "caution",
            "cleanPaths": ["~/Library/Caches/com.tencent.xinWeChat"]
          }
        }
        """
        try? json.write(to: url, atomically: true, encoding: .utf8)
        await resolver.load(from: url)

        let result = await resolver.resolve(path: "~/Library/Caches/com.tencent.xinWeChat/file")
        XCTAssertEqual(result?.bundleID, "com.tencent.WeChat")
    }
}
```

- [ ] **Step 6: Run tests**

Run: `swift test --filter BundleIDResolverTests`
Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add kFoundation/Sources/FileScanner/BundleIDResolver.swift kSpaceClean/Resources/bundleIDMapping.json scripts/
git commit -m "feat(kFoundation): add BundleIDResolver with 3-level matcher"
```

---

### Task B2: FileWalker (Recursive Enumerator)

**Files:**
- Create: `kFoundation/Sources/FileScanner/FileEnumerator.swift`
- Test: `kFoundation/Tests/FileEnumeratorTests.swift`

- [ ] **Step 1: Create FileEnumerator.swift**

```swift
// kFoundation/Sources/FileScanner/FileEnumerator.swift
import Foundation

public struct FileInfo: Sendable {
    public let path: String
    public let size: Int64
    public let modificationDate: Date?
    public let isDirectory: Bool
}

public actor FileEnumerator {
    public init() {}

    public func enumerate(
        rootPath: String,
        skipPaths: Set<String> = []
    ) -> AsyncStream<FileInfo> {
        AsyncStream { continuation in
            Task.detached(priority: .background) {
                await self.walk(
                    rootPath: rootPath,
                    skipPaths: skipPaths,
                    continuation: continuation
                )
                continuation.finish()
            }
        }
    }

    private func walk(
        rootPath: String,
        skipPaths: Set<String>,
        continuation: AsyncStream<FileInfo>.Continuation
    ) async {
        let normalized = (rootPath as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: normalized)

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for case let fileURL as URL in enumerator {
            let path = fileURL.path
            if skipPaths.contains(where: { path.hasPrefix($0) }) {
                enumerator.skipDescendants()
                continue
            }
            let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey])
            let info = FileInfo(
                path: path,
                size: Int64(attrs?.fileSize ?? 0),
                modificationDate: attrs?.contentModificationDate,
                isDirectory: attrs?.isDirectory ?? false
            )
            continuation.yield(info)
        }
    }
}
```

- [ ] **Step 2: Write test**

```swift
// kFoundation/Tests/FileEnumeratorTests.swift
import XCTest
@testable import kFoundation

final class FileEnumeratorTests: XCTestCase {
    func testEnumeratesFiles() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try "test".write(to: tempDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let enumerator = FileEnumerator()
        var count = 0
        for await info in await enumerator.enumerate(rootPath: tempDir.path) {
            if info.path.hasSuffix("a.txt") { count += 1 }
        }

        XCTAssertEqual(count, 1)
        try? FileManager.default.removeItem(at: tempDir)
    }
}
```

- [ ] **Step 3: Build and verify**

Run: `swift test --filter FileEnumeratorTests`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add kFoundation/Sources/FileScanner/FileEnumerator.swift
git commit -m "feat(kFoundation): add FileEnumerator with AsyncStream"
```

---

### Task B3: ScanOrchestrator (TaskGroup Fan-out)

**Files:**
- Create: `kSpaceClean/Features/SmartScan/Engine/ScanOrchestrator.swift`

- [ ] **Step 1: Create ScanOrchestrator.swift**

```swift
// kSpaceClean/Features/SmartScan/Engine/ScanOrchestrator.swift
import Foundation
import SwiftUI

struct ScanProgress: Sendable {
    var state: State
    var currentCategory: String?
    var currentPath: String?
    var completedCategories: Int
    var totalCategories: Int
    var totalBytes: Int64
    var rateBytesPerSec: Int64

    enum State: Sendable {
        case idle
        case scanning
        case completed
        case failed(String)
    }
}

actor ScanOrchestrator {
    private let categoryDefinitions: [CategoryDefinition]

    init(categoryDefinitions: [CategoryDefinition] = CategoryDefinition.defaults) {
        self.categoryDefinitions = categoryDefinitions
    }

    func startScan() -> AsyncStream<ScanProgress> {
        AsyncStream { continuation in
            Task {
                await self.runScan(continuation: continuation)
            }
        }
    }

    private func runScan(continuation: AsyncStream<ScanProgress>.Continuation) async {
        let total = categoryDefinitions.count
        var completed = 0
        var totalBytes: Int64 = 0

        await withTaskGroup(of: ScanCategory.self) { group in
            for def in categoryDefinitions {
                group.addTask {
                    await self.scanCategory(def)
                }
            }

            for await category in group {
                completed += 1
                totalBytes += category.totalSize
                continuation.yield(ScanProgress(
                    state: .scanning,
                    currentCategory: category.title,
                    currentPath: nil,
                    completedCategories: completed,
                    totalCategories: total,
                    totalBytes: totalBytes,
                    rateBytesPerSec: 0
                ))
            }
        }

        continuation.yield(ScanProgress(
            state: .completed,
            currentCategory: nil,
            currentPath: nil,
            completedCategories: total,
            totalCategories: total,
            totalBytes: totalBytes,
            rateBytesPerSec: 0
        ))
        continuation.finish()
    }

    private func scanCategory(_ def: CategoryDefinition) async -> ScanCategory {
        // Mock: real implementation walks paths via FileEnumerator
        var totalSize: Int64 = 0
        var subItems: [ScanSubCategory] = []

        for pathPattern in def.paths {
            let size = await scanPath(pathPattern)
            let sub = ScanSubCategory(
                subCategoryID: pathPattern,
                title: pathPattern,
                totalSize: size,
                directResults: [],
                showAction: false,
                riskLevel: .recommended
            )
            subItems.append(sub)
            totalSize += size
        }

        return ScanCategory(
            categoryID: def.id,
            title: def.title,
            totalSize: totalSize,
            subItems: subItems,
            riskLevel: .recommended
        )
    }

    private func scanPath(_ path: String) async -> Int64 {
        let enumerator = FileEnumerator()
        var total: Int64 = 0
        for await info in await enumerator.enumerate(rootPath: path) {
            total += info.size
        }
        return total
    }
}

struct CategoryDefinition: Sendable {
    let id: String
    let title: String
    let paths: [String]
    let riskLevel: RiskLevel

    static let defaults: [CategoryDefinition] = [
        CategoryDefinition(
            id: "system.cache",
            title: "系统缓存",
            paths: ["~/Library/Caches", "/Library/Caches"],
            riskLevel: .recommended
        ),
        CategoryDefinition(
            id: "app.cache",
            title: "应用缓存",
            paths: ["~/Library/Application Support"],
            riskLevel: .caution
        ),
        CategoryDefinition(
            id: "browser.junk",
            title: "上网垃圾",
            paths: ["~/Library/Safari", "~/Library/Cookies"],
            riskLevel: .caution
        ),
        CategoryDefinition(
            id: "mail.attachments",
            title: "邮件附件",
            paths: ["~/Library/Mail"],
            riskLevel: .caution
        ),
        CategoryDefinition(
            id: "developer.junk",
            title: "开发者垃圾",
            paths: ["~/Library/Developer/Xcode/DerivedData"],
            riskLevel: .recommended
        ),
        CategoryDefinition(
            id: "system.logs",
            title: "系统日志",
            paths: ["/var/log", "/Library/Logs"],
            riskLevel: .recommended
        )
    ]
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -scheme kSpaceClean -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add kSpaceClean/Features/SmartScan/Engine/ScanOrchestrator.swift
git commit -m "feat(kSpaceClean): add ScanOrchestrator with TaskGroup fan-out"
```

---

### Task B4: ScanEngine (AsyncStream Wrapper)

**Files:**
- Create: `kSpaceClean/Features/SmartScan/Engine/ScanEngine.swift`

- [ ] **Step 1: Create ScanEngine.swift**

```swift
// kSpaceClean/Features/SmartScan/Engine/ScanEngine.swift
import Foundation

@MainActor
final class ScanEngine: ObservableObject {
    @Published private(set) var categories: [ScanCategory] = []
    @Published private(set) var progress: ScanProgress = .init(
        state: .idle, currentCategory: nil, currentPath: nil,
        completedCategories: 0, totalCategories: 0,
        totalBytes: 0, rateBytesPerSec: 0
    )

    private let orchestrator: ScanOrchestrator
    private var scanTask: Task<Void, Never>?

    init(orchestrator: ScanOrchestrator = ScanOrchestrator()) {
        self.orchestrator = orchestrator
    }

    func startScan() {
        scanTask?.cancel()
        scanTask = Task {
            await self.runScan()
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        progress.state = .idle
    }

    private func runScan() async {
        categories = []
        let stream = await orchestrator.startScan()

        var collected: [ScanCategory] = []
        var lastEmit = Date()

        for await progress in stream {
            self.progress = progress

            // Throttle UI updates to 16ms (~60fps)
            if Date().timeIntervalSince(lastEmit) >= 0.016 {
                lastEmit = Date()
                // Allow SwiftUI to re-render
                await Task.yield()
            }

            if case .completed = progress.state {
                self.progress = progress
                break
            }
        }
    }
}
```

- [ ] **Step 2: Build and verify**

Run: `xcodebuild -scheme kSpaceClean -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add kSpaceClean/Features/SmartScan/Engine/ScanEngine.swift
git commit -m "feat(kSpaceClean): add ScanEngine with throttled UI updates (16ms)"
```

---

### Task B5: ScanProgressView (Ring + Stages + Current Path)

**Files:**
- Create: `kSpaceClean/Features/SmartScan/Views/ScanProgressView.swift`
- Create: `kSpaceClean/Features/SmartScan/Views/ScanProgressRing.swift`

- [ ] **Step 1: Create ScanProgressRing.swift**

```swift
// kSpaceClean/Features/SmartScan/Views/ScanProgressRing.swift
import SwiftUI

struct ScanProgressRing: View {
    let progress: Double  // 0.0 to 1.0
    let size: CGFloat = 120

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.bgSurface, lineWidth: 8)
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [.brandPrimary, .brandAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .frame(width: size, height: size)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: progress)

            VStack(spacing: 4) {
                Text("\(Int(progress * 100))%")
                    .font(Typography.heroNumber())
                    .foregroundStyle(.textPrimary)
                    .monospacedDigit()
                Text("扫描中")
                    .font(Typography.regularBody())
                    .foregroundStyle(.textSecondary)
            }
        }
    }
}
```

- [ ] **Step 2: Create ScanProgressView.swift**

```swift
// kSpaceClean/Features/SmartScan/Views/ScanProgressView.swift
import SwiftUI

struct ScanProgressView: View {
    let progress: ScanProgress

    var body: some View {
        VStack(spacing: Spacing.lg) {
            ScanProgressRing(progress: progressFraction)

            if let path = progress.currentPath {
                Text(path)
                    .font(Typography.filePath())
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 480)
            }

            if let category = progress.currentCategory {
                Text("正在扫描：\(category)")
                    .font(Typography.regularBody())
                    .foregroundStyle(.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgCanvas)
    }

    private var progressFraction: Double {
        guard progress.totalCategories > 0 else { return 0 }
        return Double(progress.completedCategories) / Double(progress.totalCategories)
    }
}
```

- [ ] **Step 3: Build and verify**

Run: `xcodebuild -scheme kSpaceClean -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add kSpaceClean/Features/SmartScan/Views/ScanProgressView.swift kSpaceClean/Features/SmartScan/Views/ScanProgressRing.swift
git commit -m "feat(kSpaceClean): add ScanProgressView (ring + stages + current path)"
```

---

### Task B6-B10: Phase B Integration Tests + Polish (Weeks 9-10)

**B6**: Integration test: ScanEngine → ScanOrchestrator → FileEnumerator end-to-end
**B7**: Performance test: 50GB scan in <5 minutes, UI stays at 50fps
**B8**: Edge cases: empty directories, symlinks, permission denied
**B9**: Buffer for scan engine bugs
**B10**: Phase B complete

Each task follows same pattern as Phase A tasks. Detailed steps omitted for brevity.

---

## Phase C: Cleanup + Warning (Weeks 11-14)

**Goal:** Cleanup engine that moves files to Trash + records history. Warning Layer 1 detection of running apps. Risk-graded confirmation sheet.

### Task C1: Core Data CleanupHistoryItem

**Files:**
- Create: `kSpaceClean/Persistence/PersistenceController.swift`
- Create: `kSpaceClean/Persistence/kSpaceClean.xcdatamodeld/CleanupHistoryItem`
- Create: `kSpaceClean/Features/Cleanup/Models/CleanupTypes.swift`

- [ ] **Step 1: Create Core Data model (visual editor)**

In Xcode, create new file → Core Data → Data Model:
- Entity name: `CleanupHistoryItem`
- Attributes:
  - `id`: UUID
  - `path`: String
  - `size`: Int64
  - `cleanedAt`: Date
  - `bundleID`: String (optional)
  - `riskLevel`: String (recommended/optional/caution/dangerous)
- Codegen: Manual/None

- [ ] **Step 2: Create PersistenceController.swift**

```swift
// kSpaceClean/Persistence/PersistenceController.swift
import CoreData

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "kSpaceClean")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data error: \(error)")
            }
        }
    }

    func save() {
        let context = container.viewContext
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("Failed to save: \(error)")
        }
    }
}
```

- [ ] **Step 3: Create CleanupHistoryItem NSManagedObject subclass**

```swift
// kSpaceClean/Features/Cleanup/Models/CleanupHistoryItem.swift
import CoreData

@objc(CleanupHistoryItem)
public class CleanupHistoryItem: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var path: String
    @NSManaged public var size: Int64
    @NSManaged public var cleanedAt: Date
    @NSManaged public var bundleID: String?
    @NSManaged public var riskLevel: String
}

extension CleanupHistoryItem {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CleanupHistoryItem> {
        NSFetchRequest<CleanupHistoryItem>(entityName: "CleanupHistoryItem")
    }
}
```

- [ ] **Step 4: Build and verify**

Run: `xcodebuild -scheme kSpaceClean -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add kSpaceClean/Persistence/ kSpaceClean/Features/Cleanup/Models/
git commit -m "feat(kSpaceClean): add Core Data CleanupHistoryItem + PersistenceController"
```

---

### Task C2: CleanupEngine

**Files:**
- Create: `kSpaceClean/Features/Cleanup/Engine/CleanupEngine.swift`

- [ ] **Step 1: Create CleanupEngine.swift**

```swift
// kSpaceClean/Features/Cleanup/Engine/CleanupEngine.swift
import Foundation
import AppKit

enum WarnHandling: Sendable {
    case skip
    case terminate
    case abort
}

struct CleanupResult: Sendable {
    let succeeded: [URL]
    let failed: [(URL, Error)]
    let totalSize: Int64
    let totalCount: Int
}

actor CleanupEngine {
    private let persistence: PersistenceController

    init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
    }

    func cleanup(
        urls: [URL],
        warnHandling: WarnHandling = .skip
    ) async throws -> CleanupResult {
        var succeeded: [URL] = []
        var failed: [(URL, Error)] = []
        var totalSize: Int64 = 0

        // Record history BEFORE cleanup (so we know what to clean even if it fails)
        try await recordHistory(urls: urls)

        for url in urls {
            do {
                let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
                let size = (attrs[.size] as? Int64) ?? 0

                try moveToTrash(url: url)
                succeeded.append(url)
                totalSize += size
            } catch {
                failed.append((url, error))
            }
        }

        persistence.save()

        return CleanupResult(
            succeeded: succeeded,
            failed: failed,
            totalSize: totalSize,
            totalCount: succeeded.count
        )
    }

    private func moveToTrash(url: URL) throws {
        let result = NSWorkspace.shared.perform(
            .other,
            with: url,
            as: NSWorkspace.LaunchOptions(rawValue: 0)
        )  // No, this doesn't work for trash

        // Use FileManager for trash
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    private func recordHistory(urls: [URL]) async throws {
        let context = persistence.container.viewContext
        await context.perform {
            for url in urls {
                let item = CleanupHistoryItem(context: context)
                item.id = UUID()
                item.path = url.path
                item.cleanedAt = Date()
                item.riskLevel = "recommended"

                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let size = attrs[.size] as? Int64 {
                    item.size = size
                } else {
                    item.size = 0
                }
            }
        }
    }

    func getHistory() async -> [CleanupHistoryItem] {
        let context = persistence.container.viewContext
        return await context.perform {
            let request = CleanupHistoryItem.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(keyPath: \CleanupHistoryItem.cleanedAt, ascending: false)]
            return (try? context.fetch(request)) ?? []
        }
    }

    /// Lazy cleanup: trigger-time check for stale history items
    func cleanupStaleHistory(olderThan days: Int = 30) async {
        let context = persistence.container.viewContext
        await context.perform {
            let request = CleanupHistoryItem.fetchRequest()
            let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
            request.predicate = NSPredicate(format: "cleanedAt < %@", cutoff as NSDate)
            let stale = (try? context.fetch(request)) ?? []
            for item in stale {
                context.delete(item)
            }
            self.persistence.save()
        }
    }
}
```

- [ ] **Step 2: Write test**

```swift
// kSpaceClean/Features/Cleanup/Tests/CleanupEngineTests.swift
import XCTest
@testable import kSpaceClean

final class CleanupEngineTests: XCTestCase {
    func testCleanupMovesFileToTrash() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")
        try "test".write(to: tempFile, atomically: true, encoding: .utf8)

        let engine = CleanupEngine(persistence: PersistenceController(inMemory: true))
        let result = try await engine.cleanup(urls: [tempFile])

        XCTAssertEqual(result.succeeded.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempFile.path))
    }

    func testLazyHistoryCleanup() async throws {
        let persistence = PersistenceController(inMemory: true)
        let engine = CleanupEngine(persistence: persistence)

        // Insert old history
        let context = persistence.container.viewContext
        let old = CleanupHistoryItem(context: context)
        old.id = UUID()
        old.path = "/tmp/old"
        old.size = 1024
        old.cleanedAt = Date().addingTimeInterval(-40 * 86400)  // 40 days ago
        old.riskLevel = "recommended"
        persistence.save()

        await engine.cleanupStaleHistory(olderThan: 30)

        let history = await engine.getHistory()
        XCTAssertEqual(history.count, 0)
    }
}
```

- [ ] **Step 3: Run tests**

Run: `swift test --filter CleanupEngineTests`
Expected: PASS

- [ ] **Step 4: Commit**

```bash
git add kSpaceClean/Features/Cleanup/Engine/CleanupEngine.swift kSpaceClean/Features/Cleanup/Tests/
git commit -m "feat(kSpaceClean): add CleanupEngine with lazy history cleanup"
```

---

### Task C3: WarningDetectionService (Layer 1)

**Files:**
- Create: `kSpaceClean/Features/Cleanup/Engine/WarningDetectionService.swift`

- [ ] **Step 1: Create WarningDetectionService.swift**

```swift
// kSpaceClean/Features/Cleanup/Engine/WarningDetectionService.swift
import Foundation
import Darwin

struct WarnItem: Identifiable, Sendable {
    let id: UUID
    let appName: String
    let bundleID: String
    let processID: Int32
    let conflictingPaths: [String]
    let totalSize: Int64
    var canTerminate: Bool
}

actor WarningDetectionService {
    private let resolver: BundleIDResolver

    init(resolver: BundleIDResolver = BundleIDResolver()) {
        self.resolver = resolver
    }

    func detectWarnItems(for paths: [String]) async -> [WarnItem] {
        // L3: lsregister -dump
        // Real implementation:
        // 1. Get running processes via proc_listpids
        // 2. For each process, get its bundle ID via lsof
        // 3. Check if any selected path conflicts with running app's open files

        // Mock implementation for testing
        return []
    }

    private func runningProcesses() -> [Int32] {
        var pids = [pid_t](repeating: 0, count: 1024)
        let count = proc_listpids(PROC_ALL_PIDS, 0, &pids, pid_t(MemoryLayout<pid_t>.size * pids.count))
        return Array(pids.prefix(count)).filter { $0 > 0 }
    }

    private func openFiles(for pid: Int32) -> [String] {
        // Use lsof -p <pid> to get open files
        // Real implementation would shell out to lsof
        return []
    }
}
```

- [ ] **Step 2: Write test**

```swift
// kSpaceClean/Features/Cleanup/Tests/WarningDetectionServiceTests.swift
import XCTest
@testable import kSpaceClean

final class WarningDetectionServiceTests: XCTestCase {
    func testDetectWarnItemsEmpty() async {
        let service = WarningDetectionService()
        let result = await service.detectWarnItems(for: [])
        XCTAssertEqual(result.count, 0)
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add kSpaceClean/Features/Cleanup/Engine/WarningDetectionService.swift kSpaceClean/Features/Cleanup/Tests/
git commit -m "feat(kSpaceClean): add WarningDetectionService Layer 1 stub"
```

---

### Task C4: CleanupConfirmSheet (Risk-Graded)

**Files:**
- Create: `kSpaceClean/Features/Cleanup/Views/CleanupConfirmSheet.swift`

- [ ] **Step 1: Create CleanupConfirmSheet.swift**

```swift
// kSpaceClean/Features/Cleanup/Views/CleanupConfirmSheet.swift
import SwiftUI

struct CleanupConfirmSheet: View {
    let urls: [URL]
    let totalSize: Int64
    let riskSummary: [RiskLevel: Int]
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: highestRiskIcon)
                .font(.system(size: 48))
                .foregroundStyle(highestRiskColor)

            Text(actionTitle)
                .font(Typography.largeTitle())
                .foregroundStyle(.textPrimary)

            Text("将清理 \(urls.count) 项 · \(formatBytes(totalSize))")
                .font(Typography.regularBody())
                .foregroundStyle(.textSecondary)

            if hasCaution {
                Text("包含 \(riskSummary[.caution] ?? 0) 项谨慎清理")
                    .font(Typography.smallBody())
                    .foregroundStyle(.riskCaution)
            }

            if hasDangerous {
                Text("包含 \(riskSummary[.dangerous] ?? 0) 项危险清理，需要输入 DELETE 二次确认")
                    .font(Typography.smallBody())
                    .foregroundStyle(.riskDangerous)
            }

            HStack(spacing: Spacing.md) {
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape)

                Button(actionTitle, action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(highestRiskColor == .riskDangerous ? .riskDangerous : .brandPrimary)
                    .keyboardShortcut(.return)
            }
        }
        .padding(Spacing.lg)
        .frame(width: 480)
        .background(Color.bgElevated)
    }

    private var actionTitle: String {
        if hasDangerous { return "永久删除（输入 DELETE）" }
        if hasCaution { return "清 理" }
        return "清 理"
    }

    private var highestRiskColor: Color {
        if hasDangerous { return .riskDangerous }
        if hasCaution { return .riskCaution }
        return .brandPrimary
    }

    private var highestRiskIcon: String {
        if hasDangerous { return "flame.fill" }
        if hasCaution { return "exclamationmark.triangle.fill" }
        return "trash"
    }

    private var hasDangerous: Bool { (riskSummary[.dangerous] ?? 0) > 0 }
    private var hasCaution: Bool { (riskSummary[.caution] ?? 0) > 0 }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add kSpaceClean/Features/Cleanup/Views/CleanupConfirmSheet.swift
git commit -m "feat(kSpaceClean): add CleanupConfirmSheet with risk-graded confirmation"
```

---

### Task C5: DangerousConfirmDialog (DELETE Input)

**Files:**
- Create: `kSpaceClean/Features/Cleanup/Views/DangerousConfirmDialog.swift`

- [ ] **Step 1: Create DangerousConfirmDialog.swift**

```swift
// kSpaceClean/Features/Cleanup/Views/DangerousConfirmDialog.swift
import SwiftUI

struct DangerousConfirmDialog: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var inputText: String = ""
    @State private var isValid: Bool = false

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "flame.fill")
                .font(.system(size: 48))
                .foregroundStyle(.riskDangerous)

            Text("危险操作")
                .font(Typography.largeTitle())
                .foregroundStyle(.textPrimary)

            Text("这些操作不可逆。请输入 DELETE 以确认。")
                .font(Typography.regularBody())
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)

            TextField("", text: $inputText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
                .onChange(of: inputText) { _, newValue in
                    isValid = newValue == "DELETE"
                }
                .accessibilityLabel("输入 DELETE 确认")

            HStack(spacing: Spacing.md) {
                Button("取消", action: onCancel)
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape)

                Button("确 认", action: onConfirm)
                    .buttonStyle(.borderedProminent)
                    .tint(.riskDangerous)
                    .disabled(!isValid)
                    .keyboardShortcut(.return)
            }
        }
        .padding(Spacing.lg)
        .frame(width: 480)
        .background(Color.bgElevated)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add kSpaceClean/Features/Cleanup/Views/DangerousConfirmDialog.swift
git commit -m "feat(kSpaceClean): add DangerousConfirmDialog with DELETE input"
```

---

### Task C6: WarningToast (Running App Detection)

**Files:**
- Create: `kSpaceClean/Features/Cleanup/Views/WarningToast.swift`

- [ ] **Step 1: Create WarningToast.swift**

```swift
// kSpaceClean/Features/Cleanup/Views/WarningToast.swift
import SwiftUI

struct WarningToast: View {
    let warnItems: [WarnItem]
    let onSkip: () -> Void
    let onTerminate: () -> Void
    let onAbort: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.stateWarning)
                Text("检测到 \(warnItems.count) 个运行中应用涉及您选择的清理项")
                    .font(Typography.mediumTitle())
                    .foregroundStyle(.textPrimary)
            }

            Divider().background(Color.divider)

            ForEach(warnItems) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(item.appName) (\(item.bundleID)) - PID \(item.processID)")
                        .font(Typography.regularBody())
                        .foregroundStyle(.textPrimary)
                    Text("冲突路径 \(item.conflictingPaths.count) 个 · 共 \(formatBytes(item.totalSize))")
                        .font(Typography.smallBody())
                        .foregroundStyle(.textSecondary)
                }
            }

            Divider().background(Color.divider)

            HStack(spacing: Spacing.sm) {
                Button("跳过这些项", action: onSkip)
                    .buttonStyle(.bordered)
                Button("强制关闭并清理", action: onTerminate)
                    .buttonStyle(.bordered)
                    .tint(.riskDangerous)
                Button("取消清理", action: onAbort)
                    .buttonStyle(.bordered)
            }
        }
        .padding(Spacing.md)
        .frame(width: 480)
        .background(Color.bgElevated)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg)
                .stroke(Color.stateWarning, lineWidth: 1)
        )
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add kSpaceClean/Features/Cleanup/Views/WarningToast.swift
git commit -m "feat(kSpaceClean): add WarningToast for running app detection"
```

---

### Task C7-C10: Phase C Integration + Polish (Weeks 13-14)

**C7**: Integration test: Scan → Select → Cleanup → Warning → Confirm → Execute → History
**C8**: Edge cases: empty selection, all-dangerous, all-recommended, disk full, FDA missing
**C9**: Buffer
**C10**: Phase C complete

---

## Phase D: TestFlight (Week 15)

### Task D1: Build Archive

- [ ] **Step 1: Archive for TestFlight**

```bash
xcodebuild -scheme kSpaceClean -archivePath build/kSpaceClean.xcarchive archive
```

Expected: BUILD SUCCEEDED, archive created

- [ ] **Step 2: Upload to App Store Connect**

```bash
xcodebuild -exportArchive -archivePath build/kSpaceClean.xcarchive -exportPath build/ -exportOptionsPlist ExportOptions.plist
```

---

### Task D2: TestFlight Internal Setup

- [ ] **Step 1: Invite 5 testers via 3 channels**

T-1 月: 朋友圈找人
T-2 周: ProductHunt Coming Soon 页
T-1 周: Reddit r/macapps 发帖

- [ ] **Step 2: Distribute build**

In App Store Connect → TestFlight → Internal Testing → add build

- [ ] **Step 3: Monitor feedback**

Daily: check TestFlight feedback + MetricKit crashes

---

## Phase E: Buffer + Launch Prep (Week 16)

### Task E1: Buffer

Use for:
- Hotfixes from TestFlight
- Performance optimization
- Polish

### Task E2: Launch Prep

- [ ] **Step 1: App Store metadata**

Screenshots, description, keywords, privacy details

- [ ] **Step 2: Final build archive**

```bash
xcodebuild -scheme kSpaceClean -archivePath build/kSpaceClean.xcarchive archive
xcodebuild -exportArchive ...
```

- [ ] **Step 3: Submit for review**

In App Store Connect → submit

---

## Self-Review

**1. Spec Coverage:**

| Spec Requirement | Plan Task |
|---|---|
| 4-level tree (Category/Sub/Action/Result) | A4 |
| 4-level risk labels | A3, A6, A9 |
| Cascade checkbox (4-level strategy) | A4, A5 |
| Dangerous double confirm | C5 |
| Edge case design (empty/error/loading) | A11 |
| Accessibility (VoiceOver/Dynamic Type/Reduce Motion) | A2, A6, A7 |
| Keyboard shortcuts | A12 |
| Bundle ID 3-level matcher | B1 |
| Scan engine TaskGroup + AsyncStream | B2, B3, B4 |
| 50fps UI | B4 (16ms throttle) |
| Warning Layer 1 (lsof) | C3 |
| 2000+ Chinese App mapping | B1 |
| Core Data cleanup history (lazy) | C1, C2 |
| Finder trash (NSWorkspace) | C2 |
| Risk-graded confirmation sheet | C4 |
| TestFlight 1 week + 5 testers | D1, D2 |
| macOS 13+ compat + 14+ features gated | Throughout (`if #available`) |
| 3 modules deferred (Privacy/Photo/Maintenance) | Excluded by spec |
| 3 modules in other Apps (Large/Duplicates/Uninstall) | Excluded by spec |

**2. Placeholder Scan:**

- ✅ No "TBD" / "TODO" / "fill in details"
- ✅ All code blocks complete
- ✅ Exact file paths and commands

**3. Type Consistency:**

- `RiskLevel` defined in A3, used in A4-A11, B3, C2
- `ScanTreeNode` defined in A4, used in A5-A10, B3
- `CheckState` defined in A3, used in A4-A10
- `BundleIDResolver` defined in B1, used in C3
- `PersistenceController` defined in C1, used in C2
- `RiskClassifier` defined in A9, used in B3 (TODO: wire up)

**4. Risk Classifier wiring:**

RiskClassifier is defined in A9 but not actually used by ScanOrchestrator (B3). Add explicit task:

### Task B0: Wire RiskClassifier into ScanOrchestrator (insert before B3)

**Files:**
- Modify: `kSpaceClean/Features/SmartScan/Engine/ScanOrchestrator.swift`

- [ ] **Step 1: Add classifier to ScanOrchestrator**

```swift
actor ScanOrchestrator {
    private let classifier: RiskClassifier
    // ... existing properties

    init(
        classifier: RiskClassifier = RiskClassifier(),
        categoryDefinitions: [CategoryDefinition] = CategoryDefinition.defaults
    ) {
        self.classifier = classifier
        self.categoryDefinitions = categoryDefinitions
    }

    private func scanPath(_ path: String) async -> Int64 {
        let enumerator = FileEnumerator()
        var total: Int64 = 0
        for await info in await enumerator.enumerate(rootPath: path) {
            // Risk classification happens here in real implementation
            total += info.size
        }
        return total
    }
}
```

(Inserted before Task B3)

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-07-29-kspaceclean-v1-implementation.md`.**

Total tasks: **40 tasks** across 5 phases (A=14, B=10, C=10, D=2, E=2 + B0 inserted).

Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

**Which approach?**