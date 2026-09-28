# Klaris P0 — 归因引擎 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 建成归因引擎（L0 规则全链路 + 卷层通道 + 黑盒数学 + 规则可查页 + 最小验证面），达成 spec §8 的 P0 四条验收。

**Architecture:** 新模块 `kWise/Features/Attribution/`，消费 `ScanOrchestrator` 产出的 `ScanCategory` 森林（只读，不改树模型）；`AttributionRuleEngine` 做 L0 路径规则匹配（first-match-wins）；`VolumeLayerReader` 经 `diskutil` 子进程读 APFS 快照（复用 `SMARTReader` 的 Process 范式）；`BlackBoxMath` 做「卷用量 − 可见文件合计」的诚实残差；产出 `AttributionReport`（items / refused / 黑盒）。删除执行**完全不接**——P0 是描述性归因，不是清理功能。

**Tech Stack:** Swift 5.9 严格并发、SwiftUI、XCTest、Process 子进程（diskutil）、String Catalog 三语。

**Spec:** `docs/superpowers/specs/2026-09-27-klaris-attribution-design.md`（§4 归因引擎 / §5 信任契约 / §7 降级矩阵 / §8 P0 验收 / §10 分期）

## Global Constraints

- 最低系统 macOS 13.0；Widget target 14.0（勿动）。
- **零网络**：禁止 URLSession；entitlements `network.client=false` 保持不变。
- **P0 只交付 L0**（规则层）；NLEmbedding / CreateML / FM（L1/L2）不在本计划。
- **永不自动删除**：归因是描述性输出，禁止接 `CleanupEngine`。
- 每条归因输出必须带来源标注（`AttributionSource`）与置信度；`reclaim == .uncertain` 一律进拒答清单。
- 拿不到的数据**出状态不出数字**（快照读取失败 → 明示 unreadable，禁止用 0 冒充）。
- 本地化：每个新 key 三语（en/zh-Hans/ja）齐全，`LocalizationCompletenessTests` 强制。
- 恐吓禁语生效于全部归因文案（Task 10 审计）。
- 测试基线全绿：`xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWise`（基线 522 用例起）。
- 提交：`scripts/commit-app.sh kWise`（本计划不碰 kFoundation，无需 `--allow-kfoundation`）。
- P0 不改 Core Data 模型（`FileEntry.confidence` 持久化推迟到 P1）。
- 仓库现状锚点：`kWise/App/AppState.swift:34`（NavigationItem 枚举）、`kWise/App/RootView.swift:206-225`（视图分发 switch）、`kWise/Features/Toolbox/ToolboxView.swift:25`（卡片栅格）、`kWise/Features/DiskHealth/SMARTReader.swift:100`（Process 范式）、`kWise/project.yml:34-128`（bundle id 五处）。

## File Structure

```
Create:
  kWise/Features/Attribution/AttributionTypes.swift      # 核心类型（Owner/Cause/Reclaimability/Evidence/SpaceAttribution）
  kWise/Features/Attribution/PathGlobMatcher.swift       # 纯函数 glob 匹配（~ 展开、**、*）
  kWise/Features/Attribution/AttributionRule.swift       # 规则模型 + 语料加载（schemaVersion 守卫）
  kWise/Features/Attribution/AttributionRuleEngine.swift # L0 匹配引擎 + bundleDir 归属解析
  kWise/Features/Attribution/VolumeLayerReader.swift     # diskutil apfs listSnapshots 通道
  kWise/Features/Attribution/BlackBoxMath.swift          # 黑盒残差数学（纯函数）
  kWise/Features/Attribution/AttributionService.swift    # 整合：文件层 + 卷层 + 黑盒 → AttributionReport
  kWise/Features/Attribution/AttributionCopy.swift       # 本地化文案装配（cause/reclaim/evidence 标签）
  kWise/Features/Attribution/AttributionRulesView.swift  # 规则可查页（信任契约「规则开放」实体）
  kWise/Features/Attribution/AttributionPreviewView.swift# P0 验证面（Top-N + 理由展开 + 拒答清单 + 黑盒卡）
  kWise/Resources/attribution_rules.json                 # 归因语料第一批（16 条）
  kWise/Tests/AttributionTypesTests.swift
  kWise/Tests/PathGlobMatcherTests.swift
  kWise/Tests/AttributionRuleTests.swift                 # 语料加载 + 审计（含三语 evidence key 校验）
  kWise/Tests/AttributionRuleEngineTests.swift           # 黄金用例
  kWise/Tests/VolumeLayerReaderTests.swift
  kWise/Tests/BlackBoxMathTests.swift
  kWise/Tests/AttributionServiceTests.swift
  kWise/Tests/AttributionCopyAuditTests.swift
  kWise/Tests/Fixtures/apfs_snapshots.plist              # diskutil 输出 fixture（从源码树读取，不进 bundle）
Modify:
  kWise/Resources/Localizable.xcstrings                  # 新增 ~50 key × 3 语
  kWise/App/AppState.swift                               # NavigationItem.attribution + isToolboxTool
  kWise/App/RootView.swift                               # 视图分发 case + VM 绑定
  kWise/Features/Toolbox/ToolboxView.swift               # 第 10 张卡
  kWise/project.yml / kWise/kWise.entitlements 等        # Task 11 bundle id 改名
```

---

### Task 1: 核心类型 `AttributionTypes.swift`

**Files:**
- Create: `kWise/Features/Attribution/AttributionTypes.swift`
- Test: `kWise/Tests/AttributionTypesTests.swift`

**Interfaces:**
- Produces（后续任务依赖的精确签名）:
  - `enum AttributionScope: String, Codable, Sendable { case fileTree, volumeLayer }`
  - `enum AttributionOwner: Equatable, Sendable { case app(bundleID: String, appName: String?); case system; case user; case unknown }`
  - `enum AttributionCause: String, Codable, Sendable, CaseIterable`（case: cache/snapshot/developerCache/aiModel/chatFiles/renderCache/download/archive/backup/log/mailAttachment/iOSBackup/containerData/unknown）
  - `enum Reclaimability: Equatable, Codable, Sendable { case recycles(expectedDays: Int); case resurrects(via: String); case permanent; case uncertain }`
  - `enum AttributionConfidence: String, Codable, Sendable { case certain, probable, refused }`
  - `enum AttributionSource: String, Codable, Sendable { case rule, nlEmbedding, createML, fmTagging, unattributed }`
  - `enum EvidenceKind: String, Codable, Sendable { case pathPattern, ownerApp, ruleCitation, lastModified }`
  - `struct Evidence: Equatable, Sendable { let kind: EvidenceKind; let textKey: String; let arguments: [String] }`
  - `struct SpaceAttribution: Identifiable, Equatable, Sendable`（id/scope/paths/bytes/owner/cause/reclaim/confidence/source/ruleID/evidence/lastModified）

- [ ] **Step 1: 写失败测试** — `kWise/Tests/AttributionTypesTests.swift`

```swift
import XCTest
@testable import kWise

final class AttributionTypesTests: XCTestCase {
    func testReclaimabilityCodableRoundTrip() throws {
        let cases: [Reclaimability] = [.recycles(expectedDays: 30),
                                        .resurrects(via: "tmutil deletelocalsnapshots"),
                                        .permanent, .uncertain]
        for original in cases {
            let data = try JSONEncoder().encode([original])
            let decoded = try JSONDecoder().decode([Reclaimability].self, from: data)
            XCTAssertEqual(decoded, [original], "\(original) must round-trip")
        }
    }

    func testReclaimabilityJSONShape() throws {
        let data = try JSONEncoder().encode(Reclaimability.recycles(expectedDays: 30))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["kind"] as? String, "recycles")
        XCTAssertEqual(object["expectedDays"] as? Int, 30)
    }

    func testReclaimabilityRejectsUnknownKind() {
        let data = Data(#"{"kind":"magic"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Reclaimability.self, from: data))
    }

    func testCauseCoversSpecTaxonomy() {
        // spec §4.1 的 14 类原因，缺一不可（golden 断言防手滑删 case）。
        XCTAssertEqual(Set(AttributionCause.allCases.map(\.rawValue)),
            ["cache", "snapshot", "developerCache", "aiModel", "chatFiles",
             "renderCache", "download", "archive", "backup", "log",
             "mailAttachment", "iOSBackup", "containerData", "unknown"])
    }

    func testSpaceAttributionFields() {
        let a = SpaceAttribution(
            scope: .fileTree, paths: ["/tmp/x"], bytes: 100,
            owner: .app(bundleID: "com.apple.dt.Xcode", appName: "Xcode"),
            cause: .developerCache, reclaim: .recycles(expectedDays: 30),
            confidence: .certain, source: .rule, ruleID: "xcode.derived-data",
            evidence: [Evidence(kind: .ruleCitation, textKey: "attr.ev.ruleCitation",
                                arguments: ["xcode.derived-data"])],
            lastModified: nil)
        XCTAssertEqual(a.ruleID, "xcode.derived-data")
        XCTAssertEqual(a.confidence, .certain)
    }
}
```

- [ ] **Step 2: 跑测试确认失败** — `xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWise -only-testing:kWiseTests/AttributionTypesTests 2>&1 | tail -5`；预期：编译错误 `cannot find 'Reclaimability' in scope`。

- [ ] **Step 3: 最小实现** — `kWise/Features/Attribution/AttributionTypes.swift`

```swift
// kWise/Features/Attribution/AttributionTypes.swift
//
// 归因引擎核心类型（spec §4.1）。设计红线：
// - 每条输出必须能回答「谁拥有 / 为什么在这 / 删了会不会回来」与
//   「这个结论怎么来的」（source + confidence）。
// - `reclaim == .uncertain` 的项永远不进清理建议，只进拒答清单。
import Foundation

public enum AttributionScope: String, Codable, Sendable {
    /// 文件树层：有具体路径。
    case fileTree
    /// 卷层：APFS 快照 / 系统保留空间，无文件路径。
    case volumeLayer
}

/// ① 归属判定。
public enum AttributionOwner: Equatable, Sendable {
    case app(bundleID: String, appName: String?)
    case system
    case user
    case unknown
}

/// ② 存在原因。rawValue 同时是语料 JSON 与本地化 key 的后缀（attr.cause.<raw>）。
public enum AttributionCause: String, Codable, Sendable, CaseIterable {
    case cache
    case snapshot
    case developerCache
    case aiModel
    case chatFiles
    case renderCache
    case download
    case archive
    case backup
    case log
    case mailAttachment
    case iOSBackup
    case containerData
    case unknown
}

/// ③ 可回收性 —— 本产品的差异化核心（全品类无人做「删了会不会回来」）。
public enum Reclaimability: Equatable, Sendable {
    /// 会回来：缓存类，预期 N 天后重建。
    case recycles(expectedDays: Int)
    /// 会复活：直接删没用，`via` 给出正确解法（如 tmutil 引导）。
    case resurrects(via: String)
    /// 不会回来：真空间（旧导出 / 安装包）。
    case permanent
    /// 不敢判 → 拒答清单，绝不进清理建议。
    case uncertain
}

extension Reclaimability: Codable {
    private enum CodingKeys: String, CodingKey { case kind, expectedDays, via }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "recycles":
            self = .recycles(expectedDays: try container.decodeIfPresent(Int.self, forKey: .expectedDays) ?? 30)
        case "resurrects":
            self = .resurrects(via: try container.decodeIfPresent(String.self, forKey: .via) ?? "tmutil")
        case "permanent":
            self = .permanent
        case "uncertain":
            self = .uncertain
        default:
            let raw = (try? container.decode(String.self, forKey: .kind)) ?? "nil"
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container,
                debugDescription: "unknown reclaim kind: \(raw)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .recycles(let days):
            try container.encode("recycles", forKey: .kind)
            try container.encode(days, forKey: .expectedDays)
        case .resurrects(let via):
            try container.encode("resurrects", forKey: .kind)
            try container.encode(via, forKey: .via)
        case .permanent:
            try container.encode("permanent", forKey: .kind)
        case .uncertain:
            try container.encode("uncertain", forKey: .kind)
        }
    }
}

/// 置信度三档（spec §4.5 渲染契约：确定 / 推测 / 不知道）。
public enum AttributionConfidence: String, Codable, Sendable {
    /// 规则命中，可引用 ruleID —— P0 唯一的正常产出。
    case certain
    /// 模型推测（P0 不产出；L1/L2 预留）。
    case probable
    /// 没有规则能判断 → 拒答清单。
    case refused
}

/// 来源标注 —— HIG GenAI「标注 AI 生成」的落地形式。
public enum AttributionSource: String, Codable, Sendable {
    case rule
    case nlEmbedding
    case createML
    case fmTagging
    /// 无来源（未匹配任何规则）。
    case unattributed
}

public enum EvidenceKind: String, Codable, Sendable {
    case pathPattern
    case ownerApp
    case ruleCitation
    case lastModified
}

/// 理由链的一环。`textKey` 指向 xcstrings（可含 %@ / %lld），
/// 禁止在代码里拼接英文/中文句子 —— 文案必须可审计、可翻译。
public struct Evidence: Equatable, Sendable {
    public let kind: EvidenceKind
    public let textKey: String
    public let arguments: [String]

    public init(kind: EvidenceKind, textKey: String, arguments: [String] = []) {
        self.kind = kind
        self.textKey = textKey
        self.arguments = arguments
    }
}

public struct SpaceAttribution: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let scope: AttributionScope
    public let paths: [String]
    public let bytes: Int64
    public let owner: AttributionOwner
    public let cause: AttributionCause
    public let reclaim: Reclaimability
    public let confidence: AttributionConfidence
    public let source: AttributionSource
    public let ruleID: String?
    public let evidence: [Evidence]
    public let lastModified: Date?

    public init(id: UUID = UUID(),
                scope: AttributionScope,
                paths: [String],
                bytes: Int64,
                owner: AttributionOwner,
                cause: AttributionCause,
                reclaim: Reclaimability,
                confidence: AttributionConfidence,
                source: AttributionSource,
                ruleID: String?,
                evidence: [Evidence],
                lastModified: Date?) {
        self.id = id
        self.scope = scope
        self.paths = paths
        self.bytes = bytes
        self.owner = owner
        self.cause = cause
        self.reclaim = reclaim
        self.confidence = confidence
        self.source = source
        self.ruleID = ruleID
        self.evidence = evidence
        self.lastModified = lastModified
    }
}
```

