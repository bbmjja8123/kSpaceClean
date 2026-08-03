# kSift P0 Implementation Plan — 对标头部竞品补齐产品完成度

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按 Gap 文档 `2026-08-02-ksift-top-gap.md` 的 P0 清单（10 项 + 2 项收尾）补齐 kSift 产品完成度，达到与 App Store「重复文件」分类头部竞品（Gemini 2 / DFFP / Easus / CMM）对齐的可用水准。检测引擎不动，只做产品化。

**Architecture:** 延续现有 MVVM（SwiftUI → @MainActor ViewModel → actor Service → Core Data Repository）。新增能力均为轻量独立模块：FDA 探测、Vault 浏览、扫描范围预估、缩略图/图标异步缓存，不侵入检测引擎。

**Tech Stack:** Swift 5.9（严格并发）、SwiftUI、Swift Concurrency、Core Data、QuickLookThumbnailing、XcodeGen

**Design Spec:** `docs/superpowers/specs/2026-08-02-ksift-top-gap.md`

**基线:** commit `39e16e1`（kSift v1 全量已提交，94 测试通过 + 1 预存失败）

## Global Constraints

- Swift 5.9+ strict concurrency（`SWIFT_STRICT_CONCURRENCY = complete`），编译在 Xcode 14.3.1 / Swift 5.8.1 toolchain 下也要过
- macOS 13.0+ deployment target；macOS 14+ API 用 `#available` 包裹
- Bundle ID：`app.kraftly.ksift`；App Sandbox 强制；无 Privileged Helper
- **本地化（强制）**：SwiftUI 组件 prop 用 `LocalizedStringKey`；String 类型参数用 `NSLocalizedString`；新增文案必须同时写入 `kDupe/Resources/en.lproj/Localizable.strings` 和 `kDupe/Resources/zh-Hans.lproj/Localizable.strings`。Int 用 `%lld`、String 用 `%@`
- **DesignSystem（强制）**：颜色/间距/圆角用 `kFoundation` DesignSystem tokens；Empty/Loading/Error 状态用 `kFoundation` 组件，禁止 App 内重写
- **新增文件后必须重新生成工程**：`cd /Users/mengjianjun/Documents/ai/aicoding/macapp/kDupe && xcodegen generate`（project.yml sources 按目录 glob，新文件自动纳入）
- 禁止复用 Lemon 代码（Objective-C/C++ 一律不抄）
- 只做 P0 范围（Task 1-12）；P1/P2 不在本次实现
- 每个 Task 完成即跑构建 + 相关测试，不允许带红色错误进入下一个 Task

## Build & Test Commands

```bash
# 构建
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/kDupe
xcodegen generate
xcodebuild -project kSift.xcodeproj -scheme kSift -configuration Debug build

# 测试
xcodebuild -project kSift.xcodeproj -scheme kSift -configuration Debug test
```

## File Structure（新增 / 修改）

