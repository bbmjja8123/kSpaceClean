# kUninstall v1 设计规格

**项目**：Kraftly Mac App Suite
**App**：kUninstall（应用卸载）
**作者**：独立开发者
**日期**：2026-07-26
**状态**：v1 设计定稿，待实施

---

## 1. 概述

### 1.1 一句话定位
让 Mac 应用卸载回到"彻底"——删一个 App，连它的所有指纹一起清干净。

### 1.2 目标用户
- **主**：全人群，特别是"试装党"（喜欢装各种 App 试用、频繁卸载的）
- **次**：Mac 新手，不知道 App 有残留文件、启动项概念的用户
- **不服务**：开发者（→kDupe）、极客玩家（→kDupe）、磁盘清理需求者（→kSpaceClean）

### 1.3 独立 App 定位
kUninstall 为**独立 App**，不与 kSpaceClean 合并。后续 4 款 App（kSpaceClean / kWatch / kDupe / kUninstall）在成熟后考虑组合为统一 Kraftly 套件。

### 1.4 核心差异化

| 维度 | AppCleaner | Nektony App Cleaner | TrashMe 3 | Cleaner One Pro | **kUninstall** |
|---|---|---|---|---|---|
| **价格** | 免费 | $19.99 买断 | ~$9.99 买断 | 免费+$19.99/年 | **免费卸载+$9.99 Pro** |
| **卸载残留** | ✅ 基础 | ✅ 高级 | ✅ 高级 | ✅ 基础 | ✅ 基础(免费)+深度(Pro) |
| **启动项管理** | ❌ | ❌ | ❌ | ✅ 部分 | ✅ **Pro** |
| **系统级清理** | ❌ | ❌ | ❌ | ✅ | ✅ **Pro** |
| **批量操作** | ❌ | ✅ | ❌ | ❌ | ✅ **Pro** |
| **App Store** | ❌ 非 MAS | ✅ | ✅ | ✅ | ✅ |
| **Widget** | ❌ | ❌ | ❌ | ❌ | ✅ **Pro** |
| **Shortcuts** | ❌ | ❌ | ❌ | ❌ | ✅ **Pro** |
| **Finder 右键** | ❌ | ❌ | ❌ | ❌ | ✅ |
| **可视化报告** | ❌ | ❌ | ❌ | ❌ | ✅ **Pro** |
| **零网络隐私** | ❌ | ❌ | ❌ | ❌ | **✅ 原生** |
| **AI 使用分析** | ❌ | ❌ | ❌ | ❌ | ✅ **Pro** |

---

## 2. 工程组织

### 2.1 Workspace 位置
`/Users/mengjianjun/Documents/ai/aicoding/macapp/KraftlyWorkspace.xcworkspace`

### 2.2 kUninstall target 结构

```
kUninstall/
├── App/
│   ├── kUninstallApp.swift               # @main
│   ├── RootView.swift                    # NavigationSplitView
│   └── AppCoordinator.swift
├── Features/
│   ├── AppList/                          # 应用列表主页
│   │   ├── AppListView.swift
│   │   ├── AppListViewModel.swift
│   │   └── AppRowView.swift
│   ├── Detail/                           # 应用详情 + 卸载
│   │   ├── AppDetailView.swift
│   │   ├── DetailViewModel.swift
│   │   └── ResidueSectionView.swift
│   ├── DeepClean/                        # 深度清理（Pro）
│   │   ├── DeepCleanView.swift
│   │   ├── DeepCleanViewModel.swift
│   │   └── SystemCleanGroupView.swift
│   ├── StartupItems/                     # 启动项管理（Pro）
│   │   ├── StartupItemsView.swift
│   │   └── StartupItemsViewModel.swift
│   └── Onboarding/                       # FDA 引导
│       ├── FDAGuideView.swift
│       └── FDAGuideController.swift
├── Core/
│   ├── Detect/
│   │   ├── InstalledApp.swift            # 核心模型
│   │   ├── AppCatalogService.swift       # 扫描已安装 App
│   │   └── ResidueDetector.swift         # 推理残留文件
│   ├── Clean/
│   │   ├── TrashMover.swift              # 移入废纸篓
│   │   └── DeepCleanEngine.swift         # 深度清理（Pro）
│   └── Startup/
│       └── StartupItemManager.swift      # 登录项管理
├── Intents/                              # Shortcuts
│   ├── UninstallAppIntent.swift
│   ├── ScanResidueIntent.swift
│   └── DeepCleanIntent.swift
├── Widgets/
│   ├── AppUsageWidget.swift
│   └── QuickUninstallWidget.swift
├── FinderExtension/
│   ├── FinderSync.swift
│   └── Info.plist
├── Store/                                # 内购
│   ├── StoreManager.swift
│   └── StoreDefinitions.swift
├── MenuBar/
│   └── MenuBarController.swift
└── Resources/
    ├── Assets.xcassets
    └── Localizable.xcstrings             # en / zh-Hans / ja
```

