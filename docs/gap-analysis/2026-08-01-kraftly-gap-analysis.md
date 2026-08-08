# Kraftly 4-App 竞品对标缺口分析报告

> **日期**：2026-08-01
> **范围**：kWatch（深挖）/ kSpaceClean / kDupe / kFresh 全量覆盖
> **基准**：各赛道 top 竞品（Web 取证）+ Apple HIG / 精品感知标准
> **证据**：竞品侧 `/tmp/competitor-evidence.md`（11 个竞品画像 + 四赛道精品标准）；现状侧 `/tmp/kwatch-evidence.md` + `/tmp/other-apps-evidence.md`（代码级盘点）
> **方法限制**：kWatch 无 `.xcodeproj`（仅 project.yml，本机 xcodegen 不可用）→ kWatch 现状为**纯代码阅读**证据；kSpaceClean / kDupe / kFresh 有工程可构建，为代码盘点证据。竞品侧为公开网页 + App Store 元数据。

---

## 0. 执行摘要（TL;DR）

四个 App 的**核心引擎都是真的**——扫描、清理、哈希、七阶段编排、卸载残留、备份回滚都写完了。真正的问题不在引擎，在**"价值呈现"层**：

1. **付费墙没有入口**（4 个 App 全部未接线）：paywall 写了，但没有任何路径能触发它 → 收入为零，且审核时"无功能墙"反而安全，但商业化完全没闭环。
2. **结果页断连**：扫描做完，结果数据加载不出来（kDupe 结果页无调用者）、价值页面不可达（kFresh 两个完整功能页无入口）、可视化是 stub（kSpaceClean 星系渲染器 19 行）。
3. **UI/UX 与 top 精品差距集中在"信息密度 × 可定制性 × 即时反馈"**：竞品的共同卖点是高密度但可读、深度自定义、清理/监控后的即时数字反馈。当前实现是三样都缺。
4. **kWatch 差距最大**（旗舰首屏 MenuBarView 只有 100 行基础 popover）——本次按 8 屏逐屏对标，P0 缺口已映射到 Stage 1 任务清单（`kWatch/V1-TODO.md`）。

**一句话**：引擎是 80 分，UI 入口与商业闭环是 20 分。优先补后者，价值立现。

---

## 1. 方法学

| 维度 | 做法 |
|---|---|
| 现状侧 | 代码级盘点（行数为证据锚点，非全量清单） |
| 竞品侧 | WebSearch + 官网 curl + App Store iTunes Lookup API（2026-08-01 采集） |
| 对标方式 | 每个 App：现状快照 → 对标矩阵（竞品共有功能）→ 分级 gap（P0/P1/P2 按商业影响）→ 建议动作 |
| kWatch | 8 屏逐屏：菜单栏 / Dashboard / History / Processes / Alerts / Settings / Onboarding+Paywall / Widget+Live Activity，每屏按 功能/交互/视觉/技术 四类列 gap |
| 分级标准 | **P0**=拒审风险 / 30 秒劝退 / 付费转化受阻；**P1**=竞品高频功能缺失 + 精品感差距；**P2**=打磨 |
| 排序 | 尊重现有路线图（kWatch 先行；其余 3 App 给建议优先级，不改路线图） |

---

## 2. 跨 App 总览矩阵

| 维度 | kSpaceClean | kDupe | kFresh | kWatch |
|---|---|---|---|---|
| 源码规模 | ~12,535 行 | ~4,614 行 | ~5,477 行 | ~—（无 xcodeproj） |
| 核心引擎 | ✅ ScanEngine(337) + ScanRule(786) + CleanupEngine(197) | ✅ ScanOrchestrator 七阶段 + VaultManager + Core Data | ✅ AppCatalog 四源合并 + ResidueDetector 13 模板 + TrashMover 7 步 + BackupManager | ✅ MetricsAggregator AsyncStream + 8 AppIntents |
| 测试 | 16 个 | — | 17 个 | 阶段 0 已补 |
| 结果页断连 | ⚠️ 星系渲染 stub + AI 死代码 | ❌ ResultViewModel.loadGroups 无调用者 | ⚠️ 两个孤儿页不可达 | ⚠️ 多处 stub |
| Paywall 入口 | ❌ PaywallView 仅自引用 | ❌ 无 gating | ❌ showPaywall 只 print | ⚠️ Pro 徽标有、入口死 |
| 精品 UI 差距 | 中（有真实主界面） | 大（结果页未通） | 小（引擎最全，UI 缺入口） | **最大（旗舰屏仅 100 行）** |

