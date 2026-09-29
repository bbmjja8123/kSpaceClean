# Klaris P1 — 信任契约 + 解剖视图 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 P0 的归因引擎装进看得见的 UX——解剖视图上首屏英雄位、清理预演（Rehearsal）两段式确认、拒答清单进主流程、L1 句向量接入（.probable 档）、旧资产清理（死代码/聊天框/双引擎/配额→买断）。

**Architecture:** 新增 `.anatomy` 导航位替换 `.smartCare` 的 rail 首位（SmartCare 收缩为「安全快捷回收」次级页，深链兼容保留 case）；预演插入 `CleanupViewModel.cleanupNow` 的 targets 构造与 `engine.cleanup` 之间（两入口共享）；L1 为 service 层升级（engine 不动，refused 项经理向量近邻升级为 `.probable`，仍在拒答区渲染「可能」徽章）；配额从「1GB 月度截断」改为「未购买即拒绝」，`CleanupEvent.quotaExhausted` 字段名保留（sink 契约不横切）。

**Tech Stack:** SwiftUI、NaturalLanguage（NLEmbedding sentence embedding）、StoreKit 2（非消耗型买断）、XCTest。

**Spec:** `docs/superpowers/specs/2026-09-27-klaris-attribution-design.md`（§2.2 定价 / §3.1 停止清单 / §4.5 AI 分层 / §5 信任契约 / §10 P1 行）

## Global Constraints

- 最低系统 macOS 13.0；零网络（全部新代码禁 URLSession；audit 测试守卫）
- **永不自动删除**：预演是执行前的最后一道人签；预演清单与实际执行必须逐项一致（spec §10 P1 验收）
- 定价：免费=扫描+归因可视化+拒答清单；**回收执行=买断 $9.90 门控**；禁止订阅话术与「AI 智能分类/CoreML」假卖点（spec §2.2）
- 每个新本地化 key 三语（en/zh-Hans/ja）齐全
- 恐吓禁语（AttributionCopyAuditTests + NewCopyAuditTests 两层）对全部新文案生效
- 测试基线全绿：`xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWise`；**环境 wedge 已知**——实施时用 build-for-testing + `-only-testing:` 分批，最终任务跑一次全量
- 提交：`scripts/commit-app.sh kWise`（+显式 `git add CLAUDE.md` 当任务触碰它）
- P0 既有契约继续有效：证据链恒 4 元（空参数 lastModified 隐藏渲染）、`snapshots == nil` 语义、`refused` 双源以 `ruleID == nil` 区分、`AttributionRuleCorpus` schemaVersion 守卫
- 探勘锚点（实施者以内容定位为准，行号可能漂移 ±5）：
  - `kWise/App/AppState.swift`：`NavigationItem` 枚举（:35 区）、`railItems`（:63-65）、`isToolboxTool`（:68-77）、`iconName`（:79）/`tooltip`（:103）
  - `kWise/App/RootView.swift`：`mainContent` switch（:180-225）、`.onAppear` 晚绑定链（:129-167，smartCare attach/useEngine/attribution rebind 都在这）、Paywall sheet（:115-117）
  - `kWise/App/AppCoordinator.swift`：`case "smartcare"` 深链（:41-43）、`presentPaywall()`（:125）
  - `kWise/Features/Cleanup/CleanupViewModel.swift`：`cleanupNow(sizes:)`（:75-115）
  - `kWise/Features/Cleanup/CleanupEngine.swift`：quota 门（:134/:146/:244/:416）、`cleanup(targets:config:)`（:374-377）
  - `kWise/App/AppGraph.swift`：quotaChecker（:28/:124-128）、FreeQuotaStore（:129）、QuotaRecordSink（:133）、engine 注入（:139-143）、`assistantVM()`（:102-104）
  - `kWise/Features/Store/StoreManager.swift`：`productID`（:8）、`isSubscribed`（:5）、`purchase()`（:24）
  - 测试硬闸：AppStateTests `allCases.count == 19`（:59）+ railItems 精确断言（:63-66）+ tooltip 遍历（:73）；AssistantAndCopyAuditTests `v2FeatureFiles` 文件存在性（:69-87）

## Controller Rulings（绑定全计划）

- **R1 首屏**：rail = `[.anatomy, .scan, .tools, .cleanup, .history, .settings]`；`.smartCare` case 保留（深链/菜单栏兼容）但视图收缩为 `SafeQuickCleanView`（保留全部状态机**含 scopeGrantCard 授权卡**——勘察建议删它，裁定不删：无授权时快捷回收必须诚实降级）；`AppState.navigation` 初始值 → `.anatomy`
- **R2 L1.5 CreateML 延后 P2**：离线训练工具链风险大；L1 句向量已覆盖诚实降级链（L0→L1→拒答）。`AttributionSource.createML` 枚举保留不接
- **R3 L1 路由**：engine 输出契约不变（.certain/.refused）；service 层把 refused 项经理向量升级为 `.probable`（confidence/source/cause 升级），**仍渲染在拒答区**、带「可能」徽章——推测不等于建议。M4 precondition 保留在 engine 输出检查处
- **R4 Intents 退役旧语义**：`CleanCacheIntent` 的 `Set<Int>` subCategoryID 数字语义废除，改为「推荐项清理」（复用 SmartCareOrchestrator 的推荐挑选逻辑抽公共 helper）
- **R5 买断门控语义**：`CleanupQuotaChecker` 已购→nil（不限）、未购→0（全部 skippedForQuota→paywall）；`CleanupEvent.quotaExhausted` 字段名不改（sink 契约不横切），语义变为「未购拦截」
- **R6 P0 验证面退役**：`AttributionPreviewView` 被 AnatomyView 整体替换（删除文件+对应测试用例），规则可查页保留
- **R7 Assistant**：删聊天框（AssistantView/Toolbox 卡/`.assistant` case/AppGraph.assistantVM）；保留 matcher+builder；新形态=DetailPanelView 内嵌建议问题问答

## File Structure

```
Create:
  kWise/Features/Attribution/SemanticAttribution.swift        # L1 句向量 provider + 词元化
  kWise/Features/Cleanup/CleanupRehearsal.swift               # RehearsalItem + 纯函数 builder
  kWise/Features/Cleanup/CleanupRehearsalSheet.swift          # 预演 sheet 视图
  kWise/Features/Attribution/AnatomyView.swift                # 新首屏（VM + View）
  kWise/Features/SmartScan/IntentScanAdapter.swift            # Intents → ScanOrchestrator 共享适配
  kWise/Configuration/Klaris.storekit                         # 买断产品本地测试配置（若无既有 .storekit）
Delete:
  kWise/Features/Attribution/AttributionPreviewView.swift     # 被 AnatomyView 替换（R6）
  kWise/Features/Assistant/AssistantView.swift                # 聊天框（R7）
  kWise/Features/SmartScan/ScanEngine.swift                   # LegacyScanEngine
  kWise/Features/SmartScan/ScanViewModel.swift
  kWise/Features/SmartScan/ScanRule.swift
  kWise/Features/SmartScan/AppScanRules.swift
  kWise/Features/SmartScan/FilterEvaluator.swift
  kWise/Features/SmartScan/SpecializedScanners.swift
  kWise/Features/AIClassifier/AIClassifier.swift              # 死代码（R7/§3.1）
  kWise/Features/AIClassifier/RuleClassifier.swift            # 随旧引擎退役
  kWise/Tests/RuleClassifierTests.swift
  kWise/Tests/ScanEngineIntegrationTests.swift                # 旧引擎集成测试
  kWise/Tests/AttributionViewTests.swift 中 preview 用例      # R6（文件保留，删用例）
Modify:
  AppState / RootView / AppCoordinator / AppGraph / ToolboxView
  CleanupViewModel / ScanResultsView / CleanupContentView / SmartCareHeroView
  StoreManager / StoreProtocol / CleanupQuota / PaywallView / AppGraph quota 装配
  DetailPanelView（节点问答嵌入）
  Intents/ScanIntent · CleanCacheIntent · ShowLargeFilesIntent
  Resources/Localizable.xcstrings（每任务的新 key ×3 语）
  CLAUDE.md（T10）
Test:
  新/改：SemanticAttributionTests · CleanupRehearsalTests · CleanupViewModelRehearsalTests ·
        AnatomyViewTests · StoreManagerTests · CleanupEngineTests(quota 路径) · AppCoordinatorTests ·
        IntentScanAdapterTests · AssistantAndCopyAuditTests(清单同步) · AppStateTests · ToolTabTests
```

---

### Task 1: 导航层 — `.anatomy` 进 rail，`.smartCare` 退居深链

**Files:**
- Modify: `kWise/App/AppState.swift`（NavigationItem 枚举 / railItems / iconName / tooltip / 初始 navigation）
- Modify: `kWise/App/AppCoordinator.swift:41-43`（smartcare 深链 → `.anatomy`）
- Modify: `kWise/Resources/Localizable.xcstrings`（`nav.anatomy` ×3 语）
- Modify: `kWise/Tests/AppStateTests.swift:59,63-66,73`、`kWise/Tests/AppCoordinatorTests.swift`