---

## 3. 检测原理与 Sandbox 策略

### 3.1 Entitlements

```xml
<!-- kUninstall.entitlements -->
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

### 3.4 App 检测流程

1. **LaunchServices 缓存查询**：快速获取所有已注册 App（不依赖 FDA）
2. **/Applications 遍历**：有 FDA 时补充，配合 Security-Scoped Bookmark
3. **NSRunningApplication**：标记当前正在运行的 App
4. **去重 & 合并**：Bundle ID 为主键
5. **分组**：system / appleBuiltIn / mas / userInstalled

### 3.5 残留文件推理算法

给定 App 的 Bundle ID（如 `com.example.Foo`），按路径模板匹配：

| 路径模板 | 置信度 | FDA |
|---|---|---|
| `~/Library/Preferences/{bundleID}.plist` | 高(0.99) | ✅ |
| `~/Library/Caches/{bundleID}/` | 高(0.99) | ✅ |
| `~/Library/Application Support/{AppName}/` | 高(0.95) | ✅ |
| `~/Library/Saved Application State/{bundleID}.savedState` | 高(0.99) | ✅ |
| `~/Library/Containers/{bundleID}/` | 高(0.99) | ✅ |
| `~/Library/WebKit/{bundleID}/` | 中(0.85) | ✅ |
| `~/Library/HTTPStorages/{bundleID}/` | 高(0.95) | ✅ |
| `~/Library/Group Containers/{groupID}/` | 中(0.80) | ✅ |
| `~/Library/Internet Plug-Ins/{AppName}.plugin/` | 中(0.80) | ✅ |
| `/Library/LaunchAgents/{bundleID}.plist` | 高(0.95) | ✅ |
| `/Library/LaunchDaemons/{bundleID}.plist` | 高(0.95) | ✅ |
| `/Library/PreferencePanes/{AppName}.prefPane` | 中(0.85) | ✅ |
| `/Library/StartupItems/{AppName}/` | 中(0.85) | ✅ |

每条残留路径带有 `confidence: Double`（0.0~1.0），UI 上按置信度排序，低置信度项默认不选中。

---

## 4. 架构模式 + 模块划分

### 4.1 Clean Architecture 分层

```
┌─────────────────────────────────────────┐
│  UI Layer (SwiftUI)                      │
│  AppListView / AppDetailView /          │
│  DeepCleanView / SettingsView           │
├─────────────────────────────────────────┤
│  Presentation Layer (ViewModels)        │
│  AppListViewModel / DetailViewModel     │
│  DeepCleanViewModel / ScanViewModel     │
├─────────────────────────────────────────┤
│  Domain Layer (Use Cases / Models)      │
│  AppDetectionUseCase / ResidueScanUseCase│
│  DeepCleanUseCase / StartupItemManager   │
├─────────────────────────────────────────┤
│  Data Layer (Services / Repositories)    │
│  AppCatalogService / ResidueDetector    │
│  TrashMover / FDAuthorizer              │
│  UninstallHistoryRepository             │
├─────────────────────────────────────────┤
│  System Interface (Low-level APIs)       │
│  LaunchServices / FileManager / libproc │
│  SMCopyAllJobDictionaries / NSWorkspace │
└─────────────────────────────────────────┘
```

### 4.2 核心类图

```
┌──────────────────────────────────┐
│ InstalledApp                     │
├──────────────────────────────────┤
│ url: URL                          │
│ displayName: String               │
│ bundleID: String                  │
│ version: String                   │
│ icon: NSImage                     │
│ sizeBytes: Int64                  │
│ source: AppSource                 │
│ isProtected: Bool                 │
│ protectionReason: String?         │
│ isRunning: Bool                   │
│ lastUsedDate: Date?               │
│ residues: [ResidueFile]           │
└──────────┬───────────────────────┘
           │