> **重要更正**：早前我误判"kSpaceClean Features 目录全空"。已核实 `kWise/Features/` 下实有 **49 个 Swift 文件**（SmartScan 10 个、Cleanup、DiskGalaxy 等），ScanEngine/ScanRule/CleanupEngine 都是真引擎。问题不是没有代码，而是**这些引擎的 UI 入口 / 商业化闭环没接上**。

---

## 3. kSpaceClean — 磁盘清理（对标 CleanMyMac X / BuhoCleaner / DaisyDisk）

### 3.1 现状快照

- 扫描引擎（目录遍历 + 规则评估）、规则系统（786 行多类文件规则）、清理引擎、App 卸载残留扫描（11 个模板）均为**真实实现**
- UI 层：ScanContentView / CleanupContentView / AppUninstallView 为真实 SwiftUI；SettingsView / MenuBarManager 存在但多处 stub
- Store：StoreManager 用真实 StoreKit 2，产品 ID `app.kraftly.sclean.subscription.yearly`

### 3.2 对标矩阵

| 竞品共有功能 | CleanMyMac X | BuhoCleaner | DaisyDisk | kSpaceClean 现状 |
|---|---|---|---|---|
| 模块化仪表盘首页（大卡片） | ✅ | ✅ | —（可视化为核） | ⚠️ 有主界面，无"一键智能清理"主流程 |
| 一键 Smart Care / Flash Clean | ✅ | ✅ | — | ❌ 无 |
| 空间可视化反馈 | ✅（Storage 视图） | ✅ | ✅（环图招牌） | ⚠️ 星系 stub（19 行） |
| 清理后"回收空间"即时数字反馈 | ✅ | ✅ | ✅ | ⚠️ 无 |
| 安全回退（废纸篓 / 30 天） | ✅ | ✅ | ✅ | ✅ 有历史记录 |
| 卸载器 / 启动项 / 内存释放 | ✅ | ✅ | — | ⚠️ AppUninstall 有扫描但 UI 入口弱 |
| 菜单栏监控入口 | ✅ CleanMyMac Menu | ✅ Mac Monitor | — | ❌ quickClean 占位 |
| 免费额度 → 订阅转化漏斗 | ✅ | ✅ | —（买断） | ❌ PaywallView 无入口 |

### 3.3 分级 Gap

**P0（商业化闭环，不做收入为零）**
- **G-SC-01** PaywallView 无任何入口、无 gating：免费层限制"清理额度 1GB，超出引导订阅"的设计**完全没有落地**。
- **G-SC-02** SettingsView「管理订阅」是 stub + 「当前: Pro」硬编码：用户无法管理订阅，也无法感知免费/Pro 状态。

**P1（价值呈现 + 精品感）**
- **G-SC-03** "一键智能清理"主流程缺失（Smart Care / Flash Clean 是竞品首页心智）。
- **G-SC-04** 清理后"回收空间"即时数字反馈缺失（竞品清理完成都展示回收了多少）。
- **G-SC-05** 空间可视化：星系渲染器是 19 行 stub，DaisyDisk 靠可视化拿了 3 次 App Store 年度奖——这是 v2 差异化核心，v1 至少要有可用的分类条/环图反馈。
- **G-SC-06** MenuBarManager.quickClean 无动作（竞品菜单栏是高频入口）。

**P2（打磨）**
- **G-SC-07** AIClassifier 死代码（全工程从未实例化、Resources/Models 缺失）：要么接上本地 embedding 分类，要么删掉避免误导。
- **G-SC-08** 菜单栏图标无系统脉搏信息（竞品常驻显示已用空间）。

### 3.4 建议动作（不改路线图，仅排优先级）

1. 先把 P0 的 paywall 入口 + 免费额度 gating 接上（参考 kWatch 阶段 0 已落地的 terms checkbox + restore 模式）
2. 补 P1 的一键清理 + 回收空间数字反馈（改动小、精品感提升大）
3. 星系图放 v2，v1 先用 DesignSystem 分类环图兜底

