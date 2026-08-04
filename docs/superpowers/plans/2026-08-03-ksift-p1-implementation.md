# kSift P1 Implementation Plan — 锦上添花（gap → App Store top tier）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 按 Gap 文档 `2026-08-02-ksift-top-gap.md` 的 P1 清单（8 项 ~52h）让 kSift 从"功能完整"跨过"好用"门槛，对齐 Gemini 2 / CleanMyMac X 的体验细节。基线是 P0 commit `9259253`（94/94 测试通过）。

**Architecture:** 沿用 P0 后的 SwiftUI + MVVM + actor Service 模式。P1-8 是新增独立 MenuBar 模块（LSUIElement + NSStatusItem + App Group），其他 7 项均为现有 UI/ViewModel 增量。P1-7 不引入新代码、只跑基准与优化。

**Tech Stack:** Swift 5.9（strict concurrency）、SwiftUI、Swift Concurrency、Core Data、QuickLookThumbnailing、XcodeGen

**Design Spec:** `docs/superpowers/specs/2026-08-02-ksift-top-gap.md` §4 P1 段

## Global Constraints

- Swift 5.9+ strict concurrency（`SWIFT_STRICT_CONCURRENCY = complete`），Xcode 14.3.1 / Swift 5.8.1 toolchain 必须编译
- macOS 13.0+ deployment target；macOS 14+ API 用 `#available` 包裹
- Bundle ID：`app.kraftly.ksift`；App Sandbox 强制
- 本地化：SwiftUI 组件 prop 用 `LocalizedStringKey`；String 参数用 `NSLocalizedString`；新增文案同步写入 en + zh-Hans；plutil OK；keys 完全对齐
- DesignSystem tokens 强制（颜色/间距/圆角）；Empty/Loading/Error 状态用 `kFoundation` 组件
- 新增 .swift 文件后必须 `cd kDupe && xcodegen generate`
- 不动 P2 范围（视频/Photos/选择策略/lsof/动效/历史趋势/Paywall FAQ 不在本计划）
- 不修改检测引擎（detectors / orchestrator / persistence 只在必要接口处调整）
- 每个 Task 完成即跑构建 + 相关测试

## Build & Test Commands

```bash
cd /Users/mengjianjun/Documents/ai/aicoding/macapp/kDupe
xcodegen generate
xcodebuild -project kSift.xcodeproj -scheme kSift -configuration Debug build CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES 2>&1 | tail -40

xcodebuild -project kSift.xcodeproj -scheme kSiftTests -configuration Debug test CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES 2>&1 | grep -E "(failed|Executed [0-9]+ tests|TEST )" | tail -5
```

## File Structure（新增 / 修改）

```
kDupe/
├── App/
│   ├── AppState.swift                  # [修改] P1-3 清理汇总、P1-5 ⌘N 新扫描
│   └── MenuBarController.swift         # [新增] P1-8 NSStatusItem + 菜单
├── UI/
│   ├── Result/
│   │   ├── ResultView.swift            # [修改] P1-1 过滤条 / P1-4 占比条 / P1-5 键盘
│   │   ├── ResultViewModel.swift       # [修改] P1-1 sizeRange/dateRange 过滤
│   │   ├── FilterChipsView.swift       # [新增] P1-1 大小范围 + 日期滑块
│   │   ├── CategoryBreakdownBar.swift  # [新增] P1-4 类别占比可视化
│   │   ├── FileRowView.swift           # [修改] P1-6 类型图标 / 同名聚合 / 重复标记
│   │   └── GroupRowView.swift          # [修改] P1-6 同名组徽标
│   ├── Settings/
│   │   └── SettingsView.swift          # [修改] P1-2 排除目录 UI
│   ├── Onboarding/                     # 不变
│   └── Scan/
│       └── ScanResultView.swift        # [修改] P1-3 释放汇总
├── Resources/{en,zh-Hans}.lproj/Localizable.strings   # [修改] 全部 Task
├── project.yml                         # [修改] P1-8 LSUIElement + MenuBar 文件 glob
├── kSift.entitlements                  # [修改] P1-8 App Group 复用
└── Tests/PerformanceTests/
    └── LargeResultBenchmark.swift      # [新增] P1-7 10k+ 组基准
```