┌──────────▼───────────────────────┐
│ ResidueFile                      │
├──────────────────────────────────┤
│ url: URL                          │
│ type: ResidueType                 │
│ sizeBytes: Int64                  │
│ confidence: Double                │
│ description: String               │
│ isSystemLevel: Bool               │
│ isProtected: Bool                 │
└──────────────────────────────────┘

ResidueType:  .preferences / .caches / .appSupport /
              .container / .launchAgent / .launchDaemon /
              .prefPane / .plugin / .startupItem

AppSource:    .system / .appleBuiltIn / .mas / .userInstalled / .unknown

┌──────────────────────────────────┐
│ StartupItem                      │
├──────────────────────────────────┤
│ name: String                      │
│ type: StartupItemType             │
│ url: URL                          │
│ appURL: URL?                      │
│ enabled: Bool                     │
│ isProtected: Bool                 │
└──────────────────────────────────┘

StartupItemType:  .loginItem / .launchAgent / .launchDaemon

┌──────────────────────────────────────┐
│ AppCatalogService (actor)            │
├──────────────────────────────────────┤
│ + scannedApps: [InstalledApp]        │
│ + scan() async -> [InstalledApp]     │
│ + refresh() async                    │
│ - queryLaunchServices()              │
│ - enumerateApplications()            │
│ - deduplicate()                      │
│ - classifySource(for:)               │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│ ResidueDetector (actor)              │
├──────────────────────────────────────┤
│ + detectResidues(for:) async         │
│ - scanLibraryPaths(for:)             │
│ - matchByBundleID(_:)                │
│ - matchByAppName(_:)                 │
│ - calculateConfidence(_:)            │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│ TrashMover (actor)                   │
├──────────────────────────────────────┤
│ + canMoveToTrash(app:) -> Bool       │
│ + moveToTrash(app:) async -> Result  │
│ + moveToTrash(residues:) async       │
│ + restore(id:) async                 │
│ + undoLastMove() async               │
│ - terminateApp(_:)                   │
│ - backupResidues(_:)                 │
│ - saveHistory(_:)                    │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│ DeepCleanEngine (actor, Pro)         │
├──────────────────────────────────────┤
│ + scanSystemWideResidues() async     │
│ + cleanLaunchAgents(_:)              │
│ + cleanLaunchDaemons(_:)             │
│ + cleanPreferencePanes(_:)           │
│ - verifyFDA() -> Bool                │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│ StartupItemManager (actor, Pro)      │
├──────────────────────────────────────┤
│ + listItems() async -> [StartupItem] │
│ + enable(item:)                      │
│ + disable(item:)                     │
│ + remove(item:)                      │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│ UninstallHistoryRepository           │
├──────────────────────────────────────┤
│ + save(record:)                      │
│ + fetchAll() -> [UninstallRecord]    │
│ + fetch(id:) -> UninstallRecord?     │
│ + markRestored(id:)                  │
│ + deleteExpired(olderThan:)          │
└──────────────────────────────────────┘
```

### 4.3 并发策略

- 所有 Service 层使用 `actor` 隔离状态
- ViewModel 使用 `@MainActor` 确保 UI 线程安全
- 扫描操作使用 `TaskGroup` 并行化：App 列表扫描 + 残留扫描并行
- 卸载操作使用 `async/await` 顺序执行（需按步骤保证原子性）

---

## 5. 数据层设计

### 5.1 Core Data 模型

```
UninstallHistory
├── id: UUID
├── appName: String
├── bundleID: String
├── appPath: String
├── appSize: Int64
├── totalResidueSize: Int64
├── residueCount: Int32
├── uninstalledAt: Date
├── isFromDeepClean: Bool
├── isRestored: Bool
├── backupPath: String
└── residues: [ResidueRecord] (Transformable)

