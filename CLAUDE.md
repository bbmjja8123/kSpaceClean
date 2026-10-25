# Kraftly Mac App Suite — 项目指南

> 这是基于腾讯柠檬清理（`/Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon`）独立开发者启动的新一代 Mac App 矩阵。**所有代码全新 Swift 编写，仅核心逻辑参考 Lemon 实现思路，绝不复用 Lemon 任何 Objective-C / C++ 代码。**

---

## 1. 项目总览

### 1.1 目标
打造 **4 款精品 Mac App**，独立开发者运营，全球 + 中国 App Store 同步上架，通过免费层 + 买断盈利，并争取苹果编辑推荐。

### 1.2 4 款 App 一览

| App | Bundle ID | 主轴 | 定价 | 状态 |
|---|---|---|---|---|
| **kWise**（Mac 管家 / CMM 对标，产品名 Klaris） | `app.kraftly.klaris` | 空间解剖单一画布（扫描即动作 + 就地预演）+ 叙事历史 | 免费（扫描+归因+拒答清单）+ $9.90 买断 | 🔄 **Klaris P2 单一画布完成** |
| **kMonitor**（菜单栏监控） | `app.kraftly.kmonitor` | 平台集成 + Widget | 待设计 | 📋 Backlog |
| **kSift**（重复/大文件/粉碎） | `app.kraftly.ksift` | 极客 + AI（开发者场景） | $9.99 买断 | 📋 Spec 定稿 |
| **kUninstall**（应用卸载） | `app.kraftly.kuninstall` | 平台集成 + 自动化 | 待设计 | 📋 Backlog |

### 1.3 品牌
- 命名规范：所有 App 以 `k` 前缀开头（kWise, kMonitor, kSift, kUninstall）
- 统一品牌：**Kraftly**（App Store 元数据、官网、社交账号统一）
- Slogan 候选：`Kraft — Cleaner Mac tools, made with care`
- **历史改名**：原 `kSpaceClean` 已重命名为 `kWise`（2026-08-03 锁定）；2026-09-28 P0 归因改造时 bundle ID 再次迁移为 `app.kraftly.klaris`（App 从未上架，无历史评分/内购需保留，App Group 同步迁至 `group.app.kraftly.klaris`，深链统一为 `klaris://`）。详见 §3.0。

---

## 2. 工程架构（已确认）

### 2.1 Workspace 结构
```
KraftlyWorkspace.xcworkspace         # 顶层 workspace
├── kFoundation/                     # 本地 Swift Package（共享层）
│   ├── FileScanner/                 # 文件枚举、Hash、相似度
│   ├── PrivacyShield/               # TCC 权限管理
│   ├── AppCatalog/                  # 应用识别
│   ├── DaemonBridge/                # XPC 抽象
│   ├── Capabilities/                # OS 版本能力探测
│   ├── DesignSystem/                # SwiftUI Tokens / 组件
│   └── CommonUtils/
├── kWise/                     # App target
├── kMonitor/                          # App target
├── kDupe/                           # App target
├── kUninstall/                      # App target
├── Tools/                           # 共享脚本（版本号/签名/归档）
└── docs/
```

### 2.1.1 kFoundation 框架架构（v2.2 起）

各 App 的引擎代码已抽取为 kFoundation 的独立 library target，App 只做 UI 壳：

| Target | 来源 App | 内容 | 依赖 |
|---|---|---|---|
| `DetectionCore` | kSift | 重复/大文件检测管线（字节级/APFS clone/感知哈希/构建产物/目录去重）、ScanOrchestrator、Vault、SelectionPlanner | FileScanner |
| `AppCatalogCore` | kFresh | 应用目录扫描、残留检测（cask_rules.json 1141 条 + zh_app_mappings.json 为包资源）、Backup/Audit、FDA probe | CommonUtils, FileScanner |
| `MonitorCore` | kMonitor | SharedSnapshot/SnapshotWriter（App Group 契约）、MetricAlert、AlertEvaluator、诊断导出 | MetricsKit |

**规则**：修改这三个 target 走 kFoundation 特殊路径（§5，--allow-kfoundation）；App 专属实现（Core Data 仓库、PowerScope 授权引导、Photos、支付）留在各自 App 目录；注入点：kSift `App/CleanupStack.swift`、kFresh `App/AppServices.swift`。

### 2.2 关键技术决策
- **语言**：Swift 5.9+
- **UI**：SwiftUI 为主 + AppKit 兜底菜单栏 / 系统集成
- **最低系统**：macOS 13.0（用户本地机器版本）
- **编译目标**：macOS 14 SDK（用 `#available` 包裹高版本 API）
- **持久化**：Core Data（统一）+ Codable + FileManager（轻量场景）
- **并发**：Swift Concurrency（async/await + TaskGroup）
- **图形**：纯 SwiftUI 声明式 UI（无 Metal、无自绘地图；2D 空间地图 sunburst/treemap 已随 P2 T9 退役）
- **AI**：NLEmbedding（端上语义归因，零网络）+ 本机规则引擎（无 CoreML 模型、无云服务）
- **分发**：**仅 Mac App Store**（不做 DMG / 官网 / Notarized）

### 2.3 能力降级策略
使用 `kFoundation/Capabilities/CapabilityGate.swift` 集中探测：

| 能力 | 最低版本 | 用法 |
|---|---|---|
| SwiftData | macOS 14+ | 13 降级到 Core Data |
| Live Activities | macOS 14+ | 13 不展示 |
| Interactive Widgets | macOS 14+ | 13 用基础 Widget |
| Control Widgets | macOS 14+ | 13 隐藏入口 |
| App Intents | macOS 13+ | 全版本支持 |
| TipKit | macOS 14+ | 13 跳过引导提示 |

### 2.4 沙箱与权限
所有 App **App Sandbox 强制开启**（App Store 必需）。**不使用 Privileged Helper / SMJobBless**（App Store 不允许且维护成本高）。改用 TCC Full Disk Access（用户手动授权）。

