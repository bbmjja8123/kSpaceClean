# kFresh v1 设计规格（2026-08-01 refresh）

**项目**: Kraftly Mac App Suite
**App**: kFresh（应用卸载，前身 kUninstall）
**Bundle ID**: `app.kraftly.kfresh`（Finder 扩展 `app.kraftly.kfresh.finder-sync`，测试 `app.kraftly.kfresh.tests`）
**作者**: 独立开发者
**日期**: 2026-08-01（基于 2026-07-26 原版 refresh）
**状态**: Wave 0 ✅ DONE · Wave 1 启动中

---

## 0. 状态与变更

### 0.1 Wave 状态

| Wave | 范围 | 状态 | 文档 |
|---|---|---|---|
| Wave 0 | Bundle ID 启发式规则库 + Core 重写（TrashMover/ResidueDetector/AppCatalogService/BackupManager）+ Animation tokens + SwiftLint+CI | ✅ **COMPLETE**（35 commits, 59/59 tests） | `.superpowers/sdd/progress-kfresh-wave0.md` · `wave0-final-fix-report.md` |
| Wave 1 | 5 核心 feature 端到端：Onboarding / AppList / AppDetail / 卸载确认 / 历史 + 启动项 + 深度清理 + Pro gate | 🔄 **启动中** | `docs/superpowers/plans/2026-08-01-kfresh-wave1.md` |
| Wave 2 | Widget / App Intents / Finder Extension / MenuBar / 多语言 / Spotlight / 批量卸载 | 📋 Backlog | — |
| Wave 3 | 性能优化 / 多语言精修 / TestFlight / App Store 提交 | 📋 Backlog | — |

### 0.2 本版相对 2026-07-26 原版的变更

1. **品牌重命名**: kUninstall → kFresh（避免与商业产品名混淆）
2. **Bundle ID**: `app.kraftly.kuninstall` → `app.kraftly.kfresh`
3. **路径根**: `~/Library/Application Support/app.kraftly.kuninstall/` → `~/Library/Application Support/app.kraftly.kfresh/`
4. **Wave 0 状态**: Core 层 5 个服务已重写完成，Design tokens 已落地，CI 已跑通。本 spec 不再重复 Wave 0 实现细节，以链接引用为准。
5. **Wave 1 范围显式锁定**: §7 列出 Wave 1 必做与推迟项，作为 Wave 1 plan 的 spec 输入
6. **平台集成拆分**: Widget / Shortcuts / Finder / MenuBar 整体推迟到 Wave 2，独立 App 上架后再补
7. **风险更新**: §10 反映 Wave 0 完成后剩余风险

旧 spec 文档 `docs/superpowers/specs/2026-07-26-kraftly-kuninstall-design.md` 作为历史归档保留，不再生效。

---

## 1. 概述

### 1.1 一句话定位
让 Mac 应用卸载回到"彻底"——删一个 App，连它的所有指纹一起清干净。

### 1.2 目标用户
- **主**：全人群，特别是"试装党"（喜欢装各种 App 试用、频繁卸载的）
- **次**：Mac 新手，不知道 App 有残留文件、启动项概念的用户
- **不服务**：开发者（→kSift）、极客玩家（→kSift）、磁盘清理需求者（→kSpaceClean）

### 1.3 独立 App 定位
kFresh 为**独立 App**，不与 kSpaceClean 合并。后续 4 款 App（kSpaceClean / kWatch / kSift / kFresh）在成熟后考虑组合为统一 Kraftly 套件。

### 1.4 核心差异化

| 维度 | AppCleaner | Nektony App Cleaner | TrashMe 3 | Cleaner One Pro | **kFresh** |
|---|---|---|---|---|---|
| **价格** | 免费 | $19.99 买断 | ~$9.99 买断 | 免费+$19.99/年 | **免费卸载+$9.99 Pro** |
| **卸载残留** | ✅ 基础 | ✅ 高级 | ✅ 高级 | ✅ 基础 | ✅ 基础(免费)+深度(Pro) |
| **启动项管理** | ❌ | ❌ | ❌ | ✅ 部分 | ✅ **Pro** |
| **系统级清理** | ❌ | ❌ | ❌ | ✅ | ✅ **Pro** |
| **批量操作** | ❌ | ✅ | ❌ | ❌ | ✅ **Pro (Wave 2)** |
| **App Store** | ❌ 非 MAS | ✅ | ✅ | ✅ | ✅ |
| **Widget** | ❌ | ❌ | ❌ | ❌ | ✅ **Pro (Wave 2)** |
| **Shortcuts** | ❌ | ❌ | ❌ | ❌ | ✅ **Pro (Wave 2)** |
| **Finder 右键** | ❌ | ❌ | ❌ | ❌ | ✅ **(Wave 2)** |
| **可视化报告** | ❌ | ❌ | ❌ | ❌ | ✅ **Pro (Wave 2)** |
| **零网络隐私** | ❌ | ❌ | ❌ | ❌ | **✅ 原生** |
| **AI 使用分析** | ❌ | ❌ | ❌ | ❌ | ✅ **Pro (Wave 2)** |