AppAnalysis
├── id: UUID
├── bundleID: String (unique)
├── displayName: String
├── lastUsedDate: Date?
├── firstDetectedDate: Date
├── usedCount: Int32
├── isAnalyzed: Bool
└── suggestedAction: String?  // "keep" / "uninstall" / "never_used"
```

### 5.2 存储策略

| 数据类型 | 存储方式 | 说明 |
|---|---|---|
| App 列表 | 不持久化，实时构建 | 每次扫描重建 |
| 卸载历史 | Core Data `UninstallHistory` | 30 天保留 |
| AI 分析 | Core Data `AppAnalysis` | 累积使用数据 |
| 用户偏好 | UserDefaults | FDA 状态、付费状态 |
| 付费凭证 | StoreManager + Keychain | 防破解 |
| FDA 书签 | App Sandbox Security-Scoped Bookmark | 持久化到 `~/Library/Application Support/app.kraftly.kuninstall/Bookmarks/` |

### 5.3 备份策略

```
备份根目录：
~/Library/Application Support/app.kraftly.kuninstall/Backups/

结构：
Backups/<bundleID>/
  ├── Library/Preferences/<bundleID>.plist
  ├── Library/Caches/<bundleID>/
  ├── Library/Application Support/<AppName>/
  └── ...

清理策略：
- 30 天后自动删除
- isRestored = true 后立即删除
- App 启动时后台清理过期备份
```

### 5.4 回滚机制

```
卸载流程：
1. App → 废纸篓（NSWorkspace.shared.recycle）
2. 残留文件 → 备份目录 cp
3. 写入 UninstallHistory（Core Data）
4. 30 天后自动清理

回滚流程：
1. 废纸篓 → 原位（FileManager.move）
2. 备份 → 原位（FileManager.copy）
3. isRestored = true
4. 立即清理备份
```

---

## 6. UX 交互设计

### 6.1 信息架构

```
App Launch
│
├─ [首次] FDA 引导
│    ├─ Welcome Screen → "让 kUninstall 彻底清理 App 残留"
│    ├─ 系统设置引导（动图演示如何授权 FDA）
│    └─ 跳过 → 基础模式
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
│    ├─ AI 分析: "这个 App 你 90 天没用了"
│    ├─ [Pro] 深度清理入口
│    ├─ [Pro] 启动项管理入口
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

**卸载撤销 Toast**：
```
┌──────────────────────────────────────────────┐
│  ✅ 已卸载 Xcode (1.2 GB)         [撤销]  5s │
└──────────────────────────────────────────────┘
```
- 卸载成功后立即弹出
- 10 秒倒计时自动消失
- 点击撤销 → 自动调用回滚

**卸载确认 Sheet**：
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
| **品牌色** | 冷色调（深蓝/蓝灰渐变），与 kSpaceClean 统一 |
| **排版** | SF Pro，大标题 + 清晰层级，留白充足 |
| **App Icon** | 提取系统 icon，大尺寸圆角，柔和背景模糊 |
| **动效** | 卸载流畅过渡、骨架屏加载、触感反馈 |
| **付费锁** | 模糊透明效果 + "解锁 Pro" 按钮 ≤ 2 处/页 |
| **无数据** | "没有找到 App？尝试扫描" 友好引导 |
| **加载** | 扫描进度 + 逐项露出 |