- [ ] **Step 4: 跑测试确认通过** — 同 Step 2 命令；预期 `Executed 5 tests, with 0 failures`。

- [ ] **Step 5: 提交**

```bash
scripts/commit-app.sh kWise && git commit -m "feat(kWise): attribution core types — owner/cause/reclaimability taxonomy (P0 Task 1)"
```

---

### Task 2: 路径 glob 匹配 `PathGlobMatcher.swift`

**Files:**
- Create: `kWise/Features/Attribution/PathGlobMatcher.swift`
- Test: `kWise/Tests/PathGlobMatcherTests.swift`

**Interfaces:**
- Produces:
  - `enum PathGlobMatcher { static func expandTilde(_ glob: String, home: String) -> String; static func matches(path: String, glob: String, home: String) -> Bool }`
  - 语义：`~` 前缀展开为 `home`；`**` 跨任意段（含 0 段）；`*` 只在单段内；大小写不敏感（macOS 默认 FS）；路径尾随 `/` 不影响结果。

- [ ] **Step 1: 写失败测试** — `kWise/Tests/PathGlobMatcherTests.swift`

```swift
import XCTest
@testable import kWise

final class PathGlobMatcherTests: XCTestCase {
    private let home = "/Users/tester"

    func testExactPathMatches() {
        XCTAssertTrue(PathGlobMatcher.matches(
            path: "/Users/tester/Library/Logs", glob: "~/Library/Logs", home: home))
    }

    func testDoubleStarMatchesDescendantsAndSelf() {
        let glob = "~/Library/Developer/Xcode/DerivedData/**"
        XCTAssertTrue(PathGlobMatcher.matches(
            path: "/Users/tester/Library/Developer/Xcode/DerivedData", glob: glob, home: home),
            "trailing ** must match the directory itself (0 segments)")
        XCTAssertTrue(PathGlobMatcher.matches(
            path: "/Users/tester/Library/Developer/Xcode/DerivedData/MyApp-abc/Build/x.o",
            glob: glob, home: home))
        XCTAssertFalse(PathGlobMatcher.matches(
            path: "/Users/tester/Library/Developer/Xcode/Archives/x.xcarchive",
            glob: glob, home: home))
    }

    func testSingleStarStaysWithinSegment() {
        XCTAssertTrue(PathGlobMatcher.matches(
            path: "/Users/tester/Library/Caches/com.apple.Safari/Cache.db",
            glob: "~/Library/Caches/*/**", home: home))
        XCTAssertFalse(PathGlobMatcher.matches(
            path: "/Users/tester/Library/Caches/a/b/Cache.db",
            glob: "~/Library/Caches/*/*.db", home: home),
            "* must not cross '/'")
    }

    func testTildeExpansionAndCaseInsensitivity() {
        XCTAssertTrue(PathGlobMatcher.matches(
            path: "/users/TESTER/library/caches/x", glob: "~/Library/Caches/x", home: home))
    }

    func testLeadingDoubleStarMatchesAnyDepth() {
        XCTAssertTrue(PathGlobMatcher.matches(
            path: "/Users/tester/Deep/Nest/Docker.raw", glob: "**/Docker.raw", home: home))
    }

    func testHomeInjectionMattersInTests() {
        // home 必须是注入的，不许偷偷读 NSHomeDirectory（可测试性红线）。
        XCTAssertFalse(PathGlobMatcher.matches(
            path: "/Users/tester/Library/Caches/x", glob: "~/Library/Caches/x", home: "/home/other"))
    }
}
```

- [ ] **Step 2: 跑测试确认失败** — 同 Task 1 Step 2 命令（替换测试类名）；预期编译错误。

- [ ] **Step 3: 最小实现** — `kWise/Features/Attribution/PathGlobMatcher.swift`

```swift
// kWise/Features/Attribution/PathGlobMatcher.swift
//
// 语料 glob 的纯函数匹配器。语义刻意小而明确（spec §4.4 语料只用到这三种）：
//   `~`   → home 前缀（注入，不读 NSHomeDirectory）
//   `**`  → 任意层（含 0 层）
//   `*`   → 单段内任意字符（不跨 '/'）
// 匹配大小写不敏感 —— macOS 默认文件系统如此。
import Foundation

enum PathGlobMatcher {

    static func expandTilde(_ glob: String, home: String) -> String {
        guard glob == "~" || glob.hasPrefix("~/") else { return glob }
        return home + glob.dropFirst(1)
    }

    static func matches(path: String, glob: String, home: String) -> Bool {
        let expanded = expandTilde(glob, home: home)
        let pathSegments = path.lowercased().split(separator: "/").map(String.init)
        let globSegments = expanded.lowercased().split(separator: "/").map(String.init)
        return matchSegments(path: pathSegments, pattern: globSegments)
    }

    private static func matchSegments(path: [String], pattern: [String]) -> Bool {
        guard let head = pattern.first else { return path.isEmpty }
        if head == "**" {
            // `**` 吃 0..n 段。
            for take in 0...path.count {
                if matchSegments(path: Array(path.dropFirst(take)), pattern: Array(pattern.dropFirst())) {
                    return true
                }
            }
            return false
        }
        guard let first = path.first, matchSegment(pattern: head, string: first) else { return false }
        return matchSegments(path: Array(path.dropFirst()), pattern: Array(pattern.dropFirst()))
    }

    /// 单段通配（`*` 不跨 '/'）：经典回溯。
    private static func matchSegment(pattern: Substring, string: Substring) -> Bool {
        if pattern.isEmpty { return string.isEmpty }
        if pattern.first == "*" {
            for drop in 0...string.count {
                if matchSegment(pattern: pattern.dropFirst(), string: string.dropFirst(drop)) {
                    return true
                }
            }
            return false
        }
        guard let p = pattern.first, let s = string.first, p == s else { return false }
        return matchSegment(pattern: pattern.dropFirst(), string: string.dropFirst())
    }
}
```

- [ ] **Step 4: 跑测试确认通过** — 预期 `Executed 6 tests, with 0 failures`。

- [ ] **Step 5: 提交**

```bash
scripts/commit-app.sh kWise && git commit -m "feat(kWise): path glob matcher for attribution corpus (P0 Task 2)"
```

---

### Task 3: 规则模型与语料加载 `AttributionRule.swift`

**Files:**
- Create: `kWise/Features/Attribution/AttributionRule.swift`
- Test: `kWise/Tests/AttributionRuleTests.swift`

**Interfaces:**
- Consumes: Task 1 的 `AttributionOwner` / `AttributionCause` / `Reclaimability`
- Produces:
  - `struct AttributionRuleMatch: Equatable, Sendable, Codable { let pathGlob: String? }`
  - `enum AttributionOwnerSpec: Equatable, Sendable, Codable { case app(bundleID: String, appName: String?); case system; case user; case bundleDir }`
  - `struct AttributionRule: Equatable, Sendable { let id: String; let match: AttributionRuleMatch; let owner: AttributionOwnerSpec; let cause: AttributionCause; let reclaim: Reclaimability; let notesKey: String }`
  - `struct AttributionRuleCorpus: Equatable, Sendable { static let currentSchemaVersion = 1; let schemaVersion: Int; let rules: [AttributionRule]; static func load(from data: Data) throws -> AttributionRuleCorpus; init(schemaVersion: Int, rules: [AttributionRule]) }`
  - JSON 形状（Task 4 语料按此写）：
    ```json
    {"schemaVersion": 1, "rules": [{
       "id": "xcode.derived-data",
       "match": {"pathGlob": "~/Library/Developer/Xcode/DerivedData/**"},
       "owner": {"kind": "app", "bundleID": "com.apple.dt.Xcode", "appName": "Xcode"},
       "cause": "developerCache",
       "reclaim": {"kind": "recycles", "expectedDays": 30},
       "notesKey": "attr.notes.xcode.derived-data"}]}
    ```
  - owner JSON: `{"kind":"app","bundleID":...,"appName":...}` | `{"kind":"system"}` | `{"kind":"user"}` | `{"kind":"bundleDir"}`

- [ ] **Step 1: 写失败测试** — `kWise/Tests/AttributionRuleTests.swift`（本任务先写加载相关 3 例；审计用例在 Task 4 追加到同一文件）

```swift
import XCTest
@testable import kWise

final class AttributionRuleTests: XCTestCase {
    private let sampleJSON = Data(#"""
    {"schemaVersion": 1, "rules": [{
        "id": "xcode.derived-data",
        "match": {"pathGlob": "~/Library/Developer/Xcode/DerivedData/**"},
        "owner": {"kind": "app", "bundleID": "com.apple.dt.Xcode", "appName": "Xcode"},
        "cause": "developerCache",
        "reclaim": {"kind": "recycles", "expectedDays": 30},
        "notesKey": "attr.notes.xcode.derived-data"}]}
    """#.utf8)

    func testLoadSampleCorpus() throws {
        let corpus = try AttributionRuleCorpus.load(from: sampleJSON)
        XCTAssertEqual(corpus.schemaVersion, 1)
        XCTAssertEqual(corpus.rules.count, 1)
        let rule = try XCTUnwrap(corpus.rules.first)
        XCTAssertEqual(rule.id, "xcode.derived-data")
        XCTAssertEqual(rule.owner, .app(bundleID: "com.apple.dt.Xcode", appName: "Xcode"))
        XCTAssertEqual(rule.cause, .developerCache)
        XCTAssertEqual(rule.reclaim, .recycles(expectedDays: 30))
    }

    func testBundleDirOwnerDecodes() throws {
        let json = Data(#"{"schemaVersion":1,"rules":[{"id":"c","match":{"pathGlob":"~/Library/Caches/**"},"owner":{"kind":"bundleDir"},"cause":"cache","reclaim":{"kind":"recycles","expectedDays":3},"notesKey":"attr.notes.c"}]}"#.utf8)
        let corpus = try AttributionRuleCorpus.load(from: json)
        XCTAssertEqual(corpus.rules.first?.owner, .bundleDir)
    }

    func testNewerSchemaVersionThrows() {
        let json = Data(#"{"schemaVersion": 999, "rules": []}"#.utf8)
        XCTAssertThrowsError(try AttributionRuleCorpus.load(from: json)) { error in
            guard case AttributionRuleCorpus.LoadError.unsupportedSchemaVersion(let found) = error else {
                return XCTFail("expected unsupportedSchemaVersion, got \(error)")
            }
            XCTAssertEqual(found, 999)
        }
    }
}
```

- [ ] **Step 2: 跑测试确认失败** — `xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWise -only-testing:kWiseTests/AttributionRuleTests 2>&1 | tail -5`；预期编译错误。

- [ ] **Step 3: 最小实现** — `kWise/Features/Attribution/AttributionRule.swift`

```swift
// kWise/Features/Attribution/AttributionRule.swift
//
// 归因语料的模型与加载（spec §4.4）。语料是产品资产、用户可查（信任契约
// 「规则开放」的实体），因此：
// - schemaVersion 向前守卫：新版本语料 + 旧版本 App → 明确报错，不静默错配。
// - 一切文案走 xcstrings key（notesKey），语料文件本身不含自然语言句子。
import Foundation

public struct AttributionRuleMatch: Equatable, Sendable, Codable {
    public let pathGlob: String?
    public init(pathGlob: String?) { self.pathGlob = pathGlob }
}

public enum AttributionOwnerSpec: Equatable, Sendable {
    case app(bundleID: String, appName: String?)
    case system
    case user
    /// 由路径中最近的疑似 bundleID 目录解析归属（如 ~/Library/Caches/<bundleID>/）。
    case bundleDir
}

extension AttributionOwnerSpec: Codable {
    private enum CodingKeys: String, CodingKey { case kind, bundleID, appName }
    private enum Kind: String, Codable { case app, system, user, bundleDir }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .app:
            self = .app(bundleID: try container.decode(String.self, forKey: .bundleID),
                        appName: try container.decodeIfPresent(String.self, forKey: .appName))
        case .system: self = .system
        case .user: self = .user
        case .bundleDir: self = .bundleDir
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .app(let bundleID, let appName):
            try container.encode(Kind.app, forKey: .kind)
            try container.encode(bundleID, forKey: .bundleID)
            try container.encodeIfPresent(appName, forKey: .appName)
        case .system: try container.encode(Kind.system, forKey: .kind)
        case .user: try container.encode(Kind.user, forKey: .kind)
        case .bundleDir: try container.encode(Kind.bundleDir, forKey: .kind)
        }
    }
}

public struct AttributionRule: Equatable, Sendable {
    public let id: String
    public let match: AttributionRuleMatch
    public let owner: AttributionOwnerSpec
    public let cause: AttributionCause
    public let reclaim: Reclaimability
    public let notesKey: String
}

public struct AttributionRuleCorpus: Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public enum LoadError: Error, Equatable {
        case unsupportedSchemaVersion(found: Int)
    }

    public let schemaVersion: Int
    public let rules: [AttributionRule]

    public init(schemaVersion: Int, rules: [AttributionRule]) {
        self.schemaVersion = schemaVersion
        self.rules = rules
    }

    public static func load(from data: Data) throws -> AttributionRuleCorpus {
        struct Wire: Codable {
            let schemaVersion: Int
            let rules: [AttributionRule]
        }
        let wire = try JSONDecoder().decode(Wire.self, from: data)
        guard wire.schemaVersion <= currentSchemaVersion else {
            throw LoadError.unsupportedSchemaVersion(found: wire.schemaVersion)
        }
        return AttributionRuleCorpus(schemaVersion: wire.schemaVersion, rules: wire.rules)
    }
}
```

- [ ] **Step 4: 跑测试确认通过** — 预期 `Executed 3 tests, with 0 failures`。

- [ ] **Step 5: 提交**

```bash
scripts/commit-app.sh kWise && git commit -m "feat(kWise): attribution rule model + corpus loader with schema guard (P0 Task 3)"
```

---

### Task 4: 归因语料第一批 + 三语文案 + 审计

**Files:**
- Create: `kWise/Resources/attribution_rules.json`
- Modify: `kWise/Resources/Localizable.xcstrings`（新增 53 key × 3 语）
- Modify: `kWise/Tests/AttributionRuleTests.swift`（追加审计用例）