**Interfaces:**
- Produces: `NavigationItem.anatomy`（rail 首位）；railItems `[.anatomy, .scan, .tools, .cleanup, .history, .settings]`；AppCoordinator `"smartcare"` host → `navigate(to: .anatomy)`；`nav.anatomy` 本地化 key
- 本任务不改 `.smartCare` 的视图（T6 做）——mainContent 的 `case .smartCare` 保持渲染 SmartCareHeroView，只是它不再是 rail 项/初始页

- [ ] **Step 1: 写失败测试** — `kWise/Tests/AppStateTests.swift`：改 `allCases.count` 断言 19→20；`test_NavigationItem_railItems` 期望数组首项改 `.anatomy`；新增：

```swift
func testAnatomyIsRailHeadAndSmartCareRetired() {
    XCTAssertEqual(NavigationItem.railItems.first, .anatomy)
    XCTAssertFalse(NavigationItem.railItems.contains(.smartCare),
                   "SmartCare 降级后不再占 rail 位（spec §3.1）")
    XCTAssertEqual(NavigationItem.railItems.count, 6)
}
```

`kWise/Tests/AppCoordinatorTests.swift` 新增：

```swift
func testSmartCareDeepLinkOpensAnatomy() {
    let coordinator = AppCoordinator()
    coordinator.handle(url: URL(string: "klaris://smartcare")!)
    XCTAssertEqual(coordinator.state.navigation, .anatomy,
                   "SmartCare 降级：深链与 Widget 按钮应落在解剖首屏（R1）")
}
```

（AppCoordinator 的 state/navigation 暴露方式以现有 AppCoordinatorTests 的 `testScanDeepLink` 写法为准——先读该文件，沿用其访问路径。）

- [ ] **Step 2: 跑测试确认失败** — `xcodebuild test-without-building ... -only-testing:kWiseTests/AppStateTests -only-testing:kWiseTests/AppCoordinatorTests`（先 build-for-testing）；预期编译错误 `'.anatomy' not found`。

- [ ] **Step 3: 实现**
1. AppState 枚举加 `case anatomy = "anatomy"`（放 `.smartCare` 声明之前）；`railItems` 改 `[.anatomy, .scan, .tools, .cleanup, .history, .settings]`；`AppState.navigation` 初始值（:6）改 `.anatomy`；`iconName` 加 `case .anatomy: return "scale.3d"`；`tooltip` 加 `case .anatomy: return String(localized: "nav.anatomy")`
2. `nav.anatomy` 三语（幂等合并脚本模式，同 P0 Task 4）：
   - zh-Hans: `空间解剖` ｜ en: `Storage Anatomy` ｜ ja: `ストレージ解析`
3. AppCoordinator `case "smartcare": navigate(to: .smartCare)` → `navigate(to: .anatomy)`（旁注：Widget 一键清理落在首屏的快捷回收入口）
4. `cd kWise && xcodegen generate`（新增 key 不需要，但保险）

- [ ] **Step 4: 跑测试确认通过** — AppStateTests + AppCoordinatorTests + ToolTabTests 全绿。

- [ ] **Step 5: 提交** — `scripts/commit-app.sh kWise && git commit -m "feat(kWise): anatomy becomes rail head — smartCare retired to deep link (P1 T1)"`

---

### Task 2: L1 语义归因层（句向量 → `.probable`）

**Files:**
- Create: `kWise/Features/Attribution/SemanticAttribution.swift`
- Modify: `kWise/Features/Attribution/AttributionService.swift`（init 加 provider；refused 升级管道）
- Modify: `kWise/Resources/Localizable.xcstrings`（`attr.confidence.probable` ×3 语）
- Test: `kWise/Tests/SemanticAttributionTests.swift`（新）+ `kWise/Tests/AttributionServiceTests.swift`（追加）

**Interfaces:**
- Consumes: Task 1 无依赖；P0 的 `AttributionService` / `SpaceAttribution` / `AttributionCause` / `AttributionSource.nlEmbedding` / `AttributionConfidence.probable`（枚举 case 已存在，P0 未接）
- Produces:
  - `protocol SemanticAttributionProviding: Sendable { func probableCause(for path: String) -> AttributionCause? }`
  - `struct SentenceEmbeddingAttributionProvider: SemanticAttributionProviding { init(); static let maxCosineDistance: Double }`（阈值 0.85，真机可调）
  - `AttributionService.init(engine:volumeReader:rootURL:volumeUsedBytesProvider:semanticProvider:)`（默认 `nil`；`live()` 传 `SentenceEmbeddingAttributionProvider()`）
  - 语义：engine 输出的 `.refused` 项经理升级 → `SpaceAttribution(confidence: .probable, source: .nlEmbedding, cause: <推测>, owner: .unknown, reclaim: .uncertain)`，**仍进 refused 列表**（R3：推测不等于建议）；provider 返回 nil → 保持原 refused
  - M4 precondition 保留：只对 **engine 直接输出** 检查 `confidence != .probable`（service 自己产生的 .probable 在检查之后）

- [ ] **Step 1: 写失败测试** — `kWise/Tests/SemanticAttributionTests.swift`

```swift
import XCTest
import NaturalLanguage
@testable import kWise

final class SemanticAttributionTests: XCTestCase {
    // MARK: - 纯函数：路径词元化

    func testPathTokensStripsNoiseAndShortFragments() {
        let tokens = SentenceEmbeddingAttributionProvider.pathTokens(
            "/Users/x/Library/Containers/com.tencent.xinWeChat/Data/Files/a1")
        XCTAssertFalse(tokens.contains("users"))
        XCTAssertFalse(tokens.contains("library"))
        XCTAssertTrue(tokens.contains("tencent"), "bundle 反域名段保留")
        XCTAssertTrue(tokens.contains("xinwechat"))
        XCTAssertFalse(tokens.contains("a"), "单字符词元丢弃")
    }

    func testMaxCosineDistanceIsCalibratable() {
        XCTAssertEqual(SentenceEmbeddingAttributionProvider.maxCosineDistance, 0.85)
    }

    // MARK: - 真实 provider（环境可用时）

    func testProviderReturnsNilOrCauseNeverCrashes() throws {
        guard NLEmbedding.sentenceEmbedding(for: .english) != nil else {
            throw XCTSkip("句向量资产不可用（CI/精简系统）——mock 路径已覆盖逻辑")
        }
        let provider = SentenceEmbeddingAttributionProvider()
        // 两种结果都合法：nil（低于阈值=拒答）或某个 cause——红线是绝不 crash。
        _ = provider.probableCause(for: "/Users/x/Library/Caches/com.apple.Safari/Cache.db")
    }

    // MARK: - Service 层升级管道（mock 驱动）

    private struct StubProvider: SemanticAttributionProviding {
        let cause: AttributionCause?
        func probableCause(for path: String) -> AttributionCause? { cause }
    }

    private func service(provider: SemanticAttributionProviding?) -> AttributionService {
        let corpus = AttributionRuleCorpus(schemaVersion: 1, rules: [])
        return AttributionService(
            engine: AttributionRuleEngine(corpus: corpus, homeDirectory: "/Users/t"),
            volumeReader: nil,
            rootURL: URL(fileURLWithPath: "/Users/t"),
            volumeUsedBytesProvider: { nil },
            semanticProvider: provider)
    }

    private func category(paths: [(String, Int64)]) -> [ScanCategory] {
        let results = paths.map {
            ScanResult(url: URL(fileURLWithPath: $0.0), path: $0.0, title: "x",
                       fileSize: $0.1, cleanType: .cache)
        }
        let action = ScanAction(actionID: "a", actionType: .cache, title: "a", results: results)
        let sub = ScanSubCategory(subCategoryID: "s", title: "s", actions: [action])
        return [ScanCategory(categoryID: "c", title: "c", subItems: [sub])]
    }

    func testRefusedUpgradesToProbableWhenProviderHits() async {
        let report = await service(provider: StubProvider(cause: .chatFiles))
            .attribute(categories: category(paths: [("/Users/t/mystery/chat.bin", 900_000_000)]))
        let refused = report.refused
        XCTAssertEqual(refused.count, 1)
        let item = refused[0]
        XCTAssertEqual(item.confidence, .probable, "provider 命中 → 升级为推测")
        XCTAssertEqual(item.source, .nlEmbedding)
        XCTAssertEqual(item.cause, .chatFiles)
        XCTAssertEqual(item.reclaim, .uncertain, "推测不改可回收性判定")
    }

    func testRefusedStaysRefusedWhenProviderMisses() async {
        let report = await service(provider: StubProvider(cause: nil))
            .attribute(categories: category(paths: [("/Users/t/mystery.bin", 900_000_000)]))
        XCTAssertEqual(report.refused[0].confidence, .refused)
        XCTAssertEqual(report.refused[0].source, .unattributed)
    }

    func testMatchedItemsNeverRoutedThroughProvider() async {
        // L0 命中的项不吃 L1——来源标注必须保持 .rule。
        let corpus = AttributionRuleCorpus(schemaVersion: 1, rules: [AttributionRule(
            id: "caches.app-generic", match: AttributionRuleMatch(pathGlob: "~/Library/Caches/**"),
            owner: .bundleDir, cause: .cache, reclaim: .recycles(expectedDays: 3),
            notesKey: "attr.notes.caches.app-generic")])
        let service = AttributionService(
            engine: AttributionRuleEngine(corpus: corpus, homeDirectory: "/Users/t"),
            volumeReader: nil, rootURL: URL(fileURLWithPath: "/Users/t"),
            volumeUsedBytesProvider: { nil },
            semanticProvider: StubProvider(cause: .aiModel))
        let report = await service.attribute(categories: category(paths: [
            ("/Users/t/Library/Caches/com.apple.Safari/x", 5_000_000)]))
        XCTAssertEqual(report.items[0].source, .rule)
        XCTAssertEqual(report.items[0].confidence, .certain)
    }
}
```

