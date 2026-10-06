# Klaris P2 — 单一主画布 UX 重构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 P0+P1 的能力装进「一镜到底」的单一主画布——~20 表面收敛到 6 个，全 App 一个清理句式（统一预演），rail 3 项，达到简洁大方、交互清楚、值得 App Store 编辑推荐的形态。

**Architecture:** 解剖画布（AnatomyView 重构）成为唯一首屏：hero 兼任扫描进度态；动态 cause 分组（找到才出现）带 per-cause 动词的就地预演按钮；「+」菜单 + 整窗拖放粉碎覆盖层收纳手动工具；分组下钻页由 ScanResultsView 四级树按 cause 切片改造；历史/设置/Onboarding 吸收散落功能。所有回收动作统一走 P1 的预演链（1:1 契约），废除 Smart Care 两层信任豁免。

**Tech Stack:** SwiftUI、Combine（扫描完成订阅）、NaturalLanguage、StoreKit 2、XCTest。

**Spec:** `docs/superpowers/specs/2026-10-06-klaris-single-canvas-ux-design.md`（§2 IA / §3 画布组件 / §4 交互统一 / §5 扫描即动作 / §6 下钻 / §7 深链 / §8 视觉 / §9 退役 / §10 分期）

## Global Constraints

- 最低系统 macOS 13.0；零网络（StoreKit 除外）
- **全 App 一个清理句式**：任何回收动作（组头就地 / hero 快捷 / 下钻勾选）→ 预演（1:1 契约）→ 确认执行；未购 → 预演可见、执行被拒 → 付费墙
- **C4 红线**：危险项永不自动进清理集；个人数据组默认不勾选
- 徽章五色语义系统贯穿全部新视图：绿 ✓ 可回收 / 蓝迁出引导 / 橙⚠注意 / 红数据·不属垃圾 / 灰不动·不敢判
- 本地化三语完整（en/zh-Hans/ja）；新文案过双层禁语审计
- 每波独立可演示：W1 末画布可演示、W2 末统一句式、W3 末新用户 3 屏内到首扫、W4 末零残留
- 测试：build-for-testing + `-only-testing:` 分批（环境 wedge）；每任务聚焦批，T9/T10 全量
- 提交：`scripts/commit-app.sh kWise`（+`git add CLAUDE.md` 当触碰）
- 实施者以**内容定位**锚点（行号漂移 ±10 属正常）；brief 代码有编译级笔误做最小修正并披露
- P1 既有契约继续有效：预演 1:1、sheet 三层作废、确认集执行、notes 拼接本地化、`snapshots == nil` 语义、买断门控（拒绝非截断）、启动权益刷新

## 现状锚点（P1 末，2026-10-06）

- `kWise/App/AppState.swift`：NavigationItem 18 case（anatomy/history/settings/scan/cleanup/smartCare/privacy/diskHealth/startupItems/appUninstall/shredder/tools/spaceMap/monthlyReport/duplicates/largeOld/photoClean/maintenance）；`railItems = [.anatomy, .scan, .tools, .cleanup, .history, .settings]`；初始 `.anatomy`；AppStateTests allCases == 18
- `kWise/App/RootView.swift`：`mainContent` 18 分支；`.onAppear` 晚绑定链（smartCare attach/useEngine、anatomy rebind、cleanup attributionLookup、diskHealth）；Paywall sheet
- `kWise/Features/Attribution/AnatomyView.swift`（~309 行）：AnatomyViewModel（groupedSections/probableItems/refusedItems/usedBytes/report）+ View（hero/DiskHealthCard/uncovered/sections/probable/refused/rulesLink）
- `kWise/Features/Cleanup/CleanupViewModel.swift`：`makeRehearsal(sizes:urls:)`、`executeConfirmedCleanup(sizes:confirmedTargets:)`、`attributionLookup`、`pendingTargets`、`isCleaning`
- `kWise/Features/SmartScan/Views/ScanResultsView.swift`：SummaryBar + CleanupConfirmSheet + 预演两段式；`ScanResultsViewModel` 四级树 + `assign(snapshot:)`
- `kWise/Features/SmartCare/`：SmartCareOrchestrator（state 7 case / start / confirm / reset）、SmartCareViewModel、SmartCareHeroView（已收缩）
- `kWise/Features/DetailPanel/DetailPanelView.swift`：三态详情 + AssistantNodePanel
- 测试硬闸：AppStateTests allCases==18 + railItems 断言；ToolTabTests；AppCoordinatorTests 深链