---

## 4. kDupe — 重复/大文件（对标 Gemini 2 / PhotoSweeper / Nektony）

> **竞品更正**：原锁定名单中的 nk Duplicate Finder 已疑似停更（域名无法解析、App Store 无记录、Wayback 无快照）。改用仍活跃的 **Nektony Duplicate File Finder Pro** 作为第三对标样本。本次矩阵以 Gemini 2（智能+设计奖）与 PhotoSweeper（摄影师深度集成）为主。

### 4.1 现状快照

- ScanOrchestrator 七阶段（enumerating→byteIdentical→directoryDedup→perceptual→largeFiles→buildArtifacts→rawJPEG→completed）**真实且编排完整**，AsyncStream<ScanEvent> 驱动
- VaultManager：copy-first + SHA-256 校验、批次中止、restore hash 复验、30 天过期 —— 工程严谨
- DuplicateRepositoryCoreData 完整（save/load/evidence 编解码）
- **但结果页断连**：ResultView.swift:71-72 `onAppear { // Load groups... }` 是 stub；ResultViewModel.loadGroups() 存在但**无任何调用者**

### 4.2 对标矩阵

| 竞品共有功能 | Gemini 2 | PhotoSweeper | kDupe 现状 |
|---|---|---|---|
| 分组对比视图（One by One / Face-to-Face / All in One） | ✅ 卡片式 | ✅ 三模式 | ❌ 结果页未通 |
| 相似度阈值可视化滑动 | ✅ | ✅ | ⚠️ 有 perceptual 引擎，无 UI |
| 相似文件（感知哈希） | ✅ Similars | ✅ 核心 | ✅ 引擎有，UI 无 |
| 自动保留规则 / 智能选择 | ✅ Smart Select（AI 学习） | ✅ Auto Mark | ❌ 无 |
| 白名单排除 | ✅ | — | ❌ 无 |
| 删除进废纸篓可恢复 | ✅ | ✅ | ✅ Vault 有 |
| 专项库（Photos / 音乐） | ✅ | ✅ Apple Photos 集成 | ❌ 无 |
| 大型库性能（连拍组/多核） | ✅ | ✅ | ⚠️ 未验证 |
| 菜单栏快捷入口 | ✅ | — | ❌ 无 |
| 即时预览（Quick Look / EXIF） | ✅ | ✅ | ❌ 无 |

### 4.3 分级 Gap

**P0**
- **G-KD-01** 结果页数据链路不通：MainView→ScanResultView 的 onReview 未驱动 ResultView 数据加载。**扫描白做，用户看不到成果 = 30 秒劝退。**
- **G-KD-02** 结果分组对比视图缺失：这是重复文件 App 的**产品本体**（Gemini 靠它拿 Red Dot）。

**P1**
- **G-KD-03** 相似度阈值 UI + 即时预览（Quick Look / EXIF）——摄影师向用户的核心工作流。
- **G-KD-04** 自动保留规则（Auto Mark / Smart Select 的朴素版：按大小/路径/修改时间打分推荐保留项）。
- **G-KD-05** 白名单 + 菜单栏快捷入口。

**P2**
- **G-KD-06** IncrementalIndex 从未实例化（重复检测的增量索引是性能差异化点，或删或接）。
- **G-KD-07** 商业化无 gating：PaywallView 无入口（同 kSpaceClean 的 P0 模式）。

### 4.4 建议动作

1. 先把 P0 的**结果页接通**（onReview→loadGroups→分组列表）——这是 1-2 天的活，但直接决定产品是否可用
2. 补结果分组对比视图 + 废纸篓恢复闭环
3. 再谈 AI 选择 / 相似度 UI / 专项库

---

## 5. kFresh — 应用卸载（对标 AppCleaner / Pearcleaner / CleanMyMac X 卸载器）

### 5.1 现状快照