```
kDupe/
├── Detection/
│   ├── FDAChecker.swift                # [新增] P0-1 FDA 探测 + 打开系统设置
├── UI/
│   ├── Onboarding/
│   │   ├── OnboardingView.swift        # [修改] P0-1 插入权限卡
│   │   └── PermissionView.swift        # [新增] P0-1 FDA 状态 + 跳转按钮
│   ├── Scan/
│   │   ├── MainView.swift              # [修改] P0-1 扫描守卫 / P0-5 拖拽 / P0-9 范围预览
│   │   ├── ScanProgressView.swift      # [修改] P0-6 取消 + 实时信息
│   │   ├── ScanRangePreview.swift      # [新增] P0-9 预估组件
│   │   └── ScanResultView.swift        # [修改] P0-10 空结果引导
│   ├── Result/
│   │   ├── ResultView.swift            # [修改] P0-3 缩略图 / P0-4 搜索 / P0-8 排序 / P0-2 入口
│   │   ├── ResultViewModel.swift       # [修改] P0-4 searchText / P0-8 排序增强
│   │   ├── GroupDetailView.swift       # [修改] P0-3 缩略图条 / P0-8 组内排序
│   │   ├── FileRowView.swift           # [修改] P0-7 icon 异步
│   │   ├── FileIconCache.swift         # [新增] P0-7 图标缓存
│   │   ├── ThumbnailCache.swift        # [新增] P0-3 缩略图缓存
│   │   └── ThumbnailView.swift         # [新增] P0-3 缩略图组件
│   └── Vault/
│       ├── VaultView.swift             # [新增] P0-2 浏览 + 恢复
│       └── VaultViewModel.swift        # [新增] P0-2 状态管理
├── App/
│   ├── AppState.swift                  # [修改] P0-2 增加 .vault 导航
│   └── RootView.swift                  # [修改] P0-2 导航栏 Vault 入口
├── Resources/Info.plist                # [修改] P0-1 NSDesktopFolderUsageDescription
└── Resources/{en,zh-Hans}.lproj/Localizable.strings   # [修改] 全部 Task
```

---

## Task 1: P0-1 FDA 权限引导（UX）

> 对应 Gap U1。目标：新用户首启明确知道需要 Full Disk Access，未授权时扫描受限却不自知的盲区消除。

**Files:**
- Create: `kDupe/Detection/FDAChecker.swift`
- Create: `kDupe/UI/Onboarding/PermissionView.swift`
- Modify: `kDupe/UI/Onboarding/OnboardingView.swift`
- Modify: `kDupe/UI/Scan/MainView.swift`
- Modify: `kDupe/Info.plist`（加 `NSDesktopFolderUsageDescription`）
- Modify: 两个 Localizable.strings

**Interfaces:**
- `enum FDAStatus { case granted, denied, unknown }`
- `struct FDAChecker { static func status() -> FDAStatus; static func openSystemSettings() }`
  - 探测法：`FileManager.default.isReadableFile(atPath:)` 探测 FDA 保护的路径（如 `~/Library/Safari/Bookmarks.plist`、`~/Library/Mail`），任一可读即视为 granted
  - 打开设置：`NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)`
- `struct PermissionView: View` — `@Binding var fdaStatus: FDAStatus`；绿色勾「已获得完全磁盘访问权限」/ 橙色「需要完全磁盘访问权限」+ 说明 + "Open System Settings" 按钮 + "Re-check" 按钮

**Steps:**
- [ ] 新建 `FDAChecker.swift`，实现探测 + 跳转（封装成可测的纯函数，避开主线程问题）
- [ ] 新建 `PermissionView.swift`，插到 OnboardingView 的 ProfileSetupView 与 Get Started 按钮之间（权限卡，不强制阻断，可跳过）
- [ ] OnboardingView 持有 `@State fdaStatus`，onAppear 探测一次
- [ ] MainView `startScan(at:)` 与 idle 的 Start Scan 按钮调用前置守卫：`FDAChecker.status()` 非 granted 时弹非阻断横幅（带 "Open System Settings"），扫描仍可进行（沙箱目录内的结果依然有效）
- [ ] Info.plist 增加 `NSDesktopFolderUsageDescription`
- [ ] 新增 4-6 条中英文案（权限标题/说明/按钮/横幅）
- [ ] `xcodegen generate` + 构建 + 冒烟

**Acceptance:** 首启 Onboarding 出现权限卡；无 FDA 时 Start Scan 出现引导横幅；有 FDA 时全部隐藏；无硬编码文案。

---

## Task 2: P0-2 Vault 浏览 + 恢复 UI（功能）

> 对应 Gap F1/U8。目标：付费卖点落地 — 清理进 Vault 的东西用户能看、能恢复、能过期清理。

**Files:**
- Create: `kDupe/UI/Vault/VaultViewModel.swift`
- Create: `kDupe/UI/Vault/VaultView.swift`
- Modify: `kDupe/App/AppState.swift`
- Modify: `kDupe/App/RootView.swift`
- Modify: `kDupe/UI/Result/ResultView.swift`（清理成功后提供"打开保险库"入口）
- Modify: 两个 Localizable.strings