## File Structure

```
Create:
  kWise/Features/Anatomy/CanvasGroupCard.swift          # 组卡组件（图标/措辞行/徽章/就地清理按钮，per-cause 动词）
  kWise/Features/Anatomy/CanvasPlusMenu.swift           # 「+」菜单 + 整窗拖放粉碎覆盖层
  kWise/Features/Anatomy/GroupDrillDownView.swift       # 分组下钻页（树切片 + 节点问答 + 预演入口）
  kWise/Features/Anatomy/AnatomyScanState.swift         # hero 扫描进度态模型（Combine 订阅 hasScanning）
  kWise/Features/History/NarrativeHeader.swift          # 历史叙事头（这周回收 X GB + 打卡小字）
Delete:
  kWise/Features/Toolbox/ToolboxView.swift              # W4
  kWise/Features/SpaceMap/（整目录，SegmentBuilder 迁出保留）# W4
  kWise/Features/Cleanup/Views/CleanupContentView.swift  # W4
  kWise/Features/SmartCare/SmartCareHeroView.swift       # W4（Orchestrator/VM 保留）
  kWise/Features/SmartScan/Views/ScanResultsView.swift 的独立页形态 # W4（改造为 GroupDrillDownView 后）
  kWise/Features/Report/MonthlyReportView.swift          # W4（叙事头承接）
  kWise/Features/Privacy/PrivacyClean 相关独立页          # W4（功能迁设置）
Modify:
  AppState / RootView / AppCoordinator / AppGraph（装配收敛）
  AnatomyView（重构为主画布）/ CleanupViewModel（组过滤预演 + 快捷回收走预演）
  ScanResultsView→GroupDrillDownView 改造 / DetailPanelView / SmartCareOrchestrator（快捷回收改预演流）
  OnboardingPages（5→3 页）/ SettingsView（吸收维护+隐私+规则）
  Resources/Localizable.xcstrings（每任务新 key ×3）
  CLAUDE.md（T10）
Test:
  CanvasGroupCardTests · AnatomyScanStateTests · GroupDrillDownTests · UnifiedRehearsalPathTests ·
  NarrativeHeaderTests · OnboardingFlowTests · SurfaceRetirementAuditTests + 既有套件同步
```

---

### Task 1: rail 收敛至 3 项 + 深链终态映射

**Files:**
- Modify: `kWise/App/AppState.swift`（railItems、tooltip/iconName 保留其余 case——W4 才删）
- Modify: `kWise/App/AppCoordinator.swift`（深链终态映射：smartcare→.anatomy 已是；`kwise://health` host→.anatomy；确认 scan?path= 保持）
- Modify: `kWise/Tests/AppStateTests.swift`（railItems 断言改 3 项）、`kWise/Tests/AppCoordinatorTests.swift`（health 深链用例）
- Modify: `kWise/Resources/Localizable.xcstrings`（无新 key——nav.anatomy/history/settings 已存在）

**Interfaces:**
- Produces: `railItems = [.anatomy, .history, .settings]`；深链终态：`smartcare→.anatomy`（已）、`health→.anatomy`（新）、`history→.history`、`scan?path→.anatomy`（带 path 的文件夹模式保持现状实现）
- 其余 15 个 case 保留编译（RootView 分支不动），W4 清扫删除

- [ ] **Step 1: 失败测试** — AppStateTests railItems 断言改：

```swift
func testRailCollapsedToThree() {
    XCTAssertEqual(NavigationItem.railItems, [.anatomy, .history, .settings],
                   "单一主画布：rail 3 项（spec §2）")
}
```

AppCoordinatorTests 新增（镜像现有 `test_handleDeepLink_*` 写法）：

```swift
func testHealthDeepLinkOpensAnatomy() {
    // DiskHealthCard 已在画布上——health 深链落首屏（spec §7）。
    // 断言 handleDeepLink 后 appState.navigation == .anatomy
}
```

- [ ] **Step 2: RED**；**Step 3: 实现**（railItems 数组 + AppCoordinator `case "health"` 分支）；**Step 4: GREEN**（AppStateTests + AppCoordinatorTests + ToolTabTests）；**Step 5: 提交** `feat(kWise): rail collapsed to 3 — deep links land on canvas (P2 T1)`