| App | Sandbox | 需要的 TCC 权限 |
|---|---|---|
| kWise | ✅ | Full Disk Access + Automation |
| kMonitor | ✅ | 无（只读系统 API） |
| kDupe | ✅ | Full Disk Access + 用户授权目录 |
| kUninstall | ✅ | Full Disk Access + Automation |

### 2.5 与 Lemon 的关系
- ✅ **参考**：扫描算法（两阶段 size→hash）、Daemon 架构思路、Helper 思路（但新写不部署）
- ❌ **不复用**：任何 Objective-C / C++ 代码、UI 代码、上报/统计逻辑
- ❌ **不接**：腾讯上报后台 / QQ / 微信相关 SDK
- ✅ **重新做**：所有 Swift 代码、所有 SwiftUI UI、所有 TCC 权限处理、所有 XPC Service

---

## 3. kWise 详细设计（v1.5 路线定稿）

> **v1 → v1.5 演进**：原 kSpaceClean v1（2026-07-25 定稿）已重命名为 kWise，对标 CleanMyMac X。v1 已完成模块（扫描树 / 应用缓存规则 / Widget / Shortcuts 等）大部分继承——其中旧 FDA 引导已由 PowerScope 主目录授权替代（P1）、旧规则引擎已删除（P1 T9）。v1.5 新增 6 个模块作为 App Store 上架硬门槛。详细 roadmap 见 `docs/superpowers/specs/2026-08-03-kwise-cmm-parity-roadmap.md`。

### 3.0 命名与定位

- **产品名**：Klaris（CN: 明澈）—— Xcode target/模块名仍为 `kWise`（2026-09-28 P0 已迁移，PRODUCT_NAME=Klaris）
- **bundle ID**：`app.kraftly.klaris`（2026-09-28 P0 迁移；App Group `group.app.kraftly.klaris`，深链 `klaris://`）
- **Slogan**：Smarter care for your Mac / 智能清理，焕然如新
- **对标**：CleanMyMac X
- **产品矩阵**：kWise 主 + kMonitor / kSift / kUninstall 独立 App（双层矩阵，B1a）

### 3.1 一句话定位
让 Mac 回到"最佳状态"——一键智能清理 + 启动项 + 隐私 + 磁盘健康，对标 CleanMyMac X 的全能 Mac 管家。

### 3.2 目标用户
- **主**：MacBook 256GB/512GB 用户，频繁弹"磁盘已满"告警
- **次**：创意工作者（视频/摄影），需要定期清理临时文件
- **不服务**：开发者（→kDupe）、极客玩家（→kDupe）、系统监控需求者（→kMonitor）

### 3.3 核心差异化
| 维度 | CleanMyMac X | DaisyDisk | kWise 差异点 |
|---|---|---|---|
| 主界面 | 模块拼盘 | 磁盘可视化 | **空间解剖单一画布**——唯一首屏，动态分组（归因 cause 组 + 重复/相似照片/大文件检测组，空组不出现），扫描在 hero 内发起（扫描即动作），就地预演，无独立扫描页/清理页/工具箱 |
| 智能分类 | 规则匹配 | 无 | **本机规则归因（attribution_rules.json）+ NLEmbedding 端上语义推测（probable 档），零网络、无云模型** |
| 扫描速度 | 中等 | 慢 | **单引擎 ScanOrchestrator 流式扫描（实时合成 + ETA）** |
| 隐私 | 上报统计 | 本地 | **零网络上报，所有计算在本地** |
| 一键清理 | ✅ | ❌ | ✅ **统一两段预演式清理**（画布组/快捷回收/下钻页三个入口全部先预演再执行，预演与执行逐项一致、每项给原因、可逐项豁免）+ 废纸篓回滚 |
| App Store 集成 | ✅ | ❌ | ✅ + Shortcuts 集成 |

### 3.4 Klaris 功能现状（P2 单一画布后）

> IA 收敛（P2 T9）：导航只剩 3 项 `.anatomy / .history / .settings`；下钻页在画布内路由，粉碎窗 / 磁盘健康详情以 sheet 呈现。已退役表面：Toolbox / SpaceMap（2D 空间地图）/ CleanupContent / SmartCareHero / 独立扫描页 / 各工具视图（~27 个 UI 文件删除）。

| 模块 | 内容 | 状态 |
|---|---|---|
| 🆕 **空间解剖单一画布** | 唯一首屏（AnatomyView）：动态分组（归因 cause 组 + 重复/相似照片/大文件三检测组，空组不出现）+ 五色徽章（绿可回收/蓝迁出/橙注意/红数据·不属垃圾/灰不敢判）+ refused 派生 UncertainCard | 🔴 P2 重做 |
| 流式扫描（ScanOrchestrator） | 扫描在画布 hero 内发起（扫描即动作，含进行中/取消/完成态）；单引擎，实时合成 + ETA | ✅（P2 收进画布） |
| 统一预演式清理 | **三个入口（画布组 / 快捷回收 / 下钻页）全部先预演再执行**，预演=执行逐项一致、每项给原因、可逐项豁免 + 废纸篓 30 天回滚 | ✅（P2 T5 收口） |
| **Smart Care** | 降级为画布 hero「安全快捷回收」流（QuickCleanHeroStates），不再是独立页面；深链 `klaris://smartcare` 落画布 | 🔄 P2 再降级 |
| 分组下钻 | GroupDrillDownView（画布内 navigationDestination）：文件级勾选 + 就地预演入口 + 节点问答（AssistantNodePanel 复用） | 🔴 P2 新增 |
| 叙事历史 | TimelineView + NarrativeHeader（吸收月报，P2 T7）；按 run 分组、整体回滚 | ✅ |
| 设置 | 吸收维护（~/Library/Logs 引导动作）/ 隐私（TCC 概览）/ 归因规则查看（P2 T8） | ✅ |
| Onboarding | 3 页（价值主张 → 扫描承诺+主目录授权合并 → 就绪），完成后自动首扫（P2 T8） | ✅ |
| 文件粉碎 | 画布「+」菜单 sheet（1-pass 覆写 SSD 诚实文案 + 校验 + 改名 + trash 处置） | ✅（P2 T4） |
| 磁盘健康 | 画布 DiskHealthCard + 详情 sheet（S.M.A.R.T. + 卷诊断 + 预测） | ✅ |
| 🆕 启动项管理 | 引擎 + UI 均交付（P3：设置页分区 + 「+」菜单 sheet；系统级项只读引导） | ✅（P3 重接入） |
| 🆕 应用卸载（基础） | 引擎 + UI 均交付（P3：「+」菜单 sheet，双栏 + 残留分组 + 提交口径诚实弹窗） | ✅（P3 重接入） |
| PowerScope 主目录授权 | 主目录书签授权（画布 grant gate 承接，替代旧 FDA 引导） | ✅ |
| 菜单栏图标 | 显示已用空间 + 一键扫描入口 | ✅ |
| 桌面 Widget | 基础版（13）+ Interactive 版（14+，交互按钮落 `klaris://smartcare` → 画布） | ✅ |
| Shortcuts App Intents | 扫描/清理等（走 ScanOrchestrator 单引擎） | ✅ |
| Finder 扩展 | 右键"用 Klaris 扫描" → `klaris://scan?path=` 落画布 | ✅ |
| 助手问答 | 下钻页节点级问答（AssistantNodePanel，聊天框已退役；答案诚实，不承诺扫描/清理范围外的事） | ✅（P2 T9 fix） |
| Live Activities / Spotlight / 空间地图 | 已删除（v2.0 Phase 1 / P2 T9 清理死面） | ❌ 已删 |
| 本地化 | 英文 + 简体中文 + 日文 | ✅ |