---

## 2. 工程组织

### 2.1 Workspace 位置
`/Users/mengjianjun/Documents/ai/aicoding/macapp/KraftlyWorkspace.xcworkspace`

### 2.2 kFresh target 结构（Wave 0 + Wave 1 增量）

```
kFresh/                                          # 前身 kUninstall/，已重命名
├── App/
│   ├── kFreshApp.swift                          # @main
│   ├── RootView.swift                           # NavigationSplitView
│   └── AppCoordinator.swift
├── Features/                                    # ← Wave 1 主要工作区
│   ├── AppList/                                 # 主页 (Wave 1)
│   │   ├── AppListView.swift
│   │   ├── AppListViewModel.swift
│   │   └── AppRowView.swift
│   ├── Detail/                                  # 详情 + 卸载入口 (Wave 1)
│   │   ├── AppDetailView.swift
│   │   ├── DetailViewModel.swift
│   │   ├── ResidueSectionView.swift
│   │   └── UninstallConfirmSheet.swift
│   ├── History/                                 # 卸载历史 + 撤销 (Wave 1)
│   │   ├── HistoryView.swift
│   │   └── HistoryViewModel.swift
│   ├── DeepClean/                               # 深度清理（Pro, Wave 1）
│   │   ├── DeepCleanView.swift
│   │   ├── DeepCleanViewModel.swift
│   │   └── SystemCleanGroupView.swift
│   ├── StartupItems/                            # 启动项管理（Pro, Wave 1）
│   │   ├── StartupItemsView.swift
│   │   └── StartupItemsViewModel.swift
│   ├── Onboarding/                              # FDA 引导 5 页 (Wave 1)
│   │   ├── FDAGuideView.swift
│   │   ├── FDAGuideController.swift
│   │   └── pages/  (Welcome / Value / Permission / Privacy / Ready)
│   └── Settings/                                # 设置 (Wave 1)
│       ├── SettingsView.swift
│       └── AboutView.swift
├── Core/                                        # Wave 0 已完成
│   ├── Detect/
│   │   ├── InstalledApp.swift
│   │   ├── AppCatalogService.swift              # ← Wave 0 重写
│   │   ├── ResidueDetector.swift                # ← Wave 0 重写
│   │   └── BundleRuleStore.swift                # ← Wave 0
│   ├── Rules/
│   │   ├── KFreshBundleRule.swift
│   │   └── CaskParser.swift
│   ├── Clean/
│   │   ├── TrashMover.swift                     # ← Wave 0 重写
│   │   ├── BackupManager.swift                  # ← Wave 0 重写
│   │   └── AuditLogger.swift                    # ← Wave 0
│   └── Startup/
│       └── StartupItemManager.swift             # ← Wave 1 (Pro)
├── Intents/                                     # App Intents (Wave 2)
├── Widgets/                                     # (Wave 2)
├── FinderExtension/                             # (Wave 2)
├── Store/                                       # ← Wave 1 (StoreKit + Pro gates)
│   ├── StoreManager.swift
│   └── ProGateModifier.swift
├── MenuBar/                                     # (Wave 2)
└── Resources/
    ├── Assets.xcassets
    ├── Localizable.xcstrings                    # (Wave 2 with frozen text)
    └── cask_rules.json                          # Wave 0 生成
```

### 2.3 Wave 0 已交付组件（不重写）

| 组件 | 路径 | 状态 |
|---|---|---|
| `KFreshBundleRule` / `CaskParser` / `BundleRuleStore` | `kFresh/Core/Rules/` + `kFresh/Core/Detect/BundleRuleStore.swift` | 1141 条规则，172 带真 bundle ID |
| `TrashMover` (actor) | `kFresh/Core/Clean/TrashMover.swift` | recycle + 30 天可回滚 + AuditLogger |
| `ResidueDetector` | `kFresh/Core/Detect/ResidueDetector.swift` | 13 路径模板 + BundleRuleStore 集成 |
| `AppCatalogService` (actor) | `kFresh/Core/Detect/AppCatalogService.swift` | LaunchServices + /Applications 遍历 + 5 类 AppSource 分类 + sizeOfApp |
| `BackupManager` | `kFresh/Core/Clean/BackupManager.swift` | 版本化（manifest.json + sha256）+ 30 天 TTL + 完整性校验 |
| `AuditLogger` | `kFresh/Core/Clean/AuditLogger.swift` | JSONL 追加，含 TOCTOU 注释 |
| `KFAnimation` tokens | `kFoundation/Sources/DesignSystem/Animation.swift` | duration fast/normal/slow + scale tap/hover/insert + smooth/easeInOut |
| SwiftLint + GitHub Actions CI | `kFresh/.swiftlint.yml` + `.github/workflows/ci.yml` | lint + test 双 job |