---

### Task 2: 画布数据层 — CanvasGroup 模型 + CanvasScanCoordinator（扇出扫描）

**Files:**
- Create: `kWise/Features/Anatomy/CanvasGroup.swift`（模型 + 组装）
- Create: `kWise/Features/Anatomy/CanvasScanCoordinator.swift`（归因 + 三个检测器扇出）
- Test: `kWise/Tests/CanvasGroupTests.swift`、`kWise/Tests/CanvasScanCoordinatorTests.swift`

**Interfaces:**
- Consumes: `AttributionService.attribute(categories:)`（P0）；`DuplicateScanner`（kWise/Features/DuplicateFile/DuplicateScanner.swift——**先读真实 API 再接**）；`PhotoSimilarityScanner.scan(config:controller:progress:)`（PhotoClean/）；`LargeOldScanner`（LargeOldFile/）；`ToolboxGroup.map(_:strategy:scanRoots:)`（P0 重复→工具箱映射，检测组条目复用其 reason）
- Produces:
  - `enum GroupKind: Equatable { case cause(AttributionCause); case duplicates; case similarPhotos; case largeFiles }`
  - `struct CanvasEntry: Identifiable { let id: UUID; let title: String; let bytes: Int64; let badge: BadgeKind; let detail: String?; let target: CleanupTarget? }`——`enum BadgeKind { case recyclable, migrate, attention, dataNotJunk, leaveAlone }`（五色语义）
  - `struct CanvasGroup: Identifiable { let id: GroupKind; let icon: String; let title: String; let subtitle: String; let totalBytes: Int64; let entries: [CanvasEntry]; let action: GroupAction }`——`enum GroupAction { case rehearse; case guidance(text: String); case migrate; case none }`
  - `@MainActor final class CanvasScanCoordinator: ObservableObject { init(attributionService:, duplicateScanner:, photoScanner:, largeFileScanner:); func runScan(scope:) async -> CanvasReport }`；`struct CanvasReport { let groups: [CanvasGroup]; let uncovered: BlackBoxBreakdown?; let snapshots: [APFSSnapshot]?; let generatedAt: Date }`
  - 扇出顺序与进度：归因扫描（已有 AsyncStream）→ 重复 → 照片 → 大文件；每组完成即产出一个 group（画布增量出现）；检测器为 nil（未授权/关闭）时对应组跳过——**不出空组**
  - 组规则：字节为 0 或条目为空的组不出现；「我不敢判的」从 refused 派生为虚线卡数据（不占 CanvasGroup，画布单独渲染）

- [ ] **Step 1: 失败测试** — CanvasGroupTests（组组装规则：空组不出现/五色徽章映射/排序 totalBytes 降序/`uniquingKeysWith` 路径去重）+ CanvasScanCoordinatorTests（**注入 mock 检测器**——protocol 化三个 scanner 参数，验扇出顺序、单检测器 nil 跳过、全部 nil 时仅归因组）：

```swift
func testEmptyGroupsNeverAppear() {
    let group = CanvasGroupAssembler.assemble(
        kind: .duplicates, icon: "⧉", entries: [])
    XCTAssertNil(group, "空组不出现（spec §2 动态分组）")
}
func testBadgeMappingFiveColors() {
    XCTAssertEqual(CanvasEntry.badge(forReclaim: .recycles(expectedDays: 3)), .recyclable)
    XCTAssertEqual(CanvasEntry.badge(forReclaim: .resurrects(via: "tmutil")), .attention)
    XCTAssertEqual(CanvasEntry.badge(forReclaim: .permanent), .dataNotJunk)
    XCTAssertEqual(CanvasEntry.badge(forReclaim: .uncertain), .leaveAlone)
}
```

（`CanvasGroupAssembler` 为纯函数组装器——scanner 产出的中间类型 → CanvasGroup，便于不启扫描就测。）

- [ ] **Step 2: RED**；**Step 3: 实现**（先读三个 scanner 的真实签名再写适配层；重复组条目复用 `ToolboxGroup.map` 的 reason；检测器包 protocol seam 供注入）；**Step 4: GREEN**；**Step 5: 提交** `feat(kWise): canvas group model + scan coordinator fan-out (P2 T2)`

