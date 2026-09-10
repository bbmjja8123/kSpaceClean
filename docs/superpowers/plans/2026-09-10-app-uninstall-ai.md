# 应用卸载 AI 深度优化 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把「应用卸载」残留列表升级为 AI 理解的可读视图：规则+NLEmbedding 语义分组、白话解释器、健康摘要卡、右侧详情面板。

**Architecture:** 新增 4 个类型（ResidueGroupingEngine / HealthSummaryBuilder / ResidueExplainer / AppUninstallDetailPanel），AppUninstallView 改双栏（左列表/右面板），ViewModel 增选中条目发布 + 勾选态单一来源（selectedResiduePaths）+ 分组惰性缓存。清理管道不变（CleanupEngine 扁平 URL）。

**Tech Stack:** SwiftUI + NaturalLanguage (NLEmbedding) + AppKit；测试 XCTest。

**Spec:** `docs/superpowers/specs/2026-09-10-app-uninstall-ai-design.md`

## Global Constraints

- 零网络；NLEmbedding 不可用时全落「其他」并显示降级提示（C-5）
- 勾选态唯一来源 = 面板 `selectedResiduePaths: Set<String>`（键 = 残留路径）
- 卸载提交语义：条目勾选 = App 本体 + 全部残留；面板显式勾选过 = App 本体 + 仅选中残留（清空回退整 App）
- 所有删除走 CleanupEngine（废纸篓 + 30 天历史 + 配额）
- 文案 C-5（无恐吓）、路径 C-1（友好显示，raw 仅 tooltip）、DesignSystem tokens（AppSpacing/AppFont/AppRadius/Color.*）
- 每次新增文件后 `bash kWise/scripts/generate.sh`
- 每任务结束 commit 到 main 并推送

---

### Task 1: ResidueExplainer 白话解释器

**Files:**
- Create: `kWise/Features/AppUninstall/ResidueExplainer.swift`
- Test: `kWise/Tests/ResidueExplainerTests.swift`

**Interfaces:**
- Consumes: `ResidueFile`（AppCatalogCore：url/type/sizeBytes/confidence/isProtected）、`MappingStore`（zh_app_mappings）
- Produces: `enum ResidueExplainer { static func explain(_ residue: ResidueFile, appName: String) -> String ; static func ownerHint(forLabel label: String, mappings: [ZhAppMapping]) -> String? }`

- [ ] **Step 1: 写失败测试**

```swift
// kWise/Tests/ResidueExplainerTests.swift
import XCTest
import AppCatalogCore
@testable import kWise

final class ResidueExplainerTests: XCTestCase {
    private func residue(_ type: ResidueType, _ path: String) -> ResidueFile {
        ResidueFile(url: URL(fileURLWithPath: path), type: type, sizeBytes: 100,
                    confidence: 0.9, description: "")
    }

    func testPreferencesExplanation() {
        let text = ResidueExplainer.explain(
            residue(.preferences, "/Users/x/Library/Preferences/com.test.app.plist"),
            appName: "TestApp")
        XCTAssertTrue(text.contains("偏好设置"), text)
    }

    func testCachesExplanation() {
        let text = ResidueExplainer.explain(
            residue(.caches, "/Users/x/Library/Caches/com.test.app"),
            appName: "TestApp")
        XCTAssertTrue(text.contains("缓存"), text)
    }

    func testLaunchAgentExplanation() {
        let text = ResidueExplainer.explain(
            residue(.launchAgent, "/Users/x/Library/LaunchAgents/com.test.app.plist"),
            appName: "TestApp")
        XCTAssertTrue(text.contains("启动") || text.contains("自启动"), text)
    }

    func testUnknownPatternGetsGenericText() {
        let text = ResidueExplainer.explain(
            residue(.plugin, "/Users/x/Library/Whatever/odd.bin"),
            appName: "TestApp")
        XCTAssertTrue(text.contains("支撑文件") || text.contains("文件"), text)
    }

    func testChatPathMention() {
        let text = ResidueExplainer.explain(
            residue(.appSupport, "/Users/x/Library/Application Support/com.tencent.xinWeChat/Message"),
            appName: "WeChat")
        XCTAssertTrue(text.contains("聊天") || text.contains("消息"), text)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `xcodebuild -workspace KraftlyWorkspace.xcworkspace -scheme kWise build-for-testing CODE_SIGNING_ALLOWED=NO 2>&1 | grep error`
Expected: FAIL — "cannot find 'ResidueExplainer' in scope"

- [ ] **Step 3: 最小实现**

```swift
// kWise/Features/AppUninstall/ResidueExplainer.swift
//
// 残留白话解释器 (v2.6)：规则表 + 路径模式 → 确定性白话说明。
// 不调用生成式模型 —— 可解释、可测试（spec §5）。
import Foundation
import AppCatalogCore