---

## 3. 检测原理与 Sandbox 策略

### 3.1 Entitlements

```xml
<!-- kFresh.entitlements -->
com.apple.security.app-sandbox = YES
com.apple.security.files.user-selected.read-write = YES
com.apple.security.temporary-exception.files.home-relative-path.read-write = YES
com.apple.security.network.client = NO
```

- App Sandbox **强制开启**（App Store 必需）
- 零网络，彻底禁用网络客户端
- 用户通过 Security-Scoped Bookmark 授权读写 `/Applications`
- `temporary-exception.files.home-relative-path.read-write` 用于访问 ~/Library 残留路径，App Store 审核时需提交视频演示证明用途

### 3.2 FDA 依赖矩阵

| 操作 | API | 需 FDA | 无 FDA 时 |
|---|---|---|---|
| 获取 App 列表 | NSWorkspace + Security-Scoped Bookmark + FileManager | 部分 | LaunchServices 缓存列表 |
| App 图标/元数据 | NSWorkspace.shared.icon(forFile:) | ❌ | 可用 |
| App 占用大小 | NSURL.totalFileSizeKey | ✅ | 不可用 |
| 读取 ~/Library 残留 | FileManager | ✅ | 不可用 |
| 读取 /Library 系统级残留 | FileManager | ✅ | 不可用 |
| 移入废纸篓 | NSWorkspace.shared.recycle([URL]) | ❌ | 可用(仅App本体) |
| 操作 LaunchAgents | FileManager 删除 .plist | ✅ | 不可用 |
| 读取 Login Items | LSSharedFileList（公开 API） | ✅ | 不可用 |

### 3.3 FDA 状态机

```
[app启动]
   ↓
检查 ~/Library/Application Support/ 可读性
   ↓
┌──── 不可读 ────▶ 无 FDA ──▶ 基础模式
│                                ├─ 列 App（LaunchServices 缓存）
│                                ├─ 看大小（元数据级别）
│                                ├─ 卸载（移入废纸篓，不清残留）
│                                └─ UI：显示 "授权 FDA 以扫描残留"
│
└──── 可读 ──────▶ 有 FDA ──▶ 全功能模式
                                    ├─ 列全量 App
                                    ├─ 残留全扫描
                                    ├─ 深度清理
                                    ├─ 启动项管理
                                    └─ UI：全功能可用
```

### 3.4 App 检测流程（已 Wave 0 落地）

1. **LaunchServices 缓存查询**：快速获取所有已注册 App（不依赖 FDA）
2. **/Applications 遍历**：有 FDA 时补充，配合 Security-Scoped Bookmark
3. **NSRunningApplication**：标记当前正在运行的 App
4. **去重 & 合并**：Bundle ID 为主键
5. **分组**：system / appleBuiltIn / mas / userInstalled

### 3.5 残留文件推理算法（已 Wave 0 落地）

给定 App 的 Bundle ID（如 `com.example.Foo`），按路径模板匹配（Wave 0 落地 13 模板，详 `ResidueDetector.swift`）。

### 3.6 BundleRuleStore 集成（Wave 0 落地）
- 资源：`kFresh/Resources/cask_rules.json`（1141 条 Homebrew Cask 规则）
- 加载：`BundleRuleStore.loadFromBundledJSON()` 由 `ResidueScanner` 在生产 init 注入
- 查询：先按 bundle ID 精确匹配；miss 后按 displayName 模糊匹配；再 miss 落模板分支

---

## 4. 架构模式 + 模块划分

### 4.1 Clean Architecture 分层

```
┌─────────────────────────────────────────┐
│  UI Layer (SwiftUI)                      │  ← Wave 1 主要工作
│  AppListView / AppDetailView /          │
│  DeepCleanView / SettingsView           │
├─────────────────────────────────────────┤
│  Presentation Layer (ViewModels)        │  ← Wave 1
│  AppListViewModel / DetailViewModel     │
│  DeepCleanViewModel / ScanViewModel     │
├─────────────────────────────────────────┤
│  Domain Layer (Use Cases / Models)      │  ← 复用 Wave 0 模型
│  AppDetectionUseCase / ResidueScanUseCase│
│  DeepCleanUseCase / StartupItemManager   │
├─────────────────────────────────────────┤
│  Data Layer (Services / Repositories)    │  ← Wave 0 已完成
│  AppCatalogService / ResidueDetector    │
│  TrashMover / BackupManager /           │
│  FDAuthorizer / UninstallHistoryRepository│
├─────────────────────────────────────────┤
│  System Interface (Low-level APIs)       │  ← Wave 1 增量 StartupItemManager
│  LaunchServices / FileManager / libproc │
│  LSSharedFileList / NSWorkspace         │
└─────────────────────────────────────────┘
```