- **引擎最完整的一个**：AppCatalogService 四源合并（runningApps + /Applications + Homebrew Caskroom + Setapp）+ bundleID 去重；ResidueDetector 精确匹配 + 13 路径模板 + confidence 计算；ResidueScanner 并发富集；TrashMover 7 步（保护拒绝→优雅终止 8s→备份→trash→残留清理 conf>0.5→记录→审计）；BackupManager 版本化备份 + SHA-256 + 30 天 TTL；CaskParser 解析 Homebrew ruby DSL
- UI：AppListView / AppDetailView / HistoryView / SettingsView 真实，Filter/Sort/Search 齐全；Loading/Empty/Error 共享组件真实
- Widgets + Intents + FinderSync 真实

### 5.2 对标矩阵

| 竞品共有功能 | AppCleaner | Pearcleaner | CMM X 卸载器 | kFresh 现状 |
|---|---|---|---|---|
| 拖拽即扫（零学习成本） | ✅ | ✅ | ✅ | ⚠️ 列表为主，拖拽入口弱 |
| 全量残留扫描（缓存/偏好/保存状态） | ✅ | ✅ | ✅ | ✅ 引擎有 |
| 扫描结果透明可勾选 | ✅ | ✅ | ✅ | ✅ 有 |
| 按需增删扫描条目 | ✅ | ✅ | — | ⚠️ 未确认 |
| 列表/网格双视图 | — | ✅ | — | ⚠️ 有列表 |
| 损坏/过时 App 识别 | — | ✅ | ✅ | ❌ 无 |
| 轻量常驻自动清理 | — | ✅ Sentinel | — | ❌ 无 |
| 批量/更新管理联动 | — | ✅ Homebrew/PKG | ✅ | ❌ 无 |
| 安全回退（废纸篓） | ✅ | ✅ | ✅ | ✅ 有 |

### 5.3 分级 Gap

**P0**
- **G-KF-01** 两个完整功能页不可达：DeepCleanView（:68 挂 proGate）与 StartupItemsView（:60 挂 proGate）在 RootView 无入口 → **写了等于没写**，且 proGate 挂在不可达页面 = 商业化死路。
- **G-KF-02** Paywall 无活入口：AppCoordinator.showPaywall 从未置 true；SettingsViewModel.showPaywall() 只 print → 无订阅转化路径。

**P1**
- **G-KF-03** 拖拽即扫的零学习交互（AppCleaner 18 年靠这个心智）：列表式 App 管理代替不了"把 App 拖进窗口"。
- **G-KF-04** 卸载结果"回收空间"即时反馈 + 与 kSpaceClean 生态的"卸载即清理"闭环（Shortcuts / Control Widget 自动化）。
- **G-KF-05** 残留扫描结果给 confidence 可视化 + 可勾选（引擎有 confidence，UI 没暴露）。

**P2**
- **G-KF-06** AppCoordinator.handleDeepLink 空实现（deep link 是 Shortcuts 自动化的入口，接了才有生态位）。
- **G-KF-07** 损坏/过时 App 识别（Pearcleaner 与 CMM 都有的中频功能）。

### 5.4 建议动作

1. RootView 补上 DeepClean / StartupItems 两个入口（把已写完的页面暴露出来）
2. paywall 入口接真实状态（ShowPaywall → PaywallView）
3. 补拖拽即扫 + 回收空间反馈（引擎全在，UI 层工作量小）

---

## 6. kWatch — 菜单栏监控（深挖章节）

> **现状证据说明**：kWatch 无 `.xcodeproj`（project.yml 未生成工程），本机无法构建，以下为纯代码阅读证据，行号为锚点。竞品基准见 `/tmp/competitor-evidence.md` 赛道 1（iStat Menus 7.30 行业标准 / Stats 40.9k stars 免费替代 / iPulse 视觉派）。

### 6.1 逐屏对标（8 屏 × 功能/交互/视觉/技术）

#### 屏 1：菜单栏 popover（旗舰首屏）`MenuBar/MenuBarView.swift`（100 行）