enum ResidueExplainer {

    static func explain(_ residue: ResidueFile, appName: String) -> String {
        let path = residue.url.path

        // 聊天类路径优先（用户最关心的数据安全提示）。
        let chatMarkers = ["Message", "Chat", "聊天", "WeChat", "MessageStore"]
        if residue.type == .appSupport || residue.type == .container,
           chatMarkers.contains(where: { path.localizedCaseInsensitiveContains($0) }) {
            return "聊天记录数据，删除后聊天图片与消息不再显示"
        }

        switch residue.type {
        case .preferences:
            return "应用的偏好设置，删除后 App 恢复首次启动的默认配置"
        case .caches, .temporary:
            return "缓存文件，删除后 App 会自动重建"
        case .savedState:
            return "窗口状态记录，删除后无影响"
        case .httpStorage:
            return "网络缓存数据，删除后 App 重新登录可能需要"
        case .launchAgent, .launchDaemon, .startupItem:
            return "开机自启动配置，删除后 App 不再自动启动"
        case .webKit, .cookie:
            return "网页数据（Cookie/本地存储），清理后将退出相关网站的登录"
        case .groupContainer:
            return "应用组共享数据，可能被同厂商多个应用使用"
        case .plugin, .prefPane:
            return "应用插件或系统偏好面板"
        case .database:
            return "应用数据库文件"
        default:
            break
        }

        // 路径模式补充（未知 type 或需要更细的解释）。
        if path.contains("Application Support") {
            return "应用支撑数据目录"
        }
        if path.contains("Logs") {
            return "日志文件，通常可安全删除"
        }
        return "应用的支撑文件（由「\(appName)」创建）"
    }