**深链（P2 终态）**：`klaris://scan?path=` / `smartcare` / `health` → anatomy；`history` → history；`settings` → settings。退役面的旧深链（clean/privacy/startup/uninstall/shred/tools/spacemap 等）不再路由。

### 3.5 kWise 内部模块
```
kWise/
├── App/
│   ├── kWiseApp.swift                # @main
│   ├── RootView.swift                # NavigationSplitView（rail 3 项：anatomy/history/settings）
│   ├── AppCoordinator.swift          # 深链路由（klaris:// 终态）+ 粉碎 sheet
│   └── AppGraph.swift                # DI 单根
├── Features/
│   ├── Anatomy/                      # 画布数据层（CanvasGroup/CanvasScanCoordinator）+ GroupDrillDownView
│   ├── Attribution/                  # AnatomyView（唯一首屏）+ 归因引擎（规则 + NLEmbedding）
│   ├── SmartScan/                    # ScanOrchestrator 单引擎 + IntentScanAdapter
│   ├── Cleanup/                      # 统一预演（CleanupRehearsal）+ 引擎 + buyout gate
│   ├── History/                      # 时间线 + 叙事头（吸收月报）
│   ├── Settings/                     # 设置（吸收维护/隐私/归因规则查看）
│   ├── Onboarding/                   # 3 页引导 + 自动首扫
│   └── Shredder/ ...                 # 粉碎 / DiskHealth / Assistant(节点问答) / Gamification 等支撑模块
├── Store/                            # StoreManager（$9.90 非消耗买断）+ PaywallView
├── Shared/WidgetFeed/                # Widget 快照 + 交互清理（双 target）
├── Intents/                          # App Intents / Shortcuts（走 ScanOrchestrator）
├── FinderExtension/                  # 右键菜单扩展
├── Resources/
│   ├── attribution_rules.json        # 本机归因规则
│   └── Assets.xcassets
└── Info.plist
```

### 3.6 盈利设计
- **价格**：**免费（扫描 + 归因 + 拒答清单永久免费）+ $9.90 买断**（解锁回收执行；无订阅、无试用）
- **付费门槛**：未购买时清理是**拒答**（所选目标全部跳过 → 弹 Paywall），不做额度截断（1 GiB/月配额已于 P1 T7 退役）
- **地区定价**：美 $9.90 / 中 ¥68
- **内购 SKU**：`app.kraftly.klaris.buyout`（Non-Consumable 买断）

### 3.7 ASO 关键词（美区主目标）
- **主关键词**：`mac cleaner`、`disk cleaner`、`storage cleaner`、`clean my mac`、`mac storage`
- **辅关键词**：`cache cleaner`、`system junk`、`free up space`、`apple silicon cleaner`
- **避坑**：不使用 CleanMyMac 商标名（App Store 拒）

### 3.8 上架时间表（独立开发者）
> ⚠️ 下表为 v1 时期的历史规划记录，交付现状以 §3.4 功能表与 §7 进度为准（3D 星系图 / Spotlight / Live Activities 未交付或已删）。
| 阶段 | 周次 | 交付 |
|---|---|---|
| 0 | W1-W2 | kFoundation 骨架 + 权限层 + 2D 扫描原型 |
| 1 | W3-W5 | 扫描引擎 + CoreML 分类 + 清理动作 + TCC 引导 |
| 2 | W6-W8 | 3D 磁盘星系图（Metal）+ 菜单栏图标 |
| 3 | W9-W10 | Widget + Shortcuts + Finder 扩展 + Spotlight |
| 4 | W11-W12 | Live Activities + 多语言 + App Store 元数据 + TestFlight |
| 5 | W13 | App Store 提交 + 申请苹果推荐 |
| 6 | W14-W18 | V1.1 修复评论 + 性能优化 + 小迭代 |

⏱️ 预计 **13-14 周从开工到 v1 上架**，每周投入 ~25-30 小时合理。

### 3.9 上架后第一周关键动作
1. ProductHunt + X/小红书 同步发布
2. 联系 5-10 位 Mac 评测博主送 Pro 兑换码
3. 申请 App Store 编辑推荐（Apple 开发者后台）
4. 建立 Discord/Telegram 用户群收集反馈

### 3.10 v1.5 CMM Parity 上架门槛（硬约束）

