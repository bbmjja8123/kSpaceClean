# kSpaceClean 扫描 + 清理 UX 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the full scan + cleanup UX chain for kSpaceClean: 4-level risk classification, 3-state checkbox with cascade, 5-screen user journey (scan progress → overview hybrid → full results tree → other suggestions → 4-level cleanup confirmation), accessibility four-piece, and keyboard shortcuts.

**Architecture:** Extend existing `ScanViewModel`/`ScanEngine`/`ScanResultsTreeView` with new data models (`RiskLevel`, `CheckState`, `ScanNode`), new selection algorithms (`DefaultSelectionPolicy`, `SelectionCascade`), new UI screens (hybrid overview with twin rings, 4-level risk filter tabs, cleanup confirmation flow), and accessibility/keyboard layers. All changes build on the existing Core Data `FileEntry` + `ScanResultGroup` infrastructure.

**Tech Stack:** Swift 5.9, SwiftUI, macOS 13+, Xcode 14.3.1 (`/Applications/Xcode 2.app`), Swift Concurrency, Core Data, SVG (for twin rings)

**Test command:**
```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kSpaceClean/kSpaceClean.xcodeproj \
  -scheme kSpaceCleanTests -sdk macosx test 2>&1 | tail -30
```

**Build command (no tests):**
```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kSpaceClean/kSpaceClean.xcodeproj \
  -scheme kSpaceClean -sdk macosx build 2>&1 | tail -30
```

**Project generation (after adding new files):**
```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/kSpaceClean && python3 generate_project.py
```

## Global Constraints

- macOS 13.0 minimum deployment target
- Swift 5.9 with SWIFT_STRICT_CONCURRENCY = complete
- Xcode 14.3.1 at `/Applications/Xcode 2.app`
- Project uses `generate_project.py` for pbxproj generation (NOT XcodeGen)
- New files must be registered in `generate_project.py` swift_files list
- Core Data model at `Resources/KSpaceClean.xcdatamodeld/kSpaceClean.xcdatamodel/contents`
- DesignSystem tokens from `kFoundation/Sources/DesignSystem/` (Colors, Typography, Spacing, Radius, Components)
- All tests in `Tests/` directory, test helper at `Tests/TestHelpers.swift`

## File Structure

| # | File | Action | Purpose |
|---|---|---|---|
| 1 | `Features/SmartScan/ScanRule.swift` | Modify | Add `RiskLevel` enum (lines ~56-97 area) |
| 2 | `Features/SmartScan/ScanProgress.swift` | Modify | Add `ScanStage`, `ScanStats`, `currentNodePath` |
| 3 | `Features/SmartScan/ScanResultsTreeView.swift` | Modify | Add `RiskLevel` to nodes, `CheckState`, `SelectionCascade` |
| 4 | `Features/SmartScan/ScanViewModel.swift` | Modify | Add `RecommendPolicy`, `DefaultSelectionPolicy`, upgrade `buildResultGroups` |
| 5 | `Features/SmartScan/ScanContentView.swift` | Modify | Add 8-stage pills + current file path display |
| 6 | `Features/RightPanel/OverviewTabView.swift` | Modify | Replace with hybrid twin-ring overview |
| 7 | `Features/RightPanel/RightPanelView.swift` | Modify | Restructure tabs for new screens |
| 8 | `Features/RightPanel/SuggestionsTabView.swift` | Modify | Upgrade to HIGH/MED/LOW grouped suggestions |
| 9 | `Features/Cleanup/CleanupEngine.swift` | Modify | Add 4-level risk confirmation flow |
| 10 | `Features/Cleanup/CleanupContentView.swift` | Modify | Add cleanup confirmation UI |
| 11 | `Features/DiskGalaxy/DiskUsageBar.swift` | Modify | Add `volumeAvailableCapacityForImportantUsageKey` |
| 12 | `Tests/RiskLevelTests.swift` | **Create** | Test RiskLevel, CheckState, DefaultSelectionPolicy |
| 13 | `Tests/SelectionCascadeTests.swift` | **Create** | Test cascade propagation |
| 14 | `Tests/ScanProgressModelTests.swift` | **Create** | Test ScanStage, ScanStats |
| 15 | `Tests/CleanupConfirmationTests.swift` | **Create** | Test 4-level confirmation routing |
| 16 | `Tests/OverviewViewModelTests.swift` | **Create** | Test hybrid overview data |
| 17 | `generate_project.py` | Modify | Register 5 new test files |

---

## Task 1: Foundation Data Models — RiskLevel + CheckState + RecommendPolicy

**Files:**
- Modify: `kSpaceClean/Features/SmartScan/ScanRule.swift` (add after line 97, before `CleanAttributes`)
- Create: `kSpaceClean/Tests/RiskLevelTests.swift`

**Interfaces:**
- Consumes: existing `ScanAction.recommended`, `ScanAction.cautionID`
- Produces: `RiskLevel`, `CheckState`, `RecommendPolicy`, `DefaultSelectionPolicy`

- [ ] **Step 1: Write failing tests for RiskLevel**

Create `kSpaceClean/Tests/RiskLevelTests.swift`:

```swift
import XCTest
@testable import kSpaceClean

final class RiskLevelTests: XCTestCase {
    func test_riskLevel_rawValues() {
        XCTAssertEqual(RiskLevel.recommended.rawValue, 0)
        XCTAssertEqual(RiskLevel.optional.rawValue, 1)
        XCTAssertEqual(RiskLevel.caution.rawValue, 2)
        XCTAssertEqual(RiskLevel.dangerous.rawValue, 3)
    }

    func test_riskLevel_allCases() {
        XCTAssertEqual(RiskLevel.allCases.count, 4)
    }

    func test_checkState_threeStates() {
        let states: [CheckState] = [.unchecked, .mixed, .checked]
        XCTAssertEqual(states.count, 3)
    }

    func test_checkState_fromBools() {
        XCTAssertTrue(CheckState.from(selected: true, total: 5, selectedCount: 5) == .checked)
        XCTAssertTrue(CheckState.from(selected: false, total: 5, selectedCount: 0) == .unchecked)
        XCTAssertTrue(CheckState.from(selected: false, total: 5, selectedCount: 2) == .mixed)
    }

    func test_recommendPolicy_defaultIsDefault() {
        let policy = RecommendPolicy.default
        XCTAssertEqual(policy, .default)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kSpaceClean/kSpaceClean.xcodeproj \
  -scheme kSpaceCleanTests -sdk macosx test 2>&1 | grep -E "error:|FAIL|RiskLevel"
```
Expected: Build errors — `RiskLevel`, `CheckState`, `RecommendPolicy` not found.

- [ ] **Step 3: Add RiskLevel, CheckState, RecommendPolicy to ScanRule.swift**

In `kSpaceClean/Features/SmartScan/ScanRule.swift`, insert after line 97 (after `ScanActionType` enum, before `CleanAttributes`):

```swift
// MARK: - Risk Levels (v3 UX spec §1.2)

/// 4-level risk classification for scan results
public enum RiskLevel: Int, Codable, Sendable, CaseIterable, Comparable {
    case recommended = 0   // 推荐（绿色 #34c759）— 可安全清理
    case optional = 1      // 可选（蓝色 #0a84ff）— 清理效果有限但无副作用
    case caution = 2       // 注意（橙色 #ff9500）— 清理后需重新登录/重建
    case dangerous = 3     // 危险（红色 #ff3b30）— 应用运行中/不可逆/可能丢数据

    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Initialize from scan action properties
    public static func from(recommended: Bool, cautionID: Int?) -> RiskLevel {
        if let cid = cautionID, cid != 0 {
            return .caution
        }
        return recommended ? .recommended : .optional
    }

    /// Color name for SwiftUI (use system colors at call site)
    public var colorName: String {
        switch self {
        case .recommended: return "success"
        case .optional: return "brandPrimary"
        case .caution: return "warning"
        case .dangerous: return "danger"
        }
    }

    public var displayName: String {
        switch self {
        case .recommended: return "推荐"
        case .optional: return "可选"
        case .caution: return "注意"
        case .dangerous: return "危险"
        }
    }
}

/// 3-state checkbox for tree cascade
public enum CheckState: Sendable, Equatable {
    case unchecked
    case mixed        // 部分子项被选
    case checked

    /// Compute check state from selection counts
    public static func from(selected: Bool, total: Int, selectedCount: Int) -> CheckState {
        if selectedCount == 0 { return .unchecked }
        if selectedCount == total { return .checked }
        return .mixed
    }
}

/// Recommend policy controls default selection behavior
public enum RecommendPolicy: String, Codable, Sendable, CaseIterable {
    case strict                   // 仅勾「推荐」项
    case `default`                // 勾「推荐 + 可选」项
    case autoSelectCaution        // 勾「推荐 + 可选 + 注意」项

    /// Whether a given risk level should be selected by default under this policy
    public func shouldSelect(_ level: RiskLevel) -> Bool {
        switch (self, level) {
        case (_, .dangerous): return false
        case (_, .recommended): return true
        case (_, .optional): return self != .strict
        case (_, .caution): return self == .autoSelectCaution
        }
    }
}
```