**Interfaces:**
- `@MainActor final class VaultViewModel: ObservableObject`：
  - `@Published items: [VaultItem]`、`@Published totalSize: Int64`、`@Published errorMessage: String?`、`@Published isProcessing: Bool`
  - `func load()` — `try await VaultManager().vaultItems()` + `vaultSize()`，按 `vaultedAt` 倒序
  - `func restore(_ item: VaultItem)` — `try await VaultManager().restore(itemID: item.id)`，成功后 `load()`，失败填 `errorMessage`（复用 `VaultError` 的中文文案，`VaultError` 已 Localizable）
  - `func purgeExpired()` — `try await VaultManager().deleteExpired()`
  - `func revealInFinder(_ item: VaultItem)` — `NSWorkspace.shared.activateFileViewerSelecting`
- `struct VaultView: View`：
  - 顶部 GlassPanel：标题 + 保留策略说明（30 天）+ 占用 `vaultSize` + "清理过期" 按钮
  - List（selection 无需）：行 = 文件图标 + 原名 + 原始路径 + 大小 + `vaultedAt` 日期 + 状态徽标（vaulted/restored）；行尾 "恢复" 按钮
  - 恢复冲突（`restoreTargetExists`）→ 错误 alert，提供 "在 Finder 中显示" 跳转到 vault 副本
  - Empty → 复用 `EmptyStateView`（"保险库为空"）

**Steps:**
- [ ] AppState `NavigationItem` 增加 `.vault` case（icon: `shippingbox`）
- [ ] 新建 VaultViewModel + VaultView
- [ ] RootView iconRail 增加 Vault 入口按钮
- [ ] ResultView 清理成功的 alert/toast 增加 "打开保险库" 动作（返回 `.vault`）
- [ ] 新增中英文案（标题/保留说明/清理过期/恢复/错误提示）
- [ ] 构建 + 冒烟

**Acceptance:** 清理后 Vault 列表出现条目；恢复成功文件回原位；目标已存在时提示且可选 Finder 查看；过期条目可一键清理；无硬编码文案。

---

## Task 3: P0-9 扫描前范围预览（UX）

> 对应 Gap U6。目标：点扫描前就知道"扫哪、多大"，消除盲目扫描。

**Files:**
- Create: `kDupe/UI/Scan/ScanRangePreview.swift`
- Modify: `kDupe/UI/Scan/MainView.swift`

**Interfaces:**
- `struct ScanRangePreview: View` — `let directories: [String]`，异步估算并展示：
  - 「将扫描 N 个文件夹 · 约 M 个文件 · 约 X GB」
  - 估算用 `FileManager.default.enumerator(at:...)` 轻量遍历（不 hash），上限截断 50k 文件，超出显示 `50k+`，防卡顿
  - 目录为空时显示 EmptyState 式引导 "拖入文件夹或选择目录"
- MainView idleState 在 Start Scan 按钮上方插入预览；`onAppear`/目录变化时刷新

**Steps:**
- [ ] 新建 ScanRangePreview，估算逻辑放独立 `ScanEstimator`（async，`Task` 内跑，`@State` 承接结果，带 cancel-on-disappear）
- [ ] MainView idleState 接入
- [ ] 新增中英文案（文件夹/文件/大小占位、拖入引导）
- [ ] 构建 + 冒烟

**Acceptance:** idle 时显示将扫描的范围估算；目录变化自动刷新；空目录有引导文案；大目录不卡 UI。

---

## Task 4: P0-5 拖拽目录到窗口扫描（功能+UX）

> 对应 Gap F2。目标：竞品标配的零门槛扫描入口。

**Files:**
- Modify: `kDupe/UI/Scan/MainView.swift`