### 6.4 平台集成入口

| 入口 | 付费 | 功能 |
|---|---|---|
| **菜单栏** | 免费 | 快速搜索 + 卸载最近 App |
| **Widget** | Pro | "磁盘占用大户 Top 4" |
| **Shortcuts** | Pro | 3 个 Action：卸载 / 扫描残留 / 深度清理 |
| **Finder 右键** | 免费 | "用 kUninstall 深度卸载" |
| **Spotlight** | 免费 | 搜 "卸载 X" → kUninstall 动作 |

---

## 7. 操作流程图

### 7.1 总用户流

```
┌──────────────────────────────────────────────────────────────────┐
│  Launch                                                           │
│    │                                                              │
│    ├─[首次]──▶ FDA Guide ──▶ 授权 ──▶ 主界面                       │
│    │                       └─跳过 ──▶ 主界面(受限)                │
│    │                                                              │
│    └─[非首次]──▶ 自动扫描 ──▶ 主界面                               │
│                                                                   │
│  主界面 ──┬── 点击 App → Detail View                               │
│           │       ├─ 点击"卸载" → 前置检查 → 确认 Sheet → 卸载    │
│           │       ├─ [Pro] 深度清理 → Deep Clean View             │
│           │       └─ [Pro] 启动项管理 → Startup Items View         │
│           │                                                       │
│           ├── 搜索/筛选 → 列表实时过滤                              │
│           ├── 设置 → 偏好 + 历史 + Pro 购买                       │
│           └── 菜单栏/Widget → 快捷卸载                             │
└──────────────────────────────────────────────────────────────────┘
```

### 7.2 卸载流程图

```
tap "卸载" →
  ├─ Step 1: 安全检查
  │   ├─ isProtected? → 禁止，显示 "系统组件不可卸载"
  │   └─ OK → 继续
  │
  ├─ Step 2: 运行检查
  │   ├─ 未运行 → 继续
  │   └─ 正在运行 → 弹出 Sheet:
  │       │  "Xcode 正在运行" [退出并卸载] [取消]
  │       │  └─ terminate() → 5s → kill → 继续
  │
  ├─ Step 3: 来源确认
  │   ├─ .mas → 提示 "可从 App Store 重新下载"
  │   └─ .direct → 提示 "确认有安装包备份"
  │
  ├─ Step 4: 残留预扫描（未扫描则自动扫）
  │   └─ 显示残留数 + 大小
  │
  ├─ Step 5: 确认 Sheet
  │   └─ 确认 → TrashMover.moveToTrash()
  │       ├─ ① App → 废纸篓
  │       ├─ ② 残留 → 备份目录
  │       ├─ ③ 记录 Core Data
  │       └─ ④ Toast "已卸载" + 撤销倒计时
  │
  └─ [可选] 撤销 → TrashMover.restore()
      ├─ ① 废纸篓 → 原位
      ├─ ② 备份 → 原位
      └─ ③ isRestored = true
```

---

## 8. 时序图

### 8.1 App 检测时序

```
User        UI                AppCatalogService     ResidueDetector     System
 │           │                       │                    │               │
 │ launch    │                       │                    │               │
 ├──────────▶│  scan()               │                    │               │
 │           ├──────────────────────▶│                    │               │
 │           │                       │ queryLS()          │               │
 │           │                       ├──────────────────────────────────▶│
 │           │                       │◀─[App Metadata]──────────────────│
 │           │                       │ enumerateApps()   │               │
 │           │                       ├──────────────────────────────────▶│
 │           │                       │◀─[App URLs]──────────────────────│
 │           │                       │                    │               │
 │           │                       │ 去重+合并+分类     │               │
 │           │                       │                    │               │
 │           │  [InstalledApps]      │                    │               │
 │           │◀──────────────────────┤                    │               │
 │           │                       │                    │               │
 │           │ for each app:         │                    │               │
 │           │ detectResidues()      │                    │               │
 │           ├───────────────────────────────────────────▶│               │
 │           │                       │                    │ scanPaths()   │
 │           │                       │                    ├──────────────▶│
 │           │                       │                    │◀──[files]────│
 │           │                       │                    │               │
 │           │                       │                    │ matchByID()   │
 │           │                       │                    │ calcConf()   │
 │           │                       │                    │               │
 │           │◀──[ResidueFiles]──────┼────────────────────┤               │
 │           │                       │                    │               │
 │ 显示列表  │                       │                    │               │
 │◀──────────┤                       │                    │               │
```