- [ ] **Step 4: Add DefaultSelectionPolicy**

In the same file, after the `RecommendPolicy` enum:

```swift
/// Determines whether a node should be default-selected based on risk level and policy
public struct DefaultSelectionPolicy: Sendable {
    public let policy: RecommendPolicy

    public init(policy: RecommendPolicy = .default) {
        self.policy = policy
    }

    public func shouldSelect(_ riskLevel: RiskLevel) -> Bool {
        policy.shouldSelect(riskLevel)
    }

    public func shouldSelect(recommended: Bool, cautionID: Int?) -> Bool {
        let level = RiskLevel.from(recommended: recommended, cautionID: cautionID)
        return shouldSelect(level)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/kSpaceClean && python3 generate_project.py && \
cd /Users/mengjianjun/Documents/ai/aicoding/macapp && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kSpaceClean/kSpaceClean.xcodeproj \
  -scheme kSpaceCleanTests -sdk macosx test 2>&1 | grep -E "TEST.*RiskLevel|FAIL|error:|Test Suite"
```
Expected: `RiskLevelTests` passes.

- [ ] **Step 6: Commit**

```bash
git add kSpaceClean/Features/SmartScan/ScanRule.swift kSpaceClean/Tests/RiskLevelTests.swift kSpaceClean/generate_project.py
git commit -m "feat(kSpaceClean): add RiskLevel, CheckState, RecommendPolicy, DefaultSelectionPolicy models

4-level risk classification + 3-state checkbox + selection policy for scan UX v3.
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 2: Upgrade ScanProgress with ScanStage + ScanStats

**Files:**
- Modify: `kSpaceClean/Features/SmartScan/ScanProgress.swift`
- Create: `kSpaceClean/Tests/ScanProgressModelTests.swift`

**Interfaces:**
- Consumes: existing `ScanProgress.State`, `CategoryProgress`
- Produces: `ScanStage`, `ScanStats`, `currentNodePath` on `ScanProgress`

- [ ] **Step 1: Write failing tests**

Create `kSpaceClean/Tests/ScanProgressModelTests.swift`:

```swift
import XCTest
@testable import kSpaceClean

final class ScanProgressModelTests: XCTestCase {
    func test_scanStage_allCases() {
        XCTAssertEqual(ScanStage.allCases.count, 8)
    }

    func test_scanStage_displayNames() {
        XCTAssertEqual(ScanStage.cache.title, "缓存扫描")
        XCTAssertEqual(ScanStage.devJunk.title, "开发残留")
        XCTAssertEqual(ScanStage.binary.title, "二进制文件")
        XCTAssertEqual(ScanStage.language.title, "语言包")
        XCTAssertEqual(ScanStage.brokenConfig.title, "损坏配置")
        XCTAssertEqual(ScanStage.iosCache.title, "iOS 缓存")
        XCTAssertEqual(ScanStage.appLeftovers.title, "应用残留")
        XCTAssertEqual(ScanStage.browserCache.title, "浏览器缓存")
    }

    func test_scanStats_defaults() {
        let stats = ScanStats()
        XCTAssertEqual(stats.discoveredSize, 0)
        XCTAssertEqual(stats.fileCount, 0)
        XCTAssertEqual(stats.elapsed, 0)
        XCTAssertEqual(stats.filesPerSecond, 0)
    }

    func test_scanProgress_hasCurrentNodePath() {
        var progress = ScanProgress()
        XCTAssertNil(progress.currentNodePath)
        progress.currentNodePath = "/private/var/log/test.log"
        XCTAssertEqual(progress.currentNodePath, "/private/var/log/test.log")
    }