- [ ] **Step 2: 跑测试确认失败** — `-only-testing:kWiseTests/SemanticAttributionTests`；预期编译错误 `cannot find 'SentenceEmbeddingAttributionProvider'`。

- [ ] **Step 3: 实现** — `kWise/Features/Attribution/SemanticAttribution.swift`

```swift
// kWise/Features/Attribution/SemanticAttribution.swift
//
// L1 语义归因（spec §4.5 第二层）。红线：
// - 只在 L0 未命中后调用；命中阈值以下返回 nil（调用方保持 refused）——绝不猜。
// - 推测产物 confidence = .probable / source = .nlEmbedding / reclaim 不变
//   （.uncertain）——推测不产生清理建议。
// - 样本短语表与语料规则的 cause 分类一一呼应；全英文（句向量英文资产最全），
//   路径先词元化（去框架噪音词）再拼回空格句。
import Foundation
import NaturalLanguage

public protocol SemanticAttributionProviding: Sendable {
    func probableCause(for path: String) -> AttributionCause?
}

public struct SentenceEmbeddingAttributionProvider: SemanticAttributionProviding {

    /// 原因 → 样本短语（英文，路径词元域）。阈值与样本表是真机校准点（P0 验收）。
    static let samplePhrases: [AttributionCause: [String]] = [
        .cache: ["cache temporary files app cache", "cached data browser cache"],
        .developerCache: ["developer build intermediates derived data xcode", "simulator caches device support"],
        .chatFiles: ["chat message attachments wechat files", "instant messaging received files"],
        .aiModel: ["machine learning model weights local ai models"],
        .log: ["log files diagnostics crash reports"],
        .mailAttachment: ["mail attachments email files"],
        .iOSBackup: ["iphone ipad device backup files mobile sync"],
        .renderCache: ["video render files media cache editing projects"],
        .download: ["downloaded installer files downloads"],
        .archive: ["compressed archive zip disk image"],
        .backup: ["backup snapshots system reserved"],
        .containerData: ["app container application support data"],
        .snapshot: ["time machine local snapshot"],
        .unknown: [],
    ]

    /// cosine 距离阈值（0=同向，2=反向）。真实机器上用语料路径校准。
    public static let maxCosineDistance = 0.85

    /// 词元化时剔除的框架噪音词——每条路径都有，无判别力。
    static let noiseTokens: Set<String> = [
        "users", "library", "containers", "data", "application",
        "support", "group", "private", "var", "tmp",
    ]

    public init() {}

    public func probableCause(for path: String) -> AttributionCause? {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else { return nil }
        let tokens = Self.pathTokens(path)
        guard !tokens.isEmpty else { return nil }
        let sentence = tokens.joined(separator: " ")
        var best: (cause: AttributionCause, distance: NLDistance)?
        for (cause, phrases) in Self.samplePhrases where !phrases.isEmpty {
            for phrase in phrases {
                let distance = embedding.distance(between: sentence, and: phrase,
                                                  distanceType: .cosine)
                if best == nil || distance < best!.distance {
                    best = (cause, distance)
                }
            }
        }
        guard let best, best.distance <= Self.maxCosineDistance else { return nil }
        return best.cause
    }

    /// 路径 → 词元：非字母数字折成空格、丢单字符与噪音词。
    static func pathTokens(_ path: String) -> [String] {
        let flattened = path.lowercased().map { char -> Character in
            (char.isLetter || char.isNumber) ? char : " "
        }.reduce(into: "") { $0.append($1) }
        return flattened
            .split(separator: "")
            .map(String.init)
    }
}
```

> ⚠️ 上面的 `pathTokens` reduce 写法是**故意的坑位检查**：正确实现应为
> `flattened.split(separator: " ").map(String.init).filter { $0.count > 1 && !Self.noiseTokens.contains($0) }`。
> 若照抄上面的 split(separator: "") 会得到逐字符数组——测试 `testPathTokensStripsNoiseAndShortFragments`
> 会失败，这就是 RED 的预期失败点。按下述修正后转绿。

修正后的 `pathTokens` 尾段：

```swift
        return flattened
            .split(separator: " ")
            .map(String.init)
            .filter { $0.count > 1 && !Self.noiseTokens.contains($0) }
```

- [ ] **Step 4: Service 层接入** — `AttributionService.swift`：
1. 加存储属性 `public let semanticProvider: SemanticAttributionProviding?`，init 增参 `semanticProvider: SemanticAttributionProviding? = nil`（放 `volumeUsedBytesProvider` 之后，默认参数保证既有调用点编译）。
2. `attribute(categories:)` 中 engine 输出循环**之后**、组装 report 之前加升级管道：

```swift
        // L1 语义升级（spec §4.5）：仅对 L0 拒答项；推测不改 reclaim、不进 items。
        if let semanticProvider {
            refused = refused.map { item in
                guard item.confidence == .refused,
                      let path = item.paths.first,
                      let cause = semanticProvider.probableCause(for: path)
                else { return item }
                return SpaceAttribution(
                    scope: item.scope, paths: item.paths, bytes: item.bytes,
                    owner: item.owner, cause: cause, reclaim: item.reclaim,
                    confidence: .probable, source: .nlEmbedding, ruleID: nil,
                    evidence: item.evidence, lastModified: item.lastModified)
            }
        }
```

（`refused` 需从 `let` 改 `var`；`items` 分支不受影响。）
3. `live()` 传 `semanticProvider: SentenceEmbeddingAttributionProvider()`。

- [ ] **Step 5: 追加 confidence 徽章 key** — `attr.confidence.probable`：zh-Hans `推测（本地模型）` ｜ en `Probable (on-device model)` ｜ ja `推測（端末内モデル）`。幂等合并，跑 `LocalizationCompletenessTests` 确认绿。

- [ ] **Step 6: 跑测试确认通过** — SemanticAttributionTests 6/6 + AttributionServiceTests 既有 5/5 仍绿（默认参 provider=nil 不改变 P0 行为）。

- [ ] **Step 7: 提交** — `scripts/commit-app.sh kWise && git commit -m "feat(kWise): L1 semantic attribution — sentence-embedding probable tier in service pipeline (P1 T2)"`

---

### Task 3: 预演数据层 `CleanupRehearsal.swift`（纯函数）

**Files:**
- Create: `kWise/Features/Cleanup/CleanupRehearsal.swift`
- Test: `kWise/Tests/CleanupRehearsalTests.swift`

**Interfaces:**
- Consumes: `CleanupTarget`（CleanupTypes.swift：id/url/size/risk/bundleID/categoryID）；P0 `SpaceAttribution`（paths: [String]）
- Produces:
  - `struct RehearsalItem: Identifiable, Equatable, Sendable { let id: UUID; let target: CleanupTarget; let attribution: SpaceAttribution? }`
  - `enum CleanupRehearsal { static func build(targets: [CleanupTarget], attributions: [SpaceAttribution]) -> [RehearsalItem] }`
  - **验收契约（spec §10 P1）**：输出与 targets **1:1 同序**——预演清单 == 实际执行清单；归因按 `url.path == attribution.paths.first` 匹配，匹配不到 → `attribution: nil`（视图显示诚实「无归因信息」行）

- [ ] **Step 1: 写失败测试** — `kWise/Tests/CleanupRehearsalTests.swift`

```swift
import XCTest
@testable import kWise

final class CleanupRehearsalTests: XCTestCase {
    private func target(_ path: String, size: Int64 = 100) -> CleanupTarget {
        CleanupTarget(url: URL(fileURLWithPath: path), size: size, risk: .recommended)
    }

    private func attribution(path: String, cause: AttributionCause = .cache) -> SpaceAttribution {
        SpaceAttribution(scope: .fileTree, paths: [path], bytes: 100,
                         owner: .app(bundleID: "com.x", appName: nil), cause: cause,
                         reclaim: .recycles(expectedDays: 3), confidence: .certain,
                         source: .rule, ruleID: "caches.app-generic", evidence: [], lastModified: nil)
    }

    func testOneToOneSameOrderContract() {
        let targets = [target("/a"), target("/b"), target("/c")]
        let items = CleanupRehearsal.build(targets: targets, attributions: [])
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.map(\.target.url.path), ["/a", "/b", "/c"],
                       "预演与执行必须逐项一致（spec §10 P1 验收）")
        XCTAssertTrue(items.allSatisfy { $0.attribution == nil })
    }

    func testAttributionJoinedByPath() {
        let targets = [target("/Users/t/Library/Caches/Safari/x")]
        let items = CleanupRehearsal.build(
            targets: targets, attributions: [attribution(path: "/Users/t/Library/Caches/Safari/x")])
        XCTAssertEqual(items[0].attribution?.ruleID, "caches.app-generic")
        XCTAssertEqual(items[0].attribution?.cause, .cache)
    }

    func testRefusedAttributionStillShownHonestly() {
        // 拒答项被用户手动勾选时，预演必须如实显示「这是推测/不敢判」而不是装作有依据。
        let refused = SpaceAttribution(scope: .fileTree, paths: ["/m"], bytes: 1,
                                       owner: .unknown, cause: .unknown,
                                       reclaim: .uncertain, confidence: .refused,
                                       source: .unattributed, ruleID: nil,
                                       evidence: [], lastModified: nil)
        let items = CleanupRehearsal.build(targets: [target("/m")], attributions: [refused])
        XCTAssertEqual(items[0].attribution?.confidence, .refused)
    }
}
```