| 类别 | 竞品基准（iStat/Stats） | kWatch 现状 | 缺口 |
|---|---|---|---|
| 功能 | 全 7 指标逐项可显隐/排序/合并（Combined 模式） | 固定 4 行（CPU/Memory/Disk/Network），`enabledKinds` 偏好**未应用** | 🔴 **P0** G-KW-01 指标可配置 + 全 7 项展示 |
| 功能 | 每项：数值 + 历史 sparkline + 副标题（"Used 12GB/16GB"） | MiniTrendChart 仅 trend 模式；无副标题 | 🔴 **P0**（并入 F1） |
| 交互 | 顶部快捷开关栏（Wi-Fi/蓝牙/夜览/DND） | 无 | 🔴 **P0** G-KW-02 = Stage 1 F9 |
| 交互 | 点击指标进详情 | 仅 5 个导航按钮 | 🟠 **P1** |
| 视觉 | 高信息密度但可读；主题可换 | `frame(width: 280)` 单列朴素列表；无主题 | 🔴 **P0** G-KW-03 360 宽度 + 卡片化 = Stage 1 F1/U1/U2 |
| 视觉 | 菜单栏图标主题化（数字/条状/文字） | 固定 SF Symbol | 🔴 **P0** = Stage 1 F10/V6 |
| 技术 | 每项独立 MenuBarExtra（多图标模式） | 单一 popover | 🔴 **P0** G-KW-04 = Stage 1 U9/I7 |
| 技术 | 低 CPU 占用为卖点 | 未验证 | 🟢 P2 |

#### 屏 2：Dashboard `Dashboard/DashboardView.swift`

| 类别 | 竞品基准 | kWatch 现状 | 缺口 |
|---|---|---|---|
| 功能 | 6-7 指标卡片全览 | 有卡片 | ✅ 基础有 |
| 交互 | 点击卡片进详情页（大图 + 趋势 + 进程排行） | 无详情下钻 | 🟠 **P1** G-KW-05（= Stage 2 U3） |
| 视觉 | 卡片 + sparkline + 主题 | CardColor 枚举 6 色硬编码 | 🟠 **P1** 接入 DesignSystem（= Stage 1 V1/V2） |
| 技术 | 实时数据流 | ✅ MetricsAggregator AsyncStream | ✅ |

#### 屏 3：History `History/HistoryView.swift`

| 类别 | 竞品基准 | kWatch 现状 | 缺口 |
|---|---|---|---|
| 功能 | 24h/7d/30d 三档趋势 | 有分段？未确认完整 | 🟠 **P1** |
| 交互 | 缩放 / 拖动 / crosshair | 无 | 🔴 **P0** G-KW-06（= Stage 1 F3） |
| 技术 | 趋势图（line + area fill） | Sparkline 只有迷你版 | 🔴 **P0**（并入 F3） |
| 技术 | 数据真实性 | HistoryRepository.swift:30-33 网络近似 `receive=send=total/2` | 🟠 **P1** G-KW-07 采集真实流量（= Stage 2 F5 的前置） |

#### 屏 4：Processes `Processes/ProcessListView.swift`

| 类别 | 竞品基准 | kWatch 现状 | 缺口 |
|---|---|---|---|
| 功能 | 进程级网络排行（按 App 流量分解） | LiveIntentService.topProcesses 返回**空数组**（:96-112） | 🔴 **P0** G-KW-08 = Stage 1 I4 + Stage 2 F5 |
| 交互 | 免费层 5 条限制的 UI 说明 + 升级引导 | 硬限制但无解释 | 🟠 **P1** G-KW-09 转化路径 |
| 技术 | libproc 精确采集 | show* intents 空实现（:61-68） | 🔴 **P0**（并入 G-KW-08） |

#### 屏 5：Alerts `Alerts/AlertEditorView.swift`

| 类别 | 竞品基准 | kWatch 现状 | 缺口 |
|---|---|---|---|
| 功能 | 每指标上下双阈值 | 单阈值 + AlertEvaluator **stub** | 🔴 **P0** G-KW-10（= Stage 1 F4） |
| 功能 | 触发频率限制（每 5 分钟） | 无 | 🟠 **P1**（并入 F4） |
| 交互 | 告警历史视图 | 无历史入口 | 🟠 **P1** G-KW-11 |
| 技术 | 本地通知渠道 | NotificationScheduler 有 | ✅ |

#### 屏 6：Settings `Settings/SettingsView.swift`