**Steps:**
- [ ] idleState 外包一层支持 `.dropDestination(for: URL.self)`（或 `.onDrop(of: [.fileURL])`），拖入时调用现有 `startScan(at: path)`（文件夹被拖入时 `hasDirectoryPath == true`）
- [ ] 拖拽悬停时显示高亮边框 + "松手开始扫描" 文案；接受多目录时取第一个或合并（合并更符合竞品：按 `ProfileConfig` 多目录构造 config 后 `startScan(config:)`）
- [ ] 新增中英文案
- [ ] 构建 + 冒烟

**Acceptance:** 从 Finder 拖文件夹进窗口即开始扫描；悬停有视觉反馈；非目录不触发。

---

## Task 5: P0-6 扫描实时反馈 + 取消（UX）

> 对应 Gap F9/U2。目标：长扫描可感知、可中断；取消后干净回到 idle。

**Files:**
- Modify: `kDupe/UI/Scan/ScanProgressView.swift`
- Modify: `kDupe/UI/Scan/MainView.swift`
- Modify: `kDupe/UI/Scan/ScanViewModel.swift`
- Modify: `kDupe/Detection/ScanOrchestrator.swift`（如有低成本相位路径可带）

**Interfaces:**
- `ScanProgressView` 增加参数：`onCancel: () -> Void`，新增展示：
  - 当前目录（`progress.currentPath`，枚举期已有；其他相位无则显示"正在 \(phaseTitle)"）
  - 已发现组数（需 ScanViewModel 提供 `@Published groupsFound`，由 `.group` 事件累加）
  - 已用时间（`TimelineView`/`Timer` 驱动，从开始扫描计时）
  - 红色 "取消" 按钮 → `onCancel`
- ScanViewModel：`startScan` 时 `startDate`；`.group` 事件时 `groupsFound += 1`；确保 `cancelScan()` 后不被流尾部回调覆盖（现状 `guard let summary` 已兜底，保留并加注释）

**Steps:**
- [ ] ScanViewModel 加 `groupsFound`、`elapsed` 发布，`cancelScan` 保持幂等
- [ ] ScanProgressView 加参数 + 四块信息 + 取消按钮
- [ ] MainView 调用点传 `onCancel: { viewModel.cancelScan() }`
- [ ] 新增中英文案（取消/当前目录/已发现组/用时）
- [ ] 构建 + 冒烟

**Acceptance:** 扫描中显示当前目录 + 已发现组数 + 用时；点取消立即回 idle 无残留；重复扫描正常。

---

## Task 6: P0-3 图片缩略图预览（功能+UI）

> 对应 Gap F3/V1。目标：perceptual 组直接看到缩略图对比，感知价值对齐 Gemini 2。依赖感知检测结果质量，本任务只做呈现。

**Files:**
- Create: `kDupe/UI/Result/ThumbnailCache.swift`
- Create: `kDupe/UI/Result/ThumbnailView.swift`
- Modify: `kDupe/UI/Result/GroupDetailView.swift`
- Modify: `kDupe/UI/Result/ResultView.swift`

**Interfaces:**
- `ThumbnailCache`: `final class`（`@unchecked Sendable` 包 `NSCache<NSURL, NSImage>`）+ `actor ThumbnailGenerator`（async 生成，`QuickLookThumbnailGenerator.shared.generateBestRepresentation(for: URL, at: NSSize(128), representing: .file) async throws`，macOS 13 可用；失败降级 `NSImage(contentsOf:)`）
- `ThumbnailView: View` — `let url: URL`，async 加载缩略图，loading 时占位（`ProgressView`），失败显示文件类型 icon
- GroupDetailView：`group.category == .perceptual` 时顶部显示横向/网格缩略图条（最多 12 张 + "+N"），点击缩略图不打断既有选择交互
- ResultView GroupRowView：perceptual 组行尾显示 1-2 张缩略图缩略（可选，有就做）