**Interfaces:**
- Consumes: Task 3 的 `AttributionRuleCorpus.load(from:)`
- Produces: 16 条规则，id 集合 = `xcode.derived-data / xcode.device-support / xcode.simulator-caches / docker.disk-image / ai.models-intelligence / wechat.files / wecom.files / feishu.files / dingtalk.files / qq.files / imessage.attachments / podcasts.downloads / proapps.render-cache / ios.backups / mail.attachments / caches.app-generic`；`notesKey` 一律 `attr.notes.<id>`；Task 5 引擎按「数组顺序 = 优先级」做 first-match-wins。

- [ ] **Step 1: 写语料** — `kWise/Resources/attribution_rules.json`

```json
{
  "schemaVersion": 1,
  "rules": [
    {"id": "xcode.derived-data",
     "match": {"pathGlob": "~/Library/Developer/Xcode/DerivedData/**"},
     "owner": {"kind": "app", "bundleID": "com.apple.dt.Xcode", "appName": "Xcode"},
     "cause": "developerCache",
     "reclaim": {"kind": "recycles", "expectedDays": 30},
     "notesKey": "attr.notes.xcode.derived-data"},
    {"id": "xcode.device-support",
     "match": {"pathGlob": "~/Library/Developer/Xcode/iOS DeviceSupport/**"},
     "owner": {"kind": "app", "bundleID": "com.apple.dt.Xcode", "appName": "Xcode"},
     "cause": "developerCache",
     "reclaim": {"kind": "recycles", "expectedDays": 90},
     "notesKey": "attr.notes.xcode.device-support"},
    {"id": "xcode.simulator-caches",
     "match": {"pathGlob": "~/Library/Developer/CoreSimulator/Caches/**"},
     "owner": {"kind": "app", "bundleID": "com.apple.dt.Xcode", "appName": "Xcode"},
     "cause": "developerCache",
     "reclaim": {"kind": "recycles", "expectedDays": 30},
     "notesKey": "attr.notes.xcode.simulator-caches"},
    {"id": "docker.disk-image",
     "match": {"pathGlob": "~/Library/Containers/com.docker.docker/Data/vms/**"},
     "owner": {"kind": "app", "bundleID": "com.docker.docker", "appName": "Docker"},
     "cause": "containerData",
     "reclaim": {"kind": "permanent"},
     "notesKey": "attr.notes.docker.disk-image"},
    {"id": "ai.models-intelligence",
     "match": {"pathGlob": "/System/Library/AssetsV2/com.apple.appleintelligence/**"},
     "owner": {"kind": "system"},
     "cause": "aiModel",
     "reclaim": {"kind": "uncertain"},
     "notesKey": "attr.notes.ai.models-intelligence"},
    {"id": "wechat.files",
     "match": {"pathGlob": "~/Library/Containers/com.tencent.xinWeChat/**"},
     "owner": {"kind": "app", "bundleID": "com.tencent.xinWeChat", "appName": "微信"},
     "cause": "chatFiles",
     "reclaim": {"kind": "uncertain"},
     "notesKey": "attr.notes.wechat.files"},
    {"id": "wecom.files",
     "match": {"pathGlob": "~/Library/Containers/com.tencent.WeWorkMac/**"},
     "owner": {"kind": "app", "bundleID": "com.tencent.WeWorkMac", "appName": "企业微信"},
     "cause": "chatFiles",
     "reclaim": {"kind": "uncertain"},
     "notesKey": "attr.notes.wecom.files"},
    {"id": "feishu.files",
     "match": {"pathGlob": "~/Library/Containers/com.electron.lark/**"},
     "owner": {"kind": "app", "bundleID": "com.electron.lark", "appName": "飞书"},
     "cause": "chatFiles",
     "reclaim": {"kind": "uncertain"},
     "notesKey": "attr.notes.feishu.files"},
    {"id": "dingtalk.files",
     "match": {"pathGlob": "~/Library/Containers/com.alibaba.DingTalk/**"},
     "owner": {"kind": "app", "bundleID": "com.alibaba.DingTalk", "appName": "钉钉"},
     "cause": "chatFiles",
     "reclaim": {"kind": "uncertain"},
     "notesKey": "attr.notes.dingtalk.files"},
    {"id": "qq.files",
     "match": {"pathGlob": "~/Library/Containers/com.tencent.qq/**"},
     "owner": {"kind": "app", "bundleID": "com.tencent.qq", "appName": "QQ"},
     "cause": "chatFiles",
     "reclaim": {"kind": "uncertain"},
     "notesKey": "attr.notes.qq.files"},
    {"id": "imessage.attachments",
     "match": {"pathGlob": "~/Library/Messages/Attachments/**"},
     "owner": {"kind": "app", "bundleID": "com.apple.iChat", "appName": "信息"},
     "cause": "chatFiles",
     "reclaim": {"kind": "uncertain"},
     "notesKey": "attr.notes.imessage.attachments"},
    {"id": "podcasts.downloads",
     "match": {"pathGlob": "~/Library/Containers/com.apple.podcasts/**"},
     "owner": {"kind": "app", "bundleID": "com.apple.podcasts", "appName": "播客"},
     "cause": "download",
     "reclaim": {"kind": "uncertain"},
     "notesKey": "attr.notes.podcasts.downloads"},
    {"id": "proapps.render-cache",
     "match": {"pathGlob": "~/Library/Application Support/ProApps/**"},
     "owner": {"kind": "app", "bundleID": "com.apple.FinalCut", "appName": "Final Cut Pro"},
     "cause": "renderCache",
     "reclaim": {"kind": "recycles", "expectedDays": 30},
     "notesKey": "attr.notes.proapps.render-cache"},
    {"id": "ios.backups",
     "match": {"pathGlob": "~/Library/Application Support/MobileSync/Backup/**"},
     "owner": {"kind": "system"},
     "cause": "iOSBackup",
     "reclaim": {"kind": "uncertain"},
     "notesKey": "attr.notes.ios.backups"},
    {"id": "mail.attachments",
     "match": {"pathGlob": "~/Library/Containers/com.apple.mail/**"},
     "owner": {"kind": "app", "bundleID": "com.apple.mail", "appName": "邮件"},
     "cause": "mailAttachment",
     "reclaim": {"kind": "uncertain"},
     "notesKey": "attr.notes.mail.attachments"},
    {"id": "caches.app-generic",
     "match": {"pathGlob": "~/Library/Caches/**"},
     "owner": {"kind": "bundleDir"},
     "cause": "cache",
     "reclaim": {"kind": "recycles", "expectedDays": 3},
     "notesKey": "attr.notes.caches.app-generic"}
  ]
}
```

- [ ] **Step 2: 写三语文案** — 运行下面的脚本把 53 个 key 合并进 `kWise/Resources/Localizable.xcstrings`（幂等：已存在的 key 不覆盖）。

```bash
python3 - <<'PYEOF'
import json

PATH = "kWise/Resources/Localizable.xcstrings"
# key: (zh-Hans, en, ja)
T = {
 "attr.ev.pathPattern": ("匹配规则路径「%@」", "Matches rule path '%@'", "ルールのパス「%@」に一致"),
 "attr.ev.ownerApp": ("属于 %@", "Owned by %@", "所有者：%@"),
 "attr.ev.ruleCitation": ("依据规则 %@", "Per rule %@", "ルール %@ に基づく"),
 "attr.ev.lastModified": ("最后修改 %@", "Last modified %@", "最終更新 %@"),
 "attr.reclaim.recycles": ("会回来（预期约 %lld 天后重建）", "Comes back (rebuilt in ≈ %lld days)", "戻ってきます（約%lld日で再生成）"),
 "attr.reclaim.resurrects": ("直接删会复活，正确做法：%@", "Comes back unless done right: %@", "そのまま削除すると復活します。正しい方法：%@"),
 "attr.reclaim.permanent": ("不会回来", "Will not come back", "戻りません"),
 "attr.reclaim.uncertain": ("不敢判，不进入清理建议", "Can't judge — excluded from suggestions", "判定できないため、クリーンアップ候補から除外"),
 "attr.cause.cache": ("缓存", "Cache", "キャッシュ"),
 "attr.cause.snapshot": ("本地快照", "Local snapshot", "ローカルスナップショット"),
 "attr.cause.developerCache": ("开发缓存", "Developer cache", "開発キャッシュ"),
 "attr.cause.aiModel": ("AI 模型", "AI models", "AIモデル"),
 "attr.cause.chatFiles": ("聊天文件", "Chat files", "チャットファイル"),
 "attr.cause.renderCache": ("渲染缓存", "Render cache", "レンダーキャッシュ"),
 "attr.cause.download": ("下载内容", "Downloads", "ダウンロード"),
 "attr.cause.archive": ("归档", "Archives", "アーカイブ"),
 "attr.cause.backup": ("备份", "Backups", "バックアップ"),
 "attr.cause.log": ("日志", "Logs", "ログ"),
 "attr.cause.mailAttachment": ("邮件附件", "Mail attachments", "メール添付ファイル"),
 "attr.cause.iOSBackup": ("iOS 备份", "iOS backups", "iOSバックアップ"),
 "attr.cause.containerData": ("应用数据", "App data", "アプリデータ"),
 "attr.cause.unknown": ("未知原因", "Unknown", "不明"),
 "attr.notes.xcode.derived-data": ("Xcode 构建中间产物，下次构建时自动重建；删除安全。", "Xcode build intermediates; rebuilt automatically on the next build. Safe to remove.", "Xcode のビルド中間生成物。次のビルドで自動的に再生成されます。削除は安全です。"),
 "attr.notes.xcode.device-support": ("连接过的 iOS 设备调试符号；再次连接设备时按需重建。", "Debug symbols for previously connected iOS devices; rebuilt on demand when the device reconnects.", "接続したことのある iOS 端末のデバッグシンボル。再接続時に必要に応じて再生成されます。"),
 "attr.notes.xcode.simulator-caches": ("模拟器运行缓存，会按需重建。", "Simulator runtime caches, rebuilt on demand.", "シミュレータの実行キャッシュ。必要に応じて再生成されます。"),
 "attr.notes.docker.disk-image": ("Docker 虚拟磁盘：删除会连带删除全部镜像与容器。这是数据删除，不是垃圾清理。", "Docker's VM disk: deleting it removes every image and container. This is data deletion, not junk cleanup.", "Docker の仮想ディスクです。削除すると全イメージとコンテナが失われます。これはデータ削除であり、ゴミ掃除ではありません。"),
 "attr.notes.ai.models-intelligence": ("系统管理的 AI 模型，下载与启用由系统设置控制；本应用不会也无法删除它。", "System-managed AI models. Downloads and enablement are controlled in System Settings; this app will not — and cannot — delete them.", "システム管理の AI モデルです。ダウンロードと有効化はシステム設定で管理され、本アプリは削除できません。"),
 "attr.notes.wechat.files": ("聊天记录与文件属于个人数据；是否清理只能由你逐项判断。", "Chat history and files are personal data; only you can judge them item by item.", "チャット履歴とファイルは個人データです。判断はご自身でのみ可能です。"),
 "attr.notes.wecom.files": ("工作聊天数据属个人数据；本应用不给删除建议。", "Work-chat data is personal data; no deletion advice is given.", "仕事用チャットのデータは個人データです。削除の提案はしません。"),
 "attr.notes.feishu.files": ("协作与聊天数据属个人数据；本应用不给删除建议。", "Collaboration and chat data are personal data; no deletion advice is given.", "コラボレーションとチャットのデータは個人データです。"),
 "attr.notes.dingtalk.files": ("办公与聊天数据属个人数据；本应用不给删除建议。", "Work and chat data are personal data; no deletion advice is given.", "業務・チャットデータは個人データです。"),
 "attr.notes.qq.files": ("聊天数据属个人数据；本应用不给删除建议。", "Chat data is personal data; no deletion advice is given.", "チャットデータは個人データです。"),
 "attr.notes.imessage.attachments": ("受系统隐私保护，通常无法直接读取；即使可见也属个人数据。", "Protected by system privacy; usually unreadable — and personal data even when visible.", "システムのプライバシー保護対象で、通常は読み取れません。読めたとしても個人データです。"),
 "attr.notes.podcasts.downloads": ("单集可重新下载，但保留与否由你决定。", "Episodes can be re-downloaded, but keeping them is your call.", "エピソードは再ダウンロードできますが、残すかはご自身で決めてください。"),
 "attr.notes.proapps.render-cache": ("视频工程的渲染文件，重新渲染时重建；删除后首次打开工程会变慢。", "Render files for video projects; rebuilt on re-render. The first open is slower afterwards.", "動画プロジェクトのレンダリングファイル。再レンダリング時に再生成されます。"),
 "attr.notes.ios.backups": ("整机备份。删除后该时间点的数据无法恢复。", "Full-device backups. Once deleted, that point in time cannot be restored.", "デバイスの完全バックアップです。削除するとその時点の状態は復元できません。"),
 "attr.notes.mail.attachments": ("邮件附件属个人数据；删除影响本地副本。", "Mail attachments are personal data; deletion affects local copies.", "メール添付ファイルは個人データです。"),
 "attr.notes.caches.app-generic": ("应用缓存。这是「删了又回来」的典型：通常数天内按需重建。", "App caches — the classic 'deletes itself back': usually rebuilt within days.", "アプリのキャッシュ。「削除すると戻ってくる」代表例です。通常は数日で再生成されます。"),
 "attr.preview.title": ("归因透视", "Space Attribution", "スペース解析"),
 "attr.preview.top": ("占用最大的项目", "Largest items", "最大の項目"),
 "attr.preview.empty": ("先运行一次扫描，这里会显示「你的空间去哪了」。", "Run a scan first — this shows where your space went.", "まずスキャンを実行すると、容量の行き先が表示されます。"),
 "attr.preview.refresh": ("重新归因", "Re-analyze", "再解析"),
 "attr.preview.reasons": ("理由", "Why", "理由"),
 "attr.refused.title": ("我不敢判的（%lld 项）", "Can't judge (%lld items)", "判定できない項目（%lld件）"),
 "attr.refused.banner": ("这些项我们判断不了安全性，所以不提供清理建议。", "We can't judge these safely, so they are excluded from suggestions.", "これらは安全に判定できないため、提案対象から除外しています。"),
 "attr.blackbox.title": ("黑盒空间（快照与系统保留）", "Unattributed space (snapshots & system)", "未帰属領域（スナップショットとシステム）"),
 "attr.blackbox.residual": ("约 %@ 未能归因到具体文件", "≈ %@ is not attributable to files", "約 %@ はファイル単位で帰属できません"),
 "attr.blackbox.snapshots": ("本地快照 %lld 个", "%lld local snapshots", "ローカルスナップショット %lld 件"),
 "attr.blackbox.unreadable": ("无法读取卷信息", "Volume info unavailable", "ボリューム情報を取得できません"),
 "attr.blackbox.insufficient": ("样本不足，暂不出数字", "Not enough data yet", "データ不足のため数値は非表示"),
 "attr.rules.title": ("归因规则", "Attribution rules", "解析ルール"),
 "attr.rules.subtitle": ("我们据以判断的完整规则，可随时核对。", "The complete rules we judge by — verify any time.", "判定に使うルールの一覧です。いつでも確認できます。"),
 "attr.rules.count": ("共 %lld 条规则", "%lld rules", "全 %lld 件のルール"),
}

with open(PATH, encoding="utf-8") as f:
    doc = json.load(f)
strings = doc.setdefault("strings", {})
added = 0
for key, (zh, en, ja) in T.items():
    entry = strings.setdefault(key, {"extractionState": "stale"})
    locs = entry.setdefault("localizations", {})
    for lang, value in (("zh-Hans", zh), ("en", en), ("ja", ja)):
        if not locs.get(lang, {}).get("stringUnit", {}).get("value"):
            locs[lang] = {"stringUnit": {"state": "translated", "value": value}}
            added += 1
with open(PATH, "w", encoding="utf-8") as f:
    json.dump(doc, f, ensure_ascii=False, indent=2, sort_keys=True)
    f.write("\n")
print(f"added {added} string units across {len(T)} keys")
PYEOF
```