- [ ] **Step 2: 跑测试确认失败** — `-only-testing:kWiseTests/CleanupRehearsalTests`；预期编译错误。

- [ ] **Step 3: 实现** — `kWise/Features/Cleanup/CleanupRehearsal.swift`

```swift
// kWise/Features/Cleanup/CleanupRehearsal.swift
//
// 预演数据层（spec §5 Rehearsal）。红线：与执行 1:1 同序——预演撒谎 = 信任崩塌
// （P0 评审原话）。归因信息是「为什么可以回收」的展示层，缺席时诚实留空。
import Foundation

public struct RehearsalItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let target: CleanupTarget
    /// 该项的归因（可能为 nil——展示层必须诚实渲染「无归因信息」）。
    public let attribution: SpaceAttribution?

    public init(id: UUID = UUID(), target: CleanupTarget, attribution: SpaceAttribution?) {
        self.id = id
        self.target = target
        self.attribution = attribution
    }
}

public enum CleanupRehearsal {
    /// targets 与输出 1:1 同序；归因按路径首段匹配。
    public static func build(targets: [CleanupTarget],
                             attributions: [SpaceAttribution]) -> [RehearsalItem] {
        let byPath = Dictionary(attributions.map { ($0.paths.first ?? "", $0) },
                                uniquingKeysWith: { first, _ in first })
        return targets.map { target in
            RehearsalItem(target: target, attribution: byPath[target.url.path])
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过**；**Step 5: 提交** — `scripts/commit-app.sh kWise && git commit -m "feat(kWise): cleanup rehearsal data layer — 1:1 order contract with execution (P1 T3)"`

---

### Task 4: 预演接入执行链（CleanupViewModel 两段式 + RehearsalSheet）

**Files:**
- Modify: `kWise/Features/Cleanup/CleanupViewModel.swift:75-115`（cleanupNow 拆两段）
- Create: `kWise/Features/Cleanup/CleanupRehearsalSheet.swift`
- Modify: `kWise/Features/SmartScan/Views/ScanResultsView.swift:377-494`（CleanupConfirmSheet 确认按钮 → 弹预演）
- Modify: `kWise/Features/Cleanup/Views/CleanupContentView.swift:40-68`（confirmationDialog 确认 → 同样弹预演）
- Modify: `kWise/App/RootView.swift` `.onAppear`（attributionLookup 晚绑定）
- Modify: `kWise/Resources/Localizable.xcstrings`（预演 key ×3 语，见 Step 4）
- Test: `kWise/Tests/CleanupViewModelRehearsalTests.swift`（新）

**Interfaces:**
- Consumes: T3 `CleanupRehearsal.build` / `RehearsalItem`；P0 `AttributionReport.items`
- Produces（T5 解剖页复用）:
  - `CleanupViewModel.attributionLookup: (() -> [SpaceAttribution])?`（RootView 晚绑定）
  - `func makeRehearsal(sizes: [URL: Int64]?) async -> [RehearsalItem]`（构造并暂存 targets）
  - `func executeConfirmedCleanup(sizes: [URL: Int64]?) async`（用暂存 targets 走原 cleanupNow 逻辑）
  - `@Published private(set) var pendingTargets: [CleanupTarget]`
- 行号漂移声明：CleanupViewModel.swift 内部实现以内容定位（搜 `func cleanupNow`）

- [ ] **Step 1: 写失败测试** — `kWise/Tests/CleanupViewModelRehearsalTests.swift`

```swift
import XCTest
@testable import kWise