---

## Task 1: P1-1 结果排序 / 过滤增强

> 在 P0 已有的「按类别过滤 + 排序菜单」基础上加「大小范围 + 日期范围」两维度过滤；同样遵守竞品标配（Gemini 2、DFFP 均有）。

**Files:**
- Create: `kDupe/UI/Result/FilterChipsView.swift`
- Modify: `kDupe/UI/Result/ResultViewModel.swift`
- Modify: `kDupe/UI/Result/ResultView.swift`
- Modify: `kDupe/Resources/{en,zh-Hans}.lproj/Localizable.strings`

**Interfaces:**
- `ResultViewModel`：
  - `@Published var minSize: Int64 = 0`（字节，含 0 = 不限）
  - `@Published var maxSize: Int64 = .max`
  - `@Published var dateFrom: Date?`、`@Published var dateTo: Date?`
  - `filteredGroups` 串联 category → searchText → size range → date range → sort
- `FilterChipsView: View`：接收 binding 6 个值，提供两个 Slider（min/max size）+ 两个 DatePicker（from/to，nil 切换）；DisplayMode 折叠（默认隐藏，点击"More filters"展开）

**Steps:**
- [ ] ResultViewModel 加 4 个 published + 串联过滤
- [ ] FilterChipsView：大小滑块 0...10GB（log 步进）、日期范围 DatePicker（提供 "Anytime" 清除按钮）
- [ ] ResultView 插入到 FilterBarView 与排序行之间；新增"更多筛选 / Less filters"切换按钮
- [ ] en/zh-Hans 文案：Filter / Size range / From / To / Date range / Any size / Any date / Apply / Reset
- [ ] xcodegen + 构建 + 测试

**Acceptance:** 同时按大小 + 日期 + 类别 + 关键字过滤；任意一个为空/无限都不影响其他维度；滑动无卡顿。

---

## Task 2: P1-2 排除目录 UI

> `ProfileConfig.exclusions` 已存在但 SettingsView 只有添加扫描目录，无排除入口。补齐后用户能直接控制不扫的目录。

**Files:**
- Modify: `kDupe/UI/Settings/SettingsView.swift`
- Modify: `kDupe/UI/Settings/SettingsViewModel.swift`
- Modify: `kDupe/Resources/{en,zh-Hans}.lproj/Localizable.strings`

**Interfaces:**
- `SettingsViewModel`：`@Published var exclusionPaths: [String]`、`func addExclusion(_ path: String)`、`func removeExclusion(_ path: String)`
- `ProfileConfigStore.save(...)` 时把 `exclusions` 写回（已实现校验）

**Steps:**
- [ ] SettingsViewModel 加 API + 持久化（save to UserDefaults/JSON via ProfileConfigStore）
- [ ] SettingsView "Scan Directories" 之后新增 Section "Excluded Directories"：列表 + Add（NSOpenPanel）+ Remove（swipeActions）
- [ ] 空时显示提示"未配置排除项" + "添加" 按钮
- [ ] 文案（en/zh-Hans）4-6 条
- [ ] 构建 + 测试

**Acceptance:** 添加/移除排除目录立即生效；下次扫描 ProfileConfig.exclusions 反映新值；空状态有引导。

---

## Task 3: P1-3 清理成功 toast + 本次释放汇总

> 现状是 alert（modal），改为 toast + 数字汇总（竞品 Gemini 2 标配），让用户对"清理效果"有即时量化感知。

**Files:**
- Modify: `kDupe/UI/Result/ResultView.swift`
- Modify: `kDupe/UI/Scan/ScanResultView.swift`
- Create（可选）：`kDupe/UI/Common/ToastView.swift`
- Modify: `kDupe/Resources/{en,zh-Hans}.lproj/Localizable.strings`