Expected output: `added 159 string units across 53 keys`（53 × 3）。

- [ ] **Step 3: 追加审计用例** — 在 `kWise/Tests/AttributionRuleTests.swift` 末尾追加（语料从**源码树**读取，沿用 `MaintenanceGuidanceTests` 的 `#filePath` 定位模式，避免测试 bundle 资源问题）：

```swift
// MARK: - 语料审计（Task 4）

extension AttributionRuleTests {

    /// 语料 JSON 的源码树位置 —— 审计读源文件，保证 CI 与本机同判。
    private func corpusData() throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // kWise/
            .appendingPathComponent("Resources/attribution_rules.json")
        return try Data(contentsOf: url)
    }

    private func localizationCatalog() throws -> [String: [String: String]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Localizable.xcstrings")
        struct Catalog: Decodable { let strings: [String: [String: Unit]] }
        struct Unit: Decodable { struct SU: Decodable { let value: String? }; let stringUnit: SU? }
        let decoded = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
        var out: [String: [String: String]] = [:]
        for (key, langs) in decoded.strings {
            var values: [String: String] = [:]
            for (lang, unit) in langs {
                if let v = unit.stringUnit?.value { values[lang] = v }
            }
            out[key] = values
        }
        return out
    }

    func testCorpusIntegrity() throws {
        let corpus = try AttributionRuleCorpus.load(from: try corpusData())
        XCTAssertEqual(corpus.schemaVersion, AttributionRuleCorpus.currentSchemaVersion)
        XCTAssertGreaterThanOrEqual(corpus.rules.count, 16, "第一批语料不得少于 16 条")
        let ids = corpus.rules.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "规则 id 必须唯一")
        let globs = corpus.rules.compactMap(\.match.pathGlob)
        XCTAssertEqual(Set(globs).count, globs.count, "重复 glob = 死规则")
        for rule in corpus.rules {
            XCTAssertFalse(rule.id.isEmpty)
            XCTAssertNotNil(rule.match.pathGlob, "P0 语料全部为路径规则")
            XCTAssertEqual(rule.notesKey, "attr.notes.\(rule.id)",
                           "notesKey 必须遵循 attr.notes.<id> 约定")
        }
        // 优先级：具体规则必须在通配的 caches.app-generic 之前（first-match-wins）。
        let genericIndex = try XCTUnwrap(ids.firstIndex(of: "caches.app-generic"))
        for specific in ["wechat.files", "qq.files", "docker.disk-image"] {
            let index = try XCTUnwrap(ids.firstIndex(of: specific))
            XCTAssertLessThan(index, genericIndex,
                              "\(specific) 必须排在通配规则之前，否则永不被命中")
        }
    }

    func testEveryRuleCopyIsTrilingual() throws {
        let corpus = try AttributionRuleCorpus.load(from: try corpusData())
        let catalog = try localizationCatalog()
        var required = corpus.rules.map(\.notesKey)
        required += ["attr.ev.pathPattern", "attr.ev.ownerApp",
                     "attr.ev.ruleCitation", "attr.ev.lastModified"]
        for key in required {
            let langs = try XCTUnwrap(catalog[key], "missing xcstrings key \(key)")
            for lang in ["en", "zh-Hans", "ja"] {
                XCTAssertNotNil(langs[lang], "\(key) 缺少 \(lang) 译文")
            }
        }
    }
}
```

- [ ] **Step 4: 跑测试确认通过** — `xcodebuild test ... -only-testing:kWiseTests/AttributionRuleTests`；预期 `Executed 5 tests`（3 旧 + 2 新）全绿。**同时**跑 `-only-testing:kWiseTests/LocalizationCompletenessTests` 确认全仓三语守卫仍绿。

- [ ] **Step 5: 提交**

```bash
scripts/commit-app.sh kWise && git commit -m "feat(kWise): attribution corpus batch-1 (16 rules) + trilingual copy + integrity audit (P0 Task 4)"
```

---

### Task 5: L0 匹配引擎 `AttributionRuleEngine.swift`

**Files:**
- Create: `kWise/Features/Attribution/AttributionRuleEngine.swift`
- Test: `kWise/Tests/AttributionRuleEngineTests.swift`

**Interfaces:**
- Consumes: Task 1 类型、Task 2 `PathGlobMatcher`、Task 3 语料；`ScanResult`（现有类型，`url/path/title/fileSize/modificationDate` 字段，init 为 `ScanResult(url:path:title:fileSize:modificationDate:cleanType:riskLevel:)`）
- Produces:
  - `struct AttributionRuleEngine: Sendable { init(corpus:homeDirectory:bundleDirOwnerResolver:); func attribute(results: [ScanResult]) -> [SpaceAttribution]; static func defaultBundleDirOwner(_ directoryName: String?) -> AttributionOwner? }`
  - 契约：语料数组顺序 = 优先级，first-match-wins；`~/` 经 `homeDirectory` 展开；未匹配 → `confidence: .refused, source: .unattributed, reclaim: .uncertain, owner: .unknown, cause: .unknown, ruleID: nil, evidence: []`；`bundleDir` 归属 = 匹配前缀之后的第一段目录名交给 resolver，nil → `.unknown`。

- [ ] **Step 1: 写失败测试** — `kWise/Tests/AttributionRuleEngineTests.swift`

```swift
import XCTest
@testable import kWise

final class AttributionRuleEngineTests: XCTestCase {
    private let home = "/Users/tester"

    /// 与语料等价的内存语料 —— 引擎测试不依赖 JSON 文件（Task 4 审计已管语料）。
    private func corpus(_ rules: [AttributionRule]) -> AttributionRuleCorpus {
        AttributionRuleCorpus(schemaVersion: 1, rules: rules)
    }

    private func rule(_ id: String, _ glob: String, owner: AttributionOwnerSpec,
                      cause: AttributionCause, reclaim: Reclaimability) -> AttributionRule {
        AttributionRule(id: id, match: AttributionRuleMatch(pathGlob: glob), owner: owner,
                        cause: cause, reclaim: reclaim, notesKey: "attr.notes.\(id)")
    }

    private func result(_ path: String, bytes: Int64,
                        modified: Date? = nil) -> ScanResult {
        ScanResult(url: URL(fileURLWithPath: path), path: path, title: "x",
                   fileSize: bytes, modificationDate: modified, cleanType: .cache)
    }

    func testDerivedDataMatchesXcodeRule() {
        let engine = AttributionRuleEngine(corpus: corpus([
            rule("xcode.derived-data", "~/Library/Developer/Xcode/DerivedData/**",
                 owner: .app(bundleID: "com.apple.dt.Xcode", appName: "Xcode"),
                 cause: .developerCache, reclaim: .recycles(expectedDays: 30)),
        ]), homeDirectory: home)
        let out = engine.attribute(results: [
            result("/Users/tester/Library/Developer/Xcode/DerivedData/App-abc/Build/x.o", bytes: 500)
        ])
        XCTAssertEqual(out.count, 1)
        let a = out[0]
        XCTAssertEqual(a.owner, .app(bundleID: "com.apple.dt.Xcode", appName: "Xcode"))
        XCTAssertEqual(a.cause, .developerCache)
        XCTAssertEqual(a.reclaim, .recycles(expectedDays: 30))
        XCTAssertEqual(a.confidence, .certain)
        XCTAssertEqual(a.source, .rule)
        XCTAssertEqual(a.ruleID, "xcode.derived-data")
        XCTAssertEqual(a.evidence.map(\.kind), [.pathPattern, .ownerApp, .ruleCitation, .lastModified])
        XCTAssertEqual(a.evidence[2].arguments, ["xcode.derived-data"])
    }

    func testBundleDirOwnerResolvedFromComponentAfterMatchedPrefix() {
        var resolved: String?
        let engine = AttributionRuleEngine(
            corpus: corpus([rule("caches.app-generic", "~/Library/Caches/**",
                                 owner: .bundleDir, cause: .cache,
                                 reclaim: .recycles(expectedDays: 3))]),
            homeDirectory: home,
            bundleDirOwnerResolver: { name in
                resolved = name
                return name.map { .app(bundleID: $0, appName: nil) }
            })
        let out = engine.attribute(results: [
            result("/Users/tester/Library/Caches/com.apple.Safari/Cache.db", bytes: 10)
        ])
        XCTAssertEqual(resolved, "com.apple.Safari", "必须取匹配前缀后的第一段")
        XCTAssertEqual(out[0].owner, .app(bundleID: "com.apple.Safari", appName: nil))
    }

    func testBundleDirFallbackToUnknownWhenResolverNil() {
        let engine = AttributionRuleEngine(
            corpus: corpus([rule("caches.app-generic", "~/Library/Caches/**",
                                 owner: .bundleDir, cause: .cache,
                                 reclaim: .recycles(expectedDays: 3))]),
            homeDirectory: home,
            bundleDirOwnerResolver: { _ in nil })
        let out = engine.attribute(results: [
            result("/Users/tester/Library/Caches/loose.file", bytes: 10)
        ])
        XCTAssertEqual(out[0].owner, .unknown)
        XCTAssertEqual(out[0].confidence, .certain, "匹配到规则仍是规则判定；owner 未知只影响 owner")
    }

    func testFirstMatchWinsByCorpusOrder() {
        let engine = AttributionRuleEngine(corpus: corpus([
            rule("specific", "~/Library/Caches/com.apple.Safari/**",
                 owner: .app(bundleID: "com.apple.Safari", appName: "Safari"),
                 cause: .cache, reclaim: .permanent),
            rule("generic", "~/Library/Caches/**",
                 owner: .bundleDir, cause: .cache, reclaim: .recycles(expectedDays: 3)),
        ]), homeDirectory: home)
        let out = engine.attribute(results: [
            result("/Users/tester/Library/Caches/com.apple.Safari/x", bytes: 1)
        ])
        XCTAssertEqual(out[0].ruleID, "specific", "语料顺序即优先级")
    }

    func testUnmatchedBigResultIsRefused() {
        let engine = AttributionRuleEngine(corpus: corpus([]), homeDirectory: home)
        let out = engine.attribute(results: [
            result("/Users/tester/mystery.bin", bytes: 999)
        ])
        let a = out[0]
        XCTAssertEqual(a.confidence, .refused)
        XCTAssertEqual(a.source, .unattributed)
        XCTAssertEqual(a.owner, .unknown)
        XCTAssertEqual(a.cause, .unknown)
        XCTAssertEqual(a.reclaim, .uncertain)
        XCTAssertTrue(a.evidence.isEmpty)
    }

    func testLastModifiedFlowsThrough() {
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let engine = AttributionRuleEngine(corpus: corpus([
            rule("xcode.derived-data", "~/Library/Developer/Xcode/DerivedData/**",
                 owner: .app(bundleID: "com.apple.dt.Xcode", appName: nil),
                 cause: .developerCache, reclaim: .recycles(expectedDays: 30)),
        ]), homeDirectory: home)
        let out = engine.attribute(results: [
            result("/Users/tester/Library/Developer/Xcode/DerivedData/x", bytes: 1, modified: date)
        ])
        XCTAssertEqual(out[0].lastModified, date)
        XCTAssertEqual(out[0].evidence.last?.kind, .lastModified)
        XCTAssertFalse(out[0].evidence.last!.arguments.isEmpty,
                       "lastModified 证据必须带格式化参数")
    }

    func testDefaultBundleDirOwner() {
        XCTAssertEqual(AttributionRuleEngine.defaultBundleDirOwner("com.apple.Safari"),
                       .app(bundleID: "com.apple.Safari", appName: nil))
        XCTAssertNil(AttributionRuleEngine.defaultBundleDirOwner("NoDots"))
        XCTAssertNil(AttributionRuleEngine.defaultBundleDirOwner(nil))
        XCTAssertNil(AttributionRuleEngine.defaultBundleDirOwner("a..b"), "空段不是合法 bundleID")
    }
}
```

- [ ] **Step 2: 跑测试确认失败** — `-only-testing:kWiseTests/AttributionRuleEngineTests`；预期编译错误。

- [ ] **Step 3: 最小实现** — `kWise/Features/Attribution/AttributionRuleEngine.swift`