@MainActor
final class CleanupViewModelRehearsalTests: XCTestCase {
    private func makeVM(attributions: [SpaceAttribution]) -> (CleanupViewModel, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rehearsal-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let vm = CleanupViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true), quota: nil))
        vm.attributionLookup = { attributions }
        return (vm, root)
    }

    func testRehearsalMirrorsSelectedURLsOneToOne() async {
        let (vm, root) = makeVM(attributions: [])
        let a = root.appendingPathComponent("a.bin"); let b = root.appendingPathComponent("b.bin")
        try? Data("x".utf8).write(to: a); try? Data("y".utf8).write(to: b)

        let items = await vm.makeRehearsal(sizes: [a: 1, b: 2],
                                           urls: [a, b])
        XCTAssertEqual(items.map(\.target.url), [a, b], "预演 == 执行（1:1 同序）")
        XCTAssertEqual(vm.pendingTargets.count, 2)
    }

    func testExecuteUsesPendingTargetsExactly() async {
        let (vm, root) = makeVM(attributions: [])
        let a = root.appendingPathComponent("a.bin")
        try? Data("x".utf8).write(to: a)
        _ = await vm.makeRehearsal(sizes: [a: 1], urls: [a])

        await vm.executeConfirmedCleanup(sizes: [a: 1])
        XCTAssertTrue(vm.lastOutcome?.succeeded.isEmpty == false,
                      "确认后执行必须真正清理 pendingTargets")
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
    }
}
```

> 注：`makeRehearsal(sizes:urls:)` / `executeConfirmedCleanup(sizes:)` 的 sizes 形参类型
> 以现有 `cleanupNow(sizes:)` 的真实签名为准（先读 CleanupViewModel.swift:75-115；
> 若是 `[String: Int64]` 则保持同型，测试改传 `["/path": 1]` 风格）。URLs 参数显式传入，
> 不依赖 `urlsToCleanup` 外部状态（历史页静默 no-op 的老坑不再复制）。

- [ ] **Step 2: 跑测试确认失败**；**Step 3: 实现 VM 拆分**：
1. `CleanupViewModel` 加 `public var attributionLookup: (() -> [SpaceAttribution])?` 与 `@Published public private(set) var pendingTargets: [CleanupTarget] = []`
2. `makeRehearsal(sizes:urls:)`：按原 `cleanupNow` 的 :83-88 逻辑构造 targets（含存在性过滤）→ 暂存 `pendingTargets` → `CleanupRehearsal.build(targets:attributions: attributionLookup?() ?? [])`
3. `executeConfirmedCleanup(sizes:)`：原 `cleanupNow` 的 :90-115 主体，改用 `pendingTargets`（空 → 直接返回，绝不把「上次 targets」当成兜底）
4. 旧 `cleanupNow(sizes:)` 保留为兼容包装：`makeRehearsal` + 无预演直接 `executeConfirmedCleanup`（AppUninstall 等不接预演的调用方不受影响——先 grep `cleanupNow(` 全部调用点确认各自走哪条）
5. `cd kWise && xcodegen generate`

- [ ] **Step 4: 预演视图** — `kWise/Features/Cleanup/CleanupRehearsalSheet.swift`（完整新建）：

```swift
// kWise/Features/Cleanup/CleanupRehearsalSheet.swift
//
// 清理预演（spec §5 Rehearsal）：执行前的最后一道人签。逐项 = 路径 + 大小 +
// 风险徽章 + 「为什么可以回收」（归因在）或诚实「无归因信息」（归因缺）。
// 红线：确认只执行预演过的清单——sheet 关闭即作废，不缓存跨面板。
import SwiftUI

struct CleanupRehearsalSheet: View {
    let items: [RehearsalItem]
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @State private var exemptedPaths: Set<String> = []

    private var confirmedItems: [RehearsalItem] {
        items.filter { !exemptedPaths.contains($0.target.url.path) }
    }
    private var totalBytes: Int64 {
        confirmedItems.reduce(0) { $0 + $1.target.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("attr.rehearsal.title")
                .font(AppFont.title2)
            Text("attr.rehearsal.banner")
                .font(AppFont.footnote)
                .foregroundStyle(Color.textSecondary)

            List {
                ForEach(items) { item in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { !exemptedPaths.contains(item.target.url.path) },
                            set: { on in
                                if on { exemptedPaths.remove(item.target.url.path) }
                                else { exemptedPaths.insert(item.target.url.path) }
                            })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.target.url.lastPathComponent)
                                    .font(AppFont.body)
                                reasonLine(item)
                                    .font(AppFont.caption)
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        Spacer()
                        Text(FileSizeFormatter.abbreviated(from: item.target.size))
                            .font(AppFont.caption.monospaced())
                    }
                }
            }
            .frame(minHeight: 240)

            HStack {
                Text(String(format:
                    String(localized: String.LocalizationValue("attr.rehearsal.total")),
                    FileSizeFormatter.abbreviated(from: totalBytes),
                    confirmedItems.count, items.count))
                    .font(AppFont.body)
                Spacer()
                Button(role: .cancel) { onCancel() } label: { Text("attr.rehearsal.cancel") }
                Button { onConfirm() } label: { Text("attr.rehearsal.confirm") }
                    .disabled(confirmedItems.isEmpty)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(AppSpacing.lg)
        .frame(width: 560, height: 480)
    }

    @ViewBuilder
    private func reasonLine(_ item: RehearsalItem) -> some View {
        if let attribution = item.attribution {
            // P0 契约：ruleID==nil 的拒答项/推测项不渲染 notes 行（诚实降级）。
            if item.attribution?.confidence == .certain,
               let ruleID = attribution.ruleID {
                Text(String(localized: String.LocalizationValue("attr.notes.\(ruleID)")))
                    .lineLimit(2)
            } else if attribution.confidence == .probable {
                Text(String(format:
                    String(localized: String.LocalizationValue("attr.confidence.probable.reason")),
                    AttributionCopy.causeLabel(attribution.cause)))
            } else {
                Text("attr.rehearsal.noReason")
            }
        } else {
            Text("attr.rehearsal.noReason")
        }
    }
}
```

新 key（幂等合并 ×3 语）：
- `attr.rehearsal.title`: 清理预演 / Cleanup Rehearsal / クリーンアップ プレビュー
- `attr.rehearsal.banner`: 以下是将要移入废纸篓的全部内容，可逐项取消勾选；确认后才执行。/ Everything below moves to the Trash — uncheck any line; nothing runs until you confirm. / 以下はゴミ箱へ移動される全内容です。項目ごとに解除でき、確認後に実行されます。
- `attr.rehearsal.total`: 共 %@ · 确认 %lld / 项（全部 %lld 项） / %@ total · %lld of %lld items confirmed / 合計 %@ · %lld / %lld 件を確認
- `attr.rehearsal.confirm`: 确认执行 / Confirm & Run / 確認して実行
- `attr.rehearsal.cancel`: 取消 / Cancel / キャンセル
- `attr.rehearsal.noReason`: 无归因信息——这是你手动勾选的项 / No attribution info — manually selected / 帰属情報なし — 手動で選択した項目
- `attr.confidence.probable.reason`: 本地模型推测：%@ / On-device model suggests: %@ / 端末内モデルの推測：%@

- [ ] **Step 5: 两入口接线**：
1. `ScanResultsView.swift` CleanupConfirmSheet 的确认按钮（:476-479 区）→ 改为 `Task { rehearsalItems = await cleanupViewModel.makeRehearsal(...) }` + 二层 sheet 呈现 `CleanupRehearsalSheet(items:)`，`onConfirm` → `await cleanupViewModel.executeConfirmedCleanup(...)`（沿用现有 `urlsToCleanup`/`selectedURLs()` 数据源）
2. `CleanupContentView.swift` 的 `performCleanup()`（:110-117）同样改为预演两段式
3. `RootView` `.onAppear`（attribution rebind 旁）加：`cleanupViewModel.attributionLookup = { attributionPreviewViewModel.report?.items ?? [] }`
   （⚠️ T5 会把预览 VM 换成 anatomy VM——此处接线在 T5 任务里同步改为 anatomy VM 的 report；本任务先按现状接。）

- [ ] **Step 6: 跑测试** — CleanupViewModelRehearsalTests + CleanupConfirmationTests + CleanupEngineTests + WarningToastTests 聚焦批，全绿。

- [ ] **Step 7: 提交** — `scripts/commit-app.sh kWise && git commit -m "feat(kWise): two-stage cleanup rehearsal — per-item reasons, exempt toggles, honest no-attribution rows (P1 T4)"`

---

### Task 5: 解剖视图（新首屏）+ P0 验证面退役

**Files:**
- Create: `kWise/Features/Attribution/AnatomyView.swift`（VM + View）
- Delete: `kWise/Features/Attribution/AttributionPreviewView.swift`（R6）
- Modify: `kWise/Tests/AttributionViewTests.swift`（删 preview 用例，保留 RulesViewModel 用例）
- Modify: `kWise/App/RootView.swift`（`case .anatomy` / `case .smartCare` 指向、attributionLookup 改接 anatomy VM、删除 preview VM）
- Modify: `kWise/Features/Toolbox/ToolboxView.swift`（`.attribution` 卡 destination → `.anatomy`）
- Modify: `kWise/Resources/Localizable.xcstrings`（anatomy key ×3 语，见 Step 4）

**Interfaces:**
- Consumes: P0 `AttributionReport` / `AttributionCopy` / T2 `.probable` 语义 / `FileSizeFormatter` / `AppFont` / `AppSpacing`
- Produces:
  - `@MainActor final class AnatomyViewModel: ObservableObject { init(service: AttributionService); func rebindCategories(_ provider: @escaping () -> [ScanCategory]); func refresh() async; var report: AttributionReport?; var groupedSections: [AnatomySection]; var refusedItems: [SpaceAttribution]; var probableItems: [SpaceAttribution] }`
  - `struct AnatomySection: Identifiable { let id: AttributionCause; let title: String; let totalBytes: Int64; let items: [SpaceAttribution] }`（items 按 bytes 降序，section 按 totalBytes 降序）
  - RootView：`case .anatomy: AnatomyView(viewModel: anatomyViewModel)`；`cleanupViewModel.attributionLookup = { anatomyViewModel.report?.items ?? [] }`（T4 接线点迁移）

- [ ] **Step 1: 写失败测试** — `kWise/Tests/AttributionViewTests.swift`：删除 `AttributionPreviewViewModel` 相关用例（该 VM 不复存在），新增 AnatomyViewModel 用例：

```swift
@MainActor
final class AnatomyViewModelTests: XCTestCase {
    private func makeVM(rules: [AttributionRule]) -> AnatomyViewModel {
        AnatomyViewModel(service: AttributionService(
            engine: AttributionRuleEngine(corpus: AttributionRuleCorpus(schemaVersion: 1, rules: rules),
                                          homeDirectory: "/Users/t"),
            volumeReader: nil, rootURL: URL(fileURLWithPath: "/Users/t"),
            volumeUsedBytesProvider: { 10_000 }))
    }

    private func category(paths: [(String, Int64)]) -> [ScanCategory] {
        let results = paths.map {
            ScanResult(url: URL(fileURLWithPath: $0.0), path: $0.0, title: "x",
                       fileSize: $0.1, cleanType: .cache)
        }
        let action = ScanAction(actionID: "a", actionType: .cache, title: "a", results: results)
        return [ScanCategory(categoryID: "c", title: "c",
                             subItems: [ScanSubCategory(subCategoryID: "s", title: "s",
                                                        actions: [action])])]
    }

    func testGroupedByCauseSortedByBytes() async {
        var corpus = AttributionRuleCorpus(schemaVersion: 1, rules: [])
        let vm = makeVM(rules: corpus.rules)
        let engine = AttributionRuleEngine(corpus: AttributionRuleCorpus(schemaVersion: 1, rules: [
            AttributionRule(id: "xcode.derived-data",
                            match: AttributionRuleMatch(pathGlob: "~/Library/Developer/Xcode/**"),
                            owner: .app(bundleID: "com.apple.dt.Xcode", appName: "Xcode"),
                            cause: .developerCache, reclaim: .recycles(expectedDays: 30),
                            notesKey: "attr.notes.xcode.derived-data"),
            AttributionRule(id: "caches.app-generic",
                            match: AttributionRuleMatch(pathGlob: "~/Library/Caches/**"),
                            owner: .bundleDir, cause: .cache,
                            reclaim: .recycles(expectedDays: 3),
                            notesKey: "attr.notes.caches.app-generic"),
        ]), homeDirectory: "/Users/t")
        _ = corpus // Silence unused warning in edited form.
        let service = AttributionService(engine: engine, volumeReader: nil,
                                         rootURL: URL(fileURLWithPath: "/Users/t"),
                                         volumeUsedBytesProvider: { 10_000 })
        let vm2 = AnatomyViewModel(service: service)
        vm2.rebindCategories { category(paths: [
            ("/Users/t/Library/Developer/Xcode/DerivedData/a", 700),
            ("/Users/t/Library/Caches/b", 200),
            ("/Users/t/Library/Caches/c", 100),
        ]) }
        await vm2.refresh()

        let sections = vm2.groupedSections
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections.first?.id, .developerCache, "总字节降序：700 > 300")
        XCTAssertEqual(sections.first?.totalBytes, 700)
        XCTAssertEqual(sections.last?.totalBytes, 300)
        XCTAssertEqual(sections.last?.items.map(\.bytes), [200, 100], "组内字节降序")
    }

    func testProbableSeparatedFromRefused() async {
        let service = AttributionService(
            engine: AttributionRuleEngine(corpus: AttributionRuleCorpus(schemaVersion: 1, rules: []),
                                          homeDirectory: "/Users/t"),
            volumeReader: nil, rootURL: URL(fileURLWithPath: "/Users/t"),
            volumeUsedBytesProvider: { nil },
            semanticProvider: { path in path.contains("chat") ? .chatFiles : nil })
        let vm = AnatomyViewModel(service: service)
        vm.rebindCategories { category(paths: [
            ("/Users/t/chat-store/blob", 900_000_000),
            ("/Users/t/unknown-thing", 900_000_000),
        ]) }
        await vm.refresh()
        XCTAssertEqual(vm.probableItems.count, 1)
        XCTAssertEqual(vm.probableItems.first?.cause, .chatFiles)
        XCTAssertEqual(vm.refusedItems.count, 1)
    }
}
```

> 注：上面第一例里的 `corpus`/`vm` 步进是编辑残留——誊写时清理为单一路径
> （直接 `makeVM(rules:)` 构造 + 手工 engine），以「编译干净 + 断言全过」为准。
> `AnatomyViewModel` 的 `semanticProvider` 测试参数用尾闭包形式时需与 init 签名
> 匹配（`SemanticAttributionProviding` 协议——测试里用小 struct 包装，见 T2 的 StubProvider 模式）。

- [ ] **Step 2: 跑测试确认失败**（编译错误：AnatomyViewModel 不存在）。

- [ ] **Step 3: 实现 VM**（`AnatomyView.swift` 上半部）：

```swift
// kWise/Features/Attribution/AnatomyView.swift
//
// 解剖视图（spec §1.1 新首屏英雄）：「你的 NNN GB，去哪了」。
// 结构：英雄头（卷用量）→ 扫描未覆盖卡（P0 黑盒卡的诚实版）→ 按原因分组的
// 归因区（每组可回收性徽章 + 组内条目理由展开）→ 推测区（L1）→ 拒答区。
// 红线：本页没有任何清理动作——回收入口只有「安全快捷回收」（跳 SmartCare
// 次级页）与扫描页的预演流。
import SwiftUI
import DesignSystem
import CommonUtils