**⛔ kWise v1.5 必须完成下列 6 个模块才能提交 App Store：**

| # | 模块 | 来源 |
|---|---|---|
| M1 | **Smart Care**（一键智能清理） | 本会话主轴 |
| M2 | **启动项管理** | CMM X parity |
| M3 | **隐私清理**（浏览器历史 + 应用权限概览） | CMM X parity |
| M4 | **磁盘健康卡片**（S.M.A.R.T. + 卷状态） | CMM X parity |
| M5 | **应用卸载（基础版）** | 由 kUninstall 集成 |
| M6 | **文件粉碎（基础版）** | 由 kSift 集成 |

**强烈建议（非阻塞）：** 定时自动清理 / L2 语义归因。

> P3 后现状：M1 快捷回收（画布 hero）；M2/M5 已重接入 UI；M3 权限概览入设置页；M4/M6 画布 + sheet。双渠道（MAS/直营）见 §5.4。

**功能范围待 grill：** UI 重做方案 / Smart Care 具体行为 / 启动项 UI 位置 / 隐私权限数据源 / 基础 vs 深度卸载切分线。

详细 spec：`docs/superpowers/specs/2026-08-03-kwise-cmm-parity-roadmap.md`。

---

## 4. Backlog（待设计）

### 4.1 kMonitor（菜单栏监控）
- **主轴**：平台集成 + Widget + Live Activities
- **目标用户**：极客 / 设计师 / 视频创作者
- **定价**：Free + $7.99 Pro 买断（vs iStat Menus $11.99）
- **详细规格**：`docs/superpowers/specs/2026-07-26-kraftly-kmonitor-design.md`
- **状态**：✅ v1 设计定稿，待 writing-plans 拆解实施计划

### 4.2 kDupe（重复/大文件）
- **主轴**：极客 + AI（开发者场景）
- **目标用户**：开发者 / 设计师 / 摄影师
- **待定**：是否独立还是合并到 kWise V2
- **预期时间**：kWise 稳定后再启动

### 4.3 kUninstall（应用卸载）
- **主轴**：平台集成 + 自动化（Shortcuts / Finder 扩展 / Control Widget）
- **目标用户**：全人群，特别是试装党
- **待定**：是否独立还是合并到 kWise V2
- **预期时间**：Backlog

---

## 5. 通用约定

### 5.1 代码风格
- SwiftLint 强制（`swiftlint` 配置在 `kFoundation/.swiftlint.yml`）
- Swift 5.9+ 严格并发（`SWIFT_STRICT_CONCURRENCY = complete`）
- 所有公共 API 必须有 DocC 注释
- 提交前必须跑 `swift test` + 单元测试覆盖率 > 70%

### 5.2 Git 规范
- 主分支：`main`（保护，仅 PR / 显式 merge 合并）
- **全部 App 直接在 main 开发**（2026-09-09 起）：4 个 worktree 全部删除，主 worktree（kSpaceClean，main 分支）是唯一开发现场；kFoundation 框架架构（§2.1.1）不受影响
  - `scripts/commit-app.sh <app>` 仍用于 stage 边界检查（跨 App 路径拒绝、kFoundation 需 --allow-kfoundation）
  - 多 App 改动的调用点修复在同一 commit 内完成（单 worktree 有全部 App 源码，可一次构建验证 4 个 target）
- 开发分支：`feature/<app>-<feature>`、`fix/<app>-<bug>`（短期 feature 分支在对应 worktree 内使用）
- 提交信息：`feat(kWise): add anatomy hero view`
- Merge 节奏：见 `docs/workflow/4-worktree-merge-cadence.md`（默认每周五 16:00 merge window）

### 5.3 安全与隐私
- 任何网络请求必须经过用户明确同意
- 默认零分析、零上报
- 如需崩溃收集，使用 **Apple MetricKit**（本地，不上报）

---

## 6. 参考资源

### 6.1 Lemon 老项目
- 路径：`/Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon`
- **使用方式**：仅参考核心逻辑（扫描算法、Daemon 架构思路）
- **禁用**：不要复制 Objective-C / C++ 代码

### 6.2 关键文档（仅逻辑参考）
- `Lemon/doc/清理流程文档.doc`
- `Lemon/doc/查找大文件.docx`
- `Lemon/doc/查找重复文件.docx`
- `Lemon/doc/Lemon Daemon启动流程.md`

### 6.3 外部参考
- CleanMyMac X（订阅标杆）
- DaisyDisk（视觉标杆）
- iStat Menus（菜单栏监控标杆，kMonitor 灵感）
- BuhoCleaner（华人独立开发标杆）
- Apple Design Awards 2025（推荐方向）

---

## 7. 当前进度

### kSpaceClean v1 — Complete ✅
- [x] 项目可行性分析
- [x] 竞品调研（CleanMyMac / DaisyDisk / iStat Menus / Gemini 2 / BuhoCleaner）
- [x] 拆分方案锁定（A：4 款精品矩阵）
- [x] 技术架构（Workspace + kFoundation + Swift 全新）
- [x] kSpaceClean v1 完整设计
- [x] 规格自审 + 用户复核
- [x] 实施计划（writing-plans）
- [x] **v1 全部 19 个 Task、39 个文件已创建（2026-07-25）**

### kMonitor v1 — Spec 定稿 ✅
- [x] 产品定位 + 定价（Freemium + $7.99 Pro 买断）
- [x] 功能规格（4 Free + 3 Pro 指标 + 平台集成）
- [x] 技术架构（Clean Architecture + actor + AsyncStream）
- [x] 完整 UX 交互设计（菜单栏 + Dashboard + Widget + Live Activity + Shortcuts + Spotlight）
- [x] 数据层设计（Core Data + App Group JSON snapshot）
- [x] 7 大指标检测实现细节（host_processor_info / SMC / libproc 等）
- [x] 隐私与合规策略（GDPR / CCPA / App Privacy Details）
- [x] 崩溃监控与诊断方案（MetricKit）
- [x] 测试策略（单元/集成/UI/性能 + 兼容性矩阵）
- [x] 营销与发布节奏（4 周预热 + 上线日动作清单）
- [x] 5 大风险 Plan B（审核被拒 / SMC 不可用 / Live Activity 拒绝等）