**Steps:**
- [ ] 新建 ThumbnailCache + ThumbnailView
- [ ] GroupDetailView 接入缩略图条
- [ ] ResultView GroupRowView 加缩略图（可选增强）
- [ ] 新增中英文案（更多 N 张）
- [ ] 构建 + 冒烟（用包含相似图的测试目录验证）

**Acceptance:** perceptual 组进组即见缩略图；loading/失败有占位；大组截断不崩；不阻塞组内文件行选择与清理。

---

## Task 7: P0-8 结果排序支持（功能）

> 对应 Gap F5。ResultViewModel 已有 `sortOrder`，缺 UI 暴露与组内排序。

**Files:**
- Modify: `kDupe/UI/Result/ResultView.swift`
- Modify: `kDupe/UI/Result/ResultViewModel.swift`
- Modify: `kDupe/UI/Result/GroupDetailView.swift`

**Interfaces:**
- ResultView：FilterBar 行右侧加排序 `Picker`（Menu 样式），选项 = `ResultViewModel.SortOrder` 全部 case（`sizeDesc/sizeAsc/countDesc/type`）+ 新增 `wasteDesc`（可回收空间 = `totalSize - max(files.size)`，高→低）
- ResultViewModel：加 `wasteDesc` case，`filteredGroups` 支持
- GroupDetailView：标题栏加组内排序 Menu（大小/日期/路径），影响文件行顺序（默认已是按日期由"Auto Keep Newest"用）

**Steps:**
- [ ] ResultViewModel 加 `wasteDesc` case + 计算
- [ ] ResultView 加排序 Picker（Menu）
- [ ] GroupDetailView 加组内排序 Menu
- [ ] 新增中英文案（排序标签）
- [ ] 构建 + 冒烟

**Acceptance:** 结果页可按大小/数量/类别/可回收排序；组内可按大小/日期/路径排；排序选择跨切换保持。

---

## Task 8: P0-4 结果搜索（功能）

> 对应 Gap F4。目标：结果页按文件名即时过滤，⌘F 聚焦。

**Files:**
- Modify: `kDupe/UI/Result/ResultView.swift`
- Modify: `kDupe/UI/Result/ResultViewModel.swift`

**Interfaces:**
- ResultViewModel：`@Published var searchText = ""`；`filteredGroups` 先按 category 再按 searchText 过滤（任一组内任一文件 `lastPathComponent.localizedCaseInsensitiveContains(searchText)` 即保留）
- ResultView：FilterBar 上方/嵌入一个 `TextField("Search…")` + 清除按钮；`.keyboardShortcut("f", modifiers: .command)` 聚焦；结果为空但 searchText 非空时显示 "无匹配结果" 空态
- 搜索时组内行也高亮命中文件名（可选增强，`GroupDetailView` 传 searchText）

**Steps:**
- [ ] ResultViewModel 加 searchText + 过滤逻辑
- [ ] ResultView 加搜索框 + ⌘F
- [ ] 新增中英文案（搜索占位/无匹配）
- [ ] 构建 + 冒烟

**Acceptance:** 输入即过滤；⌘F 聚焦；清空恢复全量；无匹配有空态。

---

## Task 9: P0-7 icon 异步加载 + 缓存（性能）

> 对应 Gap P1。现状 `FileRowView` 每行主线程 `NSWorkspace.shared.icon(forFile:)`，大列表卡 UI。

**Files:**
- Create: `kDupe/UI/Result/FileIconCache.swift`
- Modify: `kDupe/UI/Result/FileRowView.swift`

**Interfaces:**
- `FileIconCache`（`@unchecked Sendable` 包 `NSCache<NSString, NSImage>`）：`static func icon(for url: URL) -> NSImage?`（缓存命中同步返回）+ `static func loadAsync(for url: URL, into onImage: @escaping @Sendable (NSImage) -> Void)`（主线程回调）
- FileRowView：`@State private var icon: NSImage?`；onAppear 缓存命中直接显示，未命中占位（`doc` 图标）+ 异步加载替换