    /// 归属推断共享 API：label 反查 zh 映射 → 「这是 XX 的后台助手」。
    /// 启动项模块 (StartupItemsViewModel.inferUsage) 同步迁移到此。
    static func ownerHint(forLabel label: String, mappings: [ZhAppMapping]) -> String? {
        let cleaned = label
            .replacingOccurrences(of: "com.", with: "")
            .replacingOccurrences(of: "update", with: "")
            .replacingOccurrences(of: "agent", with: "")
            .replacingOccurrences(of: "helper", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        for mapping in mappings {
            if cleaned.lowercased().contains(
                mapping.bundleID.replacingOccurrences(of: "com.", with: "").lowercased())
                || mapping.bundleID.lowercased().contains(cleaned.lowercased()) {
                return "这是「\(mapping.displayName)」的后台助手"
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `xcodebuild -workspace KraftlyWorkspace.xcworkspace -scheme kWise build-for-testing CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|TEST BUILD"`
Expected: TEST BUILD SUCCEEDED

- [ ] **Step 5: Commit**

```bash
git add kWise/Features/AppUninstall/ResidueExplainer.swift kWise/Tests/ResidueExplainerTests.swift
git commit -m "feat(kWise): residue explainer — deterministic plain-language explanations"
```

---

### Task 2: ResidueGroupingEngine（规则遍 + NLEmbedding 遍）

**Files:**
- Create: `kWise/Features/AppUninstall/ResidueGroupingEngine.swift`
- Test: `kWise/Tests/ResidueGroupingEngineTests.swift`

**Interfaces:**
- Consumes: `ResidueFile`、`NLEmbedding`（NaturalLanguage）
- Produces:
  - `enum ResidueGroupKind: String, CaseIterable { preferences, caches, appData, webData, launchAgents, plugins, savedState, other }`（title/icon/anchorWords 计算属性）
  - `struct ResidueGroup: Identifiable { let kind: ResidueGroupKind; let residues: [ResidueFile] }`
  - `enum ResidueGroupingEngine { static func group(_ residues: [ResidueFile], embedding: NLEmbedding?) -> [ResidueGroup] }`（embedding 可注入 mock；nil = NLEmbedding 不可用 → 全落 other）

- [ ] **Step 1: 写失败测试**

```swift
// kWise/Tests/ResidueGroupingEngineTests.swift
import XCTest
import NaturalLanguage
import AppCatalogCore
@testable import kWise

final class ResidueGroupingEngineTests: XCTestCase {

    private func residue(_ type: ResidueType, _ path: String) -> ResidueFile {
        ResidueFile(url: URL(fileURLWithPath: path), type: type, sizeBytes: 100,
                    confidence: 0.9, description: "")
    }

    func testRulePassMapsKnownTypes() {
        let groups = ResidueGroupingEngine.group([
            residue(.preferences, "/Users/x/Library/Preferences/com.a.plist"),
            residue(.caches, "/Users/x/Library/Caches/com.a"),
            residue(.launchAgent, "/Users/x/Library/LaunchAgents/com.a.plist"),
            residue(.appSupport, "/Users/x/Library/Application Support/com.a"),
            residue(.webKit, "/Users/x/Library/WebKit/com.a"),
            residue(.savedState, "/Users/x/Library/Saved Application State/com.a.savedState"),
        ], embedding: nil)

        let dict = Dictionary(uniqueKeysWithValues: groups.map { ($0.kind, $0.residues.count) })
        XCTAssertEqual(dict[.preferences], 1)
        XCTAssertEqual(dict[.caches], 1)
        XCTAssertEqual(dict[.launchAgents], 1)
        XCTAssertEqual(dict[.appData], 1)
        XCTAssertEqual(dict[.webData], 1)
        XCTAssertEqual(dict[.savedState], 1)
    }

    func testUnknownPathFallsToOtherWhenEmbeddingUnavailable() {
        let groups = ResidueGroupingEngine.group([
            residue(.plugin, "/nonstandard/odd/path.bin"),
        ], embedding: nil)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.kind, .other)
    }

    func testFixedCategoryOrder() {
        let groups = ResidueGroupingEngine.group([
            residue(.savedState, "/a"),
            residue(.preferences, "/b"),
            residue(.caches, "/c"),
        ], embedding: nil)
        let order = groups.map(\\.kind)
        XCTAssertEqual(order, ResidueGroupKind.allCases.filter { order.contains($0) },
                       "分组输出必须按 ResidueGroupKind.allCases 固定排序")
    }

    func testEmptyInputYieldsEmptyOutput() {
        XCTAssertTrue(ResidueGroupingEngine.group([], embedding: nil).isEmpty)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: 同 Task 1 模式
Expected: FAIL — "cannot find 'ResidueGroupingEngine' in scope"

- [ ] **Step 3: 最小实现**

```swift
// kWise/Features/AppUninstall/ResidueGroupingEngine.swift
//
// AI 语义分组引擎 (v2.6)：规则遍 + NLEmbedding 遍。纯内存、零网络。
import Foundation
import NaturalLanguage
import AppCatalogCore

enum ResidueGroupKind: String, CaseIterable {
    case preferences, caches, appData, webData, launchAgents, plugins, savedState, other

    var title: String {
        switch self {
        case .preferences: return "偏好设置"
        case .caches: return "缓存数据"
        case .appData: return "应用数据"
        case .webData: return "网页数据"
        case .launchAgents: return "启动项"
        case .plugins: return "插件与面板"
        case .savedState: return "窗口状态"
        case .other: return "其他"
        }
    }

    var icon: String {
        switch self {
        case .preferences: return "gearshape"
        case .caches: return "cpu"
        case .appData: return "shippingbox"
        case .webData: return "globe"
        case .launchAgents: return "power"
        case .plugins: return "puzzlepiece"
        case .savedState: return "rectangle.stack"
        case .other: return "shippingbox"
        }
    }

    /// NLEmbedding 归组的锚点词。
    var anchorWords: [String] {
        switch self {
        case .preferences: return ["preferences", "plist", "设置", "偏好", "config"]
        case .caches: return ["cache", "caches", "缓存", "临时", "temp"]
        case .appData: return ["support", "数据", "data", "documents", "container"]
        case .webData: return ["webkit", "cookie", "storage", "网页", "localstorage"]
        case .launchAgents: return ["agent", "daemon", "launch", "启动", "login"]
        case .plugins: return ["plugin", "prefpane", "插件", "panel"]
        case .savedState: return ["saved", "state", "状态", "windows"]
        case .other: return []
        }
    }
}

struct ResidueGroup: Identifiable {
    let kind: ResidueGroupKind
    let residues: [ResidueFile]
    var id: ResidueGroupKind { kind }
}

public enum ResidueGroupingEngine {

    private static let embeddingCache = NSCache<NSString, NSArray>()

    /// 主入口：规则遍 + embedding 遍。`embedding` 可注入 mock（测试），
    /// nil 时尝试系统 zh/en 词向量，均不可用则全落 other。
    public static func group(_ residues: [ResidueFile],
                             embedding: NLEmbedding?) -> [ResidueGroup] {
        let effective = embedding ?? NLEmbedding.wordEmbedding(for: .simplifiedChinese)
            ?? NLEmbedding.wordEmbedding(for: .english)

        var buckets: [ResidueGroupKind: [ResidueFile]] = [:]
        var unknowns: [ResidueFile] = []

        for residue in residues {
            guard let kind = ruleKind(for: residue) else {
                unknowns.append(residue)
                continue
            }
            buckets[kind, default: []].append(residue)
        }

        // embedding 遍：未知路径按组件词向量与锚点余弦相似度归组。
        if let embedding = effective {
            for residue in unknowns {
                if let kind = bestEmbeddingMatch(for: residue.url.path, embedding: embedding) {
                    buckets[kind, default: []].append(residue)
                }
            }
        }
        // embedding 不可用 → unknowns 全落 other（诚实降级）。

        return ResidueGroupKind.allCases.compactMap { kind in
            guard let items = buckets[kind], !items.isEmpty else { return nil }
            return ResidueGroup(kind: kind, residues: items)
        }
    }

    /// 规则遍：ResidueType → kind。nil = 规则未覆盖，交给 embedding。
    private static func ruleKind(for residue: ResidueFile) -> ResidueGroupKind? {
        switch residue.type {
        case .preferences: return .preferences
        case .caches: return .caches
        case .appSupport, .groupContainer, .container: return .appData
        case .webKit, .cookie: return .webData
        case .launchAgent, .launchDaemon, .startupItem: return .launchAgents
        case .plugin, .prefPane: return .plugins
        case .savedState: return .savedState
        default: return nil
        }
    }

    /// 路径组件词 → 平均向量 vs 类目锚点平均向量，取最高余弦且 ≥0.45。
    private static func bestEmbeddingMatch(for path: String,
                                           embedding: NLEmbedding) -> ResidueGroupKind? {
        let components = path
            .split(whereSeparator: { "/-_ .".contains($0) })
            .map(String.init)
            .filter { $0.count >= 3 }
        guard !components.isEmpty else { return nil }

        let threshold = 0.45
        var best: (kind: ResidueGroupKind, score: Double)?
        for kind in ResidueGroupKind.allCases where !kind.anchorWords.isEmpty {
            guard let score = averageCosine(components: components,
                                            anchors: kind.anchorWords,
                                            embedding: embedding) else { continue }
            if score >= threshold, score > (best?.score ?? -1) {
                best = (kind, score)
            }
        }
        return best?.kind
    }

    private static func averageCosine(components: [String],
                                      anchors: [String],
                                      embedding: NLEmbedding) -> Double? {
        let componentVectors = components.compactMap { vector(for: $0, embedding: embedding) }
        let anchorVectors = anchors.compactMap { vector(for: $0, embedding: embedding) }
        guard !componentVectors.isEmpty, !anchorVectors.isEmpty else { return nil }

        let componentCentroid = centroid(of: componentVectors)
        let anchorCentroid = centroid(of: anchorVectors)
        let dot = zip(componentCentroid, anchorCentroid).reduce(0.0) { $0 + $1.0 * $1.1 }
        let magA = (componentCentroid.reduce(0.0) { $0 + $1 * $1 }).squareRoot()
        let magB = (anchorCentroid.reduce(0.0) { $0 + $1 * $1 }).squareRoot()
        guard magA > 0, magB > 0 else { return nil }
        return dot / (magA * magB)
    }

    private static func vector(for word: String, embedding: NLEmbedding) -> [Double]? {
        let key = "\(word)" as NSString
        if let cached = embeddingCache.object(forKey: key) as? [Double] {
            return cached
        }
        guard let vector = embedding.vector(for: word.lowercased()) else { return nil }
        embeddingCache.setObject(vector as NSArray, forKey: key)
        return vector
    }

    private static func centroid(of vectors: [[Double]]) -> [Double] {
        guard !vectors.isEmpty else { return [] }
        let dim = vectors[0].count
        var sum = [Double](repeating: 0, count: dim)
        for v in vectors for i in 0..<dim { sum[i] += v[i] }
        return sum.map { $0 / Double(vectors.count) }
    }
}
```

> 注：`embedding.language` 若此 toolchain 无该属性，缓存 key 改用 `String(describing: embedding)` 前缀。以编译为准。

- [ ] **Step 4: 跑测试确认通过**

- [ ] **Step 5: Commit**

```bash
git add kWise/Features/AppUninstall/ResidueGroupingEngine.swift kWise/Tests/ResidueGroupingEngineTests.swift
git commit -m "feat(kWise): residue grouping engine — rule pass + NLEmbedding fallback"
```

---

### Task 3: HealthSummaryBuilder

**Files:**
- Create: `kWise/Features/AppUninstall/HealthSummaryBuilder.swift`
- Test: `kWise/Tests/HealthSummaryBuilderTests.swift`

**Interfaces:**
- Consumes: `UninstallAppEntry`（appSize/leftoverSize/lastUsedDate/installDate/isOrphan）
- Produces: `struct HealthSummary { daysInstalled: Int?; lastUsedText: String; totalSizeText: String; residueRatio: Double; grade: Grade; gradeText: String }`；`enum HealthSummaryBuilder { static func build(for entry: UninstallAppEntry, now: Date = Date()) -> HealthSummary }`；`enum Grade { clean, normal, bloated }`

- [ ] **Step 1: 写失败测试**

```swift
// kWise/Tests/HealthSummaryBuilderTests.swift
import XCTest
@testable import kWise

final class HealthSummaryBuilderTests: XCTestCase {

    private func entry(appSize: Int64, leftoverSize: Int64,
                       installedDaysAgo: Int? = 100,
                       lastUsedDaysAgo: Int? = 7,
                       isOrphan: Bool = false) -> UninstallAppEntry {
        UninstallAppEntry(
            appName: "App", bundleID: "com.test",
            appURL: URL(fileURLWithPath: isOrphan ? "/nonexistent/App.app" : "/Applications/App.app"),
            appSize: appSize, leftoverURLs: [], leftoverSize: leftoverSize,
            isOrphan: isOrphan,
            lastUsedDate: lastUsedDaysAgo.map { Date().addingTimeInterval(-Double($0) * 86_400) },
            installDate: installedDaysAgo.map { Date().addingTimeInterval(-Double($0) * 86_400) },
            isRunning: false, source: .userInstalled, residues: []
        )
    }

    func testCleanGrade() {
        let summary = HealthSummaryBuilder.build(for: entry(appSize: 10_000, leftoverSize: 500))
        XCTAssertEqual(summary.grade, .clean)
    }

    func testNormalGrade() {
        let summary = HealthSummaryBuilder.build(for: entry(appSize: 10_000, leftoverSize: 3_000))
        XCTAssertEqual(summary.grade, .normal)
    }

    func testBloatedGrade() {
        let summary = HealthSummaryBuilder.build(for: entry(appSize: 10_000, leftoverSize: 8_000))
        XCTAssertEqual(summary.grade, .bloated)
    }

    func testOrphanIsAlwaysBloated() {
        let summary = HealthSummaryBuilder.build(for: entry(appSize: 0, leftoverSize: 500, isOrphan: true))
        XCTAssertEqual(summary.grade, .bloated, "孤儿条目固定臃肿（残留即全部）")
    }

    func testUnknownLastUsed() {
        let summary = HealthSummaryBuilder.build(for: entry(lastUsedDaysAgo: nil))
        XCTAssertEqual(summary.lastUsedText, "未知")
    }

    func testDaysInstalled() {
        let summary = HealthSummaryBuilder.build(for: entry(installedDaysAgo: 342))
        XCTAssertEqual(summary.daysInstalled, 342)
    }
}
```

- [ ] **Step 2: 跑测试确认失败**（同 Task 1 模式）

- [ ] **Step 3: 最小实现**

```swift
// kWise/Features/AppUninstall/HealthSummaryBuilder.swift
//
// AI 健康摘要卡 (v2.6)：可解释评级（无 AI 玄学）—— 残留/本体 比。
import Foundation
import AppCatalogCore

struct HealthSummary {
    enum Grade { case clean, normal, bloated }
    let daysInstalled: Int?
    let lastUsedText: String
    let totalSizeText: String
    let residueRatio: Double
    let grade: Grade
    let gradeText: String
}

enum HealthSummaryBuilder {

    static func build(for entry: UninstallAppEntry, now: Date = Date()) -> HealthSummary {
        let daysInstalled = entry.installDate.map {
            max(0, Calendar.current.dateComponents([.day], from: $0, to: now).day ?? 0)
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        let lastUsedText = entry.lastUsedDate.map {
            "最近使用是 " + formatter.localizedString(for: $0, relativeTo: now)
        } ?? "最近使用未知"

        let ratio = entry.appSize > 0
            ? Double(entry.leftoverSize) / Double(entry.appSize)
            : 1.0
        let grade: HealthSummary.Grade
        if entry.isOrphan || entry.appSize == 0 || ratio > 0.5 {
            grade = .bloated
        } else if ratio >= 0.1 {
            grade = .normal
        } else {
            grade = .clean
        }
        let gradeText = switch grade {
        case .clean: "干净"
        case .normal: "正常"
        case .bloated: "臃肿"
        }
        let total = FileSizeFormatter.abbreviated(from: entry.appSize + entry.leftoverSize)

        return HealthSummary(
            daysInstalled: daysInstalled,
            lastUsedText: lastUsedText,
            totalSizeText: total,
            residueRatio: ratio,
            grade: grade, gradeText: gradeText
        )
    }
}
```

> 注：`FileSizeFormatter.abbreviated` 在 CommonUtils（已链接）；`switch` 表达式需 Swift 5.9（本工程 SWIFT_VERSION 5.9 ✓）。

- [ ] **Step 4: 跑测试确认通过**

- [ ] **Step 5: Commit**

```bash
git add kWise/Features/AppUninstall/HealthSummaryBuilder.swift kWise/Tests/HealthSummaryBuilderTests.swift
git commit -m "feat(kWise): health summary builder — explainable residue grading"
```

---

### Task 4: AppUninstallDetailPanel 视图 + 双栏改造

**Files:**
- Create: `kWise/Features/AppUninstall/AppUninstallDetailPanel.swift`
- Modify: `kWise/Features/AppUninstall/AppUninstallView.swift`（双栏 + 选中条目）
- Modify: `kWise/Features/AppUninstall/AppUninstallViewModel.swift`（selectedEntryID / selectedResiduePaths / 分组惰性缓存）

**Interfaces:**
- Consumes: Task 1-3 全部类型
- Produces:
  - VM 新增：`@Published var selectedEntryID: UUID?`；`var selectedEntry: UninstallAppEntry?`；`@Published var selectedResiduePaths: [UUID: Set<String>]`（按条目隔离）；`func toggleResidue(entryID: UUID, path: String)`；`func setGroupSelection(entryID: UUID, residues: [ResidueFile], selected: Bool)`；`var hasExplicitResidueSelection: Bool`；`@Published private(set) var groupedResidues: [UUID: [ResidueGroup]]`（惰性缓存）
  - 面板视图：`struct AppUninstallDetailPanel: View`（三段：摘要卡 / 分组卡 / 动作栏）
  - AppRow 点击 → 设置 selectedEntryID（面板出现）；行内展开保留为只读快览

- [ ] **Step 1: 写失败测试（VM 部分）**

```swift
// 追加到 kWise/Tests/AppUninstallDragResetTests.swift
func testResidueSelectionIsIsolatedPerEntry() {
    let vm = AppUninstallViewModel(engine: CleanupEngine(
        persistence: PersistenceController(inMemory: true)))
    let idA = UUID()
    vm.toggleResidue(entryID: idA, path: "/a")
    let idB = UUID()
    vm.toggleResidue(entryID: idB, path: "/b")
    XCTAssertEqual(vm.selectedResiduePaths[idA], Set(["/a"]))
    XCTAssertEqual(vm.selectedResiduePaths[idB], Set(["/b"]))
}

func testHasExplicitResidueSelection() {
    let vm = AppUninstallViewModel(engine: CleanupEngine(
        persistence: PersistenceController(inMemory: true)))
    XCTAssertFalse(vm.hasExplicitResidueSelection)
    let id = UUID()
    vm.toggleResidue(entryID: id, path: "/a")
    XCTAssertTrue(vm.hasExplicitResidueSelection)
}
```

- [ ] **Step 2: VM 扩展实现**

```swift
// AppUninstallViewModel.swift 追加：
@Published var selectedEntryID: UUID?
@Published var selectedResiduePaths: [UUID: Set<String>] = [:]
@Published private(set) var groupedResidues: [UUID: [ResidueGroup]] = [:]
private(set) var groupingDegraded = false   // NLEmbedding 不可用 → 面板降级提示

var selectedEntry: UninstallAppEntry? {
    guard let selectedEntryID else { return nil }
    return entries.first { $0.id == selectedEntryID }
}

var hasExplicitResidueSelection: Bool {
    guard let id = selectedEntryID else { return false }
    return !(selectedResiduePaths[id] ?? []).isEmpty
}

func toggleResidue(entryID: UUID, path: String) {
    var set = selectedResiduePaths[entryID] ?? []
    if set.contains(path) { set.remove(path) } else { set.insert(path) }
    selectedResiduePaths[entryID] = set
}

func setGroupSelection(entryID: UUID, residues: [ResidueFile], selected: Bool) {
    let paths = Set(residues.map { $0.url.path })
    var set = selectedResiduePaths[entryID] ?? []
    if selected { set.formUnion(paths) } else { set.subtract(paths) }
    selectedResiduePaths[entryID] = set
}

/// 选中条目的分组（惰性计算：命中缓存直接返回；否则后台分组 + 发布）。
func groupedResiduesForSelectedEntry() -> [ResidueGroup]? {
    guard let entry = selectedEntry else { return nil }
    if let cached = groupedResidues[entry.id] { return cached }
    Task {
        let groups = await ResidueGroupingEngine.group(entry.residues)
        await MainActor.run { self.groupedResidues[entry.id] = groups }
    }
    return nil
}
```

> `ResidueGroupingEngine.group(_:)` 需增加接受 `[ResidueFile]` 的重载（Task 2 的版本接受 ResidueFile 数组，签名一致 ✓）。

- [ ] **Step 3: 面板视图**（`AppUninstallDetailPanel.swift`，~200 行 SwiftUI）

- 三段：`HealthSummaryCard`（HealthSummaryBuilder 输出 + 评级胶囊）→ `ResidueGroupCard` 列表（ResidueGroupKind.icon/title + 组大小 + 组勾选级联 + 组内残留行带 ResidueExplainer 解释）→ 动作栏（卸载 / App Reset / 备份说明）。
- NLEmbedding 降级提示行（groupingDegraded）；分组计算 >50ms → 「分析中…」骨架。
- 组勾选 → `viewModel.setGroupSelection(entryID:residues:selected:)`；残留行勾选 → `toggleResidue`。
- C-1 路径规则同 DuplicateView（friendly 显示、raw 仅 tooltip）。

- [ ] **Step 4: AppUninstallView 双栏改造**

- `appList` 改 `HStack`：左 260pt 列表 + Divider + 右 `AppUninstallDetailPanel`。
- `AppRow` 点击 → `viewModel.selectedEntryID = entry.id`（选中条目行 brandPrimary 0.15 背景）。

- [ ] **Step 5: 跑测试 + 构建**

- [ ] **Step 6: Commit**

```bash
git add kWise/Features/AppUninstall kWise/Tests
git commit -m "feat(kWise): uninstall detail panel — health card, AI groups, explanations"
```

---

### Task 5: 勾选语义接线 + 回归

**Files:**
- Modify: `kWise/Features/AppUninstall/AppUninstallViewModel.swift`（uninstallSelected 语义）
- Test: `kWise/Tests/AppUninstallDragResetTests.swift` 追加

**Interfaces:**
- Consumes: Task 4 的 `selectedResiduePaths` / `hasExplicitResidueSelection`
- Produces: 卸载提交语义（spec §7 消歧规则）

- [ ] **Step 1: 写失败测试**

```swift
// 追加到 AppUninstallDragResetTests.swift
@MainActor
final class UninstallSelectionSemanticsTests: XCTestCase {

    func testUninstallHonorsExplicitResidueSelection() async throws {
        // r1/r2 两个残留；面板显式只勾 r1 → 卸载后 r1 进废纸篓，r2 仍在。
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let r1 = dir.appendingPathComponent("r1.plist")
        let r2 = dir.appendingPathComponent("r2.plist")
        try Data("1".utf8).write(to: r1)
        try Data("2".utf8).write(to: r2)
        defer { try? FileManager.default.removeItem(at: dir) }

        let entry = UninstallAppEntry(
            appName: "App", bundleID: "com.test.sel",
            appURL: URL(fileURLWithPath: "/Applications/App.app"),
            appSize: 100, leftoverURLs: [r1, r2], leftoverSize: 2,
            lastUsedDate: nil, installDate: nil, isRunning: false,
            source: .userInstalled,
            residues: [
                ResidueFile(url: r1, type: .preferences, sizeBytes: 1, confidence: 0.9),
                ResidueFile(url: r2, type: .caches, sizeBytes: 1, confidence: 0.9),
            ]
        )

        let vm = AppUninstallViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true)))
        vm.entries = [entry]
        vm.selectedEntryID = entry.id
        vm.toggleResidue(entryID: entry.id, path: r1.path)   // 显式只勾 r1

        _ = await vm.uninstallSelected()
        XCTAssertFalse(FileManager.default.fileExists(atPath: r1.path), "显式勾选的 r1 应被清理")
        XCTAssertTrue(FileManager.default.fileExists(atPath: r2.path), "未勾选的 r2 必须保留")
    }
}
```

- [ ] **Step 2: 实现 uninstallSelected 语义**

```swift
// uninstallSelected() 内，targets 构造改为：
for entry in targets {
    let explicit = selectedResiduePaths[entry.id]
    let residueURLs: [URL]
    if let explicit, !explicit.isEmpty {
        residueURLs = entry.leftoverURLs.filter { explicit.contains($0.path) }
    } else {
        residueURLs = entry.leftoverURLs
    }
    let urls = ([entry.appURL] + residueURLs).filter { FileManager.default.fileExists(atPath: $0.path) }
    ... // 现有 CleanupTarget 构造与 cleanup 调用不变
}
```

- [ ] **Step 3: 跑测试确认通过**

- [ ] **Step 4: Commit**

```bash
git add kWise/Features/AppUninstall/AppUninstallViewModel.swift kWise/Tests/AppUninstallDragResetTests.swift
git commit -m "feat(kWise): uninstall honors explicit residue selection with whole-app fallback"
```

---

### Task 6: 收尾 — 性能守卫 + 降级提示 + 审计

**Files:**
- Modify: `kWise/Features/AppUninstall/AppUninstallDetailPanel.swift`（降级提示行 + 「分析中…」骨架）
- Modify: `kWise/Tests/AssistantAndCopyAuditTests.swift`（v2.6 文案审计扩展）
- Modify: `kWise/Features/StartupItems/StartupItemsViewModel.swift`（inferUsage 迁移至 `ResidueExplainer.ownerHint` 共享 API，删本地实现）

**Interfaces:**
- Consumes: Task 1-4 全部
- Produces: 共享 `ResidueExplainer.ownerHint(forLabel:mappings:)`（Task 1 已实现——本任务把 StartupItemsViewModel.inferUsage 的调用点切过去并删旧实现）

- [ ] **Step 1: 降级提示 + 骨架**（面板顶部一行「语义分组不可用…」当 NLEmbedding 为 nil；分组计算放后台 Task，>50ms 显示 ProgressView 骨架行）

- [ ] **Step 2: inferUsage 迁移**（StartupItemsViewModel 调 `ResidueExplainer.ownerHint(forLabel:mappings:)`，删本地 inferUsage；行为不变，现有启动项测试不破）

- [ ] **Step 3: 审计扩展**（AssistantAndCopyAuditTests 文件列表加 ResidueGroupingEngine/ResidueExplainer/AppUninstallDetailPanel；C-1 断言面板内 raw path 仅 tooltip）

- [ ] **Step 4: 全量验证**

```bash
bash kWise/scripts/generate.sh
xcodebuild -workspace KraftlyWorkspace.xcworkspace -scheme kWise build-for-testing CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|TEST BUILD"
```

- [ ] **Step 5: Commit + push**

```bash
git add kWise
git commit -m "feat(kWise): uninstall AI round — degradation hints, shared ownerHint, copy audit"
git push origin main
```

---

## 自审结论（已核对 spec）

- spec §3 类目/两遍算法 → Task 2；§4 摘要 → Task 3；§5 解释器 → Task 1；§6 ownerHint 共享 → Task 1 + Task 6 Step 2；§7 面板 → Task 4；§8 勾选语义 → Task 4 Step 2 + Task 5；§9 测试 → 各任务内嵌；§10 验收 → 实施完成后用户手验。
- 类型一致性：`ResidueGroup.kind/residues`、`selectedResiduePaths: [UUID: Set<String>]`、`ResidueExplainer.ownerHint(forLabel:mappings:)` 各任务引用一致。
- 已知风险：NLEmbedding zh 词向量在 macOS 13 的可用性以运行时 nil 判定兜底（Task 2 实现）；本计划不涉及私有 API。