```swift
// kWise/Features/Attribution/AttributionRuleEngine.swift
//
// L0 归因引擎（spec §4.5）。红线：
// - first-match-wins，语料数组顺序即优先级 —— 审计测试强制「具体规则在通配之前」。
// - 结论永远可引用：输出带 ruleID 与证据链，不存在无出处的断言。
// - 未匹配 = 诚实说不知道（.refused），绝不猜。
import Foundation

public struct AttributionRuleEngine: Sendable {
    public let corpus: AttributionRuleCorpus
    public let homeDirectory: String
    /// `bundleDir` 归属解析：输入「匹配前缀之后的第一段目录名」，nil 表示不认识。
    public let bundleDirOwnerResolver: @Sendable (String?) -> AttributionOwner?

    public init(corpus: AttributionRuleCorpus,
                homeDirectory: String,
                bundleDirOwnerResolver: @escaping @Sendable (String?) -> AttributionOwner?
                    = AttributionRuleEngine.defaultBundleDirOwner) {
        self.corpus = corpus
        self.homeDirectory = homeDirectory
        self.bundleDirOwnerResolver = bundleDirOwnerResolver
    }

    /// 疑似反向域名（如 com.apple.Safari）→ app 归属；否则 nil。
    public static func defaultBundleDirOwner(_ directoryName: String?) -> AttributionOwner? {
        guard let name = directoryName, !name.isEmpty else { return nil }
        let parts = name.split(separator: ".")
        guard parts.count >= 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return .app(bundleID: name, appName: nil)
    }

    public func attribute(results: [ScanResult]) -> [SpaceAttribution] {
        results.map { attributeOne($0) }
    }

    private func attributeOne(_ result: ScanResult) -> SpaceAttribution {
        for proposed in corpus.rules {
            guard let glob = proposed.match.pathGlob,
                  PathGlobMatcher.matches(path: result.path, glob: glob, home: homeDirectory)
            else { continue }
            return matched(proposed, result: result, glob: glob)
        }
        // 未匹配 —— 诚实拒答（spec §5 拒答清单的原料）。
        return SpaceAttribution(
            scope: .fileTree, paths: [result.path], bytes: result.fileSize,
            owner: .unknown, cause: .unknown, reclaim: .uncertain,
            confidence: .refused, source: .unattributed, ruleID: nil,
            evidence: [], lastModified: result.modificationDate)
    }

    private func matched(_ proposed: AttributionRule, result: ScanResult,
                         glob: String) -> SpaceAttribution {
        let owner = resolveOwner(proposed.owner, path: result.path, glob: glob)
        var evidence: [Evidence] = [
            Evidence(kind: .pathPattern, textKey: "attr.ev.pathPattern", arguments: [glob]),
        ]
        let ownerDisplay: String?
        switch owner {
        case .app(let bundleID, let appName):
            ownerDisplay = appName ?? bundleID
        case .system:
            ownerDisplay = "macOS"
        case .user, .unknown:
            ownerDisplay = nil
        }
        if let ownerDisplay {
            evidence.append(Evidence(kind: .ownerApp, textKey: "attr.ev.ownerApp",
                                     arguments: [ownerDisplay]))
        }
        evidence.append(Evidence(kind: .ruleCitation, textKey: "attr.ev.ruleCitation",
                                 arguments: [proposed.id]))
        if let date = result.modificationDate {
            evidence.append(Evidence(kind: .lastModified, textKey: "attr.ev.lastModified",
                                     arguments: [Self.evidenceDateFormatter.string(from: date)]))
        }
        return SpaceAttribution(
            scope: .fileTree, paths: [result.path], bytes: result.fileSize,
            owner: owner, cause: proposed.cause, reclaim: proposed.reclaim,
            confidence: .certain, source: .rule, ruleID: proposed.id,
            evidence: evidence, lastModified: result.modificationDate)
    }

    private func resolveOwner(_ spec: AttributionOwnerSpec, path: String,
                              glob: String) -> AttributionOwner {
        switch spec {
        case .app(let bundleID, let appName):
            return .app(bundleID: bundleID, appName: appName)
        case .system:
            return .system
        case .user:
            return .user
        case .bundleDir:
            let component = Self.firstComponent(afterPrefix: matchedPrefix(of: glob),
                                                in: path)
            return bundleDirOwnerResolver(component) ?? .unknown
        }
    }

    /// glob 去掉尾部 `/**` 后的稳定目录前缀（~/ 与 home 展开已在 matcher 内完成，
    /// 这里复用同一展开规则）。
    private func matchedPrefix(of glob: String) -> String {
        let expanded = PathGlobMatcher.expandTilde(glob, home: homeDirectory)
        if expanded.hasSuffix("/**") {
            return String(expanded.dropLast(3))
        }
        return expanded
    }

    private static func firstComponent(afterPrefix prefix: String, in path: String) -> String? {
        guard path.hasPrefix(prefix) else { return nil }
        let remainder = path.dropFirst(prefix.count)
        let trimmed = remainder.hasPrefix("/") ? remainder.dropFirst() : remainder
        let first = trimmed.split(separator: "/").first
        return first.map(String.init)
    }

    /// 证据参数是面向人读的字符串；用固定 ISO8601 保证测试确定性，
    /// UI 层如需本地化时间可基于 `lastModified` 重排。
    static let evidenceDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
```

- [ ] **Step 4: 跑测试确认通过** — 预期 `Executed 7 tests, with 0 failures`。

- [ ] **Step 5: 提交**

```bash
scripts/commit-app.sh kWise && git commit -m "feat(kWise): L0 attribution engine — first-match-wins + bundleDir owner + evidence chain (P0 Task 5)"
```

---

### Task 6: 卷层通道 `VolumeLayerReader.swift`

**Files:**
- Create: `kWise/Features/Attribution/VolumeLayerReader.swift`
- Create: `kWise/Tests/Fixtures/apfs_snapshots.plist`
- Test: `kWise/Tests/VolumeLayerReaderTests.swift`

**Interfaces:**
- Produces:
  - `struct APFSSnapshot: Equatable, Sendable { let name: String; let createdDate: Date? }`
  - `enum VolumeLayerError: Error, Equatable { case unreadable }`
  - `protocol VolumeCommandRunning: Sendable { func run(arguments: [String]) async -> (status: Int32, stdout: String) }`
  - `struct DiskutilRunner: VolumeCommandRunning { init(executablePath: String = "/usr/sbin/diskutil") }`
  - `struct VolumeLayerReader: Sendable { init(runner: VolumeCommandRunning = DiskutilRunner(), volumePath: String = "/"); func listSnapshots() async throws -> [APFSSnapshot]; static func parseSnapshotPlist(_ data: Data) throws -> [APFSSnapshot] }`
  - 命令：`diskutil apfs listSnapshots -plist <volumePath>`（Process 范式照抄 `SMARTReader.runDiskutilPlist`）；status != 0 或解析失败 → `VolumeLayerError.unreadable`；空数组 = 合法（无快照）。

- [ ] **Step 1: 写 fixture** — `kWise/Tests/Fixtures/apfs_snapshots.plist`（真实 `diskutil apfs listSnapshots -plist` 的代表性输出；Task 10 真机核对后如有字段出入在此修正）：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
	<dict>
		<key>Name</key>
		<string>com.apple.TimeMachine.2026-09-20-031544.local</string>
		<key>XID</key>
		<integer>1234567</integer>
		<key>Ref</key>
		<integer>89</integer>
		<key>Note</key>
		<string>THIS SNAPSHOT IS NOT PURGEABLE</string>
		<key>CreationDate</key>
		<date>2026-09-19T19:15:44Z</date>
	</dict>
	<dict>
		<key>Name</key>
		<string>com.apple.TimeMachine.2026-09-21-041002.local</string>
		<key>XID</key>
		<integer>1234568</integer>
		<key>Ref</key>
		<integer>90</integer>
	</dict>
</array>
</plist>
```

- [ ] **Step 2: 写失败测试** — `kWise/Tests/VolumeLayerReaderTests.swift`

```swift
import XCTest
@testable import kWise

final class VolumeLayerReaderTests: XCTestCase {
    /// fixture 从源码树读取（与语料审计同一 #filePath 模式）。
    private func fixtureData() throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/
            .appendingPathComponent("Fixtures/apfs_snapshots.plist")
        return try Data(contentsOf: url)
    }

    private struct StubRunner: VolumeCommandRunning {
        let status: Int32
        let output: Data
        func run(arguments: [String]) async -> (status: Int32, stdout: String) {
            (status, status == 0 ? String(data: output, encoding: .utf8) ?? "" : "")
        }
    }

    func testParseFixture() throws {
        let snapshots = try VolumeLayerReader.parseSnapshotPlist(try fixtureData())
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots[0].name, "com.apple.TimeMachine.2026-09-20-031544.local")
        XCTAssertEqual(snapshots[0].createdDate,
                       Date(timeIntervalSince1970: 1_789_855_344 - 86_400), // 见下：允许区间断言
                       "plist <date> 必须还原为 Date")
        XCTAssertNil(snapshots[1].createdDate, "无日期字段的快照必须诚实为 nil")
    }

    func testEmptyArrayIsValidNoSnapshots() throws {
        let data = Data("<plist version=\"1.0\"><array/></plist>".utf8)
        XCTAssertEqual(try VolumeLayerReader.parseSnapshotPlist(data), [])
    }

    func testNonArrayIsUnreadable() {
        let data = Data("<plist version=\"1.0\"><dict/></plist>".utf8)
        XCTAssertThrowsError(try VolumeLayerReader.parseSnapshotPlist(data)) { error in
            XCTAssertEqual(error as? VolumeLayerError, .unreadable)
        }
    }

    func testNonZeroExitIsUnreadable() async {
        let reader = VolumeLayerReader(runner: StubRunner(status: 1, output: Data()),
                                       volumePath: "/")
        do {
            _ = try await reader.listSnapshots()
            XCTFail("non-zero exit must throw")
        } catch {
            XCTAssertEqual(error as? VolumeLayerError, .unreadable)
        }
    }

    func testSuccessfulReadReturnsSnapshots() async throws {
        let reader = VolumeLayerReader(runner: StubRunner(status: 0, output: try fixtureData()),
                                       volumePath: "/")
        let snapshots = try await reader.listSnapshots()
        XCTAssertEqual(snapshots.count, 2)
    }
}
```

> 注：`testParseFixture` 中的日期断言写成「区间断言」——执行时先用
> `Date(timeIntervalSince1970:)` 打印实际值再固定，或直接改为
> `XCTAssertNotNil(snapshots[0].createdDate)` + 精确值以 fixture 为准。
> 目标是锁定「plist date → Date」的行为，不是锁定某个纪元秒。

- [ ] **Step 3: 跑测试确认失败** — `-only-testing:kWiseTests/VolumeLayerReaderTests`；预期编译错误。

- [ ] **Step 4: 最小实现** — `kWise/Features/Attribution/VolumeLayerReader.swift`

```swift
// kWise/Features/Attribution/VolumeLayerReader.swift
//
// 卷层通道（spec §4.2）：APFS 本地快照是文件扫描器看不见的黑盒大头。
// Process 范式照抄 SMARTReader.runDiskutilPlist —— 沙箱内合法（先例已在生产）。
// 红线：status != 0 或解析失败 = .unreadable，调用方必须明示，禁止 0 冒充。
import Foundation

public struct APFSSnapshot: Equatable, Sendable {
    public let name: String
    public let createdDate: Date?

    public init(name: String, createdDate: Date?) {
        self.name = name
        self.createdDate = createdDate
    }
}

public enum VolumeLayerError: Error, Equatable {
    case unreadable
}

public protocol VolumeCommandRunning: Sendable {
    func run(arguments: [String]) async -> (status: Int32, stdout: String)
}

/// 生产实现：spawn `/usr/sbin/diskutil <arguments>`。
public struct DiskutilRunner: VolumeCommandRunning {
    public let executablePath: String

    public init(executablePath: String = "/usr/sbin/diskutil") {
        self.executablePath = executablePath
    }

    public func run(arguments: [String]) async -> (status: Int32, stdout: String) {
        await withCheckedContinuation { (continuation: CheckedContinuation<(Int32, String), Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            process.terminationHandler = { terminated in
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                let payload = terminated.terminationStatus == 0
                    ? (String(data: data, encoding: .utf8) ?? "")
                    : ""
                continuation.resume(returning: (terminated.terminationStatus, payload))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: (1, ""))
            }
        }
    }
}

public struct VolumeLayerReader: Sendable {
    public let runner: VolumeCommandRunning
    public let volumePath: String

    public init(runner: VolumeCommandRunning = DiskutilRunner(), volumePath: String = "/") {
        self.runner = runner
        self.volumePath = volumePath
    }

    public func listSnapshots() async throws -> [APFSSnapshot] {
        let (status, stdout) = await runner.run(
            ["apfs", "listSnapshots", "-plist", volumePath])
        guard status == 0, let data = stdout.data(using: .utf8), !stdout.isEmpty else {
            throw VolumeLayerError.unreadable
        }
        return try Self.parseSnapshotPlist(data)
    }

    /// 解析 `diskutil apfs listSnapshots -plist` 输出。
    /// 顶层必须是数组；条目缺日期 → createdDate = nil（诚实缺省）。
    public static func parseSnapshotPlist(_ data: Data) throws -> [APFSSnapshot] {
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let topLevel = try? PropertyListSerialization.propertyList(
            from: data, options: [], format: &format),
            let entries = topLevel as? [[String: Any]]
        else { throw VolumeLayerError.unreadable }
        return entries.map { entry in
            let name = (entry["Name"] as? String)
                ?? (entry["name"] as? String)
                ?? ""
            return APFSSnapshot(name: name, createdDate: Self.date(in: entry))
        }
    }

    private static func date(in entry: [String: Any]) -> Date? {
        for key in ["CreationDate", "SnapshotCreationDate", "Snapshot Creation Date"] {
            if let date = entry[key] as? Date { return date }
            if let string = entry[key] as? String {
                if let parsed = Self.stringDateFormatter.date(from: string) { return parsed }
            }
        }
        return nil
    }

    private static let stringDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        return formatter
    }()
}
```

- [ ] **Step 5: 跑测试确认通过** — 预期 `Executed 5 tests, with 0 failures`（日期断言按注释口径固定）。

- [ ] **Step 6: 提交**

```bash
scripts/commit-app.sh kWise && git commit -m "feat(kWise): volume-layer reader — APFS snapshots via diskutil, honest unreadable state (P0 Task 6)"
```

---

### Task 7: 黑盒数学 `BlackBoxMath.swift`

**Files:**
- Create: `kWise/Features/Attribution/BlackBoxMath.swift`
- Test: `kWise/Tests/BlackBoxMathTests.swift`

**Interfaces:**
- Produces:
  - `struct BlackBoxBreakdown: Equatable, Sendable { enum Status: String, Sendable { case reconciled, negativeResidual, insufficientData }; let usedBytes: Int64?; let visibleBytes: Int64; let residualBytes: Int64; let snapshotCount: Int; let status: Status }`
  - `enum BlackBoxMath { static func reconcile(usedBytes: Int64?, visibleBytes: Int64, snapshotCount: Int) -> BlackBoxBreakdown }`
  - 契约：`usedBytes == nil` → `.insufficientData`（residual 0，**不出数字**）；`used − visible < 0` → clamp 到 0 + `.negativeResidual`；否则 `.reconciled`。

- [ ] **Step 1: 写失败测试** — `kWise/Tests/BlackBoxMathTests.swift`

```swift
import XCTest
@testable import kWise

final class BlackBoxMathTests: XCTestCase {
    func testReconciledResidual() {
        let breakdown = BlackBoxMath.reconcile(usedBytes: 1_000, visibleBytes: 700, snapshotCount: 2)
        XCTAssertEqual(breakdown.residualBytes, 300)
        XCTAssertEqual(breakdown.status, .reconciled)
        XCTAssertEqual(breakdown.snapshotCount, 2)
    }

    func testNegativeResidualClampsToZeroAndFlags() {
        // 可见文件合计超过卷用量 = 采样口径问题（快照/硬链接/时差），绝不报负数。
        let breakdown = BlackBoxMath.reconcile(usedBytes: 100, visibleBytes: 700, snapshotCount: 0)
        XCTAssertEqual(breakdown.residualBytes, 0)
        XCTAssertEqual(breakdown.status, .negativeResidual)
    }

    func testMissingUsageIsInsufficientNotZero() {
        let breakdown = BlackBoxMath.reconcile(usedBytes: nil, visibleBytes: 700, snapshotCount: 1)
        XCTAssertEqual(breakdown.status, .insufficientData)
        XCTAssertEqual(breakdown.residualBytes, 0, "拿不到数据就出 0 = 编造，禁止")
        XCTAssertEqual(breakdown.usedBytes, nil)
    }
}
```

- [ ] **Step 2: 跑测试确认失败** — `-only-testing:kWiseTests/BlackBoxMathTests`；预期编译错误。

- [ ] **Step 3: 最小实现** — `kWise/Features/Attribution/BlackBoxMath.swift`

```swift
// kWise/Features/Attribution/BlackBoxMath.swift
//
// 黑盒数学（spec §4.2 地基公式）：
//   黑盒 ≈ 卷用量 − 可见文件合计；分解 = APFS 快照(计数) + 系统保留(残差桶)
// 红线：数据缺失 → .insufficientData（residual = 0 但状态明示），
//       永远不用 0 冒充「没有黑盒」。
import Foundation

public struct BlackBoxBreakdown: Equatable, Sendable {
    public enum Status: String, Sendable {
        case reconciled
        case negativeResidual
        case insufficientData
    }

    public let usedBytes: Int64?
    public let visibleBytes: Int64
    public let residualBytes: Int64
    public let snapshotCount: Int
    public let status: Status

    public init(usedBytes: Int64?, visibleBytes: Int64,
                residualBytes: Int64, snapshotCount: Int, status: Status) {
        self.usedBytes = usedBytes
        self.visibleBytes = visibleBytes
        self.residualBytes = residualBytes
        self.snapshotCount = snapshotCount
        self.status = status
    }
}

public enum BlackBoxMath {
    public static func reconcile(usedBytes: Int64?, visibleBytes: Int64,
                                 snapshotCount: Int) -> BlackBoxBreakdown {
        guard let usedBytes else {
            return BlackBoxBreakdown(usedBytes: nil, visibleBytes: visibleBytes,
                                     residualBytes: 0, snapshotCount: snapshotCount,
                                     status: .insufficientData)
        }
        let residual = usedBytes - visibleBytes
        if residual < 0 {
            return BlackBoxBreakdown(usedBytes: usedBytes, visibleBytes: visibleBytes,
                                     residualBytes: 0, snapshotCount: snapshotCount,
                                     status: .negativeResidual)
        }
        return BlackBoxBreakdown(usedBytes: usedBytes, visibleBytes: visibleBytes,
                                 residualBytes: residual, snapshotCount: snapshotCount,
                                 status: .reconciled)
    }
}
```

- [ ] **Step 4: 跑测试确认通过** — 预期 `Executed 3 tests, with 0 failures`。

- [ ] **Step 5: 提交**

```bash
scripts/commit-app.sh kWise && git commit -m "feat(kWise): black-box math — honest residual with insufficient/negative states (P0 Task 7)"
```

---

### Task 8: 整合服务 `AttributionService.swift`

**Files:**
- Create: `kWise/Features/Attribution/AttributionService.swift`
- Test: `kWise/Tests/AttributionServiceTests.swift`

**Interfaces:**
- Consumes: Task 5 引擎、Task 6 卷层、Task 7 黑盒；`ScanCategory`（现有类型）
- Produces:
  - `struct AttributionReport: Sendable { let items: [SpaceAttribution]; let refused: [SpaceAttribution]; let unattributedBytes: Int64; let blackBox: BlackBoxBreakdown; let snapshots: [APFSSnapshot]?; let generatedAt: Date }`
  - `struct AttributionService: Sendable { static let refusedSizeThreshold: Int64; init(engine:volumeReader:rootURL:volumeUsedBytesProvider:); func attribute(categories: [ScanCategory]) async -> AttributionReport; static func live() -> AttributionService }`
  - 路由契约：匹配且 `reclaim != .uncertain` → `items`；匹配但 `.uncertain` → `refused`；未匹配且 `bytes ≥ refusedSizeThreshold(100MB)` → `refused`；未匹配且小于阈值 → 计入 `unattributedBytes`（不占清单）；`snapshots == nil` 表示卷层不可读（黑盒照算，UI 明示）。
  - `static func live()`：从 `Bundle.main` 读 `attribution_rules.json`，语料缺失 → 空语料（一切进拒答，诚实降级）。

- [ ] **Step 1: 写失败测试** — `kWise/Tests/AttributionServiceTests.swift`

```swift
import XCTest
@testable import kWise

final class AttributionServiceTests: XCTestCase {
    private let home = "/Users/tester"

    private func rule(_ id: String, _ glob: String, owner: AttributionOwnerSpec,
                      cause: AttributionCause, reclaim: Reclaimability) -> AttributionRule {
        AttributionRule(id: id, match: AttributionRuleMatch(pathGlob: glob), owner: owner,
                        cause: cause, reclaim: reclaim, notesKey: "attr.notes.\(id)")
    }

    private func result(_ path: String, bytes: Int64) -> ScanResult {
        ScanResult(url: URL(fileURLWithPath: path), path: path, title: "x",
                   fileSize: bytes, cleanType: .cache)
    }

    /// category → sub → action → results 的最小树（与生产形状一致）。
    private func category(results: [ScanResult]) -> [ScanCategory] {
        let action = ScanAction(actionID: "a", actionType: .cache, title: "a",
                                totalSize: results.reduce(0) { $0 + $1.fileSize },
                                results: results)
        let sub = ScanSubCategory(subCategoryID: "s", title: "s",
                                  totalSize: action.totalSize, actions: [action])
        return [ScanCategory(categoryID: "c", title: "c",
                             totalSize: sub.totalSize, subItems: [sub])]
    }

    private struct StubRunner: VolumeCommandRunning {
        let status: Int32
        func run(arguments: [String]) async -> (status: Int32, stdout: String) {
            (status, status == 0 ? "<plist version=\"1.0\"><array/></plist>" : "")
        }
    }

    private func makeService(rules: [AttributionRule],
                             used: Int64?,
                             snapshotStatus: Int32 = 0) -> AttributionService {
        AttributionService(
            engine: AttributionRuleEngine(corpus: AttributionRuleCorpus(schemaVersion: 1, rules: rules),
                                          homeDirectory: home),
            volumeReader: VolumeLayerReader(runner: StubRunner(status: snapshotStatus)),
            volumeUsedBytesProvider: { used })
    }

    func testRoutingItemsRefusedAndUnattributed() async {
        let service = makeService(rules: [
            rule("xcode.derived-data", "~/Library/Developer/Xcode/DerivedData/**",
                 owner: .app(bundleID: "com.apple.dt.Xcode", appName: "Xcode"),
                 cause: .developerCache, reclaim: .recycles(expectedDays: 30)),
            rule("wechat.files", "~/Library/Containers/com.tencent.xinWeChat/**",
                 owner: .app(bundleID: "com.tencent.xinWeChat", appName: "微信"),
                 cause: .chatFiles, reclaim: .uncertain),
        ], used: 10_000)
        let report = await service.attribute(categories: category(results: [
            result("/Users/tester/Library/Developer/Xcode/DerivedData/x", bytes: 300),   // → items
            result("/Users/tester/Library/Containers/com.tencent.xinWeChat/f", bytes: 200), // → refused
            result("/Users/tester/mystery-huge.bin", bytes: 500_000_000),                // → refused（≥阈值）
            result("/Users/tester/small-orphan.bin", bytes: 10),                         // → unattributedBytes
        ]))
        XCTAssertEqual(report.items.count, 1)
        XCTAssertEqual(report.items.first?.ruleID, "xcode.derived-data")
        XCTAssertEqual(report.refused.count, 2)
        XCTAssertTrue(report.refused.allSatisfy { $0.reclaim == .uncertain })
        XCTAssertEqual(report.unattributedBytes, 10)
    }

    func testBlackBoxReconcilesWithVisibleSum() async {
        let service = makeService(rules: [], used: 1_000)
        let report = await service.attribute(categories: category(results: [
            result("/Users/tester/a", bytes: 300),
            result("/Users/tester/b", bytes: 200),
        ]))
        XCTAssertEqual(report.blackBox.visibleBytes, 500)
        XCTAssertEqual(report.blackBox.residualBytes, 500)
        XCTAssertEqual(report.blackBox.status, .reconciled)
    }

    func testSnapshotCountFlowsIntoBlackBox() async {
        let service = makeService(rules: [], used: 1_000)
        let report = await service.attribute(categories: category(results: []))
        XCTAssertEqual(report.blackBox.snapshotCount, 0, "空数组 = 无快照，合法")
        XCTAssertNotNil(report.snapshots)
    }

    func testUnreadableVolumeLeavesSnapshotsNil() async {
        let service = makeService(rules: [], used: 1_000, snapshotStatus: 1)
        let report = await service.attribute(categories: category(results: []))
        XCTAssertNil(report.snapshots, "读取失败必须显式为 nil，禁止 [] 冒充")
    }

    func testFlattenWalksWholeTree() async {
        let deep = result("/Users/tester/deep", bytes: 5)
        let action = ScanAction(actionID: "a", actionType: .cache, title: "a",
                                results: [result("/Users/tester/shallow", bytes: 3)])
        let sub = ScanSubCategory(subCategoryID: "s", title: "s",
                                  directResults: [deep], showAction: true, actions: [action])
        let service = makeService(rules: [], used: nil)
        let report = await service.attribute(categories: [
            ScanCategory(categoryID: "c", title: "c", subItems: [sub])
        ])
        XCTAssertEqual(report.blackBox.visibleBytes, 8, "action.results 与 directResults 都要走到")
    }
}
```

- [ ] **Step 2: 跑测试确认失败** — `-only-testing:kWiseTests/AttributionServiceTests`；预期编译错误。

- [ ] **Step 3: 最小实现** — `kWise/Features/Attribution/AttributionService.swift`

```swift
// kWise/Features/Attribution/AttributionService.swift
//
// 归因整合（spec §4.3）：文件层（引擎）+ 卷层（diskutil）+ 黑盒数学 → 一份报告。
// 红线：只描述，不执行；未匹配的大项进拒答清单，小项并入残差（不刷屏）。
import Foundation

public struct AttributionReport: Sendable {
    /// 已归因且可给出可回收性判定（不含 .uncertain）。
    public let items: [SpaceAttribution]
    /// 拒答清单：匹配到规则但「不敢判」的 + 未匹配的大项。
    public let refused: [SpaceAttribution]
    /// 未匹配且小于阈值的小项合计 —— 并入黑盒叙事，不逐条列。
    public let unattributedBytes: Int64
    public let blackBox: BlackBoxBreakdown
    /// nil = 卷层不可读（spec §7 降级：明示，禁止 [] 冒充）。
    public let snapshots: [APFSSnapshot]?
    public let generatedAt: Date
}

public struct AttributionService: Sendable {
    /// 未匹配项进入拒答清单的大小门槛 —— 小于它不值得打扰用户。
    public static let refusedSizeThreshold: Int64 = 100 * 1024 * 1024

    public let engine: AttributionRuleEngine
    public let volumeReader: VolumeLayerReader?
    public let rootURL: URL
    public let volumeUsedBytesProvider: @Sendable () -> Int64?

    public init(engine: AttributionRuleEngine,
                volumeReader: VolumeLayerReader? = VolumeLayerReader(),
                rootURL: URL = URL(fileURLWithPath: "/"),
                volumeUsedBytesProvider: @escaping @Sendable () -> Int64?
                    = AttributionService.systemVolumeUsedBytes) {
        self.engine = engine
        self.volumeReader = volumeReader
        self.rootURL = rootURL
        self.volumeUsedBytesProvider = volumeUsedBytesProvider
    }

    /// 生产装配：语料来自 App 包。语料缺失 → 空语料（一切进拒答，诚实降级）。
    public static func live() -> AttributionService {
        let corpus = Bundle.main.url(forResource: "attribution_rules", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? AttributionRuleCorpus.load(from: $0) }
            ?? AttributionRuleCorpus(schemaVersion: 1, rules: [])
        return AttributionService(engine: AttributionRuleEngine(
            corpus: corpus, homeDirectory: NSHomeDirectory()))
    }

    public func attribute(categories: [ScanCategory]) async -> AttributionReport {
        var results: [ScanResult] = []
        for category in categories {
            Self.flatten(category, into: &results)
        }
        let visibleBytes = results.reduce(Int64(0)) { $0 + $1.fileSize }

        var items: [SpaceAttribution] = []
        var refused: [SpaceAttribution] = []
        var unattributedBytes: Int64 = 0
        for attribution in engine.attribute(results: results) {
            switch (attribution.confidence, attribution.reclaim) {
            case (.certain, .uncertain):
                refused.append(attribution)
            case (.certain, _):
                items.append(attribution)
            default:
                if attribution.bytes >= Self.refusedSizeThreshold {
                    refused.append(attribution)
                } else {
                    unattributedBytes += attribution.bytes
                }
            }
        }

        let snapshots: [APFSSnapshot]?
        if let volumeReader {
            snapshots = try? await volumeReader.listSnapshots()
        } else {
            snapshots = nil
        }
        let blackBox = BlackBoxMath.reconcile(
            usedBytes: volumeUsedBytesProvider(),
            visibleBytes: visibleBytes,
            snapshotCount: snapshots?.count ?? 0)

        return AttributionReport(items: items, refused: refused,
                                 unattributedBytes: unattributedBytes,
                                 blackBox: blackBox, snapshots: snapshots,
                                 generatedAt: Date())
    }

    /// 纯内存后序遍历 —— 不触发任何文件系统调用（spec §4.3 只读接缝）。
    static func flatten(_ node: any ScanTreeNode, into results: inout [ScanResult]) {
        if let result = node as? ScanResult {
            results.append(result)
        }
        for child in node.children {
            flatten(child, into: &results)
        }
    }

    /// 卷用量 = 总容量 − 「重要用途可用」（含 purgeable 口径，Apple 文档语义）。
    static func systemVolumeUsedBytes() -> Int64? {
        let values = try? rootURL.resourceValues(forKeys: [
            .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
        ])
        guard let total = values?.volumeTotalCapacity,
              let available = values?.volumeAvailableCapacityForImportantUsage else {
            return nil
        }
        return Int64(total) - available
    }
}
```

- [ ] **Step 4: 跑测试确认通过** — 预期 `Executed 5 tests, with 0 failures`。

- [ ] **Step 5: 提交**

```bash
scripts/commit-app.sh kWise && git commit -m "feat(kWise): attribution service — routing, black box integration, live() assembly (P0 Task 8)"
```

---

### Task 9: 文案装配 + 规则可查页 + 验证面 + 接线

**Files:**
- Create: `kWise/Features/Attribution/AttributionCopy.swift`
- Create: `kWise/Features/Attribution/AttributionRulesView.swift`
- Create: `kWise/Features/Attribution/AttributionPreviewView.swift`
- Modify: `kWise/App/AppState.swift:34`（`NavigationItem` 枚举加 `case attribution = "attribution"`；`:47-53` `isToolboxTool` 加 `.attribution`）
- Modify: `kWise/App/RootView.swift:206-225`（分发 switch 加 case；`:139` 附近 rebind categories）
- Modify: `kWise/Features/Toolbox/ToolboxView.swift:25`（加第 10 张卡）
- Test: `kWise/Tests/AttributionRuleEngineTests.swift`（追加 VM 用例，或新建 `AttributionViewTests.swift`）

**Interfaces:**
- Consumes: Task 8 `AttributionReport` / `AttributionService.live()`；Task 3 语料
- Produces:
  - `enum AttributionCopy { static func causeLabel(_:) -> String; static func reclaimLabel(_:) -> String; static func evidenceText(_ Evidence) -> String; static func ownerLabel(_ AttributionOwner) -> String }`
  - `@MainActor final class AttributionRulesViewModel: ObservableObject { private(set) var rows: [AttributionRuleRow]; func load(corpus: AttributionRuleCorpus) }`
  - `struct AttributionRuleRow: Equatable, Identifiable { let id: String; let pathGlob: String; let ownerText: String; let causeText: String; let reclaimText: String; let notesText: String }`
  - `@MainActor final class AttributionPreviewViewModel: ObservableObject { init(service: AttributionService); func rebindCategories(_ provider: @escaping () -> [ScanCategory]); func refresh() async; var topItems: [SpaceAttribution] }`
- 本地化补丁（Task 4 脚本漏了 owner 兜底两 key，本任务先补进 xcstrings）：
  - `attr.owner.user`: ("用户文件", "User files", "ユーザーファイル")
  - `attr.owner.unknown`: ("未知归属", "Unknown owner", "帰属不明")

- [ ] **Step 1: 补两个 owner key** — 复用 Task 4 的合并脚本模式，把上面两条加进 `Localizable.xcstrings`（幂等合并），随后跑 `-only-testing:kWiseTests/LocalizationCompletenessTests` 确认绿。

- [ ] **Step 2: 写失败测试** — `kWise/Tests/AttributionViewTests.swift`

```swift
import XCTest
@testable import kWise

@MainActor
final class AttributionViewTests: XCTestCase {
    func testRulesViewModelFormatsRows() {
        let corpus = AttributionRuleCorpus(schemaVersion: 1, rules: [
            AttributionRule(id: "wechat.files",
                            match: AttributionRuleMatch(
                                pathGlob: "~/Library/Containers/com.tencent.xinWeChat/**"),
                            owner: .app(bundleID: "com.tencent.xinWeChat", appName: "微信"),
                            cause: .chatFiles, reclaim: .uncertain,
                            notesKey: "attr.notes.wechat.files"),
        ])
        let viewModel = AttributionRulesViewModel()
        viewModel.load(corpus: corpus)
        XCTAssertEqual(viewModel.rows.count, 1)
        let row = viewModel.rows[0]
        XCTAssertEqual(row.id, "wechat.files")
        XCTAssertEqual(row.ownerText, "微信")
        XCTAssertFalse(row.causeText.isEmpty)
        XCTAssertFalse(row.reclaimText.isEmpty)
        XCTAssertFalse(row.notesText.isEmpty, "notes 必须走 xcstrings 装配，不许空串")
    }

    func testPreviewVMSortsTopItemsByBytes() async {
        var calls = 0
        let engine = AttributionRuleEngine(corpus: AttributionRuleCorpus(schemaVersion: 1, rules: [
            AttributionRule(id: "caches.app-generic",
                            match: AttributionRuleMatch(pathGlob: "~/Library/Caches/**"),
                            owner: .bundleDir, cause: .cache,
                            reclaim: .recycles(expectedDays: 3), notesKey: "attr.notes.caches.app-generic"),
        ]), homeDirectory: "/Users/tester")
        let service = AttributionService(engine: engine, volumeReader: nil,
                                         rootURL: URL(fileURLWithPath: "/Users/tester"),
                                         volumeUsedBytesProvider: { 9_999 })
        let viewModel = AttributionPreviewViewModel(service: service)
        viewModel.rebindCategories {
            calls += 1
            let action = ScanAction(actionID: "a", actionType: .cache, title: "a", results: [
                ScanResult(url: URL(fileURLWithPath: "/Users/tester/Library/Caches/big"),
                           path: "/Users/tester/Library/Caches/big", title: "big",
                           fileSize: 900, cleanType: .cache),
                ScanResult(url: URL(fileURLWithPath: "/Users/tester/Library/Caches/small"),
                           path: "/Users/tester/Library/Caches/small", title: "small",
                           fileSize: 100, cleanType: .cache),
            ])
            let sub = ScanSubCategory(subCategoryID: "s", title: "s", actions: [action])
            return [ScanCategory(categoryID: "c", title: "c", subItems: [sub])]
        }
        await viewModel.refresh()
        XCTAssertEqual(calls, 1, "refresh 恰好消费一次 provider")
        XCTAssertEqual(viewModel.topItems.count, 2)
        XCTAssertEqual(viewModel.topItems.first?.bytes, 900, "按字节降序")
        XCTAssertEqual(viewModel.report?.blackBox.status, .reconciled)
    }

    func testEvidenceTextContainsArguments() {
        let text = AttributionCopy.evidenceText(
            Evidence(kind: .ruleCitation, textKey: "attr.ev.ruleCitation",
                     arguments: ["wechat.files"]))
        XCTAssertTrue(text.contains("wechat.files"), "证据文本必须带上参数（可引用）")
    }
}
```

- [ ] **Step 3: 跑测试确认失败** — `-only-testing:kWiseTests/AttributionViewTests`；预期编译错误。

- [ ] **Step 4: 实现** — 三个新文件：

`kWise/Features/Attribution/AttributionCopy.swift`

```swift
// kWise/Features/Attribution/AttributionCopy.swift
//
// 归因文案装配：唯一允许产出自然语言的地方，全部走 xcstrings key。
// 文案红线由 AttributionCopyAuditTests 守卫（Task 10）。
import Foundation

enum AttributionCopy {
    static func causeLabel(_ cause: AttributionCause) -> String {
        String(localized: String.LocalizationValue("attr.cause.\(cause.rawValue)"))
    }

    static func reclaimLabel(_ reclaim: Reclaimability) -> String {
        switch reclaim {
        case .recycles(let days):
            String(format: String(localized: String.LocalizationValue("attr.reclaim.recycles")),
                   days)
        case .resurrects(let via):
            String(format: String(localized: String.LocalizationValue("attr.reclaim.resurrects")),
                   via)
        case .permanent:
            String(localized: String.LocalizationValue("attr.reclaim.permanent"))
        case .uncertain:
            String(localized: String.LocalizationValue("attr.reclaim.uncertain"))
        }
    }

    static func evidenceText(_ evidence: Evidence) -> String {
        String(format: String(localized: String.LocalizationValue(evidence.textKey)),
               arguments: evidence.arguments)
    }

    static func ownerLabel(_ owner: AttributionOwner) -> String {
        switch owner {
        case .app(_, let appName):
            return appName ?? ownerBundleID(owner)
        case .system:
            return "macOS"
        case .user:
            return String(localized: String.LocalizationValue("attr.owner.user"))
        case .unknown:
            return String(localized: String.LocalizationValue("attr.owner.unknown"))
        }
    }

    private static func ownerBundleID(_ owner: AttributionOwner) -> String {
        if case .app(let bundleID, _) = owner { return bundleID }
        return ""
    }
}
```

`kWise/Features/Attribution/AttributionRulesView.swift`

```swift
// kWise/Features/Attribution/AttributionRulesView.swift
//
// 规则可查页（spec §5「规则开放」实体）：把 attribution_rules.json 渲染成人话。
// 用户能逐条看到我们据以判断的规则 —— 对抗「黑盒清理」的第一手证据。
import SwiftUI

struct AttributionRuleRow: Equatable, Identifiable {
    let id: String
    let pathGlob: String
    let ownerText: String
    let causeText: String
    let reclaimText: String
    let notesText: String
}

@MainActor
final class AttributionRulesViewModel: ObservableObject {
    @Published private(set) var rows: [AttributionRuleRow] = []

    func load(corpus: AttributionRuleCorpus) {
        rows = corpus.rules.map { rule in
            let glob = rule.match.pathGlob ?? ""
            let ownerText: String
            switch rule.owner {
            case .app(_, let appName): ownerText = appName ?? "bundleID"
            case .system: ownerText = "macOS"
            case .user: ownerText = AttributionCopy.ownerLabel(.user)
            case .bundleDir: ownerText = AttributionCopy.ownerLabel(.unknown)
            }
            return AttributionRuleRow(
                id: rule.id, pathGlob: glob, ownerText: ownerText,
                causeText: AttributionCopy.causeLabel(rule.cause),
                reclaimText: AttributionCopy.reclaimLabel(rule.reclaim),
                notesText: String(localized: String.LocalizationValue(rule.notesKey)))
        }
    }
}

struct AttributionRulesView: View {
    @StateObject private var viewModel = AttributionRulesViewModel()
    private let corpus: AttributionRuleCorpus

    init(corpus: AttributionRuleCorpus) {
        self.corpus = corpus
    }

    var body: some View {
        List {
            Section {
                Text("attr.rules.subtitle", tableName: nil)
                    .font(AppFont.footnote)
                    .foregroundStyle(Color.textSecondary)
            }
            ForEach(viewModel.rows) { row in
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(row.notesText)
                        .font(AppFont.body)
                    Text(row.pathGlob)
                        .font(AppFont.caption1.monospaced())
                        .foregroundStyle(Color.textSecondary)
                    HStack(spacing: AppSpacing.sm) {
                        Text(row.causeText)
                        Text(row.reclaimText)
                        Text(row.ownerText)
                    }
                    .font(AppFont.caption1)
                    .foregroundStyle(Color.textSecondary)
                }
                .padding(.vertical, AppSpacing.xs)
            }
        }
        .navigationTitle(Text("attr.rules.title"))
        .onAppear { viewModel.load(corpus: corpus) }
    }
}
```

`kWise/Features/Attribution/AttributionPreviewView.swift`

```swift
// kWise/Features/Attribution/AttributionPreviewView.swift
//
// P0 验证面（TestFlight 北极星）：黑盒卡 + Top 项（理由可展开）+ 拒答清单。
// 刻意朴素 —— P1 的解剖视图会整体替换它；这里只承载「为什么」满意度的验证。
import SwiftUI

@MainActor
final class AttributionPreviewViewModel: ObservableObject {
    @Published private(set) var report: AttributionReport?
    @Published private(set) var isLoading = false

    private let service: AttributionService
    private var categoriesProvider: (() -> [ScanCategory])?

    init(service: AttributionService) {
        self.service = service
    }

    /// RootView 在 onAppear 注入（沿用 spaceMapViewModel.rebindRoots 模式）。
    func rebindCategories(_ provider: @escaping () -> [ScanCategory]) {
        categoriesProvider = provider
    }

    func refresh() async {
        guard let categoriesProvider, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        report = await service.attribute(categories: categoriesProvider())
    }

    var topItems: [SpaceAttribution] {
        (report?.items ?? []).sorted { $0.bytes > $1.bytes }.prefix(20).map { $0 }
    }

    var refusedItems: [SpaceAttribution] {
        (report?.refused ?? []).sorted { $0.bytes > $1.bytes }
    }
}

struct AttributionPreviewView: View {
    @StateObject private var viewModel: AttributionPreviewViewModel
    @State private var rulesCorpus: AttributionRuleCorpus?

    init(viewModel: AttributionPreviewViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            if let report = viewModel.report {
                blackBoxCard(report.blackBox)
                if report.snapshots == nil {
                    Text("attr.blackbox.unreadable")
                        .font(AppFont.footnote)
                        .foregroundStyle(Color.textSecondary)
                }
                Section(Text("attr.preview.top")) {
                    ForEach(viewModel.topItems) { item in
                        attributionRow(item)
                    }
                }
                Section(Text("attr.refused.title", viewModel.refusedItems.count)) {
                    Text("attr.refused.banner")
                        .font(AppFont.footnote)
                        .foregroundStyle(Color.textSecondary)
                    ForEach(viewModel.refusedItems) { item in
                        attributionRow(item)
                    }
                }
                if let corpus = rulesCorpus {
                    Section {
                        NavigationLink {
                            AttributionRulesView(corpus: corpus)
                        } label: {
                            Text("attr.rules.title")
                        }
                    }
                }
            } else {
                Text("attr.preview.empty")
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .navigationTitle(Text("attr.preview.title"))
        .toolbar {
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Text("attr.preview.refresh")
            }
            .disabled(viewModel.isLoading)
        }
        .task { loadCorpusAndRefresh() }
    }

    private func loadCorpusAndRefresh() {
        if rulesCorpus == nil {
            rulesCorpus = (Bundle.main.url(forResource: "attribution_rules",
                                           withExtension: "json"))
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap { try? AttributionRuleCorpus.load(from: $0) }
        }
        Task { await viewModel.refresh() }
    }

    @ViewBuilder
    private func blackBoxCard(_ breakdown: BlackBoxBreakdown) -> some View {
        Section(Text("attr.blackbox.title")) {
            switch breakdown.status {
            case .reconciled:
                Text(String(
                    format: String(localized: String.LocalizationValue("attr.blackbox.residual")),
                    FileSizeFormatter.abbreviated(from: breakdown.residualBytes)))
                if breakdown.snapshotCount > 0 {
                    Text(String(
                        format: String(localized: String.LocalizationValue("attr.blackbox.snapshots")),
                        breakdown.snapshotCount))
                }
            case .negativeResidual:
                Text(String(
                    format: String(localized: String.LocalizationValue("attr.blackbox.residual")),
                    FileSizeFormatter.abbreviated(from: 0)))
            case .insufficientData:
                Text("attr.blackbox.insufficient")
            }
        }
    }

    @ViewBuilder
    private func attributionRow(_ item: SpaceAttribution) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                ForEach(Array(item.evidence.enumerated()), id: \.offset) { _, evidence in
                    Text(AttributionCopy.evidenceText(evidence))
                        .font(AppFont.footnote)
                }
                Text(item.notesText)
                    .font(AppFont.footnote)
                    .foregroundStyle(Color.textSecondary)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AttributionCopy.ownerLabel(item.owner))
                        .font(AppFont.body)
                    Text(AttributionCopy.causeLabel(item.cause))
                        .font(AppFont.caption1)
                        .foregroundStyle(Color.textSecondary)
                }
                Spacer()
                Text(FileSizeFormatter.abbreviated(from: item.bytes))
                    .font(AppFont.caption1.monospaced())
            }
        }
    }
}

extension SpaceAttribution {
    /// 行内展开的理由链尾行：规则 note（xcstrings key 装配）。
    var notesText: String {
        guard let ruleID else { return "" }
        return String(localized: String.LocalizationValue("attr.notes.\(ruleID)"))
    }
}
```

- [ ] **Step 5: 接线** — 三处修改：

`kWise/App/AppState.swift`：`NavigationItem` 枚举（`:34` 起）加 `case attribution = "attribution"`；`isToolboxTool` switch（`:47-53`）的 `.startupItems, .spaceMap, .maintenance, .assistant` 那一组里加 `.attribution`。

`kWise/Features/Toolbox/ToolboxView.swift`：栅格里加卡片（放「空间地图」之后）：

```swift
ToolboxCard(
    icon: "magnifyingglass.circle",
    title: "归因透视",
    subtitle: "你的空间去哪了",
    destination: .attribution
)
```

`kWise/App/RootView.swift`：视图分发 switch（`:206-225` 区域）加：

```swift
case .attribution:
    AttributionPreviewView(viewModel: attributionPreviewViewModel)
```

并在类顶部（`spaceMapViewModel` 声明旁）加：

```swift
@StateObject private var attributionPreviewViewModel = AttributionPreviewViewModel(
    service: .live())
```

在 `.onAppear`（`:139` `spaceMapViewModel.rebindRoots` 旁）加：

```swift
attributionPreviewViewModel.rebindCategories { scanResultsViewModel.categories }
```

- [ ] **Step 6: 跑测试 + 构建** — `-only-testing:kWiseTests/AttributionViewTests` 全绿；`xcodebuild build -workspace KraftlyWorkspace.xcworkspace -scheme kWise` 通过（确认接线的 UI 目标编译）。

- [ ] **Step 7: 提交**

```bash
scripts/commit-app.sh kWise && git commit -m "feat(kWise): attribution preview + rules inspector wired into toolbox (P0 Task 9)"
```

---

### Task 10: 文案审计 + 真机核对清单（P0 验收）

**Files:**
- Create: `kWise/Tests/AttributionCopyAuditTests.swift`
- Modify: 无产品代码（审计 + 人工核对）

**Interfaces:**
- Consumes: Task 4 的 xcstrings key、Task 9 的 `AttributionCopy`
- Produces: P0 验收（spec §8）的自动化部分 + 人工清单

- [ ] **Step 1: 写失败测试** — `kWise/Tests/AttributionCopyAuditTests.swift`

```swift
import XCTest
@testable import kWise

/// 归因模块文案审计 —— 恐吓禁语 + 诚实措辞（spec §5 / §9，审核 2.3.1(a) 防线）。
final class AttributionCopyAuditTests: XCTestCase {

    private static let bannedPhrases = [
        // 品类通用禁语（与 NewCopyAuditTests 同源口径）
        "立即清理，否则", "您的电脑已感染", "系统严重受损", "垃圾文件正在危害",
        // 归因特有禁语：绝对化承诺 / 制造恐慌
        "彻底释放", "永不复返", "一键彻底", "你的磁盘正在被吞噬", "危在旦夕",
    ]

    private func attributionSourceFiles() throws -> [URL] {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // kWise/
            .appendingPathComponent("Features/Attribution")
        let files = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "Attribution 源码目录必须可读")
        return files
    }

    func testNoScarewareInAttributionModule() throws {
        for file in try attributionSourceFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            for phrase in Self.bannedPhrases {
                XCTAssertFalse(source.contains(phrase),
                               "\(file.lastPathComponent) 含禁语「\(phrase)」")
            }
            // 零网络红线落在源码层（与 Assistant 模块同一守卫口径）。
            XCTAssertFalse(source.contains("URLSession"),
                           "\(file.lastPathComponent) must not network")
        }
    }

    /// 「不敢判」必须在三种语言里都是退让措辞 —— 这是拒答清单的诚信底线。
    func testUncertainCopyHedgesInAllLanguages() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Localizable.xcstrings")
        struct Catalog: Decodable { let strings: [String: [String: Unit]] }
        struct Unit: Decodable { struct SU: Decodable { let value: String? }; let stringUnit: SU? }
        let catalog = try JSONDecoder().decode(Catalog.self,
                                               from: Data(contentsOf: url))
        let unit = try XCTUnwrap(catalog.strings["attr.reclaim.uncertain"])
        XCTAssertTrue(try XCTUnwrap(unit["zh-Hans"]?.stringUnit?.value).contains("不敢判"))
        XCTAssertTrue(try XCTUnwrap(unit["en"]?.stringUnit?.value).contains("Can't judge"))
        XCTAssertTrue(try XCTUnwrap(unit["ja"]?.stringUnit?.value).contains("判定できない"))
    }
}
```

- [ ] **Step 2: 跑测试** — `-only-testing:kWiseTests/AttributionCopyAuditTests`；预期全绿（实现里若踩线，此处会红 —— 修实现，不改禁语表）。

- [ ] **Step 3: 真机核对清单（人工，逐项记录到 PR 描述）** — P0 验收 = spec §8 四条，对应：

1. **Top-20 全部 L0 判定**：运行 App（`Cmd+R`）→ 跑一次扫描 → 工具箱「归因透视」→ 重新归因。核对占用最大的 20 项都有 owner/cause/reclaim 与可展开理由链。语料未覆盖的（本机特有的大家伙）按真机情况**补语料规则**后重测 —— 这是「语料深度」假设的直接验证。
2. **黑盒数学闭合**：黑盒卡残差 ÷ 卷用量 < 5%（记录两个数字）；`diskutil apfs listSnapshots /` 的人工计数与卡片「本地快照 N 个」一致。**同时核对 `diskutil apfs listSnapshots -plist /` 的真实输出与 `Tests/Fixtures/apfs_snapshots.plist` 字段是否一致**（字段名有出入 → 改 fixture 与 parser，这是 Task 6 注明的已知校准点）。
3. **拒答清单诚实**：微信/未匹配大项在「我不敢判的」里，横幅文案完整显示；把 PowerScope 授权撤销后重扫 → 拒答/空态必须诚实（spec §7），不得出现「一切正常」的假象。
4. **文案审计全绿**：`AttributionCopyAuditTests` + `LocalizationCompletenessTests` + `NewCopyAuditTests` 全部通过。

- [ ] **Step 4: 提交**

```bash
scripts/commit-app.sh kWise && git commit -m "test(kWise): attribution copy audit + P0 acceptance checklist (P0 Task 10)"
```

---

### Task 11: bundle id 改名（TestFlight 前置，spec §2.3）

**Files:**
- Modify: `kWise/project.yml`（5 处 id + PRODUCT_NAME）
- Modify: `kWise/kWise.entitlements`、`kWise/kWiseWidget.entitlements`（存在则改；以 grep 为准）
- Modify: 所有含 `group.app.kraftly.sclean` / `kwise://` / `kspaceclean://` 的 Swift 文件
- Modify: `kWise/Info.plist`（CFBundleURLSchemes 如有注册）
- Modify: `CLAUDE.md`（bundle id 与产品名表述）
- Regenerate: `kWise/kWise.xcodeproj`（xcodegen）

**Interfaces:**
- Produces: `app.kraftly.klaris`（App/.widget/.finder/.tests/.uitests 五个 target 同步）、App Group `group.app.kraftly.klaris`、深链 `klaris://`

- [ ] **Step 1: 改 project.yml** — `PRODUCT_BUNDLE_IDENTIFIER` 五处（`:34/:65/:90/:115/:128`）`app.kraftly.sclean` → `app.kraftly.klaris`；`PRODUCT_NAME: kWise`（`:36`）→ `PRODUCT_NAME: Klaris`。target 名与 scheme 名（`kWise`）**不改**（模块名/Swift import 不动，测试宿主不变）。

- [ ] **Step 2: 全仓替换字符串** — 先列出命中面，再逐一替换：

```bash
grep -rn "group.app.kraftly.sclean" --include="*" kWise/ | grep -v DerivedData
grep -rn "kwise://\|kspaceclean://" --include="*" kWise/ | grep -v DerivedData
grep -rn "CFBundleURLSchemes" kWise/Info.plist kWise/Widgets/Info.plist kWise/FinderExtension/Info.plist 2>/dev/null
```

替换规则：`group.app.kraftly.sclean` → `group.app.kraftly.klaris`；`kwise://` 与 `kspaceclean://` → `klaris://`（`AppCoordinator` 的双 scheme 分支合并为一个；同步更新旁注注释）。entitlements 文件里的 App Group 数组同步改。**注意**：`app.kraftly.sclean.trashmonitor` 等 LaunchAgent plist（`kWise/Resources/com.kraftly.kspaceclean.trashmonitor.plist`）如仍在打包，一并改名或确认已废弃。

- [ ] **Step 3: 重新生成工程** — `cd kWise && xcodegen generate`。

- [ ] **Step 4: 全量验证** — `xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWise` 全绿（App Group 变更会使本地 Widget 快照/配额账本容器换新 —— App 未上架，无迁移负担）。

- [ ] **Step 5: 反向验证** — 以下命令必须零命中（DerivedData/.build 除外）：

```bash
grep -rn "app.kraftly.sclean\|kwise://\|kspaceclean://" --include="*" kWise/ CLAUDE.md | grep -v DerivedData | grep -v "\.build/"
```

- [ ] **Step 6: 同步 CLAUDE.md** — §3.0 的 bundle ID 表述改为 `app.kraftly.klaris`，产品名改为 **Klaris（明澈）**，并注明「P0 已迁移」。

- [ ] **Step 7: 提交**

```bash
scripts/commit-app.sh kWise && git add CLAUDE.md && git commit -m "chore(kWise): rename bundle id to app.kraftly.klaris + deep link klaris:// (P0 Task 11, pre-TestFlight)"
```

---

## Self-Review（已执行）

1. **Spec 覆盖**：§4.1 类型 → Task 1；§4.2 卷层+黑盒 → Task 6/7；§4.3 接缝 → Task 5/8（flatten 只读遍历，`ScanTreeNode.children` 既有协议）；§4.4 语料+规则可查 → Task 4/9；§4.5 L0 与置信度 → Task 5（L1/L2 明确不在本计划）；§5 拒答/规则开放/零网络 → Task 8/9/10；§7 降级 → Task 6（unreadable）/7（insufficient）/8（snapshots nil）各有测试；§8 验收 → Task 10；§2.3 改名 → Task 11。**有意排除**：解剖视图/预演 UI/L1/L2/旧资产清理（§3.1 停止清单）→ P1。
2. **占位符扫描**：无 TBD/TODO；所有测试与实现均给全码；Task 6 日期断言与 Task 10 fixture 校准是**显式标注的执行期校准点**，非占位。
3. **类型一致性**：`AttributionRuleCorpus.currentSchemaVersion`、`VolumeLayerError.unreadable`、`AttributionReport(items/refused/unattributedBytes/blackBox/snapshots/generatedAt)`、`refusedSizeThreshold`、`FileSizeFormatter.abbreviated(from:)`（既有）、`AppFont/AppSpacing/Color.textSecondary`（既有 DesignSystem 符号）跨任务一致；`Text("attr.refused.title", count)` 用 LocalizedStringKey + CVarArg 形式。

## 执行风险提示（给实施者）

- **fixture/schema 校准**：`apfs_snapshots.plist` 与真实 diskutil 输出可能字段有出入，Task 10 清单第 2 条是硬性核对点 —— 改 fixture+parser 不视为计划偏离。
- **语料路径真机校正**：`com.electron.lark` / `com.apple.podcasts` 等路径以真机 `ls` 为准，补正走 Task 4 语料（带规则 id 追加，不破坏审计）。
- **`volumeAvailableCapacityForImportantUsageKey`**：macOS 10.15+，语义为「重要用途可用」—— 若真机残差异常为负，先核对该值口径再改代码。