### kSift v1.2 → 精品包 — Ship-Ready ✅ (2026-09-06)
- [x] **Phase 0 构建修复** — kFoundation 路径 → `../kFoundation` + XcodeGen scheme；修复 8 处未编译提交的语法/逻辑错误；测试宿主 Core Data 改用临时目录（App Group 容器楔死规避）；测试基线 136/136 绿（`chore(kSift)` 62fec92）
- [x] **Phase A 结果页重构** — SelectionPlanner 5 种保留策略 + 每副本可解释 reason（竞品无的差异化）；分组 checkbox 选择模型 + VM 同步（修 stale bug）；ToastView 复活为 Undo 入口（restoreSession + ⌘Z）；FileRowView 修改日期；真 QuickLook（_QuickLook_SwiftUI）；rail 标签/⌘1-6/菜单 Commands（a3ab780）
- [x] **Phase B 首屏与扫描** — IdleDashboardView（Quick Start 预设卡 + 最近扫描 reassurance）；ScanThroughputEstimator EWMA ETA/吞吐/已扫字节；动效体系（Reduce Motion 门控）（e9f6136）
- [x] **Phase C 引擎可配置** — SimilarityPreset strict/normal/loose 持久化并 per-run 生效（回应"误报"Top 抱怨）；大文件 UI（结果页 segmented + LargeFilesListView + 阈值设置 + ShowLargeFilesIntent 数据链）；macOS 13 兼容性提示；新增 ProfileType.custom（dfd21d2）
- [x] **Phase D 信任与付费** — Paywall 重写（6 feature/买断 vs 订阅对比/3 FAQ，不点名竞品）；InUseChecker（lsof 批量 + 2s 硬超时 + 启发式降级）接入全部 3 个清理入口（6fa075a）
- [x] **Phase E 历史洞察** — Swift Charts 周趋势（8 周桶跨月/弃 >8 周）+ 类别分布 + profile badge + 删除确认（96a2f38）
- [x] **Phase F1 相似视频** — PerceptualHashing 共享原语抽取；SimilarVideoDetector（AVAsset 关键帧采样 dHash + size/duration 容差预过滤 + union-find）；类型全链路 + AVAssetWriter 真视频集成测试（ece83ef）
- [x] **Phase F2 Photos 库去重** — PhotoLibraryProviding 协议隔离（测试零 PHPhotoLibrary）；PHAssetResourceManager 禁网 SHA-256 精确 pass（iCloud-only 快速失败并计数）；dHash perceptual pass；删除走系统"最近删除"（原生 30 天 undo，绕过 Vault）；entitlements + 权限流 + Photos 导航项（e24f60b）
- [x] **本地化** — 336 keys ×3（en/zh-Hans/ja）全程同步校验
- [x] **测试** — xcodebuild test 全绿（每 phase 一个 commit，`scripts/commit-app.sh kSift` 边界提交）

### Backlog（待设计）
- [ ] kDupe 设计 — 重复/大文件
- [ ] kUninstall 设计 — 应用卸载

> ⚠️ **现阶段不要写实现代码**。所有设计待汇总到 spec 文档并通过后，再通过 writing-plans 技能拆解为可执行任务。

---

### kWise v1.5 stage B — Ship-Ready ✅ (2026-08-08 → 2026-08-15)
- [x] **grill-me convergence** — 11 decisions locked (UI=Hybrid, Quality=MUST C-1/C-3/C-4/C-5/C-6/C-8, Scope=M1+M3+M4)
- [x] **Phase A (UI Shell)** — NavigationItem cases + Hybrid first-screen hero CTA + module grid
- [x] **Phase B (M1 Smart Care)** — 3-step orchestrator + recommended-pick + 全选/反选/清理 wiring + performCleanup+terminate+C-3 freed-bytes+C-4 rollback+C-8 menu bar + tests (11 cases)
- [x] **Phase C (M3 隐私清理)** — PrivacyView nav + inline minimal TCC.db reader (FDA-aware) + TCC overview view (12 services) + tests (7 cases)
- [x] **Phase D (M4 磁盘健康)** — SMART reader (diskutil subprocess + Apple Silicon graceful fallback) + VolumeDiagnostics + 首屏小卡 + detail view + tests (14 cases)
- [x] **Phase E (精品 audit + 本地化)** — C-1 audit (ScanTreeRow friendlyPath + 8-case test) + C-5/C-6 audit (PaywallView 3D → Smart Care + ScarewareCopyAuditTests) + Localizable.xcstrings v1.0 → v1.1 (16 new strings) + CLAUDE.md sync
- [x] **5 commits per phase / 18 commits total** — worktree-kwise-v1 ahead of origin/main
- [x] **精品 MUST 6/6** — C-1 ✅ C-3 ✅ C-4 ✅ C-5 ✅ C-6 ✅ C-8 ✅