### 8.2 卸载时序

```
User        UI              DetailVM        TrashMover          System
 │           │                 │               │                  │
 │ tap 卸载  │                 │               │                  │
 ├──────────▶│ 前置检查         │               │                  │
 │           ├─ 安全 ✅         │               │                  │
 │           ├─ 运行检查 ✅     │               │                  │
 │           ├─ 残留预扫描 ✅   │               │                  │
 │           │                 │               │                  │
 │           │ confirm sheet   │               │                  │
 │           │◀────────────────│               │                  │
 │           │                 │               │                  │
 │ 确认卸载  │                 │               │                  │
 ├──────────▶│ uninstall()     │               │                  │
 │           ├───────────────▶│               │                  │
 │           │                 │ moveToTrash() │                  │
 │           │                 ├──────────────▶│                  │
 │           │                 │               │ recycle()       │
 │           │                 │               ├────────────────▶│
 │           │                 │               │◀───[success]────│
 │           │                 │               │                  │
 │           │                 │ backupRes()   │                  │
 │           │                 │               │ cp → Backup/    │
 │           │                 │               ├────────────────▶│
 │           │                 │               │◀───[done]───────│
 │           │                 │               │                  │
 │           │                 │ saveHistory() │                  │
 │           │                 │ (Core Data)   │                  │
 │           │                 │◀──────────────│                  │
 │           │                 │               │                  │
 │           │◀──[completed]───│               │                  │
 │           │                 │               │                  │
 │◀─[Toast]──│                 │               │                  │
 │           │                 │               │                  │
 │  撤销卸载 │                 │               │                  │
 ├──────────▶│ restore()       │               │                  │
 │           ├───────────────▶│               │                  │
 │           │                 │ restore()     │                  │
 │           │                 ├──────────────▶│                  │
 │           │                 │               │ Trash→orig      │
 │           │                 │               ├────────────────▶│
 │           │                 │               │ Backup→orig     │
 │           │                 │               ├────────────────▶│
 │           │                 │               │ markRestored    │
 │           │                 │               │                  │
 │           │◀──[restored]────│               │                  │
```

### 8.3 深度清理时序

```
User        UI            DeepCleanVM      DeepCleanEngine      System
 │           │                 │                 │                 │
 │ tap 清理  │                 │                 │                 │
 ├──────────▶│ checkFDA()      │                 │                 │
 │           ├───────────────▶│                 │                 │
 │           │                 │ verifyFDA()     │                 │
 │           │                 ├────────────────▶│                 │
 │           │                 │                 │ FileManager    │
 │           │                 │                 │ Library check  │
 │           │                 │                 ├────────────────▶│
 │           │                 │                 │◀──[permission]─│
 │           │                 │                 │                 │
 │           │◀──[FDA ✅│❌]───│                 │                 │
 │           │                 │                 │                 │
 │  FDA ❌ ──▶ 引导授权 ──▶ 重试                 │                 │
 │  FDA ✅ ──▶ 继续                              │                 │
 │           │                 │                 │                 │
 │           │ scanAll()       │                 │                 │
 │           ├───────────────▶│                 │                 │
 │           │                 │ scanDaemons()   │                 │
 │           │                 ├────────────────▶│                 │
 │           │                 │                 │ ls /Library/   │
 │           │                 │                 │ LaunchDaemons/ │
 │           │                 │                 ├────────────────▶│
 │           │                 │                 │◀──[list]───────│
 │           │                 │                 │                 │
 │           │                 │ scanAgents()    │                 │
 │           │                 ├────────────────▶│                 │
 │           │                 │ scanPanes()     │                 │
 │           │                 ├────────────────▶│                 │
 │           │                 │ scanLogin()     │                 │
 │           │                 ├────────────────▶│                 │
 │           │                 │                 │                 │
 │           │◀──[grouped]─────┼─────────────────┤                 │
 │           │                 │                 │                 │
 │ 分组展示   │                 │                 │                 │
 │◀──────────┤                 │                 │                 │
 │           │                 │                 │                 │
 │ 勾选+清理  │                 │                 │                 │
 ├──────────▶│ clean(items)    │                 │                 │
 │           ├───────────────▶│                 │                 │
 │           │                 │ cleanSelected() │                 │
 │           │                 ├────────────────▶│                 │
 │           │                 │                 │ 备份→删除       │
 │           │                 │                 ├────────────────▶│
 │           │                 │                 │◀──[done]───────│
 │           │                 │ saveHistory()   │                 │
 │           │                 │                 │                 │
 │           │◀──[completed]───┤                 │                 │
 │◀─[Toast]──┤                 │                 │                 │
```