public struct AnatomySection: Identifiable, Equatable {
    public let id: AttributionCause
    public let title: String
    public let totalBytes: Int64
    public let items: [SpaceAttribution]
}

@MainActor
public final class AnatomyViewModel: ObservableObject {
    @Published public private(set) var report: AttributionReport?
    @Published public private(set) var isLoading = false

    private let service: AttributionService
    private var categoriesProvider: (() -> [ScanCategory])?

    public init(service: AttributionService) { self.service = service }

    public func rebindCategories(_ provider: @escaping () -> [ScanCategory]) {
        categoriesProvider = provider
    }

    public func refresh() async {
        guard let categoriesProvider, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        report = await service.attribute(categories: categoriesProvider())
    }

    public var usedBytes: Int64? { report?.blackBox.usedBytes }

    public var groupedSections: [AnatomySection] {
        let items = report?.items ?? []
        let grouped = Dictionary(grouping: items) { $0.cause }
        return grouped.map { cause, group in
            AnatomySection(id: cause,
                           title: AttributionCopy.causeLabel(cause),
                           totalBytes: group.reduce(0) { $0 + $1.bytes },
                           items: group.sorted { $0.bytes > $1.bytes })
        }.sorted { $0.totalBytes > $1.totalBytes }
    }

    /// L1 推测项（仍属拒答语义，但单独成区以「可能」措辞呈现）。
    public var probableItems: [SpaceAttribution] {
        (report?.refused ?? []).filter { $0.confidence == .probable }
            .sorted { $0.bytes > $1.bytes }
    }

    public var refusedItems: [SpaceAttribution] {
        (report?.refused ?? []).filter { $0.confidence != .probable }
            .sorted { $0.bytes > $1.bytes }
    }
}
```

- [ ] **Step 4: 实现 View**（同文件下半部）。结构（完整实现，誊写时保持每个子视图独立）：

```swift
public struct AnatomyView: View {
    @StateObject private var viewModel: AnatomyViewModel
    @State private var rulesCorpus: AttributionRuleCorpus?
    private let onQuickClean: () -> Void

    init(viewModel: AnatomyViewModel, onQuickClean: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onQuickClean = onQuickClean
    }

    public var body: some View {
        List {
            heroHeader
            if let report = viewModel.report { uncoveredCard(report) }
            ForEach(viewModel.groupedSections) { section in
                Section(String(format: String(localized:
                    String.LocalizationValue("attr.anatomy.section")),
                    section.title, FileSizeFormatter.abbreviated(from: section.totalBytes))) {
                    ForEach(section.items.prefix(20)) { item in
                        anatomyRow(item)
                    }
                }
            }
            probableSection
            refusedSection
            rulesLink
        }
        .navigationTitle(Text("nav.anatomy"))
        .toolbar {
            Button { Task { await viewModel.refresh() } } label: {
                Text("attr.preview.refresh")
            }.disabled(viewModel.isLoading)
        }
        .task { loadCorpusAndRefresh() }
    }