| 类别 | 竞品基准 | kWatch 现状 | 缺口 |
|---|---|---|---|
| 功能 | 7+ 分页设置（MenuBar/通知/各指标/Sensors/Battery/Display/About） | "General" tab 实际是 Widget 采样配置（命名错位）；无逐指标 tab | 🟠 **P1** G-KW-12（= Stage 2 U5） |
| 交互 | 菜单栏图标布局编辑器（拖放重排） | 无 | 🔴 **P0** G-KW-13（= Stage 1 U9 配套） |
| 技术 | 持久化布局顺序 | PreferencesRepository.menuBarOrder 有字段未用 | 🟠 **P1** |
| 交互 | Restore Purchases（阶段 0 已做） | ✅ 已落地 | ✅ |

#### 屏 7：Onboarding + Paywall

| 类别 | 竞品基准 | kWatch 现状 | 缺口 |
|---|---|---|---|
| 交互 | 引导页有动效 / 价值递进 | 4 页线性无动画 | 🟠 **P1** G-KW-14 |
| 功能 | 订阅前条款勾选（阶段 0 已做） | ✅ 已落地 | ✅ |
| 功能 | supportLink 可点击 | 勾选框有，但条款里的支持链接**不可点击** | 🟠 **P1** G-KW-15 |
| 商业化 | 订阅 vs 一次性买断语义一致 | $7.99 硬编码 3 处；订阅/买断文案自相矛盾 | 🟠 **P1** G-KW-16（清账后由代码统一） |
| 技术 | 恢复购买（阶段 0 已做） | ✅ 已落地 | ✅ |

#### 屏 8：Widget + Live Activity

| 类别 | 竞品基准 | kWatch 现状 | 缺口 |
|---|---|---|---|
| 功能 | Interactive Widget（按钮触发 AppIntent） | OpenDashboardIntent 是 **no-op**（WidgetViews.swift:25-39） | 🔴 **P0** G-KW-17（= Stage 1 I2） |
| 功能 | 实时数据显示 | SparklinePlaceholder "coming soon"（:236-246） | 🔴 **P0**（并入 I2） |
| 功能 | Live Activity 清理进度 | **完全未接线**（无 request 调用，MetricLiveActivity.swift:13） | 🔴 **P0** G-KW-18（Pro 卖点，= Stage 1 阶段未列，需补） |
| 技术 | Widget 数据通道 | App Group snapshot.json 有 | ✅ |

### 6.2 跨屏系统性缺口（非单屏，贯穿所有屏）

| # | 缺口 | 证据 | 级别 |
|---|---|---|---|
| S-01 | **无 DesignSystem token**：全 App 仅 CardColor 枚举（MetricCardView.swift:6-19），无 Color/Spacing/Type token | 违背 CLAUDE.md §5.4 强制项 | 🔴 P0（= Stage 1 V1/V2） |
| S-02 | **formatBytes 复制 6 处**、无共享工具 | 代码事实 | 🟠 P1 |
| S-03 | **零自定义动画**：无 200ms/350ms/150ms 动效语言 | 违背 CLAUDE.md §5.4 动效语言 | 🟠 P1 |
| S-04 | 加载/空/错误状态不齐：MenuBarView 无任何状态分支 | 竞品空态/加载态是标配 | 🟠 P1（= Stage 2 V8） |
| S-05 | `NSApp.sendAction(Selector(("showSettingsWindow:")))`（kWatchApp.swift:96）绕行调用 | 技术债 | 🟢 P2 |

### 6.3 P0 缺口 → Stage 1 任务映射

> Stage 1（`kWatch/V1-TODO.md` 81-177 行）已有 18 项任务。本报告 P0 缺口与它们的对应关系 + 两处**需要补进清单**的新任务：

| 本报告 P0 | 对应 Stage 1 任务 | 说明 |
|---|---|---|
| G-KW-01 全 7 指标 + 可配置 | F1 | 已覆盖 |
| G-KW-02 快捷开关栏 | F9 | 已覆盖 |
| G-KW-03 360 宽卡片化 | F1 / U1 / U2 | 已覆盖 |
| G-KW-04 多图标菜单栏 | U9 / I7 | 已覆盖 |
| G-KW-06 历史缩放/拖动 | F3 | 已覆盖 |
| G-KW-08 进程网络排行数据 | I4 | 部分覆盖（I4 是 Intent 扩展，**F5 进程级网络排行在 Stage 2**——建议提前到 Stage 1，否则 Pro 首屏卖点缺失） |
| G-KW-10 双阈值告警 | F4 | 已覆盖 |
| G-KW-13 图标布局编辑器 | U9 配套 | 需补充 UI 步骤（拖放编辑器） |
| G-KW-17 Interactive Widget | I2 | 已覆盖 |
| G-KW-18 Live Activity 未接线 | **未在 Stage 1** | ⚠️ **需新增**：Stage 0 只做了 Activity 壳，request 调用与数据源未接，这是 Pro 核心卖点 |
| S-01 DesignSystem | V1 / V2 | 已覆盖 |