### 4.2 核心类图（Wave 0 已落地 + Wave 1 增量）

```
┌──────────────────────────────────┐
│ InstalledApp                     │  ← Wave 0
├──────────────────────────────────┤
│ url, displayName, bundleID,      │
│ version, icon, sizeBytes,        │
│ source, isProtected,             │
│ protectionReason, isRunning,     │
│ lastUsedDate, residues           │
└──────────────────────────────────┘
           │
┌──────────▼───────────────────────┐
│ ResidueFile                      │  ← Wave 0
├──────────────────────────────────┤
│ url, type, sizeBytes,            │
│ confidence, description,         │
│ isSystemLevel, isProtected       │
└──────────────────────────────────┘

ResidueType:  .preferences / .caches / .appSupport /
              .container / .launchAgent / .launchDaemon /
              .prefPane / .plugin / .startupItem /
              .log / .cookie / .appleScript   ← Wave 0 增

AppSource:    .system / .appleBuiltIn / .mas /
              .userInstalled / .homebrew / .setapp / .unknown
              ← Wave 0 增 .homebrew / .setapp

┌──────────────────────────────────┐
│ StartupItem                      │  ← Wave 1
├──────────────────────────────────┤
│ name, type, url, appURL?,        │
│ enabled, isProtected             │
└──────────────────────────────────┘

StartupItemType:  .loginItem / .launchAgent / .launchDaemon

┌──────────────────────────────────────┐
│ AppCatalogService (actor)            │  ← Wave 0 完成
├──────────────────────────────────────┤
│ scannedApps, scan/refresh/           │
│ classifySource / sizeOfApp          │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│ ResidueDetector + ResidueScanner     │  ← Wave 0 完成
├──────────────────────────────────────┤
│ detectResidues + BundleRuleStore     │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│ TrashMover (actor)                   │  ← Wave 0 完成
├──────────────────────────────────────┤
│ moveToTrash + restore + markRestored │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│ BackupManager                        │  ← Wave 0 完成
├──────────────────────────────────────┤
│ backup / restore / cleanupExpired    │
│ Manifest + sha256 完整性校验         │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│ AuditLogger                          │  ← Wave 0 完成
├──────────────────────────────────────┤
│ append JSONL 事件 + recentEvents     │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│ DeepCleanEngine (actor, Pro)         │  ← Wave 1 新增
├──────────────────────────────────────┤
│ scanSystemWideResidues()             │
│ cleanLaunchAgents / Daemons /        │
│ PreferencePanes                      │
│ verifyFDA()                          │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│ StartupItemManager (actor, Pro)      │  ← Wave 1 新增
├──────────────────────────────────────┤
│ listItems() / enable / disable /     │
│ remove                               │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│ UninstallHistoryRepository           │  ← 复用 Wave 0 TrashMover 内置
├──────────────────────────────────────┤
│ save / fetchAll / fetch /            │
│ markRestored / deleteExpired         │
└──────────────────────────────────────┘
```

### 4.3 并发策略

- 所有 Service 层使用 `actor` 隔离状态
- ViewModel 使用 `@MainActor` 确保 UI 线程安全
- 扫描操作使用 `TaskGroup` 并行化：App 列表扫描 + 残留扫描并行
- 卸载操作使用 `async/await` 顺序执行（需按步骤保证原子性）
- Wave 1 新增 ViewModel 一律 `@MainActor` + `actor` 服务

---

## 5. 数据层设计

### 5.1 Core Data 模型

```
UninstallHistory                          ← Wave 0 TrashMover 已用
├── id: UUID
├── appName: String
├── bundleID: String
├── appPath: String
├── actualTrashPath: String?             ← Wave 0 增 (Finder de-dup)
├── appSize: Int64
├── totalResidueSize: Int64
├── residueCount: Int32
├── uninstalledAt: Date
├── isFromDeepClean: Bool
├── isRestored: Bool
├── backupPath: String
└── residues: [ResidueRecord] (Transformable)

AppAnalysis                               ← Wave 2 启用
├── id: UUID
├── bundleID: String (unique)
├── displayName: String
├── lastUsedDate: Date?
├── firstDetectedDate: Date
├── usedCount: Int32
├── isAnalyzed: Bool
└── suggestedAction: String?
```

### 5.2 存储策略

| 数据类型 | 存储方式 | 说明 |
|---|---|---|
| App 列表 | 不持久化，实时构建 | 每次扫描重建 |
| 卸载历史 | Core Data `UninstallHistory` | 30 天保留 |
| AI 分析 | Core Data `AppAnalysis` | Wave 2 启用 |
| 用户偏好 | UserDefaults | FDA 状态、付费状态 |
| 付费凭证 | StoreManager + Keychain | 防破解 |
| FDA 书签 | App Sandbox Security-Scoped Bookmark | `~/Library/Application Support/app.kraftly.kfresh/Bookmarks/` |