    private var heroHeader: some View {
        Section {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                if let used = viewModel.usedBytes {
                    Text(String(format: String(localized:
                        String.LocalizationValue("attr.anatomy.hero")),
                        FileSizeFormatter.abbreviated(from: used)))
                        .font(AppFont.title2)
                }
                Text("attr.anatomy.hero.subtitle")
                    .font(AppFont.callout)
                    .foregroundStyle(Color.textSecondary)
                Button(action: onQuickClean) {
                    Text("attr.anatomy.safeClean")
                }.buttonStyle(.bordered)
            }
        }
    }
    // uncoveredCard(report:)：复用 P0 黑盒卡的诚实文案
    //（attr.blackbox.uncovered.title/body/unattributed——最终修复波已加），
    // .negativeResidual 分支渲染 attr.blackbox.insufficient。
    // anatomyRow(item:)：owner 行 + cause 行 + 可回收性徽章 +
    //   DisclosureGroup 理由链（复用 P0 attributionRow 的证据渲染，含
    //   空参数 lastModified 隐藏契约）+ 置信度徽章：
    //   .certain → attr.anatomy.badge.rule / .probable → attr.confidence.probable
    // probableSection/refusedSection：同 P0 拒答语义（ruleID==nil 无 notes 行，
    //   空列表收起 Section——P0 T9 已实现，迁移时保持）。
    // rulesLink：NavigationLink → AttributionRulesView（保留）。
}
```

> 实施说明：`uncoveredCard` / `anatomyRow` / `probableSection` / `refusedSection` /
> `rulesLink` 五个子视图从 `AttributionPreviewView.swift` **迁移改造**（那三个文件
> 的逻辑是验证过的：诚实卡、证据链渲染、拒答双源、规则链接）——迁移不是复制，
> 差异点：徽章行加置信度（certain=规则判定 / probable=推测）、hero 头与快捷回收
> 按钮为新增。迁移完成后**删除 `AttributionPreviewView.swift`** 并 `xcodegen generate`。

新 key（×3 语）：
- `attr.anatomy.hero`: 你的 %@，去哪了 / Your %@ — where did it go? / あなたの %@、どこへ？
- `attr.anatomy.hero.subtitle`: 先看懂，再动手。每一项都可展开理由、可拒答。/ Understand first, act second — every item explains itself. / 先に理解し、それから動く。すべての項目に理由があります。
- `attr.anatomy.safeClean`: 安全快捷回收 / Safe quick clean / 安全なクイッククリーン
- `attr.anatomy.section`: %@ · %@ / %@ · %@ / %@ · %@
- `attr.anatomy.badge.rule`: 规则判定 / Rule-based / ルール判定

- [ ] **Step 5: 接线**：
1. RootView：`@StateObject private var anatomyViewModel = AnatomyViewModel(service: .live())`（替换 preview VM 声明）；`case .anatomy: AnatomyView(viewModel: anatomyViewModel, onQuickClean: { appState.navigation = .smartCare })`；`.onAppear` 里 `anatomyViewModel.rebindCategories { scanResultsViewModel.categories }` + `cleanupViewModel.attributionLookup = { anatomyViewModel.report?.items ?? [] }`（T4 接线迁移）；删除 preview VM 全部残留
2. ToolboxView `.attribution` 卡 destination → `.anatomy`
3. `AppStateTests`/`ToolTabTests` 若有 `.attribution` 引用同步

- [ ] **Step 6: 跑测试 + 构建** — AttributionViewTests（改造后）+ SemanticAttributionTests + CleanupViewModelRehearsalTests + AppStateTests 聚焦批；`xcodebuild build` 整体编译。

- [ ] **Step 7: 提交** — `scripts/commit-app.sh kWise && git commit -m "feat(kWise): anatomy hero view replaces preview surface — cause groups, confidence badges, L1 section (P1 T5)"`

---

### Task 6: SmartCare 降级为「安全快捷回收」次级页

**Files:**
- Modify: `kWise/Features/SmartCare/SmartCareHeroView.swift`（:209-233 moduleGrid 删除；标题/文案改「安全快捷回收」；scopeGrantCard **保留**）
- Modify: `kWise/Resources/Localizable.xcstrings`（`nav.smartCare` 文案改「安全快捷回收」×3 语）
- Modify: `kWise/Tests/AssistantAndCopyAuditTests.swift`（v2FeatureFiles 中 SmartCareHeroView.swift 保留——文件未删）
- Test: 既有 SmartCareOrchestratorTests / SmartCareViewModelTests / ScanResultsViewSnapshotTests 全绿即可

**Interfaces:**
- Produces: SmartCareHeroView 收缩为单卡次级页（状态机 7 case 不动——Orchestrator API 零改动）；ScanResultsView 内嵌面板（:184）保持

- [ ] **Step 1: 失败测试**（文案级）：在 `SmartCareOrchestratorTests` 或新建断言——

```swift
func testSmartCareHeroCopyIsHonestAfterDemotion() throws {
    // 降级后的英雄文案不得再宣称「一键焕新」级叙事（spec §3.1）。
    let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Features/SmartCare/SmartCareHeroView.swift"),
        encoding: .utf8)
    XCTAssertFalse(source.contains("焕然如新"), "降级页不得使用焕新级口号")
}
```

- [ ] **Step 2: RED 确认**；**Step 3: 实现**：
1. 删 `moduleGrid`（:209-233）与 `appState.navigation = destination` 跳转辅助（:242）——次级页不再充当导航枢纽
2. 标题文案改用 key `nav.smartCare`（值改 zh `安全快捷回收` / en `Safe Quick Clean` / ja `安全なクイッククリーン`——**修改现有 key 值**，幂等脚本覆盖写入）；页内说明行加一句「只处理可自动重建的缓存类项目，30 天内可从历史还原」（新 key `attr.safeclean.subtitle` ×3：en `Only auto-rebuildable caches — restorable from History for 30 days.` ja `自動再生成されるキャッシュのみ。30 日間は履歴から復元できます。`）
3. 保留 scopeGrantCard / busyHero / confirmHero / doneHero / failedHero 全部状态分支
4. 更新 `nav.smartCare` 后跑 `LocalizationCompletenessTests`

- [ ] **Step 4: 跑测试**；**Step 5: 提交** — `scripts/commit-app.sh kWise && git commit -m "feat(kWise): smartCare demoted to safe-quick-clean secondary page (P1 T6)"`

### Task 7: 配额废除 → 买断门控（$9.90 非消耗型）

**Files:**
- Modify: `kWise/Features/Store/StoreManager.swift`（productID → 非消耗型；purchase() 处理；`isSubscribed` → `hasPurchased`）
- Modify: `kWise/Features/Store/StoreProtocol.swift`（协议属性同步）
- Modify: `kWise/Features/Cleanup/CleanupQuota.swift:85-98`（Checker 语义）+ 删 `FreeQuotaStore`（:31-83）/ `QuotaRecordSink`（:136-144）
- Modify: `kWise/App/AppGraph.swift:28,124-143`（quotaChecker 语义、FreeQuotaStore/QuotaRecordSink 装配删除）
- Modify: `kWise/Features/Store/PaywallView.swift`（文案重写）
- Create: `kWise/Configuration/Klaris.storekit`（若无既有 .storekit——先 `find kWise -name "*.storekit"`）
- Modify: RootView `onQuotaExhausted` 闭包链（8 处调用点语义不变：quotaExhausted → presentPaywall）
- Test: `kWise/Tests/StoreManagerTests.swift`、`kWise/Tests/CleanupEngineTests.swift`（quota 路径用例改写）、`kWise/Tests/CleanupQuotaStoreTests.swift`（FreeQuotaStore 用例删除/改写）

**Interfaces:**
- Consumes: P0 `CleanupQuotaChecking` 协议（不变）
- Produces:
  - `StoreManager.productID = "app.kraftly.klaris.buyout"`；`hasPurchased: Bool`（替代 `isSubscribed`，全仓改名——grep `isSubscribed` 逐处）
  - `CleanupQuotaChecker.remainingFreeBytes()`：`store.hasPurchased → nil`；未购 → `0`（engine 贪心截断输入 0 = 全部 skippedForQuota → `CleanupOutcome.quotaExhausted = true` → paywall。**语义从截断翻转为拒绝（R5）**）
  - `FreeQuotaStore` / `QuotaRecordSink` 类型删除；`CleanupEvent.quotaExhausted` 字段名不变

- [ ] **Step 1: 写失败测试** — StoreManagerTests 改写（productID 断言 + 非消耗购买结果处理）；CleanupEngineTests 的 quota 用例改为：

```swift
func testUnpurchasedUserIsBlockedNotTruncated() async throws {
    // R5：未购 → remaining 0 → 全部 skippedForQuota（拒绝，不是截断到 1GB）。
    // 沿用既有 quota 用例的 StubQuota 模式，remaining: 0。
    // 断言：outcome.quotaExhausted == true 且 succeeded.isEmpty。
}
func testPurchasedUserHasNoQuotaCeiling() async throws {
    // StubQuota remaining: nil（已购）→ 全部成功，skippedForQuota.isEmpty。
}
```

（沿用 CleanupEngineTests 现有 StubQuota/临时目录 fixture；上面两例的完整体按该文件既有的 quota 用例模板补全——先读再写。）

- [ ] **Step 2: RED**；**Step 3: 实现**：StoreManager（productID/hasPurchased/purchase 的 `Product.PurchaseResult` 非消耗分支：`.success(verification)` → 确认 ownership 后置位）、Checker 一处语义、AppGraph 删两条装配、grep `isSubscribed` 全仓改名（含 StoreProtocol、PaywallView、RootView 闭包引用处）、`FreeQuotaStore`/`QuotaRecordSink`/`CleanupQuotaStoreTests` 对应用例删除。
- [ ] **Step 4: PaywallView 文案重写**（新 key `pw.buyout.*` ×3 语）：
  - 标题：解锁全部回收能力 / Unlock every reclamation action / すべての回収機能を解放
  - 卖点行：一次买断 ¥68（$9.90）·无订阅 ·扫描与归因永远免费 ·数据不出机——**禁止**「无限清理/免费版仅 1GB」「AI 智能分类/本地 CoreML」旧话术（跑 NewCopyAuditTests 验证）
  - 免费层说明行：扫描、归因、拒答清单永久免费
- [ ] **Step 5: .storekit 配置** — 若 `find kWise -name "*.storekit"` 为空：新建 `kWise/Configuration/Klaris.storekit`（非消耗型 `app.kraftly.klaris.buyout`，价格 $9.90/¥68），并在 scheme（kWise）的 StoreKit Configuration 选项里启用——**若 scheme 选项需要 Xcode UI 手动勾选，在报告注明为手动步骤**。若已有 .storekit 则加产品条目。
- [ ] **Step 6: 跑测试** — StoreManagerTests + CleanupEngineTests + CleanupQuotaStoreTests（改后）+ WidgetSnapshotTests 聚焦批。
- [ ] **Step 7: 提交** — `scripts/commit-app.sh kWise && git commit -m "feat(kWise): quota retired — $9.90 buyout gate replaces 1GB monthly truncation (P1 T7)"`

---

### Task 8: Assistant 聊天框退役 → DetailPanel 节点问答

**Files:**
- Delete: `kWise/Features/Assistant/AssistantView.swift`
- Modify: `kWise/App/AppState.swift`（删 `.assistant` case；allCases 20→19——T1 后基数）
- Modify: `kWise/App/AppGraph.swift:102-104`（删 assistantVM）、`kWise/App/RootView.swift`（删 `case .assistant`、`graph.assistantScanVM` 注入若仅 assistant 使用——grep 确认）
- Modify: `kWise/Features/Toolbox/ToolboxView.swift:83-84`（删卡）
- Modify: `kWise/Features/SmartScan/Views/MasterDetail/DetailPanelView.swift`（`fileBody`/`appBody` 尾部加建议问答区）
- Modify: `kWise/Tests/AssistantAndCopyAuditTests.swift`（v2FeatureFiles 移除 AssistantView.swift；matcher 测试全保留）
- Modify: `kWise/Resources/Localizable.xcstrings`（问答 key ×3 语）
- Test: `kWise/Tests/AssistantAndCopyAuditTests.swift`（3 class 全保留；新增 DetailPanel 问答 VM 用例）

**Interfaces:**
- Consumes: `AssistantIntentMatcher.match(_:)` / `AssistantAnswerBuilder.build(intent:scanVM:)` / `AssistantAnswer`（全部保留，签名不动）
- Produces: `@MainActor final class AssistantNodePanelModel: ObservableObject { init(scanResultsProvider: @escaping () -> ScanResultsViewModel?); func answer(question: String) -> AssistantAnswer? }`（question → matcher → builder；nil = 诚实「这个问题我答不了」）——DetailPanelView 用 `AssistantNodePanelModel` 渲染建议 chip（从 matcher 模板表挑 4 个通用问题）+ 答案卡。

- [ ] **Step 1: 失败测试** — AssistantAndCopyAuditTests 追加：

```swift
@MainActor
func testNodePanelAnswersFromMatcherWithoutChatInput() {
    // 节点问答不走自由输入——建议问题集必须命中 matcher 表。
    let panel = AssistantNodePanelModel(scanResultsProvider: { nil })
    for question in AssistantNodePanelModel.suggestedQuestions {
        if let intent = AssistantIntentMatcher().match(question) {
            // builder 在 scanVM 为 nil 时的诚实行为：要么 nil 要么无数据答案卡。
            _ = panel.answer(question: question)
        } else {
            XCTFail("建议问题 \(question) 必须能被 matcher 命中——建议集与模板表脱节")
        }
    }
    XCTAssertNil(panel.answer(question: "今天天气怎么样"),
                 "无关输入必须诚实拒答")
}
```

（`AssistantNodePanelModel.suggestedQuestions` 静态表：4 条中文问题，逐条对照 `Assistant.swift` 模板表挑选可命中的；`answer` 在无 scanVM 时返回 nil = 诚实。）

- [ ] **Step 2: RED**；**Step 3: 实现**：新建 `kWise/Features/Assistant/AssistantNodePanel.swift`（Model + View：建议 chip 行 + 答案卡列表，复用 AssistantAnswer 渲染）；DetailPanelView `fileBody`/`appBody` 尾部嵌入；删除清单（AssistantView/Toolbox 卡/case/AppGraph/RootView case）+ `xcodegen generate`；grep `.assistant` 残留引用逐处清理（AppCoordinator 若有 assistant 深链 host 一并删）。
- [ ] **Step 4: 跑测试** — AssistantAndCopyAuditTests（全 class）+ AccessibilityTests + AppStateTests 聚焦批。
- [ ] **Step 5: 提交** — `scripts/commit-app.sh kWise && git commit -m "feat(kWise): assistant chat retired — node-embedded Q&A in detail panel (P1 T8)"`

---

### Task 9: 双引擎退役 — Intents 切 ScanOrchestrator + 旧资产删除

**Files:**
- Create: `kWise/Features/SmartScan/IntentScanAdapter.swift`
- Modify: `kWise/Intents/ScanIntent.swift`、`kWise/Intents/CleanCacheIntent.swift`、`kWise/Intents/ShowLargeFilesIntent.swift`（全部改走 adapter；`CleanCacheIntent` 的 `Set<Int>` subCategoryID 语义废除——R4）
- Delete: `kWise/Features/SmartScan/ScanEngine.swift`（LegacyScanEngine）、`ScanViewModel.swift`、`ScanRule.swift`、`AppScanRules.swift`、`FilterEvaluator.swift`、`SpecializedScanners.swift`、`kWise/Features/AIClassifier/`（两文件）、`kWise/Tests/RuleClassifierTests.swift`、`kWise/Tests/ScanEngineIntegrationTests.swift`、`kWise/Tests/AppRuleFixtures.swift`（若仅旧引擎使用——grep 确认）
- Modify: 依赖旧类型的既有测试（ScanSpeedTests / ScanProgressModelTests 等——grep `LegacyScanEngine|ScanViewModel|ScanRuleSet|AppScanRules|FilterEvaluator|SpecializedScanners|RuleClassifier` 逐处处理）
- Modify: `kWise/UserPreferences.swift`（删 `aiClassificationEnabled` + `assistantEnabled`）+ `SettingsView.swift:58`（删 Toggle 行）+ `kWise/Tests/UserPreferencesTests.swift`（同步删断言；Codable 旧 fixture 若含这两 key，非 Optional 字段删除后解码仍向后兼容——Swift 合成解码忽略多余 key，确认 fixture 用例仍绿）

**Interfaces:**
- Consumes: `ScanOrchestrator(scope:)` + `ScanEngine(orchestrator:)` + `ScanResultsViewModel`（新引擎链）；`SmartCareOrchestrator.computeRecommendedPicks`（:162-174 四层遍历——抽为共享 helper 放入 adapter）
- Produces:
  - `struct IntentScanAdapter { static func recommendedPickTargets(scope: AppScope, engine: CleanupEngine) async -> (targets: [CleanupTarget], summary: String); static func largestFiles(scope: AppScope, limit: Int) async -> [ScanResult]; static func scanSummary(scope: AppScope) async -> (categories: Int, bytes: Int64) }`
  - `CleanCacheIntent`：跑一次新扫描 → recommendedPickTargets → `engine.cleanup(targets:)` → 返回释放量
  - `ShowLargeFilesIntent`：largestFiles 列表
  - `ScanIntent`：scanSummary

- [ ] **Step 1: 失败测试** — `kWise/Tests/IntentScanAdapterTests.swift`：

```swift
import XCTest
@testable import kWise