---

### Task 3: AnatomyView 重构为主画布（组卡 + 扫描进度态）

**Files:**
- Modify: `kWise/Features/Attribution/AnatomyView.swift`（重构——迁出 cause-section 旧渲染，换 CanvasGroup 卡；hero 兼任扫描进度态）
- Create: `kWise/Features/Anatomy/AnatomyScanState.swift`
- Modify: `kWise/App/RootView.swift`（anatomy 分支注入 coordinator + scanResultsViewModel 绑定）
- Modify: `kWise/Resources/Localizable.xcstrings`（进度态/组动词 key ×3）

**Interfaces:**
- Consumes: T2 `CanvasScanCoordinator`/`CanvasReport`/`CanvasGroup`；`ScanResultsViewModel.$isScanning`/`currentPath`/`progress`
- Produces:
  - `@MainActor final class AnatomyViewModel` 扩展：`@Published var canvasReport: CanvasReport?`、`@Published var scanPhase: ScanPhase`（`.idle/.scanning(progress: Double, path: String)/.done`）、`func startScan()`（调 coordinator + 订阅归因流进度）、`func bindScanViewModel(_ vm: ScanResultsViewModel)`（Combine 订阅 `isScanning` true→false 触发 report 刷新——沿用 P1 修复波机制）
  - View 结构：hero（idle=标题+构成条+按钮行；scanning=进度条+当前路径+取消）→ DiskHealthCard → uncovered 卡 → CanvasGroup 卡列表（CanvasGroupCard）→ 系统状态条 → 拒答虚线卡 → 规则链接。扫描中分组区 `.opacity(0.4)` 不清空
  - `CanvasGroupCard`（CanvasGroupCard.swift）：icon+title+subtitle 行（subtitle=诚实定性）+totalBytes+动作按钮；按钮文案/action 由 `GroupAction` 决定：`.rehearse→就地清理`、`.guidance→正确解法`（弹 tmutil 命令面板）、`.migrate→迁出引导`、`.none→无按钮`；展开态（默认展开前 2 组）显示 entries + 徽章五色

- [ ] **Step 1: 失败测试** — AnatomyScanStateTests：

```swift
@MainActor
final class AnatomyScanStateTests: XCTestCase {
    func testScanPhaseTransitions() {
        var phase = AnatomyViewModel.ScanPhase.idle
        phase = .scanning(progress: 0.4, path: "/Users/t/Library")
        if case .scanning(let p, let path) = phase {
            XCTAssertEqual(p, 0.4); XCTAssertEqual(path, "/Users/t/Library")
        } else { XCTFail("expected scanning") }
    }
    func testGroupsDimmedButNotEmptyWhileScanning() { /* report 保留断言 */ }
}
```

加 CanvasGroupCardTests（动词映射：`.rehearse→就地清理`、`.guidance→正确解法`、`.migrate→迁出引导`；五色徽章→色值符号）。

- [ ] **Step 2: RED**；**Step 3: 实现**（迁移 P1 AnatomyView 的诚实卡/证据链渲染——逐块搬运并接 CanvasGroup；hero 进度态新写）；**Step 4: GREEN**（AnatomyScanStateTests + CanvasGroupCardTests + 既有 Anatomy/Attribution 套件回归）；**Step 5: 提交** `feat(kWise): anatomy becomes the single canvas — dynamic groups, scan-in-hero, per-cause verbs (P2 T3)`

---

### Task 4: 「+」菜单 + 整窗拖放粉碎覆盖层

**Files:**
- Create: `kWise/Features/Anatomy/CanvasPlusMenu.swift`
- Modify: `kWise/Features/Attribution/AnatomyView.swift`（hero 按钮行加 Menu）+ RootView（onDrop 挂载 + 粉碎窗 sheet）
- Modify: `kWise/Features/Shredder/ShredderView.swift`（暴露「接收外部拖放 URL」入口——现拖放逻辑内聚在视图内，抽 `performDrop(urls:)` 公开方法）
- Test: `kWise/Tests/CanvasPlusMenuTests.swift`（菜单项注册 + 拖放覆盖层状态机）