**Interfaces:**
- 自实现轻量 toast：`.overlay(alignment: .top)` 显示一个 RoundedRectangle Card（设计 tokens 圆角/间距），3 秒自动消失，可手动 dismiss
- ResultView 清理成功：从 alert 改为 toast，内容："已移动 N 个文件 · 释放 X GB / N files moved · X GB freed" + "Open Vault" 跳转
- ScanResultView 完成后（除 Review 外）也加一个"释放 X GB"小标识

**Steps:**
- [ ] ToastView（自实现，无第三方依赖）
- [ ] ResultView 用 toast 替换 alert，"Open Vault" 仍是 .vault 跳转
- [ ] ScanResultView 加"释放 X GB"标识（接收 totalWaste 已有数据）
- [ ] 文案（en/zh-Hans）：Moved N files / Freed N GB / Tap to undo / Open Vault 等
- [ ] 构建 + 测试

**Acceptance:** 清理成功后顶部 toast 出现，3 秒自动消失；显示实际字节（人类可读 ByteCountFormatter）；"Open Vault" 跳转可用。

---

## Task 4: P1-4 分类占比可视化

> 在 ResultView 顶部 stats bar 下方加一条按类别着色的占比横条，让用户一眼看出"哪种重复最多"。

**Files:**
- Create: `kDupe/UI/Result/CategoryBreakdownBar.swift`
- Modify: `kDupe/UI/Result/ResultView.swift`
- Modify: `kDupe/Resources/{en,zh-Hans}.lproj/Localizable.strings`

**Interfaces:**
- `CategoryBreakdownBar: View` — `let groups: [DuplicateGroup]`
  - 单条 horizontal stack，每个 category 一段，宽度按 `group.totalSize` 在总占比中的份额分配
  - 段使用 `DuplicateCategory.color` 着色；悬停 tooltip 显示 "Identical · 1.2 GB · 12 groups"（先实现文字 legend 在条下方即可，tooltip 可选）
  - legend：横向 grid，每项 = 圆点 + 类别 displayName + 总大小

**Steps:**
- [ ] CategoryBreakdownBar（仅 SwiftUI，无交互数据）
- [ ] ResultView 在 stats bar 与 FilterBarView 之间插入
- [ ] 文案（en/zh-Hans）：legend 复用 `DuplicateCategory.displayName`（已本地化）
- [ ] 构建 + 测试

**Acceptance:** 6 类重复的占比按字节权重着色显示；点击段跳到该类别的 filter（可选增强，简化版只需展示）；空 groups 时不显示。

---

## Task 5: P1-5 键盘导航完善

> 竞品标配：⌘F（已有）、⌘A 全选、⌘N 新扫描、空格 QuickLook、Esc 取消、Tab 在组间移动。

**Files:**
- Modify: `kDupe/UI/Result/ResultView.swift`
- Modify: `kDupe/UI/Result/GroupDetailView.swift`
- Modify: `kDupe/App/AppState.swift`（如需暴露新扫描 closure）
- Modify: `kDupe/Resources/{en,zh-Hans}.lproj/Localizable.strings`

**Interfaces:**
- ResultView：
  - ⌘A → `viewModel.autoSelectGroups()`（selectAll 即全选）
  - ⌘N → `appState.navigation = .scan`（新扫描入口）
  - Esc → `viewModel.clearSelection()`（清除选择）
  - .focusable + .onKeyPress(.tab) → 在 group 间移动焦点（macOS 14+ 才有 onKeyPress，用 #available；macOS 13 fallback 用 NavigationLink focus）
- GroupDetailView：
  - 空格 → 选中文件 QuickLook（`previewUrl = selectedFiles.first?.url`）
  - Esc → 取消选中