### kWise v2.0 — 竞品超越冲刺 ✅ (2026-09-07)
> 8 phases / 9 commits on `worktree-kwise-v1`。计划：`.claude/plans/atomic-bubbling-wave.md`（含竞品差距矩阵 + 验收清单）。
- [x] **Phase 1 DI 统一 + 配额** — AppGraph 单根（1 StoreManager / 1 MenuBarManager / engine 带 quota+sinks）；1 GiB/月免费额度（超限截断 → Paywall）；SMAppService 登录启动；清理后通知真实化；Settings prefs 持久化修复；AI toggle 改名「智能推荐（本机规则）」；删 Spotlight/LiveActivity/LaunchAgent 死目录
- [x] **Phase 2 Toolbox + 孤儿接线** — 固定 6 项 rail + ToolboxView（8 卡片）；AppUninstall/LargeOld/Duplicate/PhotoClean 全部走 CleanupEngine（历史/回滚/配额）；Maintenance 去 Process → 引导式（~/Library/Logs 引擎动作）；deep link `?path=` 消费
- [x] **Phase 3 CTA + 菜单栏** — Smart Care hero CTA 全流程状态机 + containerOnly 授权卡；DiskHealthCard 上首页；菜单栏 quickClean/quickScan/openSettings 实现 + 真实「最近清理」行（CleanupEventSink）
- [x] **Phase 4 空间地图 2D** — SegmentBuilder（2π 守恒/小项折叠）+ Canvas sunburst/treemap + 下钻/面包屑 + ⌘选中映射 ScanTreeNode（删 .galaxy）
- [x] **Phase 5 M2 + M6** — 启动项：PowerScope 扫描 + 用户级 trash/restore 开关 + 系统级「需手动处理」引导；粉碎：护栏 → 1-pass 覆写（SSD 诚实文案）→ 校验 → 3 次改名 → trash 处置 + DELETE 确认
- [x] **Phase 6 Widget + Intents** — kWise/Shared/WidgetFeed 双 target（WidgetSnapshot 原子写 App Group + schemaVersion 守卫）；Widget 真实数据 + 交互清理按钮（Button(intent:) → klaris://smartcare）；Intents 回 target（Shortcuts 恢复）
- [x] **Phase 7 创意三件套** — Core Data 轻量迁移（runID/actionKind/restoredAt）+ 时间线（按 run 分组、整体回滚）；月报（DiskSampleStore 环形采样 + OLS 预测，r²<0.5 → 波动较大）；StreakStore/9 成就/StreakSink → widget streak
- [x] **Phase 8 助手 + Onboarding + 本地化** — AssistantIntentMatcher（zh/en 模板表，零网络，audit 测试禁 URLSession）+ 答案卡片；Onboarding 首启（welcome → PowerScope → tour）；xcstrings 30 → 51 keys（nav.* 三语）；NewCopyAuditTests（scareware 禁语 + 粉碎诚实文案）
- [x] **测试** — Phase 1/2/3/4/5/6/7/8 各模块新增 ~90 用例；xcodebuild test-runner 曾于 2026-09-05 挂起（环境 wedge），已随重启恢复 — 见「收尾债清理」全量基线

### kWise v2.1 — 精品级 UX 重构 ✅ (2026-09-07)
> 用户手动验收后判定的 4 个硬伤全部修复。4 commits on `worktree-kwise-v1`。
- [x] **Phase 1 壳层** — 删 ToolbarView（4 按钮全是 rail 重复）；rail 56pt + 品牌标志 + 对齐修复；窗口 minSize 1024×680；⌘I 面板开关；Onboarding 步骤指示（5 圆点 + 第 N/5 步 + 上一步/完成）；删 3 个空白旧页签 + 死代码（TwoColumnView/ScanContentView）
- [x] **Phase 2 三级主从扫描结果** — 根因修复：RecursiveTreeNode 展开时整棵子树一次性物化 → 主线程卡死；新 MasterDetail（分类卡 → 应用行(中文名+图标+整行点击展开) → 文件行(friendly path)）；行供给器 cap 30/20 + "显示其余 N 项"；O(1) nodeIndex/parentIndex + 增量汇总（原每次点击 2 次全树 DFS）；SummaryBar 清理改走真实勾选 + 确认面板 + 真实已释放字节
- [x] **Phase 3 详情面板** — DetailPanelView（app/category/file 三态，活解析不陈旧，C-1 raw path 仅 tooltip）；点行自动出现、无选中自动隐藏
- [x] **Phase 4 垂直预算** — PreScan 筛选控件滚动 + CTA 钉底（最小窗口不再裁切）；未扫描跳过 64pt header；400×500 卡死回归守卫测试

### kWise 工具箱深度打磨 — 三轮 ✅ (2026-09-08 → 2026-09-12)
> 全部在 main 直接开发（worktree 制度已退役）。~35 commits。
- [x] **工具箱 round-2**（9/8–9/10）— DetectionCore→toolbox 结果映射（可解释选择）；QuickLook 三件套抽到组件层；重复工具重接 ScanOrchestrator（策略/reason/缩略图/honest clones）；照片清理重做为双 Tab（相似照片网格 + 遗留缓存）；`kMDItemLastUsedDate` → InstalledApp.lastUsedDate；tabbed toolbox（每工具一个可关持久 tab）；卸载 round-2（拖入 .app 扫描 / App Reset / 共享组件告警 / 残留备份）；孤儿残留扫描 + 扫描路径记忆（AppCatalogCore + DetectionCore，Lemon 过滤规则）；大文件类型 chip、Cookie 登出告警、+3 assistant intents；启动项双栏 + 使用提示；空间地图类型着色 + hover 卡；粉碎环形进度；月报 Top5 大文件；AppDelegate 退出崩溃守卫
- [x] **卸载 AI 深度优化**（9/10–9/11，spec + 6-task plan 全落地）— ResidueExplainer（确定性白话解释 + ownerHint 提为共享 API）；ResidueGroupingEngine（规则遍 + NLEmbedding 兜底，可注入 provider）；HealthSummaryBuilder（可解释残留分级，50MB 绝对阈值优先）；AppUninstallDetailPanel（健康卡 + AI 分组 + 解释列表）；勾选语义统一（显式残留选择优先，整应用兜底）
- [x] **UX 收尾**（9/11–9/12）— W1 重复文件组内并排大图对比 + 清理完成横幅（measuredBytes 优先）；W4 照片 A/B 保留互换（组内恰保留一张语义不变）；DuplicateFolderDescriber 真语义标注（原 topicLabel 为死代码）+ 会话累计；确认面板文案与实际 commit 范围对齐；消失路径过滤；缓存 countLimit