### 5.3 备份策略（Wave 0 已落地）

```
备份根目录：
~/Library/Application Support/app.kraftly.kfresh/Backups/

结构：
Backups/<bundleID>/
  ├── manifest.json                  ← Wave 0: 含 schemaVersion + sha256
  ├── Library/Preferences/<bundleID>.plist
  ├── Library/Caches/<bundleID>/
  ├── Library/Application Support/<AppName>/
  └── ...

清理策略：
- 30 天后自动删除（Wave 0 BackupManager.cleanupExpired）
- isRestored = true 后立即删除
- App 启动时后台清理过期备份
```

### 5.4 回滚机制（Wave 0 已落地）

```
卸载流程：
1. App → 废纸篓（NSWorkspace.shared.recycle 或 FileManager.trashItem）
2. 残留文件 → 备份目录（temp-and-rename 原子）
3. 写入 UninstallHistory（Core Data, actualTrashPath 持久化 Finder de-dup 后的真实路径）
4. 30 天后自动清理

回滚流程：
1. 废纸篓 → 原位（FileManager.move 处理 actualTrashPath）
2. 备份 → 原位（FileManager.replaceItemAt 原子替换）
3. isRestored = true
4. 立即清理备份
```

---

## 6. UX 交互设计

### 6.1 信息架构

```
App Launch
│
├─ [首次] FDA 引导 (5 页 per CLAUDE.md §5.4)
│    ├─ Welcome → "kFresh — 让 App 卸载彻底干净"
│    ├─ 价值主张 → 残留 / 启动项 / 撤销 三件套
│    ├─ 权限申请 → FDA / Accessibility / Automation 清单
│    ├─ 隐私承诺 → 零网络 / 本地计算 / Data Not Collected
│    └─ Ready → 进入主界面
│
├─ [每次] 主页 AppList
│    ├─ 搜索栏
│    ├─ 分类筛选: 全部 / 用户 / 系统 / 最近安装
│    ├─ 排序: 名称 / 大小 / 安装时间 / 最近使用
│    └─ 列表 + 已卸载 App 折叠组
│
├─ App Detail
│    ├─ Hero: App Icon + 名称 + 版本 + 来源标签
│    ├─ 大小概况: "占用 1.2 GB"
│    ├─ 残留文件列表（可展开，按置信度排序）
│    ├─ [Pro 锁] 深度清理入口
│    ├─ [Pro 锁] 启动项管理入口
│    └─ 底部: "卸载" 按钮
│
├─ 卸载确认 Sheet（5 步安全检查后弹出）
│    ├─ App 本体大小
│    ├─ 残留文件（默认全选）
│    ├─ [Pro] 系统残留（锁定图标）
│    ├─ 共释放空间
│    ├─ 回滚提示
│    └─ "确认卸载"
│
├─ [Pro] 深度清理视图
│    ├─ FDA 检查（未授权则引导）
│    ├─ 分组: LaunchDaemons / LaunchAgents / PrefPanes
│    └─ 每项可展开查看详情 + 移除
│
├─ [Pro] 启动项管理视图
│    ├─ Login Items / Launch Agents / Launch Daemons
│    └─ 启用/禁用/删除
│
├─ 卸载历史
│    ├─ 最近卸载列表
│    └─ 每个可回滚（30 天内）
│
└─ 设置
     ├─ 付费状态 + "升级 Pro"
     ├─ FDA 状态指引
     ├─ 备份保留天数
     └─ 关于 + 隐私政策
```

### 6.2 关键交互细节

**卸载撤销 Toast**（Wave 1）：
```
┌──────────────────────────────────────────────┐
│  ✅ 已卸载 Xcode (1.2 GB)         [撤销]  5s │
└──────────────────────────────────────────────┘
```
- 卸载成功后立即弹出
- 10 秒倒计时自动消失
- 点击撤销 → 自动调用 `TrashMover.restore(id:)`（Wave 0 安全保证）

**卸载确认 Sheet**（Wave 1）：
```
┌─────────────────────────────────────────┐
│  [App Icon] 卸载 [App Name]?            │
│                                          │
│  App 本体:                 156 MB        │
│  残留文件(12项):            82 MB  ☑     │
│  系统残留(3项, 需Pro):      34 MB  🔒    │
│  ───────────────────────────────         │
│  共释放:                   238 MB        │
│                                          │
│  ☑ 移入废纸篓（可回滚 30 天）           │
│  ⚠️ App 正在运行，将先退出再卸载         │
│  ℹ️ 此 App 来自 App Store                │
│                                          │
│      [取消]      [确认卸载]               │
└─────────────────────────────────────────┘
```