**Steps:**
- [ ] 新建 FileIconCache
- [ ] FileRowView 改造（保留原有 24×24 布局与选择态）
- [ ] 构建 + 冒烟（构造 500+ 行结果页滚动验证不掉帧）

**Acceptance:** 大列表滚动无主线程卡顿；图标二次进入秒回（缓存命中）；失败回退占位。

---

## Task 10: P0-10 空结果引导（UX）

> 对应 Gap U4。目标：扫出 0 组时给正向反馈 + 行动建议，而不是干瘪的 EmptyState。

**Files:**
- Modify: `kDupe/UI/Scan/ScanResultView.swift`
- Modify: `kDupe/UI/Result/ResultView.swift`（兜底）

**Interfaces:**
- 扫描完成且 `groups.isEmpty` 且 `largeFiles.isEmpty` 时，显示品牌化空态：大图标（`checkmark.seal`/`sparkles`）+ "没有发现重复文件" + "试试扫描其他目录" 按钮（回 idle）+ "扫描历史" 入口
- 有 `largeFiles` 但无重复组：显示 "未发现重复文件，但找到 N 个大文件" + 查看大文件（大文件分类走 FilterBar 已支持，进入结果页）

**Steps:**
- [ ] ScanResultView 空态分支
- [ ] ResultView 空数据兜底（`latestGroups` 空时）
- [ ] 新增中英文案
- [ ] 构建 + 冒烟

**Acceptance:** 无重复扫描后出现鼓励 + 换目录动作；大文件单独存在时不被埋没；无硬编码文案。

---

## Task 11: 修复预存测试失败（测试）

> 基线 94 通过 + 1 失败：`ResultViewModelTests.testRemoveSelectedSurfacesFailuresAndKeepsGroup`。VaultManager 语义是"逐文件 trash 失败=部分成功、失败组保留并上报"（spec §5），测试期望与之一致才对。

**Files:**
- Modify: `kDupe/Tests/ResultViewModelTests.swift`

**Steps:**
- [ ] 运行 `xcodebuild ... test` 复现失败
- [ ] 读测试与 `ResultViewModel.removeSelected` / `VaultManager.moveToTrash` 语义，若测试期望与 spec（部分成功、组保留、failures 上报）不符则修正测试；若实现有 bug 则修实现（实现优先符合 spec）
- [ ] 全量测试通过

**Acceptance:** `swift test` / xcodebuild test 全绿（95 通过，0 失败）。

---

## Task 12: 本地化同步 + 双语验收（收尾）

**Files:**
- Modify: `kDupe/Resources/en.lproj/Localizable.strings`
- Modify: `kDupe/Resources/zh-Hans.lproj/Localizable.strings`

**Steps:**
- [ ] 全仓 grep 新增视图里的硬编码字符串，逐一补入两个 strings 文件
- [ ] 编译验证 `LocalizedStringKey` / `NSLocalizedString` 引用全部有定义
- [ ] 全量构建（Debug）+ 全量测试
- [ ] 按 Gap 文档验收清单逐项自查（新用户 3 步授权/扫描可取消/缩略图可见/搜索排序可用/Vault 可恢复/大列表不掉帧/双语截图）

**Acceptance:** 无硬编码 UI 文案；测试全绿；验收清单 7 项全过。

---

## 交付顺序说明

- **Phase A（核心闭环，Task 1→5）**：授权 → Vault 可恢复 → 范围透明 → 拖拽入口 → 可取消可感知。先打通"授权→选目录→扫描→清理→恢复"关键路径
- **Phase B（结果页质量，Task 6→10）**：缩略图 → 排序 → 搜索 → 图标性能 → 空态
- **收尾（Task 11→12）**：测试修复 + 双语验收

Task 间无强依赖（Task 2 的 Vault 入口按钮与 Task 6-8 的 ResultView 修改同文件，实施时按顺序合入即可）。每 Task 独立可测，完成即验证。