**需要写进 Stage 1 清单的两处新增**：
1. **F5 进程级网络排行提前到 Stage 1**（Pro 的差异化卖点，Stage 2 太晚）
2. **Live Activity 接线**（request + Activity 数据源 + 清理/监控进度演示）

### 6.4 建议动作

1. 严格按 Stage 1 执行 F1→F10 + U1/U2/U9 + V1/V2/V6 + I2/I4/I7，本报告 6.3 的两处新增并入
2. 每个功能页做完必须过"信息密度 × 可定制 × 即时反馈"三问（这是与 iStat 的差距本质）
3. V1/V2（DesignSystem）**必须最先做**——它是 U1/U9/F10 的前置依赖

---

## 7. 横向结论（4 App 共性问题）

### 7.1 三个共性断点

1. **商业闭环全线未接线**（4/4 App）：paywall 全写了，入口全没有。这是**最大的统一 P0**——按 CLAUDE.md 的定价策略，当前状态收入为 0。
2. **结果/价值页面断连**（3/4 App）：kDupe 结果页、kFresh 孤儿页、kSpaceClean 星系 stub——引擎 → 成果展示的最后一公里断了。
3. **精品 UI 三要素缺失**（4/4 App）：信息密度（可定制逐项配置）、即时数字反馈（清理/监控后的"回收 X GB"）、动效与状态完备（loading/empty/error）。

### 7.2 按商业影响排序的修复优先级（不改现有路线图，kWatch 仍最先）

| 优先级 | 动作 | 影响的 App | 理由 |
|---|---|---|---|
| 1 | kWatch Stage 1（含新增 2 项） | kWatch | 旗舰 + 付费转化 |
| 2 | paywall 入口 + 免费额度 gating 接线 | 4 个 App 通用模式 | 收入闭环 |
| 3 | 结果页接通（onReview→loadGroups→分组列表） | kDupe | 30 秒劝退 |
| 4 | RootView 补 DeepClean/StartupItems 入口 + showPaywall | kFresh | 写完的页面暴露 |
| 5 | 一键清理 + 回收空间反馈 + Settings 订阅管理 | kSpaceClean | 首页心智 |

### 7.3 给独立开发者的战略提示

- **不要跟 CleanMyMac 比功能全**（它 29M 下载 + 生态协同）；要比**单点深度 + 平台集成**——DaisyDisk 用可视化单点拿 3 次年度奖、AppCleaner 用拖拽心智活 18 年，都是先例。
- 竞品已验证的**免费→付费转化漏斗**（试用 + 额度限制 + 恢复购买）是标准动作，当前 4 个 App 一个都没接。
- 免费层做够体验（扫描/监控全开）、Pro 层做深度（历史/自动化/高级集成），是 iStat 与 Stats 共同证明的分层——kWatch 的 free/pro split 决策正确，落地时确保 UI 上 Pro 边界清晰（F2）。

---

## 8. 证据与参考

- 现状侧：`/tmp/kwatch-evidence.md`、`/tmp/other-apps-evidence.md`（代码级盘点，行号锚点）
- 竞品侧：`/tmp/competitor-evidence.md`（11 个竞品画像 + 四赛道精品标准 + 速查表 + [Web]/[Known] 标注）
- 关键来源：bjango.com/mac/istatmenus、github.com/exelban/stats、apps.apple.com iPulse、macpaw.com（CleanMyMac X / Gemini 2）、drbuho.com、daisydiskapp.com、overmacs.com、freemacsoft.net、github.com/alienator88/Pearcleaner、App Store iTunes Lookup API

---

*报告完 — 2026-08-01。kWatch 详细实施路径见 `kWatch/V1-TODO.md`（Stage 0 完成，Stage 1 待启动）。*