**Interfaces:**
- Produces: `enum CanvasPlusMenuItem: String, CaseIterable { case shredder, spaceMapLegacy, attributionRules }`；`@MainActor final class DragToShredModel: ObservableObject { @Published var isHovering = false; func urlsDropped(_ urls: [URL]) -> Bool }`（仅当全部为普通文件时返回 true 并转发粉碎窗）；AnatomyView `.onDrop(of: [.fileURL])` 全窗挂载 + `.overlay { if dragModel.isHovering { 松开以粉碎覆盖层 } }`
- 粉碎窗入口：`graph.shredderVM()` 现有装配复用

- [ ] **Step 1: 失败测试** — 菜单枚举三项、DragToShredModel：非文件 URL 拒绝、悬停状态翻转、转发调用粉碎 VM 的 spy 记录。
- [ ] **Step 2: RED**；**Step 3: 实现**（Menu + onDrop + overlay 动画 0.2s 淡入；粉碎窗以 sheet 挂 RootView，`+` 菜单触发）；**Step 4: GREEN**；**Step 5: 提交** `feat(kWise): plus menu + window-wide drag-to-shred overlay (P2 T4)`

---

### Task 5: 统一预演 — 组头就地预演 + hero 快捷回收走预演（W2 核心）

**Files:**
- Modify: `kWise/Features/Anatomy/AnatomyView.swift`（组卡 `.rehearse` 按钮 → 组过滤预演 sheet；hero 快捷回收 → 推荐项预演）
- Modify: `kWise/Features/Cleanup/CleanupViewModel.swift`（`makeRehearsal` 支持 `filter: ((CleanupTarget) -> Bool)?` 或新增 `makeGroupRehearsal(targets:)` 直接接收 CanvasEntry targets）
- Modify: `kWise/Features/SmartCare/SmartCareOrchestrator.swift`（`confirm()` 废除——快捷回收改走预演流；`start()/computeRecommendedPicks` 保留供预演数据）
- Test: `kWise/Tests/UnifiedRehearsalPathTests.swift`

**Interfaces:**
- Consumes: T2 `CanvasGroup.entries[].target` / T4 之前实现的 P1 预演链（`makeRehearsal`/`executeConfirmedCleanup` 1:1 契约）
- Produces: **统一句式**——三入口（组头/hero/下钻）全部 → 预演 → 确认 → `executeConfirmedCleanup`
- **R-统一（binding，废除 P1 两层信任裁定）**：hero 快捷回收 = 推荐项预演（已勾选好）→ 确认执行；SmartCare 确认面板（confirmHero 的 confirm 流）退役，`confirming` 态直接呈现预演 sheet

- [ ] **Step 1: 失败测试** — UnifiedRehearsalPathTests（三入口一测一例）：

```swift
@MainActor
final class UnifiedRehearsalPathTests: XCTestCase {
    // 入口 1：组头 .rehearse —— 只含该组 entries 的 targets
    func testGroupButtonRehearsalFilteredToGroupEntries() async { /* makeRehearsal(targets: group.targets) 断言 1:1 */ }
    // 入口 2：hero 快捷回收 —— 推荐项已勾选集
    func testQuickCleanRehearsalUsesRecommendedPicks() async { /* SmartCareOrchestrator recommended → rehearsal，断言无 dangerous 项（C4）*/ }
    // 入口 3：下钻勾选 —— 选中集
    func testDrillDownRehearsalMirrorsCheckedLeaves() async { /* 沿用 P1 VM 测试模式 */ }
}
```

- [ ] **Step 2: RED**；**Step 3: 实现**：
1. `CleanupViewModel.makeRehearsal` 增加直接接收 `[CleanupTarget]` 的重载（CanvasEntry.target 直接来）
2. AnatomyView 组卡按钮 → `makeRehearsal(targets: group.entries.compactMap(\.target))` + 弹 P1 预演 sheet（复用 CleanupRehearsalSheet，标题带组名）
3. hero 快捷回收按钮 → `start()` 完成后取 `recommendedEntries` → 预演 sheet → 确认 → `executeConfirmedCleanup`；SmartCareOrchestrator 保留扫描与推荐计算，删除 `confirm()` 的直接执行（state `.confirming` 由预演 sheet 接管；`doneHero/failedHero` 保留）
4. 未购路径天然生效（P1 门控在 execute）
- [ ] **Step 4: GREEN**（UnifiedRehearsalPathTests + CleanupViewModelRehearsalTests + SmartCareOrchestratorTests 回归）；**Step 5: 提交** `feat(kWise): one cleanup sentence — group/quick/drill-down all rehearse before execute (P2 T5)`

