# kDupe v1 完整设计规格

> **项目**：Kraftly Mac App Suite — kDupe（重复/大文件清理）
> **日期**：2026-07-26
> **版本**：v1（首发完整版）
> **状态**：设计定稿

---

## 目录

1. [产品定位](#1-产品定位)
2. [核心检测算法](#2-核心检测算法)
3. [架构设计](#3-架构设计)
4. [类图设计](#4-类图设计)
5. [数据层设计](#5-数据层设计)
6. [UX 交互设计](#6-ux-交互设计)
7. [系统集成](#7-系统集成)
8. [盈利设计](#8-盈利设计)
9. [隐私与合规](#9-隐私与合规)
10. [测试策略](#10-测试策略)

---

## 1. 产品定位

### 1.1 一句话定位
让 Mac 用户找到并清理重复和未使用的文件，释放磁盘空间。

### 1.2 目标用户（三画像）

| 画像 | 核心场景 | 主色 | 默认模式 |
|---|---|---|---|
| **开发者** | 代码项目中的构建产物、重复依赖、大文件 | `#4F7CFF` 蓝 | 字节级重复 + 目录重复 + 构建产物 + 大文件 |
| **设计师** | 设计稿重复、视觉素材、大文件 | `#FF6B9D` 粉 | 字节级重复 + 大文件 + 感知相似 |
| **摄影师** | RAW+JPEG 配对、大图片、视觉重复 | `#FFB340` 橙 | 字节级重复 + 大文件 + 感知相似 + RAW+JPEG |

### 1.3 差异化定位

| 维度 | Gemini 2 | Speedy Duplicate Finder | kDupe |
|---|---|---|---|
| 定价 | $19.95/年 订阅 | $29.99 买断 | **$14.99 买断** |
| 开发者工具 | ❌ | ❌ | ✅ CLI + Web Dashboard + 构建产物检测 |
| 三画像适配 | ❌ | ❌ | ✅ 开发者/设计师/摄影师差异化 UI |
| AI 感知哈希 | ✅（有限） | ❌ | ✅ CoreML ANE + vImage fallback |
| RAW+JPEG | ❌ | ❌ | ✅ EXIF 验证配对 |
| Finder 扩展 | ❌ | ❌ | ✅ Badge + 右键菜单 |
| Web Dashboard | ❌ | ❌ | ✅ localhost:7711 |

### 1.4 定价

- **模式**：一次性买断 **$14.99**
- **试用**：7 天全功能试用，到期后清理功能锁定
- **免费层**：扫描永久免费，清理需购买
- **家庭共享**：支持 Family Sharing

---

## 2. 核心检测算法

### 2.1 总体架构：两阶段流水线

```
[File URLs] → Phase 1: Size Grouping → Phase 2: Hash Verification → [Duplicate Sets]
```

**参考来源**：算法流程参考 Lemon 的 `QMDuplicateFiles`（`matchesFileSize` → `hashCompare:` 两阶段），但用 Swift Concurrency + Apple Frameworks 完全重写。

### 2.2 文件枚举（FileWalker）

采用 `FileManager.enumerator(at:includingPropertiesForKeys:)` 包装为 `AsyncThrowingStream<URL, Error>`。

**过滤规则**（同 Lemon `QMDuplicateFileScanManager`）：
- 别名文件（`isAliasFile`）→ 跳过
- 隐藏文件（`isHidden`）→ 跳过，目录跳过子节点
- Package（`isPackage`）→ 除 `~/Pictures/` 下的 package 外跳过子节点
- 保护路径 → `~/Library/`, `/Library`, `/System`, `/Applications`, `/bin`, `/cores`, `/sbin`, `/usr`, `~/.Trash/`
- 排除扩展名 → 用户配置

**Apple 优化**：`lstat()` → `resourceValues(forKeys:)`，异步流式输出避免一次性全量加载到内存。

### 2.3 字节级重复检测（Byte-Identical）

**两阶段策略**（参考 Lemon `matchesFileSize` → `hashCompare:`）：

**Phase 1: Size Grouping**
```swift
Dictionary(grouping: urls, by: { try $0.resourceValues(forKeys: [.fileSizeKey]).fileSize })
    .filter { $0.value.count > 1 && $0.key >= config.minimumFileSize }
```

**Phase 2: Hash Verification**
- **算法**：SHA-256 via CryptoKit（ARM SHA 扩展硬件加速）
- **小文件（≤10MB）**：全量 SHA-256
- **大文件（>10MB）**：head(前 10MB) + tail(最后 4KB) + random(3 × 1MB 随机采样)
- **并发**：`TaskGroup` 每组并行 hash，对比 Lemon 的 `dispatch_apply` + `md5Queue`
- **最小文件**：200KB 可配置（同 Lemon 的 `if filesize < 200*1024 continue`）

**Lemon → kDupe 变化**：

| Lemon (ObjC) | kDupe (Swift) |
|---|---|
| MD5(10MB head) + CRC32(tail) | SHA-256(head+tail+random) |
| `dispatch_apply` + 手动 queue | `TaskGroup` 自动调度 |
| `NSMutableDictionary` keyed by `NSString` | `[Int64: [URL]]` 值类型 |
| `stopped` BOOL | `Task.checkCancellation()` |
| delegate 回调 | `AsyncStream<ScanEvent>` |

### 2.4 目录级重复检测（Directory Dedup）

**参考 Lemon**：`dirContentsEqualAtItem:item2:layer:` 递归比较两个目录内容。

**kDupe 优化**：O(n²) pairwise → **O(n) content hash aggregation**

```
对每个目录：
  1. 递归遍历所有子文件
  2. 计算 content_hash = SHA256(concat(relativePath + fileSize + fileSHA256))
  3. 按 content_hash 分组 → 相同 hash 的目录即重复
```

### 2.5 感知哈希（pHash）相似检测

**适用场景**：图片缩放/格式转换/水印导致的视觉相似但字节不同。

**算法**：
1. 缩放到 32×32 灰度
2. DCT 变换 → 取左上 8×8 低频
3. 以中位数为阈值 → 64-bit fingerprint
4. Hamming distance < 10 → 相似

**硬件加速**：
- macOS 14+: CoreML ANE 推理
- macOS 13+: Accelerate vImage fallback (`vImageScale_ARGB8888` + `vDCT_Forward`)

### 2.6 大文件检测

在 FileWalker 阶段直接按 size 阈值过滤，无额外扫描开销。默认阈值 100MB（三画像不同）。

### 2.7 构建产物检测

模式匹配已知构建目录结构：
- Xcode: `DerivedData/`, `*.xcworkspace/xcuserdata/`
- Swift: `.build/`, `.swiftpm/`
- Node: `node_modules/`, `.cache/`
- Rust: `target/debug/`, `target/release/`
- Go: `vendor/`（重复依赖）
- CocoaPods: `Pods/`
- Carthage: `Carthage/Build/`

### 2.8 RAW + JPEG 配对检测

1. 文件名配对：`IMG_1234.CR3` ↔ `IMG_1234.JPG`
2. EXIF `DateTimeOriginal` 验证确认配对
3. 标记为用户可选择删除 JPEG（保留 RAW）

### 2.9 算法演进总览

| 维度 | Lemon（ObjC 参考） | kDupe（Swift + Apple） |
|---|---|---|
| 文件遍历 | NSDirectoryEnumerator + lstat | 同思路，AsyncThrowingStream + resourceValues |
| 字节级重复 | MD5(10MB) + CRC32(tail) | SHA-256(head+tail+random) via CryptoKit |
| 目录级重复 | O(n²) `dirContentsEqualAtItem:` | O(n) content hash aggregation |
| 感知重复 | 无 | pHash via CoreML ANE / vImage fallback |
| 大文件 | size 阈值 | walk 阶段直接过滤 |
| 构建产物 | 无 | 模式匹配目录结构 |
| RAW+JPEG | 无 | EXIF 匹配 |
| 并行 | dispatch_apply + dispatch_async | TaskGroup |
| 进度 | delegate + CFAbsoluteTime | AsyncStream |
| 取消 | stopped BOOL | Task.checkCancellation() |
| 分组数据 | NSMutableDictionary | 值类型 Dictionary |

---

## 3. 架构设计

### 3.1 4 层架构

```
┌──────────────────────────────────────────────┐
│  UI Layer    │  SwiftUI + NSViewRepresentable │
│              │  Profile-adaptive, Coordinator  │
├──────────────────────────────────────────────┤
│  ViewModel   │  ObservableObject + @MainActor │
│  Layer       │  State containers               │
├──────────────────────────────────────────────┤
│  Service     │  actor + Swift Concurrency     │
│  Layer       │  Business logic, pipelines      │
├──────────────────────────────────────────────┤
│  Data/       │  Core Data + Repository        │
│  Persistence │  UserDefaults + JSON cache     │
└──────────────────────────────────────────────┘
```

### 3.2 设计模式

| 模式 | 用途 | 位置 |
|---|---|---|
| **MVVM** | 视图与状态分离 | UI ↔ ViewModel |
| **Coordinator** | NavigationStack 路由 | AppCoordinator |
| **Strategy** | 可插拔检测算法 | DetectionStrategy 协议 |
| **Repository** | 持久化抽象 | DuplicateRepository 协议 |
| **Factory** | Profile 差异化场景 | ProfileSceneFactory |
| **Actor** | 隔离可变状态 | Service 层全部 |

### 3.3 通讯方式

| 方向 | 方式 |
|---|---|
| View ↔ ViewModel | `@Observable` 绑定 |
| ViewModel → Service | `async/await` |
| Service → ViewModel | `AsyncStream<ScanEvent>` |
| Service ↔ Service | actor 隔离，Orchestrator 编排 |
| Service → Data | Repository 协议 |
| 跨进程 (CLI) | XPC Service |
| 跨进程 (Web) | localhost HTTP |
| 跨进程 (Finder) | DarwinNotificationCenter |

---

## 4. 类图设计

### 4.1 核心类全景

```
kDupeApp.swift (@main)
  └── AppCoordinator (ObservableObject)
        ├── ScanView (profile-adaptive)
        │     └── ScanViewModel (@MainActor)
        ├── ResultView
        │     └── ResultViewModel
        ├── HistoryView
        │     └── HistoryViewModel
        └── SettingsView

ScanOrchestrator (actor)
  ├── FileWalker (actor)
  ├── ByteIdenticalDetector (actor)
  ├── DirectoryDedupDetector (actor)
  ├── PerceptualDetector (actor)
  ├── LargeFileDetector (actor)
  ├── BuildArtifactDetector (actor)
  └── RawJPEGPairDetector (actor)

RepositoryFactory
  ├── CoreDataDuplicateRepository
  └── JSONCacheRepository

ProfileSceneFactory → 根据 ProfileConfig 创建不同配置的 View
```

### 4.2 协议清单

| 协议 | 用途 | 实现者 |
|---|---|---|
| `DuplicateRepository` | 持久化抽象 | `CoreDataDuplicateRepository`, `JSONCacheRepository` |
| `FileFiltering` | 文件过滤策略 | `ExcludedExtensionFilter`, `ProtectedPathFilter` |
| `DetectionStrategy` | 检测策略接口 | `ByteIdenticalStrategy`, `DirectoryDedupStrategy` |
| `CleanupAction` | 清理动作接口 | `MoveToTrashAction` |
| `ProfileAdaptable` | 场景自适应 | `ScanView`, `ResultView` |

### 4.3 Profile 体系

```swift
enum ProfileType: String, CaseIterable, Codable, Sendable {
    case developer, designer, photographer
}

struct ProfileConfig: Equatable, Codable, Sendable {
    let type: ProfileType
    let displayName: String
    let symbolName: String
    let accentColor: String
    let scanModes: [ScanMode]
    let defaultDirectories: [URL]
    let defaultThresholds: ThresholdConfig
}
```

---

## 5. 数据层设计

### 5.1 持久化策略

| 数据类型 | 存储方式 | 时效 |
|---|---|---|
| 扫描结果 | Core Data | 保留 30 天 |
| 清理历史 | Core Data | 永久 |
| 用户偏好 | UserDefaults | 永久 |
| 临时缓存（>1000 组） | JSON 文件 | 随扫描周期 |
| 缩略图缓存 | NSCache + LRU | 内存压力释放 |

### 5.2 Core Data 模型

```
ScanRecord 1─* DuplicateGroupEntity 1─* FileEntryEntity
CleanupRecord（独立实体）
```

**ScanRecord**：id, date, totalSize, fileCount, scanDuration, profileType, scanModesJSON, isDeleted, groups
**DuplicateGroupEntity**：id, fileSize, matchType, fileCount, sortRank, scanRecord, files
**FileEntryEntity**：id, path, fileName, fileSize, isSelected, isKept, hashValue, group
**CleanupRecord**：id, date, action, totalSize, fileCount, detailJSON, isUndone

### 5.3 Repository 协议

```swift
protocol DuplicateRepository: Sendable {
    func saveScan(scan: ScanRecord, groups: [DuplicateGroup]) async throws
    func loadRecentScan() async throws -> (ScanRecord, [DuplicateGroup])?
    func loadScanHistory(limit: Int) async throws -> [ScanRecord]
    func deleteScan(id: UUID) async throws
    func saveCleanup(record: CleanupRecord) async throws
    func loadCleanupHistory() async throws -> [CleanupRecord]
    func undoCleanup(id: UUID) async throws
    func purgeOldScans(before: Date) async throws
}
```

### 5.4 清理撤销

- 执行清理：`FileManager.trashItem(at:)` → 废纸篓（非 `removeItem`）
- 撤销：从废纸篓 `moveItem(at:to:)` 恢复
- 记录保留 30 天，过期自动清理

---

## 6. UX 交互设计

### 6.1 导航架构

```
NavigationStack
├── MainView
│   ├── Profile 切换器 + 设置 + Web Dashboard
│   ├── 扫描模式选择（勾选矩阵）
│   ├── "开始扫描"按钮
│   └── 上次扫描摘要
├── ScanProgressView（环形进度 + 实时发现列表）
├── ResultView（统计栏 + 筛选器 + 排序 + 分组列表）
│   └── GroupDetailView（文件列表 + 自动选择 + 预览 + 清理）
├── HistoryView (Sheet)
├── SettingsView
└── WebDashboard（浏览器 localhost:7711）
```

### 6.2 关键屏幕

**Onboarding（3 步）**：欢迎 → 角色选择（三卡片）→ FDA 引导

**主界面**：三画像各自不同的默认勾选模式、主题色、SF Symbol、扫描目录

**扫描进度**：环形进度 + 阶段文字 + 实时发现列表（滚动追加）

**结果页**：
- 顶部统计栏（总组数、总大小）
- 筛选器标签（全部/字节/目录/大文件/感知/产物/RAW+JPEG + 组数）
- 排序切换（大小/数量/类型）
- 每行：icon + 标题 + 大小 + 箭头

**组详情**：
- 文件列表，每组自动保留最新 1 份（⭐标记）
- 自动选择按钮（保留 1 份）
- QuickLook 预览（Space 键）
- 底部清理按钮（选中计数 + 大小）

**清理确认**：弹窗 → 进度条 → Toast（右下角 + 撤销按钮）

### 6.3 视觉规范

| 元素 | 开发者 | 设计师 | 摄影师 |
|---|---|---|---|
| 主题色 | `#4F7CFF` 蓝 | `#FF6B9D` 粉 | `#FFB340` 橙 |
| SF Symbol | `hammer.fill` | `paintbrush.fill` | `camera.fill` |
| 卡片圆角 | 10pt | 14pt | 12pt |
| 行高 | 44pt | 56pt | 48pt |

### 6.4 键盘快捷键

| 快捷键 | 动作 |
|---|---|
| `Cmd+N` | 开始扫描 |
| `Cmd+Return` | 清理选中 |
| `Cmd+Shift+A` | 自动选择 |
| `Space` | QuickLook |
| `Cmd+1-6` | 切换筛选 |
| `Cmd+,` | 设置 |
| `Cmd+W` | Web Dashboard |

---

## 7. 系统集成

### 7.1 Finder Sync Extension

- 文件夹/文件右键 → "用 kDupe 扫描" / "在 kDupe 中查看组"
- Badge 显示该目录的重复数
- 通讯：App Group UserDefaults（路径传递）+ DarwinNotificationCenter（badge 刷新）

### 7.2 CLI 工具

XPC Service 内嵌二进制，用户可选创建 `/usr/local/bin/kdupe` 符号链接。

```
kdupe scan [path...] [--mode=...] [--json|--csv]
kdupe results [scan-id] [--latest --json]
kdupe cleanup [--dry-run]
kdupe history / undo <record-id>
kdupe status / web / version
```

### 7.3 Web Dashboard

Swifter 嵌入式 HTTP Server，localhost:7711。

```
GET  /api/status      → 服务状态
GET  /api/results     → 扫描结果 JSON
POST /api/scan        → 触发扫描
POST /api/cleanup     → 触发清理
GET  /dashboard       → HTML Dashboard
```

### 7.4 Shortcuts / App Intents

3 个 Intent：扫描目录、清理重复文件、显示大文件

### 7.5 其他集成

- **Spotlight**：`CSSearchableIndex` 索引扫描结果
- **Menu Bar**：`MenuBarExtra`（SwiftUI），扫描中动态进度点
- **Widget**（macOS 14+）：QuickScan 入口 + Storage Overview

---

## 8. 盈利设计

### 8.1 定价模型

| 项目 | 值 |
|---|---|
| 价格 | $14.99 一次性买断 |
| 试用 | 7 天全功能 |
| 免费层 | 扫描永久免费 |
| 家庭共享 | 支持 |
| 大版本升级 | $9.99（可选） |

### 8.2 付费墙

7 天后清理功能锁定（按钮灰显 + 🔒 图标），扫描永久免费。其余功能（CLI 清理/Web Dashboard 写操作/导出报告/撤销）同样锁定。

### 8.3 内购 SKU

- `app.kraftly.kdupe.full_license` — $14.99
- 未来：`app.kraftly.kdupe.upgrade_v2` — $9.99

### 8.4 地区定价

| 地区 | 价格 |
|---|---|
| 美国 | $14.99 |
| 中国 | ¥98 |
| 日本 | ¥2,000 |
| 欧洲 | €14.99 |
| 英国 | £12.99 |

### 8.5 未来收入

- v1.2：Tip Jar（$1.99 / $4.99 / $9.99）
- v2：付费升级 $9.99
- 矩阵：Kraftly Bundle $29.99（kSpaceClean + kDupe）

---

## 9. 隐私与合规

### 9.1 隐私原则

- 零网络上报，所有计算本地
- 默认不收集，用户主动开启才生效
- 透明可审计

### 9.2 Apple 隐私标签

| 类别 | 状态 |
|---|---|
| 追踪 | ❌ 不追踪 |
| 关联数据 | ❌ 无 |
| 非关联数据 | ❌ 无收集 |

唯一使用的隐私相关 API：MetricKit（用户选择是否分享诊断数据）

### 9.3 Sandbox 权限

只声明必需 entitlement：user-selected.read-write、downloads.read-write、pictures.read-write、network.server（Web Dashboard）、network.client（更新检查）。

Full Disk Access 通过 TCC 引导，非 entitlement。

### 9.4 合规

提供隐私政策 URL（kraftly.app/privacy），设置页提供"清除所有本地数据"入口，支持 GDPR/CCPA/中国个保法要求。

---

## 10. 测试策略

### 10.1 测试金字塔

```
      ╱╲
     ╱ E2E ╲          ← Finder Sync + CLI + Web Dashboard
    ╱────────╲
   ╱ 集成测试  ╲       ← 扫描管线 + 清理流程 + 跨进程
  ╱────────────╲
 ╱  单元测试     ╲    ← Detector + Repository + ViewModel
╱────────────────╲
```

### 10.2 单元测试覆盖

| 模块 | 关键测试 |
|---|---|
| ByteIdenticalDetector | 空输入、完全相同文件、不同文件、200KB 过滤、大文件 hash 稳定性、取消传播 |
| PerceptualHasher | 同图不同格式近距、不同图远距 |
| CoreDataRepository | 保存读取、撤销、30 天清理 |
| ScanViewModel | 开始扫描状态、完成更新结果、取消 |
| CleanupManager | 移到废纸篓、撤销恢复、重复撤销拒绝 |

### 10.3 集成测试

| 场景 | 验证点 |
|---|---|
| 真实目录扫描 | 字节重复组数、文件数正确 |
| 构建产物检测 | 识别 DerivedData |
| RAW+JPEG 配对 | 正确配对 CR3+JPG |
| 清理流程 | 文件移至废纸篓、撤销恢复 |
| CLI | version 输出、JSON 可解析、--dry-run 不删除 |
| Web Dashboard | /api/status 200、POST /api/scan 202 |

### 10.4 性能基线（Apple Silicon M3）

| 场景 | 目标 |
|---|---|
| 10 万文件全管线 | < 30 秒 |
| SHA-256 1GB 文件 | < 2 秒 |
| Core Data 1000 组写入 | < 5 秒 |
| 内存峰值（10 万文件） | < 500MB |
| CLI 启动到输出 | < 200ms |

### 10.5 兼容性矩阵

| 维度 | 范围 |
|---|---|
| macOS | 13/14/15 |
| Silicon | M1/M2/M3/M4 |
| Intel | Rosetta 2 |
| 语言 | en/zh-Hans/ja |
| 文件系统 | APFS/HFS+ |

### 10.6 目标覆盖率

| 层级 | 目标 |
|---|---|
| 单元测试 | > 85% 行 |
| 集成测试 | 核心管线 100% |
| UI 测试 | 5 个关键流程 |
| 性能测试 | PR 回归检测 |

---

*本设计文档由 brainstorming 流程生成，已完成规格自审。*