---

## 9. 卸载安全保护

### 9.1 不可卸载 App 规则

```
InstalledApp 字段：
  isProtected: Bool            // 是否受保护
  protectionReason: String?    // 保护原因

规则优先级：
  路径在 /System/* 下                      → isProtected = true
  bundleID 在系统保护列表中                  → isProtected = true
  其他                                      → 可卸载
```

### 9.2 系统保护列表

```swift
let protectedBundleIDs: Set<String> = [
    "com.apple.finder",
    "com.apple.Terminal",
    "com.apple.systempreferences",
    "com.apple.dock",
    "com.apple.loginwindow",
    "com.apple.WindowManager",
]

// 通配匹配：bundleID.hasPrefix("com.apple.CoreServices.")
// 或 bundleID.hasPrefix("com.apple.launchd.")
// 在 classifyProtected() 中通过 prefix 判断
```

### 9.3 运行中 App 处理

```
检测到运行 →
  按钮文案: "退出并卸载"
  点击 → NSRunningApplication.terminate()
  └─ 超时 5s → terminateForce()
  └─ 仍失败 → "App 拒绝退出，请手动退出后重试"
```

---

## 10. App 来源识别

```swift
enum AppSource {
    case system           // /System/* 下，受保护
    case appleBuiltIn     // Apple 自带但非系统（如 Utilities）
    case mas              // App Store 下载
    case userInstalled    // 互联网/其他途径
    case unknown          // 无法识别
}

// 识别逻辑
func classifySource(url: URL, bundleID: String) -> AppSource {
    if url.path.hasPrefix("/System/")          { return .system }
    if bundleID.hasPrefix("com.apple.") &&
       isAppleSigned(url)                     { return .appleBuiltIn }
    if hasMASReceipt(url)                     { return .mas }
    if url.path.contains("/Applications/")    { return .userInstalled }
    return .unknown
}
```

---

## 11. 定价与商业模型

### 11.1 定价

| 层 | 价格 | 方式 | 功能 |
|---|---|---|---|
| **免费** | $0 | — | 卸载任意 App + 基础残留扫描 |
| **Pro** | **$9.99** | 一次性买断 | 深度清理 + 启动项管理 + 批量操作 + 可视化 + Widget + Shortcuts + AI 分析 |

### 11.2 免费/Pro 分界

| 功能 | 免费 | Pro |
|---|---|---|
| 卸载 App + 基础残留 | ✅ | ✅ |
| 应用列表 + 大小查看 | ✅ | ✅ |
| 深度系统清理 | ❌ | ✅ |
| 启动项管理 | ❌ | ✅ |
| 批量卸载 | ❌ | ✅ |
| 应用体积可视化 | ❌ | ✅ |
| AI "很少用"分析 | ❌ | ✅ |
| Widget | ❌ | ✅ |
| Shortcuts | ❌ | ✅ |
| 撤销回滚 | ✅ | ✅ |