---

### Task 6: 分组下钻页

**Files:**
- Create: `kWise/Features/Anatomy/GroupDrillDownView.swift`
- Modify: `kWise/Features/Attribution/AnatomyView.swift`（组卡点击区 → NavigationLink 进下钻；动作按钮区不触发导航）
- Modify: `kWise/Features/Assistant/AssistantNodePanel.swift`（从 DetailPanel 抽出为可复用组件——构造参数化）
- Modify: `kWise/Features/DetailPanel/DetailPanelView.swift`（改用复用组件）
- Test: `kWise/Tests/GroupDrillDownTests.swift`

**Interfaces:**
- Produces: `struct GroupDrillDownView: View { let group: CanvasGroup; let entries: [CanvasEntry]; let onRehearse: ([CleanupTarget]) -> Void }`——面包屑（← 解剖）+ 文件级列表（名称/字节/五色徽章/勾选框，默认勾选态按 badge：recyclable 勾、其余不勾）+ 节点问答区（AssistantNodePanel）+ 底部 `预演并清理`（勾选集）
- 数据：cause 组从 ScanResultsViewModel 树按 cause 过滤切片（复用 `AttributionService.flatten`）；detection 组直接用 CanvasEntry

- [ ] **Step 1: 失败测试** — 勾选默认态（recyclable 勾/dataNotJunk 不勾）+ 勾选集 → 预演 targets 1:1 + 面包屑返回保持勾选（VM 级）
- [ ] **Step 2: RED**；**Step 3: 实现**（AssistantNodePanel 参数化抽屉 + 下钻视图）；**Step 4: GREEN**（GroupDrillDownTests + AssistantAndCopyAuditTests + AccessibilityTests）；**Step 5: 提交** `feat(kWise): group drill-down — file-level control with in-place rehearsal entry (P2 T6)`

---

### Task 7: 历史叙事头 + 月报退役合并

**Files:**
- Create: `kWise/Features/History/NarrativeHeader.swift`
- Modify: `kWise/Features/History/TimelineView.swift`（叙事头替换现有头；月报的周桶/Top 文件/预测卡并成「本月」可展开区）
- Delete: `kWise/Features/Report/MonthlyReportView.swift`（数据模型 MonthlyReport.swift 保留供叙事头消费；`nav.monthlyReport` case 删除）
- Test: `kWise/Tests/NarrativeHeaderTests.swift`

**Interfaces:**
- Produces: `struct NarrativeHeaderModel { static func build(records: [CleanupHistoryItem], samples: [DiskSample]) -> (headline: String, sub: String, streakLine: String?) }`——「这周你回收 12.4 GB」+「磁盘比上周轻 6%」+「打卡 5 天 🔥」（可 nil）；文案过禁语审计

- [ ] **Step 1: 失败测试**（周聚合数字正确/空历史诚实零/打卡行 nil 安全）；**Step 2: RED**；**Step 3: 实现 + MonthlyReportView 退役（`nav.monthlyReport` case 与 RootView 分支同删）**；**Step 4: GREEN**（NarrativeHeaderTests + Timeline 既有套件）；**Step 5: 提交** `feat(kWise): narrative history header absorbs monthly report (P2 T7)`

---

### Task 8: 设置吸收 + Onboarding 3 页 + 首启自动扫描

**Files:**
- Modify: `kWise/Features/Settings/SettingsView.swift`（新增「维护」区（MaintenanceTask 引导卡迁入）、「隐私」区（浏览器痕迹等 PrivacyClean 入口）、「归因规则」行）
- Modify: `kWise/Features/Onboarding/OnboardingPages.swift`（5→3 页：欢迎/扫描三类承诺+授权合并/完成即扫）
- Modify: `kWise/App/RootView.swift`（onboarding 完成回调 → 自动触发 `anatomyViewModel.startScan()`）
- Test: `kWise/Tests/OnboardingFlowTests.swift` 同步

**Interfaces:**
- Produces: OnboardingCoordinator 3 页枚举；Onboarding 完成后 `startScan()` 一次（守卫：仅首次）