### 6.3 视觉设计原则

| 维度 | 原则 |
|---|---|
| **品牌色** | 橙色（kFresh 主色 `#D97706`，与 kSpaceClean 紫 / kWatch 蓝 / kSift 绿 形成 Kraftly 色系） |
| **排版** | SF Pro，大标题 + 清晰层级，留白充足 |
| **App Icon** | 提取系统 icon，大尺寸圆角，柔和背景模糊 |
| **动效** | 全部走 `KFAnimation.durationNormal`（350ms）/ `scaleTap`（0.97）；不允许硬编码秒数 |
| **付费锁** | 模糊透明效果 + "解锁 Pro" 按钮 ≤ 2 处/页 |
| **无数据** | "没有找到 App？尝试扫描" 友好引导 |
| **加载** | 扫描进度 + 逐项露出（KFAnimation.durationFast） |
| **Onboarding** | 5 页骨架（Welcome / 价值 / 权限 / 隐私 / Ready） per CLAUDE.md §5.4 |
| **Toast** | 撤销 toast 复用，未撤销时走 HistoryView 重试 |

### 6.4 平台集成入口（Wave 2 推迟）

| 入口 | 付费 | 功能 | Wave |
|---|---|---|---|
| **菜单栏** | 免费 | 快速搜索 + 卸载最近 App | Wave 2 |
| **Widget** | Pro | "磁盘占用大户 Top 4" | Wave 2 |
| **Shortcuts** | Pro | 3 Action：卸载 / 扫描残留 / 深度清理 | Wave 2 |
| **Finder 右键** | 免费 | "用 kFresh 深度卸载" | Wave 2 |
| **Spotlight** | 免费 | 搜"卸载 X" → kFresh 动作 | Wave 2 |

---

## 7. Wave 1 范围锁定（NEW）

### 7.1 Wave 1 必做

| # | Task | DoD 主轴 | 工作日 |
|---|---|---|---|
| 1 | **Onboarding 5 页 + 权限检测** | FDA / Accessibility / Automation 检测 + 引导文案 + 状态机 | 1.5d |
| 2 | **AppList 主页**（NavigationSplitView + 搜索/筛选/排序 + 扫描进度 + 已卸载折叠组） | 主信息架构 + 实时扫描 UI | 2d |
| 3 | **AppDetail 视图**（Hero + 残留可展开列表 + 卸载入口 + Pro 锁） | 详情页交互 + 残留可视化 | 2d |
| 4 | **Uninstall 确认 Sheet + 5 步安全**（isProtected / isRunning / 来源 / 残留预扫 / 确认 + Toast 撤销） | 核心卸载闭环 + Toast 撤销 | 2d |
| 5 | **HistoryView + Restore**（CoreData 查询 + 30 天可回滚 + 详情预览） | 回滚入口 | 1.5d |
| 6 | **StartupItemManager + StartupItemsView（Pro）** | LSSharedFileList + LaunchAgents/Daemons + 启用/禁用/删除 | 1.5d |
| 7 | **DeepCleanEngine + DeepCleanView（Pro）** | LaunchAgents/Daemons/PrefPanes 分组扫描 + 选择清理 | 2d |
| 8 | **StoreKit + ProGate 修饰符** | IAP 购买 + 状态持久化 + 视图级 Pro 锁 | 1d |

合计：**13.5 working days ≈ 2.7 calendar weeks**

### 7.2 Wave 1 推迟（Wave 2+）

- **Widget**（macOS 基础 + Interactive 两版）— Wave 2
- **App Intents / Shortcuts**（3 Action: 卸载 / 扫描残留 / 深度清理）— Wave 2
- **Finder Extension**（右键 "用 kFresh 深度卸载"）— Wave 2
- **MenuBar**（快速搜索 + 最近卸载）— Wave 2
- **Spotlight 集成**— Wave 2
- **批量卸载**（多选 + 一键）— Wave 2
- **多语言**（zh-Hans / ja）— Wave 2，文本先冻结为英文
- **AppIcon 母题统一**（CLAUDE.md §5.4 骨架）— Wave 2
- **AI "很少用" 分析**（AppAnalysis 实体已建表）— Wave 2

### 7.3 Wave 1 必做的全局约束继承

来自 CLAUDE.md §5 + Wave 0 Global Constraints，Wave 1 不放松：