### kWise 收尾债清理 ✅ (2026-09-26 → 2026-09-27)
- [x] **已知红测试修复** — 2 个生产 bug：① `StreakLogic.recordCleanup` 连日判断方向反了（streak 永远到不了 2，streak.3/7/30 成就全废）② `BackupManager.cleanupExpired` 按 bundleID 目录整体过期 → 40 天前的 v1 会连坐删掉昨天的 v2（改为按 `v<N>/` 版本独立计龄 + 回归守卫）；1 个测试基建 bug（`UninstallBackupStoreTests.setUp` 未建 root，`try?` 吞掉 fixture 写失败）
- [x] **本地化补齐** — Localizable.xcstrings 224 keys × 3 语全齐（补 508 个 string unit，既有译文 0 改写）；新增 `LocalizationCompletenessTests` 守卫空译文回潮
- [x] **存量红清理（16 个 → 0）** —— 其中 **7 个是真产品 bug**：
  - 空间地图「独立文件夹模式」整页空白（`bindFolderRoot` 漏填 `totalSize`，被 `filter{totalSize>0}` 滤空）
  - 文件粉碎从未真正处置文件（`randomizeRenames` 改名后最终路径被丢弃，`trashItem` 用原路径必 ENOENT → 报失败且覆写文件以随机名残留）
  - 卸载配额被拒却报成功（引擎记入 `skippedForQuota`，`uninstallSelected` 只看 `failed.isEmpty` → 用户以为已卸载，Paywall 不弹）
  - 全选后汇总栏显示 0 KB（`walk` 对 `.checked` 节点不下钻，而 `selectAll` 不回聚合）
  - 三级 `refreshState` 把 `.mixed` 子级算成「未选」，一个勾选叶子传不上三级态
  - 粉碎器 guardrail 放行系统路径的真实拼写（`/etc`→`/private/etc` 是符号链接，裸前缀匹配可绕过；`/private/tmp` 原本不在禁区）
  - 助手「什么时候会满」匹配不上模板（复合词缺口）
  - 另 4 个为测试夹具/契约问题（夹具漏填 `totalSize`、工厂函数当 provider、审计扫到注释、`minFileSize` 滤空夹具）
- [x] **全量测试基线** — test-runner 挂起已随重启消失。**最终基线 522 tests / 0 failures**（kWiseTests，2026-09-27，耗时约 21 分钟）。对比清理前 518/502/16 且因 4 次崩溃导致 runner 反复重启跑了约 7 小时

### Klaris P1 — 信任解剖改造 ✅ (2026-09-28 → 2026-09-30)
> 10 任务 + 2 修复轮，11 commits（`5a2ce3b..0a54d3c`）。spec：`.superpowers/sdd/2026-09-29-klaris-p1-trust-anatomy/`。P0（2026-09-28 bundle 迁移 `app.kraftly.klaris` + 归因数据层）已先行落地。
- [x] **T1 空间解剖成为 rail 首屏** — rail 固定 `[.anatomy, .scan, .tools, .cleanup, .history, .settings]`；smartCare 退为深链直达
- [x] **T2 L1 语义归因** — NLEmbedding sentence embedding probable 档接入归因服务管道（零网络）
- [x] **T3+T4 两段预演式清理** — 预演与执行 1:1 契约测试 + 每项可解释原因 + 逐项豁免 + 无归因行诚实标注；修复轮：确认只带确认集 + 本地化备注 + 双击守卫
- [x] **T5 解剖首屏视图** — cause 分组 + 置信徽章 + L1 区块（原预览面退役）
- [x] **T6 Smart Care 降级** — safe-quick-clean 次级页，首屏让位空间解剖
- [x] **T7 配额退役** — 1 GiB/月截断 → $9.90 非消耗买断（`app.kraftly.klaris.buyout`）；未购买 = 拒答（全跳过 → Paywall）；修复轮：启动时 entitlement 刷新 + 购买成功态
- [x] **T8 助手聊天框退役** — 问答内嵌 DetailPanel（AssistantNodePanel 节点级问答）
- [x] **T9 双引擎合一** — 旧规则引擎 + AIClassifier/RuleClassifier 死代码删除（~4,600 行）；Intents 走 ScanOrchestrator
- [x] **T10 文档诚实化** — 本文件假卖点修正 + 全量测试基线（见下）
- [x] **测试基线** — **579 tests / 0 failures**（`xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWise`，2026-09-30，全量单跑 ~7 分钟未触发 wedge）

### Klaris P2 — 单一画布改造 ✅ (2026-10-06 → 2026-10-07)
> 11 任务 + 3 修复轮，15 commits（`ac48837..5322707` + T10 docs）。spec：`.superpowers/sdd/2026-10-06-klaris-p2-single-canvas/`。
- [x] **T1 rail 收敛为 3** — `[.anatomy, .history, .settings]`，深链全部落画布
- [x] **T2 画布数据层** — CanvasGroup/CanvasEntry/GroupKind 动态分组组装器（空组不出现、refused→UncertainCard）+ CanvasScanCoordinator 三检测器 fan-out
- [x] **T3 解剖即唯一画布** — AnatomyView 重做：动态组卡 + 扫描即动作（hero 进度/取消/完成态）+ 按因动词（rehearse/guidance/migrate）；修复轮：rescan 身份去重 + 诚实取消
- [x] **T4 「+」菜单 + 拖拽粉碎** — 窗口级 drag-to-shred overlay + 粉碎 sheet 入口
- [x] **T5 统一预演收口** — 画布组/快捷回收/下钻页三入口全部先预演再执行；修复轮：快捷清理取消中止管线 + 清 stale 结果
- [x] **T6 分组下钻** — GroupDrillDownView：文件级勾选 + 就地预演入口 + 节点问答（AssistantNodePanel 复用）
- [x] **T7 叙事历史** — NarrativeHeader 吸收月报（环境每次现取 + 诚实百分比档）
- [x] **T8 设置吸收 + Onboarding 3 页** — 维护/隐私/归因规则并入设置页；onboarding 3 页（授权合并进第 2 页）+ 完成后自动首扫；修复轮：新文案三语补齐
- [x] **T9 退役清扫** — 20 面 → 6 面（~27 个 UI 文件删除，NavigationItem 3 case）；修复轮：快捷清理 grant gate 恢复 + 结果卡渲染 + 助手诚实文案
- [x] **T10 收尾** — 本文件按单一画布现实重写 + 全量测试基线（见下）
- [x] **测试基线** — **562 tests / 0 failures**（build-for-testing + 分批 -only-testing，45 批逐批报告，2026-10-08）。13 个源码枚举型审计类/方法因宿主 wedge（沙箱测试宿主 open()/trash-XPC 阻塞，重启可解）跳过，其源码审计断言已带外 grep 复核全绿；待重启后复跑（详见 task-10-report）
- [x] **能力决策备忘（待 Product）** — 卸载/启动项引擎已交付但 UI 不可达（P3 候选）；助手答案诚实化（只承诺已实现能力）