### 11.3 地区定价

| 地区 | 价格 |
|---|---|
| 美国 | $9.99 |
| 欧元区 | €9.99 |
| 中国 | ¥48 |
| 日本 | ¥1,200 |

---

## 12. 测试策略

### 12.1 测试层次

| 层级 | 内容 | 工具 | 覆盖率 |
|---|---|---|---|
| **单元** | ResidueDetector、confidence 计算、TrashMover 状态机、AppSource 识别 | XCTest | > 80% |
| **集成** | 扫描→残留→卸载→回滚 全链路 | XCTest | 3 条核心链路 |
| **沙箱** | 无 FDA/有 FDA 功能降级 | XCTest + 手动 | 20 边界场景 |
| **UI** | 卸载流程、付费锁、引导 | XCUITest | 5 条核心用例 |
| **兼容性** | macOS 13/14/15, Intel/Apple Silicon | CI 矩阵 | 全矩阵 |
| **性能** | 1000+ App 扫描, 内存泄漏 | XCTest Metrics | < 200ms |

### 12.2 沙箱测试矩阵

| Scenario | FDA | Expected Result |
|---|---|---|
| 基础卸载 | ❌ | App 移入废纸篓，残留不可扫 |
| 基础卸载 | ✅ | App + 残留全部移入废纸篓 |
| 深度清理 | ❌ | 显示"需要 FDA 授权" |
| 深度清理 | ✅ | LaunchAgents/PrefPanes 可管理 |
| 卸载运行中 App | ❌ | 提示退出，不强制 |
| 卸载系统 App | ❌ | 按钮禁用 |
| 回滚恢复 | ❌ | 废纸篓→原位 |

---

## 13. 上线时间线

| 阶段 | 周次 | 交付 | 依赖 |
|---|---|---|---|
| 0 | W1-W2 | kFoundation 复用 + Sandbox 原型验证 | kSpaceClean v1 稳定 |
| 1 | W3-W4 | AppCatalogService + ResidueDetector + TrashMover | kFoundation |
| 2 | W5-W6 | UI 全流程（列表/详情/确认/回滚/历史） | 阶段 1 |
| 3 | W7-W8 | DeepCleanEngine + StartupItemManager（Pro 功能） | 阶段 2 |
| 4 | W9-W10 | Widget + Shortcuts + Finder Extension + 菜单栏 | 阶段 2 |
| 5 | W11-W12 | StoreManager(IAP) + FDA 引导 + 多语言 | 阶段 3 |
| 6 | W13-W14 | TestFlight + Bug Bash + 性能优化 + App Store 提交 | 全部完成 |

预估：**14 周**，每周 ~25 小时

---

## 14. 无障碍

| 类别 | 支持 |
|---|---|
| VoiceOver | 所有按钮 + 交互元素有 label |
| 动态字体 | SwiftUI Dynamic Type 自适应 |
| 减少动效 | 检测 AccessibilitySettings，关闭过渡动画 |
| 键盘导航 | ⌘F 搜索 / ⌘, 设置 / ⌘⌫ 卸载 / Space 预览 |

---

## 15. 隐私与合规

- **零网络**：entitlements 禁用网络，无数据上报
- **本地计算**：AI 分析在 Core Data 本地完成，不上传
- **FDA 仅本地**：Full Disk Access 仅用于本地文件扫描
- **GDPR / CCPA**：无个人数据收集，无需额外合规
- **App Privacy Details**：
  - 不收集任何数据
  - App Store 隐私标签：**Data Not Collected**

---

## 16. 实施计划过渡

本 spec 文档完成后，下一步通过 **writing-plans** 技能拆解为：
1. kFoundation 复用模块识别
2. 各阶段任务拆解（每个阶段对应一个 feature branch）
3. 文件级 task 分配
4. 里程碑 checkpoint 定义