- **Bundle ID**: `app.kraftly.kfresh` 全栈一致（Info.plist、entitlements、App Group、CoreData model URL、Security-Scoped Bookmark 路径）
- **No `kUninstall/` 路径**：所有新增/修改文件必须落在 `kFresh/`
- **DocC**：所有 public API（含 ViewModifier、Intent、Widget）必须有 DocC
- **No `@unchecked Sendable`**：除 NSImage-bearing 类型（NSImage 在 Wave 1 仅出现在 InstalledApp.icon 字段，沿用 Wave 0 的例外）
- **No `try?` silent swallow**：用 `do/catch` + 显式错误或 `Result<_, Error>`
- **Design tokens 强制**：颜色 / 字体 / 间距 / 圆角 / 阴影 / 动效全走 `kFoundation/Sources/DesignSystem/*`，不写硬编码值
- **5 页 Onboarding 骨架**：Wave 1 必须严格实现 §6.1 的 5 页结构
- **测试**：XCTest + `@testable import kFresh`，每 view/viewmodel 至少一个 ViewInspector 或单元测试覆盖关键状态机
- **提交**：一个 commit per task，conventional-commit 前缀（`feat(kFresh): ...` / `test(kFresh): ...`）
- **直推 main**：与 Wave 0 一致，subagent 获授权后直接 commit 到 main，不开 PR

---

## 8. 定价与商业模型

### 8.1 定价

| 层 | 价格 | 方式 | 功能 |
|---|---|---|---|
| **免费** | $0 | — | 卸载任意 App + 基础残留扫描 + 30 天回滚 |
| **Pro** | **$9.99** | 一次性买断 | 深度清理 + 启动项管理 + Wave 2 起的批量/Widget/Shortcuts/AI |

### 8.2 免费/Pro 分界

| 功能 | 免费 | Pro |
|---|---|---|
| 卸载 App + 基础残留 | ✅ | ✅ |
| 应用列表 + 大小查看 | ✅ | ✅ |
| 撤销回滚 | ✅ | ✅ |
| 深度系统清理 | ❌ | ✅ |
| 启动项管理 | ❌ | ✅ |
| 批量卸载 | ❌ | ✅ (Wave 2) |
| 应用体积可视化 | ❌ | ✅ (Wave 2) |
| AI "很少用"分析 | ❌ | ✅ (Wave 2) |
| Widget | ❌ | ✅ (Wave 2) |
| Shortcuts | ❌ | ✅ (Wave 2) |

### 8.3 地区定价

| 地区 | 价格 |
|---|---|
| 美国 | $9.99 |
| 欧元区 | €9.99 |
| 中国 | ¥48 |
| 日本 | ¥1,200 |

---

## 9. 测试策略

### 9.1 Wave 1 测试层次

| 层级 | 内容 | 工具 | 覆盖率目标 |
|---|---|---|---|
| **ViewModel 单元** | AppListVM 过滤/排序逻辑、DetailVM 5 步安全、HistoryVM 撤销流、StartupVM 启用/禁用、DeepCleanVM 分组聚合、StoreManager 状态机 | XCTest | > 80% |
| **Service 集成** | TrashMover + BackupManager 端到端（Wave 0 已覆盖），StartupItemManager LSSharedFileList mock，DeepCleanEngine 路径 mock | XCTest | 关键链路 100% |
| **View 快照/行为** | 卸载确认 Sheet 5 步状态切换、Toast 撤销倒计时、Pro 锁显示、Onboarding 5 页切换 | ViewInspector + 快照 | 关键路径 |
| **UI** | 卸载完整链路（含 FDA 检测 → 引导 → 扫描 → 确认 → 撤销） | XCUITest | 5 核心用例 |
| **沙箱** | 无 FDA/有 FDA 功能降级（沿用 Wave 0 SandboxDegradationTests 4 例 + Wave 1 新增 ProGate 行为 4 例） | XCTest | 20 边界 |

### 9.2 Wave 1 关键测试用例清单

- **OnboardingController**: `testWelcomeShowsOnFirstLaunch`, `testSkippingLeavesInBasicMode`, `testAllPagesReachReady`
- **AppListViewModel**: `testFilterByUserSource`, `testSortBySizeDesc`, `testSearchByName`, `testScanProgressUpdatesRows`
- **AppDetailViewModel**: `testRunningAppShowsTerminateHint`, `testProtectedAppDisablesUninstallButton`, `testResiduesSortedByConfidence`, `testUninstallSheet5StepProgression`
- **UninstallConfirmSheet**: `testCancelDismissesSheet`, `testConfirmCallsTrashMover`, `testProSystemResiduesShowLock`, `testToastUndoCountdown`
- **HistoryViewModel**: `testRecent30DaysOnly`, `testRestoreSuccess`, `testRestoreFailsIfBackupMissing`, `testExpiredRecordsHidden`
- **StartupItemViewModel**: `testListItemsRequiresFDA`, `testEnableTogglePersists`, `testRemoveAsksConfirmation`, `testDisabledItemsHiddenInCount`
- **DeepCleanViewModel**: `testGroupedByCategory`, `testSelectAllTogglesByRiskLevel`, `testConfirmRequiresFDA`
- **StoreManager**: `testInitialStateIsFree`, `testPurchaseTransitionsToPro`, `testRestoreFromAppStore`, `testProGateViewModifierHidesContent`