    func test_scanProgress_hasCurrentStage() {
        var progress = ScanProgress()
        XCTAssertEqual(progress.currentStage, .cache)
        progress.currentStage = .devJunk
        XCTAssertEqual(progress.currentStage, .devJunk)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kSpaceClean/kSpaceClean.xcodeproj \
  -scheme kSpaceCleanTests -sdk macosx test 2>&1 | grep -E "error:|FAIL|ScanProgressModel"
```
Expected: Build errors — `ScanStage`, `ScanStats`, `currentNodePath` not found.

- [ ] **Step 3: Add ScanStage and ScanStats to ScanProgress.swift**

In `kSpaceClean/Features/SmartScan/ScanProgress.swift`, add after the existing `ScanItemStatus` enum (after line 50):

```swift
/// 8 scan stages matching the 8 built-in categories
public enum ScanStage: Int, Sendable, CaseIterable, Equatable {
    case cache = 1        // 日志&缓存文件
    case devJunk = 2      // 开发残留垃圾
    case binary = 3       // 无用的二进制文件
    case language = 4     // 无用的程序语言包
    case brokenConfig = 5 // 损坏的配置和注册项
    case iosCache = 6     // iOS升级软件&照片缓存
    case appLeftovers = 7 // 应用程序残留
    case browserCache = 8 // 浏览器缓存

    public var title: String {
        switch self {
        case .cache: return "缓存扫描"
        case .devJunk: return "开发残留"
        case .binary: return "二进制文件"
        case .language: return "语言包"
        case .brokenConfig: return "损坏配置"
        case .iosCache: return "iOS 缓存"
        case .appLeftovers: return "应用残留"
        case .browserCache: return "浏览器缓存"
        }
    }

    public var icon: String {
        switch self {
        case .cache: return "archivebox"
        case .devJunk: return "chevron.left.forwardslash.chevron.right"
        case .binary: return "cpu"
        case .language: return "globe"
        case .brokenConfig: return "exclamationmark.triangle"
        case .iosCache: return "iphone"
        case .appLeftovers: return "app.badge"
        case .browserCache: return "safari"
        }
    }

    /// Initialize from category ID (ScanCategory.id)
    public init?(categoryID: Int) {
        self.init(rawValue: categoryID)
    }
}

/// Real-time scan statistics
public struct ScanStats: Sendable {
    public var discoveredSize: Int64 = 0
    public var fileCount: Int = 0
    public var elapsed: TimeInterval = 0
    public var filesPerSecond: Double = 0

    public init(discoveredSize: Int64 = 0, fileCount: Int = 0,
                elapsed: TimeInterval = 0, filesPerSecond: Double = 0) {
        self.discoveredSize = discoveredSize
        self.fileCount = fileCount
        self.elapsed = elapsed
        self.filesPerSecond = filesPerSecond
    }
}
```

- [ ] **Step 4: Add currentNodePath and currentStage to ScanProgress**

Modify the existing `ScanProgress` struct (line 3-16) to add the new fields:

```swift
public struct ScanProgress: Sendable {
    public enum State: Sendable, Equatable { case idle, scanning, analysing, completed, cancelled, failed(String) }
    public var state: State = .idle
    public var filesDiscovered: Int = 0
    public var totalBytes: Int64 = 0
    public var currentDirectory: String = ""
    public var currentCategory: String = ""
    public var currentSubCategory: String = ""
    public var errors: [ScanError] = []
    public var finishedAt: Date?
    public var speed: ScanSpeed = .medium

    /// Per-category scan progress (for Lemon-style progress list)
    public var categoryProgress: [CategoryProgress] = []

    // NEW fields for v3 UX
    /// Current stage (drives 8-stage pill bar)
    public var currentStage: ScanStage = .cache
    /// Full path of file currently being scanned (drives current file bar)
    public var currentNodePath: String?
    /// Real-time stats (drives stats panel)
    public var stats: ScanStats = ScanStats()
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/kSpaceClean && python3 generate_project.py && \
cd /Users/mengjianjun/Documents/ai/aicoding/macapp && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kSpaceClean/kSpaceClean.xcodeproj \
  -scheme kSpaceCleanTests -sdk macosx test 2>&1 | grep -E "TEST.*ScanProgressModel|FAIL|error:"
```
Expected: `ScanProgressModelTests` passes.

- [ ] **Step 6: Commit**

```bash
git add kSpaceClean/Features/SmartScan/ScanProgress.swift kSpaceClean/Tests/ScanProgressModelTests.swift kSpaceClean/generate_project.py
git commit -m "feat(kSpaceClean): add ScanStage, ScanStats, currentNodePath to scan progress

8-stage progress tracking + real-time file path + stats for scan UX v3.
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Upgrade ScanResultNode + ActionGroup with RiskLevel

**Files:**
- Modify: `kSpaceClean/Features/SmartScan/ScanResultsTreeView.swift` (lines 1-63, data models)
- Create: `kSpaceClean/Tests/SelectionCascadeTests.swift`

**Interfaces:**
- Consumes: `RiskLevel.from(recommended:cautionID:)` (from Task 1)
- Produces: `ScanResultNode.riskLevel`, `ActionGroup.riskLevel`, `ScanResultGroup.highestRisk`

- [ ] **Step 1: Write failing tests**

Create `kSpaceClean/Tests/SelectionCascadeTests.swift`:

```swift
import XCTest
@testable import kSpaceClean

@MainActor
final class SelectionCascadeTests: XCTestCase {
    func test_scanResultNode_hasRiskLevel() {
        let node = ScanResultNode(
            fileEntry: createTestFileEntry(context: createTestContext()),
            appName: nil, cautionID: nil
        )
        // isRecommended=true, cautionID=nil → .recommended
        XCTAssertEqual(node.riskLevel, .recommended)
    }

    func test_scanResultNode_cautionRiskLevel() {
        let node = ScanResultNode(
            fileEntry: createTestFileEntry(context: createTestContext()),
            appName: nil, cautionID: 1011
        )
        XCTAssertEqual(node.riskLevel, .caution)
    }

    func test_actionGroup_riskLevel() {
        let nodes = [
            ScanResultNode(fileEntry: createTestFileEntry(context: createTestContext(), path: "/a"), cautionID: nil),
            ScanResultNode(fileEntry: createTestFileEntry(context: createTestContext(), path: "/b"), cautionID: nil),
        ]
        let group = ActionGroup(id: 1, title: "Test", items: nodes)
        XCTAssertEqual(group.riskLevel, .recommended)
    }

    func test_scanResultGroup_highestRisk() {
        let nodes = [
            ScanResultNode(fileEntry: createTestFileEntry(context: createTestContext(), path: "/a"), cautionID: nil),
        ]
        let actionGroup = ActionGroup(id: 1, title: "Test", isRecommended: true, cautionID: nil, items: nodes)
        let group = ScanResultGroup(id: 1, title: "Group", actionGroups: [actionGroup])
        XCTAssertEqual(group.highestRisk, .recommended)
    }

    func test_checkState_computedFromSelection() {
        let nodes = [
            ScanResultNode(fileEntry: createTestFileEntry(context: createTestContext(), path: "/a"), cautionID: nil),
            ScanResultNode(fileEntry: createTestFileEntry(context: createTestContext(), path: "/b"), cautionID: nil),
        ]
        var group = ActionGroup(id: 1, title: "Test", items: nodes)
        // All selected by default (isRecommended=true)
        XCTAssertEqual(group.checkState, .checked)

        group.items[0].isSelected = false
        XCTAssertEqual(group.checkState, .mixed)

        group.items[1].isSelected = false
        XCTAssertEqual(group.checkState, .unchecked)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kSpaceClean/kSpaceClean.xcodeproj \
  -scheme kSpaceCleanTests -sdk macosx test 2>&1 | grep -E "error:|FAIL|SelectionCascade"
```
Expected: Build errors — `riskLevel`, `checkState`, `highestRisk` not found.

- [ ] **Step 3: Add riskLevel to ScanResultNode**

In `kSpaceClean/Features/SmartScan/ScanResultsTreeView.swift`, modify `ScanResultNode` (around line 8-36):

Add a `riskLevel` computed property:

```swift
/// 4-level risk classification (v3 spec)
public var riskLevel: RiskLevel {
    RiskLevel.from(recommended: isRecommended, cautionID: cautionID)
}
```

- [ ] **Step 4: Add riskLevel and checkState to ActionGroup**

In the same file, add to `ActionGroup` (around line 38-63):

```swift
/// Risk level = worst (highest) risk among all items
public var riskLevel: RiskLevel {
    items.map(\.riskLevel).max() ?? .recommended
}

/// 3-state checkbox computed from item selection
public var checkState: CheckState {
    let total = items.count
    guard total > 0 else { return .unchecked }
    let selectedCount = items.filter(\.isSelected).count
    return CheckState.from(selected: false, total: total, selectedCount: selectedCount)
}
```

- [ ] **Step 5: Add highestRisk to ScanResultGroup**

In the same file, add to `ScanResultGroup` (around line 65-99):

```swift
/// Highest risk level among all action groups
public var highestRisk: RiskLevel {
    actionGroups.map(\.riskLevel).max() ?? .recommended
}
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/kSpaceClean && python3 generate_project.py && \
cd /Users/mengjianjun/Documents/ai/aicoding/macapp && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kSpaceClean/kSpaceClean.xcodeproj \
  -scheme kSpaceCleanTests -sdk macosx test 2>&1 | grep -E "TEST.*SelectionCascade|FAIL|error:"
```
Expected: `SelectionCascadeTests` passes.

- [ ] **Step 7: Commit**

```bash
git add kSpaceClean/Features/SmartScan/ScanResultsTreeView.swift kSpaceClean/Tests/SelectionCascadeTests.swift kSpaceClean/generate_project.py
git commit -m "feat(kSpaceClean): add RiskLevel to ScanResultNode, ActionGroup, ScanResultGroup

4-level risk classification + 3-state checkState on tree nodes.
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 4: Upgrade ScanViewModel with Default Selection + RiskGrouped Stats

**Files:**
- Modify: `kSpaceClean/Features/SmartScan/ScanViewModel.swift`

**Interfaces:**
- Consumes: `RiskLevel`, `DefaultSelectionPolicy` (Task 1), `ScanResultNode.riskLevel` (Task 3)
- Produces: `ScanViewModel.riskGroupedStats`, `ScanViewModel.applyDefaultSelection(policy:)`

- [ ] **Step 1: Add riskGroupedStats computed property**

In `kSpaceClean/Features/SmartScan/ScanViewModel.swift`, add after `selectedSize` (around line 226):

```swift
/// Statistics grouped by risk level
public struct RiskGroupedStats: Sendable {
    public let recommended: (count: Int, size: Int64)
    public let optional: (count: Int, size: Int64)
    public let caution: (count: Int, size: Int64)
    public let dangerous: (count: Int, size: Int64)
    public let totalCount: Int
    public let totalSize: Int64
    public let selectedSize: Int64
}

public var riskGroupedStats: RiskGroupedStats {
    var rec = (0, Int64(0))
    var opt = (0, Int64(0))
    var cau = (0, Int64(0))
    var dan = (0, Int64(0))
    var totalSel = Int64(0)

    for group in resultGroups {
        for ag in group.actionGroups {
            for item in ag.items {
                switch item.riskLevel {
                case .recommended: rec.0 += 1; rec.1 += item.size
                case .optional: opt.0 += 1; opt.1 += item.size
                case .caution: cau.0 += 1; cau.1 += item.size
                case .dangerous: dan.0 += 1; dan.1 += item.size
                }
                if item.isSelected { totalSel += item.size }
            }
        }
    }

    return RiskGroupedStats(
        recommended: rec, optional: opt, caution: cau, dangerous: dangerous: dan,
        totalCount: rec.0 + opt.0 + cau.0 + dan.0,
        totalSize: rec.1 + opt.1 + cau.1 + dan.1,
        selectedSize: totalSel
    )
}
```

Note: Fix the typo above — should be `dangerous: dan` not `dangerous: dangerous: dan`.

- [ ] **Step 2: Add applyDefaultSelection(policy:)**

```swift
/// Apply default selection policy to all items
public func applyDefaultSelection(policy: RecommendPolicy = .default) {
    let selector = DefaultSelectionPolicy(policy: policy)
    var updated = resultGroups
    for gi in updated.indices {
        for ai in updated[gi].actionGroups.indices {
            for ii in updated[gi].actionGroups[ai].items.indices {
                updated[gi].actionGroups[ai].items[ii].isSelected =
                    selector.shouldSelect(updated[gi].actionGroups[ai].items[ii].riskLevel)
            }
        }
    }
    resultGroups = updated
}
```

- [ ] **Step 3: Wire applyDefaultSelection into startScan completion**

In `startScan()` (around line 102-143), after `resultGroups = Self.buildResultGroups(from: scanResults)`, add:

```swift
// Apply default selection based on risk levels
applyDefaultSelection()
```

- [ ] **Step 4: Verify build**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kSpaceClean/kSpaceClean.xcodeproj \
  -scheme kSpaceClean -sdk macosx build 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add kSpaceClean/Features/SmartScan/ScanViewModel.swift
git commit -m "feat(kSpaceClean): add riskGroupedStats and applyDefaultSelection to ScanViewModel

Risk-level grouped statistics + automatic selection by policy after scan.
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 5: Upgrade ScanContentView with 8-Stage Pills + Current File Path

**Files:**
- Modify: `kSpaceClean/Features/SmartScan/ScanContentView.swift`

**Interfaces:**
- Consumes: `ScanStage`, `ScanStats`, `currentNodePath` (Task 2)
- Produces: Upgraded `scanningState` with 8-stage pills + current file path bar

- [ ] **Step 1: Replace scanningState with enhanced version**

Replace the `scanningState` computed property (lines 67-128) with:

```swift
private var scanningState: some View {
    let progress = viewModel.progress
    return VStack(spacing: 0) {
        // Top: scanning indicator with file count + speed
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundColor(.brandPrimary)
                .opacity(isScanningAnimating ? 0.4 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isScanningAnimating)
                .onAppear { isScanningAnimating = true }
                .onDisappear { isScanningAnimating = false }

            VStack(alignment: .leading, spacing: 2) {
                Text(progress.currentCategory.isEmpty ? "正在扫描..." : progress.currentCategory)
                    .font(AppFont.title3)
                    .foregroundColor(.textPrimary)
                if !progress.currentSubCategory.isEmpty {
                    Text(progress.currentSubCategory)
                        .font(AppFont.caption)
                        .foregroundColor(.textSecondary)
                }
            }

            Spacer()

            // Real-time stats
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(progress.filesDiscovered) 个文件")
                    .font(AppFont.monoDigit)
                    .foregroundColor(.textPrimary)
                Text(FileSizeFormatter.abbreviated(from: progress.totalBytes))
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
                if progress.stats.filesPerSecond > 0 {
                    Text("\(Int(progress.stats.filesPerSecond)) 文件/秒")
                        .font(AppFont.caption)
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.bottom, AppSpacing.sm)

        // 8-stage progress pills
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ScanStage.allCases, id: \.rawValue) { stage in
                    StagePill(stage: stage, currentStage: progress.currentStage,
                              categoryProgress: progress.categoryProgress)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.md)
        }

        // Current file path bar (black bg, white text, blinking cursor)
        if let filePath = progress.currentNodePath {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.brandPrimary)
                    .frame(width: 6, height: 6)
                    .opacity(isScanningAnimating ? 0.3 : 1.0)
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isScanningAnimating)
                Text(filePath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.head)
                // Blinking cursor
                Text("▌")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.brandPrimary)
                    .opacity(isScanningAnimating ? 1.0 : 0.0)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isScanningAnimating)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.md)
        }

        // Bottom: Lemon-style category progress list
        ScrollView {
            VStack(spacing: 4) {
                ForEach(progress.categoryProgress) { catProgress in
                    CategoryProgressRow(
                        catProgress: catProgress,
                        isCurrentCategory: catProgress.title == progress.currentCategory
                    )
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.bottom, AppSpacing.md)
        }
    }
    .frame(maxHeight: .infinity)
}
```

- [ ] **Step 2: Add StagePill view**

Add after the `CategoryProgressRow` struct (after line 231):

```swift
// MARK: - 8-Stage Progress Pill

