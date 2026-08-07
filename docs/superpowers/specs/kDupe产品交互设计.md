# kDupe 产品交互设计 — 会话完整记录

> **项目**：Kraftly Mac App Suite — kDupe（重复/大文件清理）
> **设计日期**：2026-07-26
> **对应规格文档**：`docs/superpowers/specs/2026-07-26-kraftly-kdupe-design.md`
> **本文目的**：记录本次 brainstorming 会话的完整过程、所有设计决策、Review 发现及修复内容

---

## 目录

1. [会话概览](#1-会话概览)
2. [探索项目上下文](#2-探索项目上下文)
3. [产品定位澄清](#3-产品定位澄清)
4. [方案设计与选择](#4-方案设计与选择)
5. [9 大设计章节逐节确认](#5-9-大设计章节逐节确认)
6. [综合 Review 与修复](#6-综合-review-与修复)
7. [最终规格概览](#7-最终规格概览)
8. [附录：与会话相关的参考代码](#8-附录与会话相关的参考代码)

---

## 1. 会话概览

### 1.1 会话流程

```
探索项目上下文 → 澄清问题 (×3) → 方案设计 (2-3 方案) → 设计章节逐节确认 (×9) → 综合 Review → 修复 10 项 → 产出规格文档
```

### 1.2 参与角色

- **用户**：独立开发者，正在构建 Kraftly Mac App Suite（4 款精品 Mac App）
- **AI**：brainstorming 流程引导者，负责提问、设计方案、编写规格、Review 和修复

### 1.3 前置条件

- kSpaceClean v1 已设计定稿并进入实施
- kWatch v1 已设计定稿
- kDupe 位于 Backlog，本次正式启动设计
- 已有 Lemon 项目作为算法参考（`/Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon/Tools/LemonDuplicatefile/LemonDuplicatefile/DuplicateFileScan/`）

---

## 2. 探索项目上下文

### 2.1 读取的参考文件

| 文件 | 用途 |
|---|---|
| `CLAUDE.md` | 项目总览、4 款 App 矩阵、技术架构、当前进度 |
| `MEMORY.md` | 用户记忆：Kraftly 项目、Lemon 参考策略、禁止复用代码、设计先行偏好 |
| `2026-07-26-kraftly-kdupe-design.md` | （前一 session 已开始编写的设计规格） |
| `QMDuplicateFileScanManager.h` | Lemon 重复文件扫描管理器接口 |
| `QMDuplicateFiles.h` | Lemon 重复文件检测入口 |
| `QMDuplicateFileScanManager.m` | Lemon 核心实现：文件枚举、过滤、两阶段扫描 |

### 2.2 Lemon 参考的核心逻辑

从 `QMDuplicateFileScanManager.m` 中提取的关键参考点：

**文件枚举**（`listPathContent:excludeArray:delegate:`）：
- 使用 `NSDirectoryEnumerator` 遍历目录
- 过滤规则：别名文件跳过、Package 跳过（`~/Pictures/` 下除外）、隐藏文件跳过、保护路径排除
- 进度模拟：基于 arc4random_uniform 的采样式进度回调

**两阶段扫描**：
- Phase 1：按文件大小分组（`matchesFileSize`）
- Phase 2：Hash 比对（`hashCompare:`），使用 MD5(10MB head) + CRC32(tail)

**目录比较**：`dirContentsEqualAtItem:item2:layer:` 递归 O(n²) pairwise 比较

**大小计算**：`sizeAtPath:diskMode:delegate:` 使用 lstat + BFS 遍历，限制了 10240×3 文件数

### 2.3 kSpaceClean 设计参考

作为 Kraftly 系列的第一个 App，kSpaceClean 的 4 层架构、SwiftUI + Swift Concurrency、Core Data 持久化等决策被 kDupe 继承。

---

## 3. 产品定位澄清

### 3.1 问题 1：kDupe 的差异化方向

**AI 问**：kDupe vs Gemini 2 / Speedy Duplicate Finder 的核心差异？

**用户答**：走极客 + AI 路线，面向开发者场景。

**决策**：
- 三画像设计（开发者/设计师/摄影师），各自不同的默认扫描模式和 UI 主题
- CLI 工具 + Web Dashboard 作为开发者差异化核心
- AI 感知哈希（pHash）作为技术差异化

### 3.2 问题 2：是否合并入 kSpaceClean

**AI 问**：kDupe 是否应该作为独立 App 发布，还是合并到 kSpaceClean V2？

**用户答**：独立 App，走 Kraftly 4 款矩阵策略。

**决策**：
- 独立 App，Bundle ID `app.kraftly.kdupe`
- 独立定价 $14.99 买断
- 共享 kFoundation 层的扫描/Hash 等基础能力

### 3.3 问题 3：定价与盈利

**AI 问**：定价策略和付费墙设计？

**用户答**：一次性买断 $14.99，7 天全功能试用，扫描永久免费。

**决策**：
- 清理功能在 7 天后锁定
- CLI `--dry-run` 始终免费，`cleanup`/`undo` 付费
- 家庭共享支持
- 未来 v2 付费升级 $9.99

---

## 4. 方案设计与选择

### 4.1 方案一：独立 App + 三画像 + CLI+Web（✅ 推荐并选中）

**定位**：极客 + AI（开发者场景）的独立重复/大文件清理 App

**核心差异化**：
- 三画像（开发者/设计师/摄影师）各自不同的 UI 主题和默认扫描模式
- CLI 工具 + XPC Service
- Web Dashboard（localhost:7711）
- AI 感知哈希检测（Apple Vision framework）
- Finder Sync Extension（Badge + 右键菜单）

**推荐理由**：与 Gemini 2 形成显著差异化，覆盖开发者这一高价值用户群，与 Kraftly 矩阵策略一致。

### 4.2 方案二：kSpaceClean 功能模块（被否决）

将重复/大文件检测作为 kSpaceClean V2 的一个模块。

**否决理由**：功能深度不够，无法与 Gemini 2 竞争；偏离 kSpaceClean "磁盘清理" 定位；丢失开发者用户群。

### 4.3 方案三：通用扫描工具（被否决）

定位为通用文件扫描 SDK，支持插件化检测策略。

**否决理由**：过度设计；非 App Store 友好；独立开发者维护成本过高。

---

## 5. 9 大设计章节逐节确认

### 5.1 产品定位（Section 1）

**确认内容**：
- 一句话定位：让 Mac 用户找到并清理重复和未使用的文件
- 三画像：开发者（蓝 `#4F7CFF`）、设计师（粉 `#FF6B9D`）、摄影师（橙 `#FFB340`）
- 竞品对比：vs Gemini 2 / Speedy Duplicate Finder
- 定价：$14.99 买断 + 7 天试用

**用户确认**：✅

### 5.2 核心检测算法（Section 2）

**确认内容**：

| 检测能力 | 算法 | 参考 |
|---|---|---|
| 文件枚举 | FileManager.enumerator → AsyncThrowingStream | Lemon NSDirectoryEnumerator |
| 字节级重复 | SHA-256 head(10MB)+tail(4KB)+random(3×1MB) | Lemon MD5+CRC32 |
| 目录级重复 | O(n) content hash aggregation | Lemon O(n²) pairwise |
| 感知哈希 | VNGenerateImageFeaturePrintRequest → Hamming | 无（新增） |
| 大文件 | size 阈值直接过滤 | Lemon 同 |
| 构建产物 | 模式匹配目录结构 | 无（新增） |
| RAW+JPEG | EXIF DateTimeOriginal 验证 | 无（新增） |

**Apple Silicon 优化**：
- SHA-256 通过 CryptoKit 使用 ARM SHA 扩展硬件加速
- pHash macOS 14+ 自动路由到 ANE（~8-15ms/张），13 fallback vImage（~20-40ms/张）
- TaskGroup 替代 Lemon 的 dispatch_apply

**用户确认**：✅

### 5.3 架构设计（Section 3）

**确认内容**：

**4 层架构**：
```
UI Layer (SwiftUI) → ViewModel Layer (@MainActor) → Service Layer (actor) → Data Layer (Core Data)
```

**通讯方式**：
- View → ViewModel：`@Observable` 绑定
- ViewModel → Service：`async/await`
- Service → ViewModel：`AsyncStream<ScanEvent>`
- 跨进程：XPC Service / Swifter localhost / DarwinNotificationCenter

**设计模式**：MVVM + Coordinator + Repository + Factory + Actor

**用户确认**：✅

### 5.4 类图设计（Section 4）

**确认内容**：

**核心类**：
- `ScanOrchestrator (actor)` — 编排多个 Detector
- `FileWalker (actor)`, `ByteIdenticalDetector (actor)`, `DirectoryDedupDetector (actor)`, `PerceptualDetector (actor)`, `LargeFileDetector (actor)`, `BuildArtifactDetector (actor)`, `RawJPEGPairDetector (actor)`
- `CoreDataDuplicateRepository`, `JSONCacheRepository`
- `ProfileSceneFactory` — 根据 ProfileConfig 创建不同配置的 View

**协议**：`DuplicateRepository`, `FileFiltering`, `CleanupAction`, `ProfileAdaptable`

**Profile 体系**：
```swift
enum ProfileType: String, CaseIterable, Codable, Sendable {
    case developer, designer, photographer
}
```

**用户确认**：✅

### 5.5 数据层设计（Section 5）

**确认内容**：

**持久化策略**：
- 扫描结果 → Core Data（保留 30 天）
- 清理历史 → Core Data（永久）
- 用户偏好 → UserDefaults
- 临时缓存 → JSON 文件
- 缩略图缓存 → NSCache + LRU

**Core Data 模型**：
```
ScanRecord 1─* DuplicateGroupEntity 1─* FileEntryEntity
CleanupRecord（独立实体）
```

**清理撤销**：`FileManager.trashItem(at:)` → 废纸篓，撤销从废纸篓 moveItem 恢复

**用户确认**：✅

### 5.6 UX 交互设计（Section 6）

**确认内容**：

**导航架构**：NavigationStack → MainView → ScanProgressView → ResultView → GroupDetailView

**关键屏幕**：
- Onboarding（3 步）：欢迎 → 角色选择 → FDA 引导
- 主界面：三画像各自不同主题色、SF Symbol、扫描目录
- 扫描进度：环形进度 + 实时发现列表
- 结果页：统计栏 + 筛选器 + 排序 + 分组列表
- 组详情：文件列表 + 自动选择（⭐标记保留）+ QuickLook + 清理

**视觉规范**：色彩系统（三画像）、排版层级（Title 1 → Badge）、间距网格（1x→8x）、圆角系统（1→4）、深色模式、切换过渡动画

**键盘快捷键**：Cmd+N（扫描）、Cmd+Return（清理）、Cmd+Shift+A（自动选择）、Space（QuickLook）等

**用户确认**：✅

### 5.7 系统集成（Section 7）

**确认内容**：

| 集成方式 | 技术方案 |
|---|---|
| Finder Sync Extension | 右键菜单 + Badge + DarwinNotificationCenter |
| CLI 工具 | XPC Service + `/usr/local/bin/kdupe` 符号链接（10 命令） |
| Web Dashboard | Swifter localhost:7711 |
| Shortcuts / App Intents | 3 个 Intent |
| Spotlight | CSSearchableIndex |
| Menu Bar | MenuBarExtra（SwiftUI） |
| Widget | QuickScan + Storage Overview（macOS 14+） |

**CLI 退出码**：0-6（成功/通用错误/参数错误/FDA 未授权/XPC 未运行/用户取消/需购买）

**Web Dashboard 安全**：CSRF（Origin + X-KDupe-Token）、XSS（CSP + entity escape）、127.0.0.1 only、StoreKit 付费校验、Home 路径截断

**用户确认**：✅

### 5.8 盈利设计（Section 8）

**确认内容**：
- $14.99 一次性买断
- 7 天全功能试用，扫描永久免费
- 付费墙：清理按钮灰显 + 🔒
- CLI `--dry-run` 始终免费，`cleanup`/`undo` 付费
- Family Sharing 支持
- 地区定价：美 $14.99 / 中 ¥98 / 日 ¥2,000 / 欧 €14.99 / 英 £12.99

**用户确认**：✅

### 5.9 隐私与合规 + 测试策略（Section 9-10）

**确认内容**：

**隐私**：
- 零网络上报，所有计算本地
- Apple 隐私标签：不追踪 / 无关联数据 / 无收集
- MetricKit 可选分享诊断数据

**测试金字塔**：单元测试 → 集成测试 → E2E（Finder Sync + CLI + Web Dashboard）

**性能基线（M3）**：10 万文件 < 30 秒 / SHA-256 1GB < 2 秒 / pHash ANE ~8-15ms / 内存峰值 < 500MB

**兼容性**：macOS 13/14/15、M1-M4、Rosetta 2、en/zh-Hans/ja、APFS/HFS+

**用户确认**：✅

---

## 6. 综合 Review 与修复

### 6.1 11 项 Review 发现

在规格文档写完后，进行了全面的自审，发现 11 项问题：

| # | 章节 | 问题类型 | 描述 | 状态 |
|---|---|---|---|---|
| 1 | 3.2 | 遗漏 | 缺少状态与错误处理的设计（ScanState、错误策略、边界状态） | 已修复 |
| 2 | 3.2 | 过度设计 | `DetectionStrategy` 协议在 v1 场景下过早抽象（Strategy 模式），直接用 actor 枚举更简洁 | 已修复 |
| 3 | 4.2 | 不一致 | `DetectionStrategy` 出现在协议清单中，但设计模式中已确认不使用 | 已修复 |
| 4 | 5 | 遗漏 | Core Data 并发策略未说明（actor ↔ NSManagedObjectContext 交互） | 已修复 |
| 5 | 6.3 | 不完整 | 视觉规范仅有颜色表，缺少排版层级、间距网格、圆角、深色模式、动画 | 已修复 |
| 6 | 6 | 遗漏 | 缺少 i18n 策略（多语言支持范围、资源管理、注意事项） | 已修复 |
| 7 | 7.2 | 不完整 | CLI 命令偏少（5 命令），缺少 watch/completion 和退出码规范 | 已修复 |
| 8 | 7.3 | 不完整 | Web Dashboard 缺少 API 端点定义和安全措施 | 已修复 |
| 9 | 8.2 | 不清晰 | CLI 清理的付费边界模糊（--dry-run 是否免费、undo 是否付费） | 已修复 |
| 10 | 10.4 | 不完整 | 性能基线 5 行太少，缺少 pHash/Core Data 清理/Web Dashboard/FSync 基线 | 已修复 |
| — | 2.9 | 已在前一 session 修复 | 演进对比表中 Lemon 字节级重复写的是 SHA-256（应为 MD5+CRC32） | 已修复 |

### 6.2 10 项修复内容详解

#### 修复 1：添加 `3.4 状态与错误处理`（Section 3）

- `ScanState` 枚举：`idle` / `scanning(phase:progress)` / `completed(ScanResult)` / `failed(ScanError)`
- `ScanPhase` 枚举：`enumerating` / `hashing` / `detecting` / `cleaning`
- 8 种错误类型的处理策略表（FDA 未授权 / EACCES / 文件读取失败 / SHA-256 错误 / Core Data 写入失败 / XPC 超时 / 端口冲突 / 撤销时文件不存在）
- 5 种边界状态（空状态 / 超大结果集 / App 进入后台 / 磁盘空间不足 / 扫描中取消）

#### 修复 2：从 `3.2 设计模式` 移除 `DetectionStrategy`

删除了 `| **Strategy** | 可插拔检测算法 | DetectionStrategy 协议 |` 行。

**原因**：v1 的所有 Detector 都是 actor 直接实现，Strategy 模式引入不必要的间接层。

#### 修复 3：从 `4.2 协议清单` 移除 `DetectionStrategy`

删除了 `| DetectionStrategy | 检测策略接口 | ByteIdenticalStrategy, DirectoryDedupStrategy |` 行。

**原因**：与修复 2 一致，保持协议清单与设计模式一致。

#### 修复 4：添加 `5.5 Core Data 并发策略`

- NSPrivateQueueConcurrencyType + `context.perform` 代码片段
- 5 条关键规则：
  1. 禁止跨 actor 传递 NSManagedObject（使用 NSManagedObjectID）
  2. >1000 条使用 NSBatchInsertRequest / NSBatchDeleteRequest
  3. >5000 条使用 NSFetchRequest 分页
  4. 写操作聚合为单次 perform 块
  5. 内存警告时 refreshAllObjects()

#### 修复 5：扩展 `6.3 视觉规范` 为 6 个子章节

| 子章节 | 内容 |
|---|---|
| 色彩系统 | 三画像主色调 + 浅色/深色背景 + 卡片 + SF Symbol + 行高 |
| 排版层级 | Title 1(28pt Bold) → Badge(11pt Medium) 共 6 级 |
| 间距网格 | 1x(4pt) → 8x(32pt) 共 7 级 |
| 圆角系统 | Radius 1(6pt) → 4(20pt) 共 4 级 |
| 深色模式 | `@Environment(\.colorScheme)` 自动切换，自定义 light/dark 变体 |
| Profile 切换过渡动画 | 4 种动画场景及时长曲线 |

#### 修复 6：添加 `6.5 本地化与国际化`

- 3 语言支持：en（主开发）/ zh-Hans（母语）/ ja（外包）
- 资源清单：~300 String Catalog 条 + ~100 工具提示 + 每语言 ~6 张截图
- 5 条注意事项：日期格式 / 文件大小 / 复数处理 / 权限文案 / Web Dashboard
- 4 条开发约束：LocalizedStringResource / 无硬编码 / 伪语言测试 / RTL 适配

#### 修复 7：扩展 `7.2 CLI 工具`

- 命令从 5 个扩展到 10 个（scan / results / cleanup / watch / history / undo / status / web / version / completion）
- 7 个退出码（0-6）
- watch 模式详解：JSON streaming 示例 + 3 个信号处理（SIGINT / SIGHUP / SIGUSR1）
- bash/zsh shell 补全

#### 修复 8：扩展 `7.3 Web Dashboard`

- 5 个 API 端点表（GET /api/status / GET /api/results / POST /api/scan / POST /api/cleanup / GET /dashboard）
- 5 项安全措施表（CSRF / XSS / 本地端口绑定 / 付费校验 / 路径截断）

#### 修复 9：明确 CLI 付费边界

在 `8.2 付费墙` 中补充：
- `--dry-run` 属于"扫描"范畴，始终免费
- 实际 `cleanup` 和 `undo` 操作需要付费
- `kdupe status` 输出 `"licensed": true/false`

#### 修复 10：扩展 `10.4 性能基线` 到 10 行

新增 4 项基线：
| 场景 | 目标 |
|---|---|
| pHash 单图（ANE） | ~8-15ms |
| pHash 单图（vImage fallback） | ~20-40ms |
| Core Data 30 天数据清理 | < 1 秒 |
| Web Dashboard 首次加载 | < 500ms |
| Finder Sync Badge 刷新 | < 100ms |

---

## 7. 最终规格概览

### 7.1 文件信息

- **路径**：`docs/superpowers/specs/2026-07-26-kraftly-kdupe-design.md`
- **总行数**：~790 行
- **章节数**：10 个主章节
- **状态**：设计定稿 ✅

### 7.2 最终设计决策摘要

| 维度 | 决策 |
|---|---|
| 产品形态 | 独立 App，Kraftly 矩阵第三款 |
| 目标用户 | 三画像：开发者/设计师/摄影师 |
| 核心差异化 | CLI + Web Dashboard + AI pHash + 三画像 |
| 架构 | 4 层（UI → ViewModel → Service → Data） |
| 检测算法 | SHA-256 + O(n) dir hash + Vision pHash + 模式匹配 + EXIF |
| 持久化 | Core Data + UserDefaults + JSON cache |
| UI 技术栈 | SwiftUI + NavigationStack |
| 系统集成 | Finder Extension + CLI(XPC) + Web(Swifter) + Shortcuts + Spotlight + MenuBar + Widget |
| 定价 | $14.99 买断 + 7 天试用 |
| 免费层 | 扫描永久免费 |
| 最低系统 | macOS 13.0 |
| 隐私 | 零网络上报 |

### 7.3 Lemon → kDupe 关键演进

| 维度 | Lemon（ObjC） | kDupe（Swift） |
|---|---|---|
| 语言 | Objective-C | Swift 5.9+ |
| 并发 | dispatch_apply + dispatch_async | TaskGroup + Swift Concurrency |
| Hash | MD5 + CRC32 | SHA-256 via CryptoKit |
| 目录比较 | O(n²) pairwise | O(n) content hash |
| 感知重复 | 无 | Vision Framework pHash |
| 构建产物 | 无 | 模式匹配 |
| RAW+JPEG | 无 | EXIF 验证 |
| UI | AppKit | SwiftUI |
| 存储 | 未使用 Core Data | Core Data + Repository |
| 用户适配 | 单一 | 三画像自适应 |
| CLI | 无 | XPC Service |
| Web | 无 | Swifter Dashboard |

---

## 8. 附录：与会话相关的参考代码

### 8.1 Lemon 参考文件（仅逻辑参考，不复用代码）

```
Lemon/Tools/LemonDuplicatefile/LemonDuplicatefile/DuplicateFileScan/
├── QMDuplicateFileScanManager.h   # 扫描管理器接口
├── QMDuplicateFileScanManager.m   # 核心实现（枚举+两阶段扫描+大小计算）
├── QMDuplicateFiles.h             # 重复文件检测入口
└── QMDuplicateFiles.m             # 检测实现
```

### 8.2 kDupe 设计文档

```
docs/superpowers/specs/2026-07-26-kraftly-kdupe-design.md
```

### 8.3 项目配置参考

```
CLAUDE.md — Kraftly Mac App Suite 项目总览和约定
```

---

*本文档记录 2026-07-26  brainstorming 会话完整过程，作为 `2026-07-26-kraftly-kdupe-design.md` 的交互设计补充。*