final class IntentScanAdapterTests: XCTestCase {
    /// adapter 的核心职责是把新扫描树的叶子收敛成 CleanupTarget——
    /// 用注入的合成树直接测推荐挑选收敛（不 spawn 真扫描）。
    func testRecommendedPicksCollectOnlyDefaultCheckedLeaves() {
        let category = ScanCategory(categoryID: "c", title: "c", subItems: [
            ScanSubCategory(subCategoryID: "s", title: "s", actions: [ScanAction(
                actionID: "a", actionType: .cache, title: "a", results: [
                    ScanResult(url: URL(fileURLWithPath: "/tmp/safe"), path: "/tmp/safe",
                               title: "safe", fileSize: 10, cleanType: .cache,
                               riskLevel: .recommended),
                    ScanResult(url: URL(fileURLWithPath: "/tmp/risky"), path: "/tmp/risky",
                               title: "risky", fileSize: 20, cleanType: .preference,
                               riskLevel: .dangerous),
                ])])])
        let targets = IntentScanAdapter.targetsFromRecommendedPicks(in: [category])
        XCTAssertEqual(targets.map(\.url.path), ["/tmp/safe"],
                       "危险项绝不进 Intents 的自动清理集（R4/C4 红线）")
    }
}
```

- [ ] **Step 2: RED**；**Step 3: 实现 adapter**：从 `SmartCareOrchestrator.swift:162-174` 抽 `computeRecommendedPicks` 的四层遍历为 `IntentScanAdapter.targetsFromRecommendedPicks(in: [ScanCategory]) -> [CleanupTarget]`（SmartCareOrchestrator 改调它——单源）；三个 Intent 的 `perform()` 改走 adapter（构造 `ScanOrchestrator(scope: AppScope.shared.scope)` + await `startScan()` 流至完成 → `ScanResultsViewModel.categories` 或直接 orchestrator 的 categoryStream 终态——以现有 SmartCareOrchestrator.start() 消费扫描完成的写法为准）。
- [ ] **Step 4: 删除清单执行**：逐文件 `git rm`；`xcodegen generate`；全仓 grep 旧类型名（含测试），逐处清理；`UserPreferences` 两开关删除 + Settings 行删除 + UserPreferencesTests 同步。
- [ ] **Step 5: 跑测试** — IntentScanAdapterTests + SmartCareOrchestratorTests + ScanOrchestratorIntegrationTests + ScanProgressTests + DefaultSelectionTests + CascadeCheckboxTests + UserPreferencesTests 聚焦批；**再跑一次全量**（本任务是删除性改动最大的一步，全量绿是退役完成的定义；环境 wedge 时分批补齐并如实报告）。
- [ ] **Step 6: 提交** — `scripts/commit-app.sh kWise && git commit -m "feat(kWise): legacy scan engine retired — Intents on ScanOrchestrator, dead AI assets removed (P1 T9)"`

---

### Task 10: CLAUDE.md 假卖点修正 + P1 收尾

**Files:**
- Modify: `CLAUDE.md`（§3.3 差异化表、§2.2 定价、§3.6 盈利、§7 进度、假卖点）
- Test: 全量

- [ ] **Step 1: CLAUDE.md 修正**（逐条）：
1. §3.3 表「CoreML AI 自动分类」→ 真实表述「本机规则 + 端上语义归因（NLEmbedding），零网络」；「3D 磁盘星系图（Metal）」→「2D 空间地图（Canvas sunburst/treemap）+ 空间解剖首屏」；FDA 引导行 →「PowerScope 主目录授权」
2. §2.2/§3.6 定价：Free（扫描+归因+拒答）→ $9.90 买断（回收执行）；删订阅话术
3. §3.6 内购 SKU → `app.kraftly.klaris.buyout`（非消耗型）
4. §7 加 P1 完成条目（本计划 10 任务 + 修复轮摘要 + 测试数）
5. §3.4 表格里 FDA 引导、Widget 等行随实际修正
- [ ] **Step 2: 全量测试** — `xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWise`（wedge 时分批补齐）；记录最终基线数。
- [ ] **Step 3: 提交** — `scripts/commit-app.sh kWise && git add CLAUDE.md && git commit -m "docs: CLAUDE.md honesty pass — real capabilities, buyout pricing, P1 progress (P1 T10)"`

---

## Self-Review（已执行）

1. **Spec 覆盖**：§3.1 停止清单逐项 → T1（rail）/T5+T6（首屏与降级）/T8（聊天框+死代码）/T9（双引擎+空开关）/T10（CLAUDE.md）；§3.1 配额废除 → T7；§2.2 定价 → T7；§4.5 L1 → T2（L1.5 CreateML 裁定延后 P2 = R2）；§5 预演/拒答 → T3/T4/T5；§10 P1 验收「预演=执行逐项一致」→ T3 契约测试 + T4 VM 测试。**有意不在 P1**：空间地图联动（P2）、菜单栏一句话（P2）、Explain→Rule（P2）、迁出（P2 可选）、L2 FM（P2）。
2. **占位符扫描**：T7 Step 1 与 T5 Step 1 各标注了「按既有模板补全」的用例——均给出了断言目标与参照文件，非空泛占位；T5 Step 1 有一处标注为编辑残留清理点。其余步骤全部给全码。
3. **类型一致性**：`AnatomySection(id:title:totalBytes:items:)` ↔ T5 测试；`RehearsalItem(id:target:attribution:)` ↔ T3/T4；`SemanticAttributionProviding.probableCause(for:)` ↔ T2 service 管道；`IntentScanAdapter.targetsFromRecommendedPicks(in:)` ↔ T9 测试；`nav.anatomy` / `attr.anatomy.*` / `attr.rehearsal.*` / `attr.confidence.probable*` / `pw.buyout.*` key 名全程一致。

## 执行说明

沿用 P0 的 Subagent-Driven 流程（用户已选定）：每任务 fresh 子代理 + 两段审查；模型分配——T1/T3/T4/T10 sonnet，T2/T5/T8 sonnet，T7/T9 sonnet（均为多文件集成任务，无纯转写任务）；最终全分支评审用最强模型。