### Klaris P3 上架准备 — 双渠道 + 提审补齐 🔄 (2026-10-25)
> 5 commits（`e2e77f1..47db984`）。计划：`.claude/plans/playful-exploring-crab.md`。三路全程序排查（M1-M6 可达性 / MAS 合规 / 构建-测试-文档）后按用户决策落地。
- [x] **P0 — 图标与版本工具** — icon_1024 修为 1024×1024 8-bit（master 存 Tools/branding/）；version-bump.sh 改写为 project.yml + XcodeGen 口径
- [x] **R1 — 双渠道架构** — KlarisDirect target（Developer ID，无沙盒 + Hardened Runtime，DISTRIBUTION_DIRECT）与 MAS kWise（DISTRIBUTION_MAS）同源码共 bundle ID；PowerScope 加 `.fullAccess` 档 + DirectScopeProvider；DistributionChannel 单缝；**修复 ENTITLEMENTS_FILE 从未生效的隐性 bug**（改 CODE_SIGN_ENTITLEMENTS，Debug ad-hoc / Release 真 entitlements + Team TC973L6HPC）；hasFullDiskAccess TCC 探测删除（scope 层级语义接管）；Onboarding/设置/买断墙按渠道分支（直营 = MAS 购买引导）；MasScanScope.md 三层可读性契约 + ScanScopeContractTests（10 用例）
- [x] **R2 — MAS 扫描诚实性** — PrivacyScanner 注入真实主目录（原 NSHomeDirectory 静默扫容器）；设置页隐私区 container-only 授权引导；FDA 行直营专属；画布 systemStatus 占位符改真实 scope 状态行；引擎跳过的受限根上画布诊断（noteSkippedRegions，禁止静默丢弃）；KlarisDirect Debug 产物改名防 DerivedData 冲突
- [x] **R3 — M2/M5/M3 重接入** — AppUninstallView（双栏 + 拖入扫描 + 提交口径诚实弹窗）+ AppUninstallDetailPanel；StartupItemsView（用户项停用/恢复 + 系统项只读 + 畸形 plist）；PrivacySurfaceCatalog 入设置页（死 chevron 移除、FDA 行渠道门控）；AppGraph appUninstallVM/startupItemsVM 工厂 + CanvasPlusMenu 4 项 + 深链退役注释；GraphFactoryRewiringTests
- [x] **R4 — 提审机械项** — 全量本地化清扫（~450 keys ×3 语，3 并行批；助手意图匹配表保留中文模式）；Localizable.xcstrings 846 keys；InfoPlist.xcstrings（CFBundleDisplayName ×3 target）；appex PrivacyInfo ×2；删 NSAppleEventsUsageDescription；DiskHealthDetailView 注入画布同款 VM；文案审计测试改钉 key
- [x] **P5 文档/脚本** — upload_to_testflight.sh 重写（kWise 口径）；release_direct.sh（公证+staple）；SubmissionChecklist/Runbook/PrivacyDetails/Metadata 对齐买断制与双渠道
- [x] **双渠道全量基线（2026-10-25 重启后）** — MAS scheme kWise：**672 tests / 0 failures**（修复 1 个 R4 遗留断言：DuplicateFolderDescriberTests 改钉本地化键 `dupe.topic.photos`，commit 6330461）；P2 wedge 跳过的审计/门禁测试全数复跑通过（SurfaceRetirementAudit 3、AttributionCopyAudit 3、ScarewareCopyAudit 2、LocalizationCompletenessTests 2，本地化门禁全绿）；KlarisDirect scheme Debug 构建通过（单测宿主为 MAS app，Direct 渠道语义由渠道无关的 ScanScopeContractTests 钉住，KlarisDirect scheme 无 test action）。首次尝试编译失败系重启后 DerivedData 陈旧模块缓存，重构建即恢复
- [ ] **待办（需用户/GUI）** — UI 冒烟（onboarding 授权 / +菜单→卸载 sheet / 设置启动项 / 双渠道 Paywall 路由）；App Store Connect 记录/截图/IAP 创建；Release 归档验证（GUI 会话出 profile）
- [ ] **决策备忘** — 直营正式付费方案（许可密钥/Paddle）；直营自动更新（Sparkle）；MAS 展示名终审

### Backlog（待设计）
- [ ] Klaris P3 剩余 — L2 语义归因；直营付费/更新方案；UI 冒烟 + ASC 材料
- [ ] kWise v2 — 3D 磁盘星系图（2D 空间地图也已随 P2 T9 退役；Metal 重启需 Product 拍板）
- [ ] Klaris 发布决策 — TestFlight / MAS 元数据 / 提审节奏（功能门槛已齐：6 模块 + 双渠道；待重启后全量基线 + ASC 记录/截图/IAP）

> ⚠️ **现阶段不要写实现代码**。所有设计待汇总到 spec 文档并通过后，再通过 writing-plans 技能拆解为可执行任务。

---

最后更新：2026-10-25（Klaris P3 双渠道全量基线：MAS 672/0 修复 R4 遗留断言 + 审计测试复跑全绿 + KlarisDirect Debug 构建；此前同日 P3 上架准备双渠道架构 + M2/M5/M3 重接入 + 提审机械清扫）