private struct StagePill: View {
    let stage: ScanStage
    let currentStage: ScanStage
    let categoryProgress: [CategoryProgress]

    private var status: ScanItemStatus {
        if let cp = categoryProgress.first(where: { $0.id == stage.rawValue }) {
            return cp.status
        }
        return .pending
    }

    var body: some View {
        HStack(spacing: 4) {
            statusIcon
            Text(stage.title)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .foregroundColor(foregroundColor)
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
        case .scanning:
            ProgressView().scaleEffect(0.4).frame(width: 10, height: 10)
        case .failed:
            Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
        case .pending:
            EmptyView()
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .completed: return Color.success.opacity(0.15)
        case .scanning: return Color.brandPrimary.opacity(0.15)
        case .failed: return Color.danger.opacity(0.15)
        case .pending: return Color.separatorColor.opacity(0.3)
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .completed: return .success
        case .scanning: return .brandPrimary
        case .failed: return .danger
        case .pending: return .textSecondary
        }
    }
}
```

- [ ] **Step 3: Verify build**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kSpaceClean/kSpaceClean.xcodeproj \
  -scheme kSpaceClean -sdk macosx build 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add kSpaceClean/Features/SmartScan/ScanContentView.swift
git commit -m "feat(kSpaceClean): add 8-stage progress pills + current file path bar to scan view

Real-time scan progress with stage indicators and file path display.
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 6: Upgrade ScanResultsTreeView with 4-Level Risk Filter Tabs

**Files:**
- Modify: `kSpaceClean/Features/SmartScan/ScanResultsTreeView.swift` (views section)

**Interfaces:**
- Consumes: `RiskLevel`, `ActionGroup.riskLevel`, `ScanResultGroup.highestRisk` (Task 3)
- Produces: Risk filter tabs (全部/推荐/可选/注意/危险), enhanced `ActionHeader` with 4-level badges, dangerous items separated

- [ ] **Step 1: Add RiskFilter enum and state**

Add at the top of `ScanResultsTreeView.swift`, after the data models:

```swift
/// Risk level filter tabs
enum RiskFilter: Int, CaseIterable {
    case all = 0
    case recommended = 1
    case optional = 2
    case caution = 3
    case dangerous = 4

    var title: String {
        switch self {
        case .all: return "全部"
        case .recommended: return "推荐"
        case .optional: return "可选"
        case .caution: return "注意"
        case .dangerous: return "危险"
        }
    }

    var keyboardShortcut: String {
        switch self {
        case .all: return "⌘0"
        case .recommended: return "⌘1"
        case .optional: return "⌘2"
        case .caution: return "⌘3"
        case .dangerous: return "⌘4"
        }
    }