---

## 10. 风险与对策

### 10.1 Wave 1 风险

| 风险 | 影响 | 对策 |
|---|---|---|
| **App Sandbox 下访问 ~/Library 受限** | Onboarding 后用户拒绝 FDA，AppList 仍可用但残留扫描失效 | FDA 状态机 + UI 明确提示 + 引导跳系统设置；Wave 0 SandboxDegradationTests 已覆盖 |
| **LSSharedFileList 已 deprecated (macOS 13+)** | StartupItemManager 可能失效 | 使用 `SMAppService` (macOS 13+) 替代；保留 LSSharedFileList 作为 fallback |
| **`NSWorkspace.recycle` 在 sandbox + de-dup 下返回 Finder 加后缀的真实路径** | 卸载回滚找不到原 Trash 路径 | Wave 0 已修：recycle completion handler 拿 actualTrashPath 写 CoreData，restore 时读此字段 |
| **StoreKit 沙箱测试账号** | 付费门测试需要 StoreKit 配置 | 配置 `Configuration.storekit` + 沙箱 tester 账号，CI 跳过 Pro 门 UI 测试 |
| **`@MainActor` ViewModel 调用 actor 服务** | Swift Concurrency 严格模式下编译失败 | 所有 Service 层用 `actor`，ViewModel 用 `await` 调；不逃逸 |
| **Onboarding 状态持久化** | 关闭重启后回到第一页 | `UserDefaults` + Key 标记 `hasCompletedOnboarding`；AppCoordinator 决策 |
| **DeepClean 操作 /Library 路径需 FDA** | 无 FDA 用户点 Pro 入口看到全锁 | ProGate 修饰符在无 Pro 时显示锁；不暴露底层服务 |

### 10.2 Wave 1 累积技术债（从 Wave 0 继承）

来自 `wave0-final-fix-report.md` §3 推迟项，本波内可选消化：

- I-3: ResidueDetector 模板目录重构（如果 Wave 1 增新路径模板，先做）
- m-2: `UninstallRecord` 访问级别收紧
- m-6 / m-7: SwiftLint CI 首跑可能爆，wave 1 开始后立即跑一遍修复

---

## 11. 隐私与合规

- **零网络**：entitlements 禁用网络，无数据上报（Wave 0 已配置）
- **本地计算**：AI 分析在 Core Data 本地完成，不上传（Wave 2 启用）
- **FDA 仅本地**：Full Disk Access 仅用于本地文件扫描
- **GDPR / CCPA**：无个人数据收集，无需额外合规
- **App Privacy Details**：
  - 不收集任何数据
  - App Store 隐私标签：**Data Not Collected**

---

## 12. 上线时间线（修订）

| 阶段 | 周次 | 交付 | Wave |
|---|---|---|---|
| 0 | W1-W2 | Foundation（已完成，35 commits） | Wave 0 ✅ |
| 1 | W3-W5 | 5 核心 feature 端到端（Onboarding / AppList / Detail / 卸载 / 历史 / 启动项 / 深度清理 / StoreKit） | Wave 1 🔄 |
| 2 | W6-W8 | Widget / App Intents / Finder / MenuBar / 多语言 / Spotlight / 批量 | Wave 2 |
| 3 | W9-W10 | TestFlight + Bug Bash + 性能优化 | Wave 3 |
| 4 | W11 | App Store 提交 | Wave 3 |

**总预估**：11 周从 Wave 0 完成到 v1 上架，每周 ~25 小时。

---

## 13. 无障碍

| 类别 | 支持 |
|---|---|
| VoiceOver | 所有按钮 + 交互元素有 label（Wave 1 全覆盖） |
| 动态字体 | SwiftUI Dynamic Type 自适应 |
| 减少动效 | 检测 AccessibilitySettings，关闭 KFAnimation 过渡动画 |
| 键盘导航 | ⌘F 搜索 / ⌘, 设置 / ⌘⌫ 卸载 / Space 预览（Wave 1 全覆盖） |

---

## 14. 关联文档

- 设计：`docs/superpowers/specs/2026-07-26-kraftly-kuninstall-design.md`（历史归档）
- 设计对话：`docs/superpowers/specs/kUninstall产品交互设计.md`（历史归档）
- Wave 0 进度：`.superpowers/sdd/progress-kfresh-wave0.md`
- Wave 0 fix 报告：`.superpowers/sdd/wave0-final-fix-report.md`
- Wave 1 计划：`docs/superpowers/plans/2026-08-01-kfresh-wave1.md`
- CLAUDE.md：项目根目录（Kraftly 套件全局约束）

---

*本文件由 Claude 基于 2026-07-26 原版 refresh 生成。Wave 1 启动后所有实现以本文档 §7 + Wave 1 plan 为准。*