**Steps:**
- [ ] ResultView 加 .keyboardShortcut 三件套 + Esc 处理
- [ ] GroupDetailView 加空格 QuickLook（需先支持 selectedFileIds 单选状态；macOS 13 List 单选可用）
- [ ] macOS 14+ 用 `.onKeyPress(.tab)` 在 GroupDetailView 移动焦点（先打 #available；macOS 13 fallback 暂不实现 Tab 导航）
- [ ] 文案（en/zh-Hans）tooltip 4-6 条
- [ ] 构建 + 测试

**Acceptance:** ResultView ⌘A / ⌘N / Esc 生效；GroupDetailView 空格 QuickLook 生效；macOS 14 上 Tab 在组内行间切换。

---

## Task 6: P1-6 结果行增强

> 文件行：加类型图标（图片/视频/文档/代码）替代纯 doc icon；同名组聚合（多组文件名相同时显示 "×N" 徽标）；坏文件标记（无法读取、已删除）。

**Files:**
- Modify: `kDupe/UI/Result/FileRowView.swift`
- Modify: `kDupe/UI/Result/GroupRowView.swift`
- Modify: `kDupe/UI/Result/FileIconCache.swift`（扩展支持 UTType → icon 映射）
- Modify: `kDupe/Resources/{en,zh-Hans}.lproj/Localizable.strings`

**Interfaces:**
- `FileIconCache` 加 `func icon(for utType: UTType?) async -> NSImage`：根据 UTType 返回 SF Symbol（`photo`, `video`, `doc.richtext`, `doc.plaintext`, `terminal`, `archivebox`, `doc`）
- FileRowView：若 `file.fileType` 可识别 → 替换 doc icon；显示坏文件标记（"⚠️ File missing" 在 size 列旁）
- GroupRowView：同名检测（`group.files.first?.url.lastPathComponent` 多组相同）显示"×N" 徽标；APFS clone 标记（`isAPFSClone` 数量）

**Steps:**
- [ ] FileIconCache：先查缓存的 NSImage，再根据 UTType 选 SF Symbol 渲染
- [ ] FileRowView：用 `FileIconCache.shared.icon(for: file.fileType)` 优先；坏文件（`FileManager.default.fileExists == false`）显示 warning
- [ ] GroupRowView：同名聚合（`Dictionary(grouping: filteredGroups, by: \.files.first?.url.lastPathComponent).filter { $0.value.count > 1 }`），同名组显示"×N"；APFS clone 总数显示
- [ ] 文案（en/zh-Hans）：Missing file / ×N duplicates / N clones 等 3-5 条
- [ ] 构建 + 测试

**Acceptance:** 图片显示 photo、文档显示 doc；坏文件有提示；同名组有"×N"徽标；APFS clone 总数显示。

---

## Task 7: P1-7 大结果集性能测试与优化

> 验证 10k+ 组结果页滚动 ≥ 50fps。

**Files:**
- Create: `kDupe/Tests/PerformanceTests/LargeResultBenchmark.swift`
- Modify: `kDupe/UI/Result/ResultView.swift`（如发现瓶颈）
- Modify: `kDupe/UI/Result/ResultViewModel.swift`（如发现瓶颈）

**Benchmark Approach:**
- 生成 10k 个 `DuplicateGroup`（每组 2 个 FileItem，file 类型/大小随机）→ 喂入 ResultViewModel
- 测量：`filteredGroups` 计算时长（cold/warm）、首次 body 求值时长、LazyVStack 滚动 N 帧时长

**Steps:**
- [ ] LargeResultBenchmark：XCTest `measure { ... }` 三个 metric
- [ ] 跑基线，发现瓶颈（候选：filteredGroups 每次重算全部 + sort；icon 加载并发；thumbnail 缓存）
- [ ] 优化：
  - filteredGroups 加 `@Published` cache，仅在 input 变化时重算（Combine `removeDuplicates`）
  - icon 缓存命中率验证
  - LazyVStack 用 `LazyVStack`（已用），检查 `id` 稳定性
- [ ] 重测，性能应 ≥ 50fps 等效（首次过滤 < 200ms，滚动帧间隔 < 16ms）