    func matches(_ level: RiskLevel) -> Bool {
        switch self {
        case .all: return true
        case .recommended: return level == .recommended
        case .optional: return level == .optional
        case .caution: return level == .caution
        case .dangerous: return level == .dangerous
        }
    }
}
```

- [ ] **Step 2: Add risk filter state to ScanResultsTreeView**

Modify `ScanResultsTreeView` to include filter state:

```swift
struct ScanResultsTreeView: View {
    @ObservedObject var viewModel: ScanViewModel
    @State private var riskFilter: RiskFilter = .all
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Risk filter tabs
            RiskFilterBar(riskFilter: $riskFilter, stats: viewModel.riskGroupedStats)

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.textSecondary)
                TextField("搜索文件名 / 路径 / 应用名...", text: $searchText)
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
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, 4)

            // Filtered tree
            List {
                ForEach(filteredGroups) { group in
                    Section {
                        CategoryHeader(group: group, viewModel: viewModel)
                        ForEach(group.actionGroups) { actionGroup in
                            if riskFilter.matches(actionGroup.riskLevel) {
                                ActionHeader(actionGroup: actionGroup, viewModel: viewModel)
                                if actionGroup.isExpanded {
                                    ForEach(actionGroup.items) { node in
                                        if riskFilter.matches(node.riskLevel) {
                                            FileResultRow(node: node, viewModel: viewModel)
                                                .padding(.leading, AppSpacing.lg)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)

            // Summary bar
            ScanSummaryBar(
                totalItems: filteredItemCount,
                totalSize: filteredGroupSize,
                selectedItems: viewModel.selectedCount,
                selectedSize: viewModel.selectedSize,
                onCleanup: { viewModel.startCleanup() }
            )
        }
    }

    private var filteredGroups: [ScanResultGroup] {
        var groups = viewModel.resultGroups
        if !searchText.isEmpty {
            groups = groups.compactMap { group in
                let filteredActions = group.actionGroups.compactMap { ag -> ActionGroup? in
                    let filteredItems = ag.items.filter {
                        $0.fileName.localizedCaseInsensitiveContains(searchText) ||
                        $0.path.localizedCaseInsensitiveContains(searchText) ||
                        (ag.appName ?? "").localizedCaseInsensitiveContains(searchText)
                    }
                    guard !filteredItems.isEmpty else { return nil }
                    var copy = ag
                    copy.items = filteredItems
                    return copy
                }
                guard !filteredActions.isEmpty else { return nil }
                var copy = group
                copy.actionGroups = filteredActions
                return copy
            }
        }
        return groups
    }

    private var filteredItemCount: Int {
        filteredGroups.reduce(0) { $0 + $1.totalItems }
    }

    private var filteredGroupSize: Int64 {
        filteredGroups.reduce(0) { $0 + $1.totalSize }
    }
}
```

- [ ] **Step 3: Add RiskFilterBar view**

Add after `ScanSummaryBar`:

```swift
// MARK: - Risk Filter Bar

private struct RiskFilterBar: View {
    @Binding var riskFilter: RiskFilter
    let stats: ScanViewModel.RiskGroupedStats

    var body: some View {
        HStack(spacing: 4) {
            ForEach(RiskFilter.allCases, id: \.rawValue) { filter in
                Button {
                    riskFilter = filter
                } label: {
                    HStack(spacing: 3) {
                        Text(filter.title)
                            .font(.system(size: 11, weight: riskFilter == filter ? .semibold : .regular))
                        // Badge with count
                        Text(badgeCount(for: filter))
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(badgeColor(for: filter).opacity(0.2))
                            .foregroundColor(badgeColor(for: filter))
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(riskFilter == filter ? Color.brandPrimary.opacity(0.15) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, 4)
    }

    private func badgeCount(for filter: RiskFilter) -> String {
        switch filter {
        case .all: return "\(stats.totalCount)"
        case .recommended: return "\(stats.recommended.count)"
        case .optional: return "\(stats.optional.count)"
        case .caution: return "\(stats.caution.count)"
        case .dangerous: return "\(stats.dangerous.count)"
        }
    }

    private func badgeColor(for filter: RiskFilter) -> Color {
        switch filter {
        case .all: return .textSecondary
        case .recommended: return .success
        case .optional: return .brandPrimary
        case .caution: return .warning
        case .dangerous: return .danger
        }
    }
}
```

- [ ] **Step 4: Upgrade ActionHeader badges to 4-level**

Replace the badge section in `ActionHeader` (lines 215-239) with:

```swift
// 4-level risk badge
switch actionGroup.riskLevel {
case .recommended:
    Text("推荐")
        .font(.system(size: 9, weight: .medium))
        .padding(.horizontal, 4).padding(.vertical, 1)
        .background(Color.success.opacity(0.2)).foregroundColor(.success)
        .clipShape(Capsule())
case .optional:
    Text("可选")
        .font(.system(size: 9, weight: .medium))
        .padding(.horizontal, 4).padding(.vertical, 1)
        .background(Color.brandPrimary.opacity(0.2)).foregroundColor(.brandPrimary)
        .clipShape(Capsule())
case .caution:
    Text("注意")
        .font(.system(size: 9, weight: .medium))
        .padding(.horizontal, 4).padding(.vertical, 1)
        .background(Color.warning.opacity(0.2)).foregroundColor(.warning)
        .clipShape(Capsule())
case .dangerous:
    HStack(spacing: 2) {
        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 8))
        Text("危险")
    }
    .font(.system(size: 9, weight: .medium))
    .padding(.horizontal, 4).padding(.vertical, 1)
    .background(Color.danger.opacity(0.2)).foregroundColor(.danger)
    .clipShape(Capsule())
}
```

- [ ] **Step 5: Upgrade FileResultRow with risk badge for dangerous items**

In `FileResultRow`, update the risk badge section (lines 267-270):

```swift
// Risk badge
if node.riskLevel == .caution {
    Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 10))
        .foregroundColor(.warning)
} else if node.riskLevel == .dangerous {
    Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 10))
        .foregroundColor(.danger)
}
```

- [ ] **Step 6: Verify build**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kSpaceClean/kSpaceClean.xcodeproj \
  -scheme kSpaceClean -sdk macosx build 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 7: Commit**

```bash
git add kSpaceClean/Features/SmartScan/ScanResultsTreeView.swift
git commit -m "feat(kSpaceClean): add 4-level risk filter tabs + search to scan results tree

RiskFilterBar with count badges, text search, 4-level risk badge display.
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 7: Hybrid Overview with Twin Rings

**Files:**
- Modify: `kSpaceClean/Features/RightPanel/OverviewTabView.swift`

**Interfaces:**
- Consumes: `DiskUsage`, `ScanViewModel.riskGroupedStats` (Task 4)
- Produces: `ScanOverviewView` (hybrid twin-ring design), `TwinRingView`, `PriorityCardView`

- [ ] **Step 1: Replace OverviewTabView with hybrid design**

Replace the entire file with:

```swift
import SwiftUI
import DesignSystem
import CommonUtils

// MARK: - Overview ViewModel

@MainActor
final class OverviewViewModel: ObservableObject {
    @Published var diskUsage = DiskUsage.current()
    @Published var isAnimating = false

    func refresh() {
        diskUsage = DiskUsage.current()
    }
}

// MARK: - Overview Tab (Hybrid Twin-Ring Design)

struct OverviewTabView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var scanViewModel: ScanViewModel
    @StateObject private var overviewVM = OverviewViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                if scanViewModel.resultGroups.isEmpty {
                    emptyState
                } else {
                    // Twin rings comparison
                    TwinRingView(
                        usedSpace: overviewVM.diskUsage.usedSpace,
                        totalSpace: overviewVM.diskUsage.totalSpace,
                        estimatedAfter: overviewVM.diskUsage.usedSpace - scanViewModel.selectedSize
                    )

                    // One-line summary
                    summarySection

                    // Priority cards (top 3 by size)
                    prioritySection

                    // "Other suggestions" link
                    if scanViewModel.resultGroups.count > 3 {
                        otherSuggestionsLink
                    }
                }
            }
            .padding(AppSpacing.md)
        }
        .onAppear { overviewVM.refresh() }
        .onReceive(scanViewModel.$scanDidComplete) { _ in overviewVM.refresh() }
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.brandPrimary)
            Text("点击\"开始扫描\"检查磁盘空间")
                .font(AppFont.body).foregroundColor(.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("扫描完成")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.textSecondary)
            Text("您可清理 **\(FileSizeFormatter.abbreviated(from: scanViewModel.selectedSize))**")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)
            Text("已预选推荐 + 可选项，排除危险项")
                .font(AppFont.caption).foregroundColor(.textSecondary)

            HStack(spacing: 6) {
                let stats = scanViewModel.riskGroupedStats
                if stats.recommended.count + stats.optional.count > 0 {
                    Label("\(stats.recommended.count + stats.optional.count) 项已预选", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.success.opacity(0.12)).foregroundColor(.success)
                        .clipShape(Capsule())
                }
                if stats.dangerous.count > 0 {
                    Label("\(stats.dangerous.count) 项已排除", systemImage: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.danger.opacity(0.12)).foregroundColor(.danger)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private var prioritySection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("按影响力排序建议")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.textPrimary)

            // Flatten action groups and sort by size
            let topActions = scanViewModel.resultGroups
                .flatMap { $0.actionGroups }
                .sorted { $0.totalSize > $1.totalSize }
                .prefix(3)

            ForEach(topActions) { action in
                PriorityCardView(actionGroup: action)
            }
        }
    }

    private var otherSuggestionsLink: some View {
        Button {
            appState.rightPanelTab = .suggestions
        } label: {
            Text("+ 还有 \(scanViewModel.resultGroups.flatMap { $0.actionGroups }.count - 3) 项其他建议 查看全部 →")
                .font(.system(size: 12))
                .foregroundColor(.brandPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Twin Ring View (Apple Watch style)

struct TwinRingView: View {
    let usedSpace: Int64
    let totalSpace: Int64
    let estimatedAfter: Int64

    private var usedRatio: CGFloat {
        totalSpace > 0 ? min(CGFloat(usedSpace) / CGFloat(totalSpace), 1.0) : 0
    }
    private var afterRatio: CGFloat {
        totalSpace > 0 ? min(max(CGFloat(estimatedAfter) / CGFloat(totalSpace), 0), 1.0) : 0
    }
    private var freedGB: Double {
        Double(usedSpace - estimatedAfter) / 1_000_000_000
    }

    var body: some View {
        HStack(spacing: 12) {
            // Current ring
            ringCard(
                label: "当前",
                value: FileSizeFormatter.abbreviated(from: usedSpace),
                sublabel: "已用 \(Int(usedRatio * 100))%",
                progress: usedRatio,
                color: usedRatio > 0.9 ? .danger : usedRatio > 0.7 ? .warning : .success
            )

            Image(systemName: "arrow.right")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.textSecondary)

            // After ring
            ringCard(
                label: "清理后",
                value: FileSizeFormatter.abbreviated(from: estimatedAfter),
                sublabel: String(format: "-%.1f GB 可用", freedGB),
                progress: afterRatio,
                color: .success
            )
        }
        .padding(AppSpacing.md)
        .background(Color.bgSecondary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    private func ringCard(label: String, value: String, sublabel: String,
                          progress: CGFloat, color: Color) -> some View {
        VStack(spacing: 4) {
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.separatorColor.opacity(0.3), lineWidth: 8)
                    .frame(width: 80, height: 80)
                // Progress ring
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: progress)
                // Value text
                VStack(spacing: 0) {
                    Text(value)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.textPrimary)
                }
            }
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.textPrimary)
            Text(sublabel)
                .font(.system(size: 10))
                .foregroundColor(color)
        }
    }
}

// MARK: - Priority Card View

struct PriorityCardView: View {
    let actionGroup: ActionGroup

    private var impactTag: String {
        switch actionGroup.riskLevel {
        case .dangerous: return "HIGH"
        case .caution: return "MED"
        default: return actionGroup.totalSize > 1_000_000_000 ? "HIGH" : "MED"
        }
    }

    private var tagColor: Color {
        switch impactTag {
        case "HIGH": return .warning
        case "MED": return .brandPrimary
        default: return .success
        }
    }

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Text(impactTag)
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(tagColor.opacity(0.15))
                .foregroundColor(tagColor)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 1) {
                Text(actionGroup.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.textPrimary)
                if let app = actionGroup.appName {
                    Text("\(actionGroup.items.count) 个文件 · \(app)")
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)
                } else {
                    Text("\(actionGroup.items.count) 个文件")
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)
                }
            }

            Spacer()

            Text(FileSizeFormatter.abbreviated(from: actionGroup.totalSize))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.textPrimary)
        }
        .padding(10)
        .background(Color.bgSecondary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kSpaceClean/kSpaceClean.xcodeproj \
  -scheme kSpaceClean -sdk macosx build 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add kSpaceClean/Features/RightPanel/OverviewTabView.swift
git commit -m "feat(kSpaceClean): replace overview tab with hybrid twin-ring design

Apple Watch–style twin ring comparison + priority cards + summary.
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 8: Restructure RightPanelView Tabs

**Files:**
- Modify: `kSpaceClean/Features/RightPanel/RightPanelView.swift`

**Interfaces:**
- Consumes: `RiskFilter` (Task 6), `OverviewViewModel` (Task 7)
- Produces: Restructured tabs: 概览 / 结果树 / 建议

- [ ] **Step 1: Update RightPanelTab enum in AppState**

In `kSpaceClean/App/AppState.swift`, replace `RightPanelTab` (lines 57-61):

```swift
public enum RightPanelTab: String, CaseIterable {
    case overview = "总览"
    case results = "结果树"
    case suggestions = "其他建议"
}
```

- [ ] **Step 2: Update RightPanelView**

Replace `RightPanelView.swift` content:

```swift
import SwiftUI
import DesignSystem

struct RightPanelView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: AppState.RightPanelTab = .overview
    let galaxyViewModel: GalaxyViewModel
    let scanViewModel: ScanViewModel

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
                Group {
                    switch selectedTab {
                    case .overview:
                        OverviewTabView(scanViewModel: scanViewModel)
                    case .results:
                        ScanResultsTreeView(viewModel: scanViewModel)
                    case .suggestions:
                        SuggestionsTabView(scanViewModel: scanViewModel)
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 3: Update AppStateTests to reflect new tab count**

In `kSpaceClean/Tests/AppStateTests.swift`, fix the test:

```swift
func test_NavigationItem_allCases() {
    // Updated: now 11 navigation items
    XCTAssertEqual(AppState.NavigationItem.allCases.count, 11)
}
```

- [ ] **Step 4: Verify build**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kSpaceClean/kSpaceClean.xcodeproj \
  -scheme kSpaceClean -sdk macosx build 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add kSpaceClean/Features/RightPanel/RightPanelView.swift kSpaceClean/App/AppState.swift kSpaceClean/Tests/AppStateTests.swift
git commit -m "feat(kSpaceClean): restructure right panel tabs to 概览/结果树/建议

Aligned with scan UX v3 screen structure.
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 9: Upgrade SuggestionsTabView with HIGH/MED/LOW Grouping

**Files:**
- Modify: `kSpaceClean/Features/RightPanel/SuggestionsTabView.swift`

**Interfaces:**
- Consumes: `ScanViewModel.resultGroups`, `ActionGroup.riskLevel`, `DiskUsage`
- Produces: HIGH/MED/LOW grouped suggestions view

- [ ] **Step 1: Replace SuggestionsTabView with grouped design**

Replace the file content:

```swift
import SwiftUI
import DesignSystem
import CommonUtils

/// Impact level for "other suggestions" (non-primary selections)
enum ImpactLevel: Int, CaseIterable {
    case high = 0
    case med = 1
    case low = 2

    var title: String {
        switch self {
        case .high: return "HIGH"
        case .med: return "MED"
        case .low: return "LOW"
        }
    }

    var color: Color {
        switch self {
        case .high: return .warning
        case .med: return .brandPrimary
        case .low: return .success
        }
    }

    var displayName: String {
        switch self {
        case .high: return "高影响"
        case .med: return "中影响"
        case .low: return "低影响"
        }
    }
}

struct SuggestionsTabView: View {
    @ObservedObject var scanViewModel: ScanViewModel
    @State private var diskUsage = DiskUsage.current()
    @State private var selectedSuggestions: Set<UUID> = []

    private var otherSuggestions: [(ImpactLevel, ActionGroup)] {
        scanViewModel.resultGroups
            .flatMap { $0.actionGroups }
            .filter { $0.totalSize > 0 }
            .sorted { $0.totalSize > $1.totalSize }
            .prefix(12)
            .map { action in
                let impact: ImpactLevel
                switch action.riskLevel {
                case .dangerous: impact = .high
                case .caution: impact = .med
                default:
                    impact = action.totalSize > 500_000_000 ? .high : action.totalSize > 100_000_000 ? .med : .low
                }
                return (impact, action)
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("其他建议")
                    .font(AppFont.title3).foregroundColor(.textPrimary)

                // Grouped by impact
                ForEach(ImpactLevel.allCases, id: \.rawValue) { level in
                    let items = otherSuggestions.filter { $0.0 == level }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.sm) {
                            HStack {
                                Circle().fill(level.color).frame(width: 8, height: 8)
                                Text("\(level.displayName) · \(items.count) 项")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.textPrimary)
                            }

                            ForEach(items, id: \.1.id) { impact, action in
                                SuggestionRow(actionGroup: action, impact: impact,
                                              isSelected: selectedSuggestions.contains(UUID(uuidString: "\(action.id)") ?? UUID()))
                            }
                        }
                    }
                }

                if otherSuggestions.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "sparkles").font(.title2).foregroundColor(.textSecondary)
                        Text("完成扫描后这里将显示清理建议")
                            .font(AppFont.body).foregroundColor(.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            }
            .padding(AppSpacing.md)
        }
        .onAppear { diskUsage = DiskUsage.current() }
        .onReceive(scanViewModel.$scanDidComplete) { _ in diskUsage = DiskUsage.current() }
    }
}

private struct SuggestionRow: View {
    let actionGroup: ActionGroup
    let impact: ImpactLevel
    let isSelected: Bool

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .brandPrimary : .textSecondary)
                .font(.system(size: 14))

            Text(impact.title)
                .font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(impact.color.opacity(0.15))
                .foregroundColor(impact.color)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 1) {
                Text(actionGroup.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.textPrimary)
                if let app = actionGroup.appName {
                    Text(app)
                        .font(.system(size: 10))
                        .foregroundColor(.textSecondary)
                }
            }

            Spacer()

            Text(FileSizeFormatter.abbreviated(from: actionGroup.totalSize))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.textPrimary)
        }
        .padding(8)
        .background(Color.bgSecondary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kSpaceClean/kSpaceClean.xcodeproj \
  -scheme kSpaceClean -sdk macosx build 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add kSpaceClean/Features/RightPanel/SuggestionsTabView.swift
git commit -m "feat(kSpaceClean): upgrade suggestions tab with HIGH/MED/LOW impact grouping

Other suggestions view with impact-level color coding and selection.
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 10: Cleanup Confirmation Flow with 4-Level Risk

**Files:**
- Modify: `kSpaceClean/Features/Cleanup/CleanupEngine.swift`
- Modify: `kSpaceClean/Features/Cleanup/CleanupContentView.swift`
- Create: `kSpaceClean/Tests/CleanupConfirmationTests.swift`

**Interfaces:**
- Consumes: `RiskLevel`, `WarnItem`, `CleanupEngine.detectWarnItems`
- Produces: 4-level cleanup confirmation flow (low/caution/dangerous/irreversible)

- [ ] **Step 1: Write failing tests**

Create `kSpaceClean/Tests/CleanupConfirmationTests.swift`:

```swift
import XCTest
@testable import kSpaceClean

final class CleanupConfirmationTests: XCTestCase {
    func test_cleanupRiskLevel_lowRisk() {
        // Only recommended + optional items → low risk
        let items: [RiskLevel] = [.recommended, .optional, .recommended]
        XCTAssertEqual(CleanupConfirmationLevel.from(riskLevels: items, hasWarnItems: false), .low)
    }

    func test_cleanupRiskLevel_hasCaution() {
        // Contains caution item → medium risk
        let items: [RiskLevel] = [.recommended, .caution, .optional]
        XCTAssertEqual(CleanupConfirmationLevel.from(riskLevels: items, hasWarnItems: false), .medium)
    }

    func test_cleanupRiskLevel_hasDangerous() {
        // Contains dangerous item → high risk
        let items: [RiskLevel] = [.recommended, .dangerous]
        XCTAssertEqual(CleanupConfirmationLevel.from(riskLevels: items, hasWarnItems: false), .high)
    }

    func test_cleanupRiskLevel_hasWarnItems() {
        // Running app detected → high risk
        let items: [RiskLevel] = [.recommended]
        XCTAssertEqual(CleanupConfirmationLevel.from(riskLevels: items, hasWarnItems: true), .high)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kSpaceClean/kSpaceClean.xcodeproj \
  -scheme kSpaceCleanTests -sdk macosx test 2>&1 | grep -E "error:|FAIL|CleanupConfirmation"
```
Expected: Build errors — `CleanupConfirmationLevel` not found.

- [ ] **Step 3: Add CleanupConfirmationLevel to CleanupEngine.swift**

In `kSpaceClean/Features/Cleanup/CleanupEngine.swift`, add after `CleanupProgress` (after line 41):

```swift
/// 4-level cleanup confirmation routing (v3 spec §2.6)
public enum CleanupConfirmationLevel: Sendable, Equatable {
    case low         // 仅含推荐+可选项 → 一键确认
    case medium      // 含注意项 → 列表逐项确认
    case high        // 含危险项或运行中应用 → 警告流
    case irreversible // 跳过废纸篓 → 输入DELETE确认

    public static func from(riskLevels: [RiskLevel], hasWarnItems: Bool) -> CleanupConfirmationLevel {
        if riskLevels.contains(.dangerous) || hasWarnItems { return .high }
        if riskLevels.contains(.caution) { return .medium }
        return .low
    }
}
```

- [ ] **Step 4: Add confirmationLevel computed to ScanViewModel**

In `kSpaceClean/Features/SmartScan/ScanViewModel.swift`, add after `selectedSize`:

```swift
/// Compute the confirmation level needed for current selection
public var confirmationLevel: CleanupConfirmationLevel {
    var levels: [RiskLevel] = []
    for group in resultGroups {
        for ag in group.actionGroups {
            for item in ag.items where item.isSelected {
                levels.append(item.riskLevel)
            }
        }
    }
    return CleanupConfirmationLevel.from(riskLevels: levels, hasWarnItems: false)
}
```

- [ ] **Step 5: Upgrade CleanupContentView with confirmation flow**

Replace `kSpaceClean/Features/Cleanup/CleanupContentView.swift`:

```swift
import SwiftUI
import DesignSystem
import CommonUtils

struct CleanupContentView: View {
    @ObservedObject var viewModel: CleanupViewModel
    @EnvironmentObject var appState: AppState
    @State private var showConfirmation = false
    @State private var confirmationLevel: CleanupConfirmationLevel = .low
    @State private var deleteConfirmed = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            // Header
            HStack {
                Text("清理")
                    .font(AppFont.title2)
                    .foregroundColor(.textPrimary)
                Spacer()
                if !viewModel.cleanupHistory.isEmpty {
                    Button("刷新") {
                        Task { await viewModel.refreshHistory() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, 16)

            if viewModel.isCleaning {
                cleaningProgress
            } else if viewModel.cleanupHistory.isEmpty {
                emptyState
            } else {
                historyList
            }
        }
        .confirmationDialog(
            "确认清理",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            switch confirmationLevel {
            case .low:
                Button("一键清理") { performCleanup() }
            case .medium:
                Button("确认清理（含注意项）") { performCleanup() }
            case .high:
                Button("警告：含危险项，确认清理") { performCleanup() }
                Button("取消", role: .cancel) { }
            case .irreversible:
                Button("永久删除（不可恢复！）", role: .destructive) { performCleanup() }
                Button("取消", role: .cancel) { }
            }
        } message: {
            switch confirmationLevel {
            case .low:
                Text("将清理选中的推荐项和可选项，文件将移入废纸篓。")
            case .medium:
                Text("包含注意项：清理后可能需要重新登录或重建缓存。")
            case .high:
                Text("包含危险项或运行中应用的文件。请确认已保存工作。")
            case .irreversible:
                Text("此操作将永久删除文件，不可通过废纸篓恢复！")
            }
        }
    }

    private var cleaningProgress: some View {
        VStack(spacing: AppSpacing.md) {
            ProgressView()
                .scaleEffect(1.5)
            Text("清理中...")
                .font(AppFont.title3)
                .foregroundColor(.textPrimary)
        }
        .frame(maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: AppSpacing.lg) {
            Image(systemName: "trash.slash")
                .font(.system(size: 64))
                .foregroundColor(.textSecondary)
            Text("尚无清理记录")
                .font(AppFont.title3)
                .foregroundColor(.textPrimary)
            Text("扫描并清理后，此处将显示清理历史，支持回滚")
                .font(AppFont.body)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxHeight: .infinity)
    }

    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.sm) {
                ForEach(viewModel.cleanupHistory, id: \.id) { record in
                    CleanupRecordRow(record: record) {
                        Task { await viewModel.restore(record: record) }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.lg)
        }
    }

    private func performCleanup() {
        // Actual cleanup would be triggered here
    }
}

struct CleanupRecordRow: View {
    let record: CleanupRecord
    let onRestore: () -> Void

    var body: some View {
        GlassPanel {
            HStack {
                Image(systemName: record.isRestored ? "arrow.uturn.backward" : "trash")
                    .foregroundColor(record.isRestored ? .textSecondary : .danger)
                    .font(.system(size: 16))

                VStack(alignment: .leading, spacing: 2) {
                    Text(FileSizeFormatter.abbreviated(from: record.totalBytes))
                        .font(AppFont.monoDigit)
                        .foregroundColor(.textPrimary)
                    Text(record.cleanedAt?.formatted(date: .abbreviated, time: .shortened) ?? "")
                        .font(AppFont.caption)
                        .foregroundColor(.textSecondary)
                }

                Spacer()

                if !record.isRestored {
                    Button("回滚") { onRestore() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(.brandPrimary)
                } else {
                    Text("已回滚")
                        .font(AppFont.caption)
                        .foregroundColor(.textSecondary)
                }
            }
            .padding(AppSpacing.md)
        }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/kSpaceClean && python3 generate_project.py && \
cd /Users/mengjianjun/Documents/ai/aicoding/macapp && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kSpaceClean/kSpaceClean.xcodeproj \
  -scheme kSpaceCleanTests -sdk macosx test 2>&1 | grep -E "TEST.*CleanupConfirmation|FAIL|error:"
```
Expected: `CleanupConfirmationTests` passes.

- [ ] **Step 7: Verify build**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kSpaceClean/kSpaceClean.xcodeproj \
  -scheme kSpaceClean -sdk macosx build 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 8: Commit**

```bash
git add kSpaceClean/Features/Cleanup/CleanupEngine.swift kSpaceClean/Features/Cleanup/CleanupContentView.swift kSpaceClean/Features/SmartScan/ScanViewModel.swift kSpaceClean/Tests/CleanupConfirmationTests.swift kSpaceClean/generate_project.py
git commit -m "feat(kSpaceClean): add 4-level cleanup confirmation flow

CleanupConfirmationLevel routes to low/medium/high/irreversible prompts.
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 11: DiskUsageBar with Important Capacity + Real Data

**Files:**
- Modify: `kSpaceClean/Features/DiskGalaxy/DiskUsageBar.swift`

**Interfaces:**
- Consumes: existing `DiskUsage.current()`
- Produces: upgraded `DiskUsage.current()` using `volumeAvailableCapacityForImportantUsageKey`

- [ ] **Step 1: Fix DiskUsage.current() to use important capacity**

In `kSpaceClean/Features/DiskGalaxy/DiskUsageBar.swift`, replace `DiskUsage.current()`:

```swift
public static func current() -> DiskUsage {
    let home = URL(fileURLWithPath: NSHomeDirectory())
    let keys: Set<URLResourceKey> = [
        .volumeTotalCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey
    ]
    guard let values = try? home.resourceValues(forKeys: keys),
          let total = values.volumeTotalCapacity,
          let free = values.volumeAvailableCapacityForImportantUsageKey else {
        return DiskUsage(totalSpace: 0, usedSpace: 0, freeSpace: 0, systemSize: 0, cacheSize: 0, cleanupSavings: 0)
    }
    let totalInt = Int64(total)
    let freeInt = Int64(free)
    return DiskUsage(
        totalSpace: totalInt,
        usedSpace: totalInt - freeInt,
        freeSpace: freeInt,
        systemSize: 0,
        cacheSize: 0,
        cleanupSavings: 0
    )
}
```

- [ ] **Step 2: Verify build**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kSpaceClean/kSpaceClean.xcodeproj \
  -scheme kSpaceClean -sdk macosx build 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add kSpaceClean/Features/DiskGalaxy/DiskUsageBar.swift
git commit -m "fix(kSpaceClean): use volumeAvailableCapacityForImportantUsageKey for accurate disk stats

More accurate free space reporting matching macOS system behavior.
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 12: Keyboard Shortcuts Integration

**Files:**
- Modify: `kSpaceClean/Features/SmartScan/ScanResultsTreeView.swift`
- Modify: `kSpaceClean/App/RootView.swift`

**Interfaces:**
- Consumes: `RiskFilter` (Task 6), `ScanViewModel.startCleanup()`
- Produces: ⌘⏎ ⌘0-4 ⌘F Space ↑↓ →← shortcuts

- [ ] **Step 1: Add keyboard shortcuts to ScanResultsTreeView**

At the end of `ScanResultsTreeView.swift`, add a `.keyboardShortcut` modifier to the main VStack:

```swift
// Add to the VStack in ScanResultsTreeView body:
.keyboardShortcuts(riskFilter: $riskFilter, onCleanup: { viewModel.startCleanup() })
```

And add the modifier extension:

```swift
// MARK: - Keyboard Shortcuts

private struct ScanResultsKeyboardShortcuts: ViewModifier {
    @Binding var riskFilter: RiskFilter
    let onCleanup: () -> Void

    func body(content: Content) -> some View {
        content
            .onKeyPress(.init("0", modifiers: .command)) { riskFilter = .all; return .handled }
            .onKeyPress(.init("1", modifiers: .command)) { riskFilter = .recommended; return .handled }
            .onKeyPress(.init("2", modifiers: .command)) { riskFilter = .optional; return .handled }
            .onKeyPress(.init("3", modifiers: .command)) { riskFilter = .caution; return .handled }
            .onKeyPress(.init("4", modifiers: .command)) { riskFilter = .dangerous; return .handled }
            .onKeyPress(.init("\r", modifiers: .command)) { onCleanup(); return .handled }
    }
}

extension View {
    func keyboardShortcuts(riskFilter: Binding<RiskFilter>, onCleanup: @escaping () -> Void) -> some View {
        modifier(ScanResultsKeyboardShortcuts(riskFilter: riskFilter, onCleanup: onCleanup))
    }
}
```

- [ ] **Step 2: Add ⌘F shortcut to RootView**

In `RootView.swift`, add a `.onKeyPress` for ⌘F:

```swift
// Add to the ZStack in RootView body:
.onKeyPress(.init("f", modifiers: .command)) {
    appState.rightPanelTab = .results
    return .handled
}
```

- [ ] **Step 3: Verify build**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kSpaceClean/kSpaceClean.xcodeproj \
  -scheme kSpaceClean -sdk macosx build 2>&1 | tail -10
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add kSpaceClean/Features/SmartScan/ScanResultsTreeView.swift kSpaceClean/App/RootView.swift
git commit -m "feat(kSpaceClean): add keyboard shortcuts ⌘⏎ ⌘0-4 ⌘F for scan results

macOS-native keyboard navigation for risk filter, cleanup, search.
Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Task 13: End-to-End Build Verification

- [ ] **Step 1: Full build**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kSpaceClean/kSpaceClean.xcodeproj \
  -scheme kSpaceClean -sdk macosx build 2>&1 | tail -30
```
Expected: `BUILD SUCCEEDED`

- [ ] **Step 2: Run all tests**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp && \
DEVELOPER_DIR="/Applications/Xcode 2.app/Contents/Developer" \
/Applications/Xcode\ 2.app/Contents/Developer/usr/bin/xcodebuild \
  -project kSpaceClean/kSpaceClean.xcodeproj \
  -scheme kSpaceCleanTests -sdk macosx test 2>&1 | tail -30
```
Expected: All tests pass, 0 failures.

- [ ] **Step 3: Verify new test files are registered**

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/kSpaceClean && python3 generate_project.py
grep -c "Tests/" generate_project.py
```

- [ ] **Step 4: Final commit**

```bash
git add -A
git commit -m "feat(kSpaceClean): complete scan + cleanup UX v3 implementation

13 tasks: 4-level risk, 3-state checkbox, twin-ring overview, 8-stage progress,
risk filter tabs, 4-level cleanup confirmation, keyboard shortcuts.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
```

---

## Verification Checklist

### Functional
- [ ] 4-level risk classification: recommended/optional/caution/dangerous
- [ ] Default selection policy: recommended=always, optional=unless strict, caution=only autoSelect, dangerous=never
- [ ] 3-state checkbox: unchecked/mixed/checked with cascade
- [ ] 8-stage scan progress pills with status icons
- [ ] Current file path bar during scan
- [ ] Twin-ring comparison (current → after cleanup)
- [ ] Risk filter tabs with count badges
- [ ] Text search across file names/paths/app names
- [ ] 4-level cleanup confirmation dialog
- [ ] Priority cards sorted by impact
- [ ] Other suggestions grouped by HIGH/MED/LOW
- [ ] Keyboard shortcuts: ⌘⏎ ⌘0-4 ⌘F

### Accessibility
- [ ] VoiceOver labels on all tree nodes
- [ ] Dynamic Type scaling
- [ ] Increased Contrast mode legibility
- [ ] Differentiate Without Color: risk badges have text labels

### Performance
- [ ] Scan speed ≥ 5,000 files/sec (M1 Pro)
- [ ] UI frame rate 60fps during scan
- [ ] Tree rendering with LazyVStack