- [ ] **Step 1: 失败测试**（页数 3、完成回调触发首扫一次、二次启动不触发）；**Step 2: RED**；**Step 3: 实现**（页合并：welcome 保留、page2 扫描承诺 + PowerScope 授权合并、page3 完成即扫——P0 验收手册的三屏路径）；**Step 4: GREEN**（OnboardingFlowTests + OnboardingCoordinatorTests）；**Step 5: 提交** `feat(kWise): settings absorbs maintenance/privacy/rules — onboarding 3 pages with auto first scan (P2 T8)`

---

### Task 9: 退役清扫 + 深链终态（W4）

**Files:**
- Delete（git rm + xcodegen）: `Features/Toolbox/ToolboxView.swift`、`Features/SpaceMap/`（SegmentBuilder.swift 先迁 `Features/Anatomy/`——构成条复用其 2π 数学）、`Features/Cleanup/Views/CleanupContentView.swift`、`Features/SmartCare/SmartCareHeroView.swift`、`Features/ScanResultsView.swift` 独立页形态（GroupDrillDownView 已承接）、`Features/Report/MonthlyReportView.swift`（T7 已删则跳过）、`Features/Privacy/` 独立页（功能已在设置）
- Modify: `kWise/App/AppState.swift`（NavigationItem 收敛至 `.anatomy/.history/.settings` 3 case + AppGraph 失效工厂删除）、RootView（mainContent 3 分支）、AppCoordinator（深链终态）
- Create: `kWise/Tests/SurfaceRetirementAuditTests.swift`（源码 grep：ToolboxView/SpaceMapView/CleanupContentView/SmartCareHeroView 零残留；NavigationItem case 数 == 3）
- Test: 全量

- [ ] **Step 1: 失败审计测试**（grep 断言零残留 + case 数 3）；**Step 2: RED**；**Step 3: 删除与收敛**（每删一个文件 grep 其引用逐处清理；DiskHealthDetailView 保留为下钻深链页；ScanResultsView 的 SummaryBar/CleanupConfirmSheet 组件若被下钻复用则迁文件保留）；**Step 4: 全量测试**（wedge 分批，逐批报告）；**Step 5: 提交** `feat(kWise): retirement sweep — 20 surfaces to 6, single engine single canvas (P2 T9)`

---

### Task 10: 视觉审计 + CLAUDE.md + 收尾

**Files:**
- Modify: `CLAUDE.md`（§3.4/§3.5 按新 IA 重写、§7 P2 条目、旧表面描述清除）
- Test: 全量 + 视觉走查清单

- [ ] **Step 1: 视觉走查清单**（人工，记入报告）：深色模式全页面、空态/扫描态/完成态三态切换、最小窗口 1024×680 无裁切、禁语审计全绿
- [ ] **Step 2: CLAUDE.md 修正**（对照代码逐条）
- [ ] **Step 3: 全量测试**（579± 基线记录）
- [ ] **Step 4: 提交** `docs: CLAUDE.md single-canvas rewrite + P2 baseline (P2 T10)`

---

## Self-Review（已执行）

1. **Spec 覆盖**：§2 IA→T1/T9；§3 画布→T2/T3/T4；§4 统一预演→T5；§5 扫描即动作→T3（hero 进度态）；§6 下钻→T6；§7 深链→T1/T9；§8 视觉→T3 徽章系统+T10 走查；§9 退役→T9；Onboarding→T8；隐私/维护→T8。**P1 契约延续**在 Global Constraints 逐条列明。
2. **占位符扫描**：T5/T7/T8 的测试给足断言目标与构造说明；view-restructure 任务（T3/T6）给结构树 + 迁移源 + 差异点（P1 T5/T6 先例，sonnet 可执行）；T2 明确「先读真实 scanner API」为校准点。
3. **类型一致性**：`GroupKind/CanvasEntry/BadgeKind/CanvasGroup/GroupAction/CanvasReport/CanvasScanCoordinator.runScan(scope:)`、`AnatomyViewModel.ScanPhase`、`IntentScanAdapter`（P1 已有）跨任务一致；`CleanupViewModel.makeRehearsal` 重载与 P1 签名兼容。

## 执行说明

沿用 Subagent-Driven（用户既定）；模型：T1/T3/T4/T5/T6/T7/T8 sonnet，T2 sonnet（数据层含适配）、T9 opus（删除安全审查密度最高）或 sonnet+加强审查，T10 sonnet；最终全分支评审 opus。