**Acceptance:** 10k 组下：
- 首次 filteredGroups 计算 < 200ms
- 切换排序后再次过滤 < 100ms（cache 命中）
- 滚动 100 帧间隔平均 < 16ms
- 全部原有 94 个测试仍通过

---

## Task 8: P1-8 菜单栏快捷入口

> 菜单栏常驻 + 一键扫描 / 打开结果 / 清理状态。竞品 Gemini 2 / BuhoCleaner 标配。

**Files:**
- Create: `kDupe/App/MenuBarController.swift`
- Modify: `kDupe/App/kSiftApp.swift`（启动 MenuBarController）
- Modify: `kDupe/App/AppCoordinator.swift`（深链打开 App 主窗口）
- Modify: `kDupe/project.yml`（设置 LSUIElement + 文件 glob）
- Modify: `kDupe/Info.plist`（如需 `LSUIElement = true`，或在 project.yml）
- Modify: `kDupe/Resources/{en,zh-Hans}.lproj/Localizable.strings`

**Architecture:**
- `MenuBarController: NSObject, NSMenuDelegate`：单一 NSStatusItem（system image `trash` 或 `doc.on.doc`，`length = .variableLength`）
- 菜单项：
  - "Open kSift" → `NSApp.activate(ignoringOtherApps: true)` + 显示主窗口
  - "Quick Scan…" → NSOpenPanel + 通过 AppCoordinator 触发扫描
  - "Recent Results" → 列出最近 5 个扫描（读 CoreData ScanRecord）
  - Divider
  - "Show Vault" → 深链 `.vault`
  - "Quit kSift" → `NSApp.terminate(nil)`
- 点击菜单栏图标本身（不弹菜单）→ 打开 App 主窗口
- 副标题（attributedTitle）：显示最后扫描的释放空间（如 "12.3 GB freed"）

**Steps:**
- [ ] MenuBarController 实现（NSStatusItem + NSMenu + 异步加载历史）
- [ ] kSiftApp.swift 启动时初始化（App Sandbox 内 App Group `group.app.kraftly.ksift` 共享数据）
- [ ] project.yml 加 LSUIElement = true（Info.plist 等价项；也可仅在 MenuBarController 启动后切换 `NSApp.setActivationPolicy(.accessory)`）
- [ ] 文案（en/zh-Hans）：Quick Scan / Recent Results / Show Vault / Quit kSift / Open kSift
- [ ] 构建 + 测试

**Acceptance:** 启动 App 后菜单栏出现图标；菜单可打开 / 触发扫描 / 跳转 Vault；退出 App 后菜单栏图标消失；App 不抢 Dock（accessory 模式）。

---

## 实施顺序

```
Phase I（轻量增量，~20h）：
  Task 2（排除 UI）→ Task 3（清理 toast）→ Task 4（占比可视化）→ Task 5（键盘）

Phase II（中量改动，~14h）：
  Task 1（多维过滤）→ Task 6（结果行增强）

Phase III（独立模块，~16h）：
  Task 7（性能基准）→ Task 8（菜单栏）
```

- Task 2/3/4/5 互相独立文件，可顺序派发避免 ResultView 冲突
- Task 1 与 Task 6 都动 ResultView / ResultViewModel，按顺序合入
- Task 7 性能基准在功能稳定后跑；Task 8 菜单栏是独立模块，可与 Task 7 并行（不同文件）

## 风险与备注

- **Task 5 macOS 14 onKeyPress** 需 `#available(macOS 14, *)` 包裹；macOS 13 不强求 Tab 导航
- **Task 8 LSUIElement** 与 App 主窗口共存需要切换 `NSApp.setActivationPolicy(.proposed/regular)`；避免启动时主窗口被屏蔽
- **Task 7 10k 组基准** 内存压力较大，测试用临时目录 + tearDown 清理
- **Task 1 滑块 log 步进** 避免 0...10GB 线性滑块在小范围不灵敏
- **Task 4 tooltip** 可选：先做条下 legend，要点简化为 hover；如时间允许再加 popover