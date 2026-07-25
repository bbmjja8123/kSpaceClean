# Kraftly Mac App Suite — 项目指南

> 这是基于腾讯柠檬清理（`/Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon`）独立开发者启动的新一代 Mac App 矩阵。**所有代码全新 Swift 编写，仅核心逻辑参考 Lemon 实现思路，绝不复用 Lemon 任何 Objective-C / C++ 代码。**

---

## 1. 项目总览

### 1.1 目标
打造 **4 款精品 Mac App**，独立开发者运营，全球 + 中国 App Store 同步上架，通过订阅 + 买断盈利，并争取苹果编辑推荐。

### 1.2 4 款 App 一览

| App | Bundle ID | 主轴 | 定价 | 状态 |
|---|---|---|---|---|
| **kSpaceClean**（磁盘清理） | `app.kraftly.sclean` | AI + 视觉（3D 磁盘星系图） | Free Trial 7 天 → $19.99/年 | ✅ **v1 设计定稿** |
| **kWatch**（菜单栏监控） | `app.kraftly.kwatch` | 平台集成 + Widget | 待设计 | 📋 Backlog |
| **kDupe**（重复/大文件） | `app.kraftly.kdupe` | 极客 + AI（开发者场景） | 待设计 | 📋 Backlog |
| **kUninstall**（应用卸载） | `app.kraftly.kuninstall` | 平台集成 + 自动化 | 待设计 | 📋 Backlog |

### 1.3 品牌
- 命名规范：所有 App 以 `k` 前缀开头（kSpaceClean, kWatch, kDupe, kUninstall）
- 统一品牌：**Kraftly**（App Store 元数据、官网、社交账号统一）
- Slogan 候选：`Kraft — Cleaner Mac tools, made with care`

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
├── kSpaceClean/                     # App target
├── kWatch/                          # App target
├── kDupe/                           # App target
├── kUninstall/                      # App target
├── Tools/                           # 共享脚本（版本号/签名/归档）
└── docs/
```

### 2.2 关键技术决策
- **语言**：Swift 5.9+
- **UI**：SwiftUI 为主 + AppKit 兜底菜单栏 / 系统集成
- **最低系统**：macOS 13.0（用户本地机器版本）
- **编译目标**：macOS 14 SDK（用 `#available` 包裹高版本 API）
- **持久化**：Core Data（统一）+ Codable + FileManager（轻量场景）
- **并发**：Swift Concurrency（async/await + TaskGroup）
- **图形**：Metal + SceneKit（3D 磁盘星系图）
- **AI**：CoreML（本地 embedding / 分类器）
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
| kSpaceClean | ✅ | Full Disk Access + Automation |
| kWatch | ✅ | 无（只读系统 API） |
| kDupe | ✅ | Full Disk Access + 用户授权目录 |
| kUninstall | ✅ | Full Disk Access + Automation |

### 2.5 与 Lemon 的关系
- ✅ **参考**：扫描算法（两阶段 size→hash）、Daemon 架构思路、Helper 思路（但新写不部署）
- ❌ **不复用**：任何 Objective-C / C++ 代码、UI 代码、上报/统计逻辑
- ❌ **不接**：腾讯上报后台 / QQ / 微信相关 SDK
- ✅ **重新做**：所有 Swift 代码、所有 SwiftUI UI、所有 TCC 权限处理、所有 XPC Service

---

## 3. kSpaceClean 详细设计（v1 定稿）

### 3.1 一句话定位
让 Mac 存储空间回到"足够"，最聪明的磁盘清理。

### 3.2 目标用户
- **主**：MacBook 256GB/512GB 用户，频繁弹"磁盘已满"告警
- **次**：创意工作者（视频/摄影），需要定期清理临时文件
- **不服务**：开发者（→kDupe）、极客玩家（→kDupe）、系统监控需求者（→kWatch）

### 3.3 核心差异化
| 维度 | CleanMyMac X | DaisyDisk | kSpaceClean 差异点 |
|---|---|---|---|
| 主界面 | 模块拼盘 | 磁盘可视化 | **3D 磁盘星系图（Metal 渲染）** |
| 智能分类 | 规则匹配 | 无 | **CoreML 本地 AI 自动分类** |
| 扫描速度 | 中等 | 慢 | **Apple Silicon 神经引擎加速 perceptual hash** |
| 隐私 | 上报统计 | 本地 | **零网络上报，所有计算在本地** |
| 一键清理 | ✅ | ❌ | ✅ + Interactive Widget 一键清理（macOS 14+） |
| App Store 集成 | ✅ | ❌ | ✅ + Shortcuts 集成 |

### 3.4 v1 完整功能（首发即包含全部）
| 模块 | v1 内容 |
|---|---|
| 3D 磁盘星系图 | Metal + SceneKit 主视觉，根目录 → 子目录球体化 |
| 智能扫描引擎 | 系统缓存 / 应用残留 / 大文件 / 重复文件 |
| CoreML AI 分类 | 本地 embedding 分组（图片/视频/文档/缓存/开发文件） |
| 一键清理 | 移入废纸篓 + 30 天清理历史可回滚 |
| FDA 引导 | 教育性 Full Disk Access 引导流程 |
| 菜单栏图标 | 显示已用空间 + 一键扫描入口 |
| 桌面 Widget | 基础版（13）+ Interactive 版（14+） |
| Shortcuts App Intents | 扫描 / 清理缓存 / 显示大文件 三个 action |
| Live Activities | macOS 14+，清理进度长任务显示 |
| Finder 扩展 | 右键"用 kSpaceClean 扫描" |
| Spotlight 集成 | 搜"Mac 空间"出现操作 |
| 本地化 | 英文 + 简体中文 + 日文 |

### 3.5 kSpaceClean 内部模块
```
kSpaceClean/
├── App/
│   ├── kSpaceCleanApp.swift          # @main
│   ├── RootView.swift                # NavigationSplitView
│   └── AppCoordinator.swift
├── Features/
│   ├── DiskGalaxy/                   # 3D 磁盘星系可视化（差异化核心）
│   ├── SmartScan/                    # 扫描引擎 + CoreML 分类
│   ├── Cleanup/                      # 清理动作 + 废纸篓
│   └── Onboarding/                   # FDA 引导
├── Widgets/                          # 基础 + Interactive 双版本
├── Intents/                          # App Intents / Shortcuts
├── FinderExtension/                  # 右键菜单扩展
├── Resources/
│   ├── Models/                       # .mlmodel 文件
│   └── Assets.xcassets
└── Info.plist
```

### 3.6 盈利设计
- **价格**：Free Trial 7 天 → **$19.99/年**（无买断）
- **免费层**：扫描功能可用，清理额度限制 1GB，超出引导订阅
- **地区定价**：美 $19.99 / 欧 €19.99 / 中 ¥98 / 日 ¥2,400
- **内购 SKU**：Auto-Renewable Subscription（年付）

### 3.7 ASO 关键词（美区主目标）
- **主关键词**：`mac cleaner`、`disk cleaner`、`storage cleaner`、`clean my mac`、`mac storage`
- **辅关键词**：`cache cleaner`、`system junk`、`free up space`、`apple silicon cleaner`、`metal renderer`
- **避坑**：不使用 CleanMyMac 商标名（App Store 拒）

### 3.8 上架时间表（独立开发者）
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

---

## 4. Backlog（待设计）

### 4.1 kWatch（菜单栏监控）
- **主轴**：平台集成 + Widget + Live Activities
- **目标用户**：极客 / 设计师 / 视频创作者
- **待定**：定价模式、iStat Menus 主战场切入角度
- **预期时间**：kSpaceClean 上架后启动设计

### 4.2 kDupe（重复/大文件）
- **主轴**：极客 + AI（开发者场景）
- **目标用户**：开发者 / 设计师 / 摄影师
- **待定**：是否独立还是合并到 kSpaceClean V2
- **预期时间**：kSpaceClean 稳定后再启动

### 4.3 kUninstall（应用卸载）
- **主轴**：平台集成 + 自动化（Shortcuts / Finder 扩展 / Control Widget）
- **目标用户**：全人群，特别是试装党
- **待定**：是否独立还是合并到 kSpaceClean V2
- **预期时间**：Backlog

---

## 5. 通用约定

### 5.1 代码风格
- SwiftLint 强制（`swiftlint` 配置在 `kFoundation/.swiftlint.yml`）
- Swift 5.9+ 严格并发（`SWIFT_STRICT_CONCURRENCY = complete`）
- 所有公共 API 必须有 DocC 注释
- 提交前必须跑 `swift test` + 单元测试覆盖率 > 70%

### 5.2 Git 规范
- 主分支：`main`（保护，仅 PR 合并）
- 开发分支：`feature/<app>-<feature>`、`fix/<app>-<bug>`
- 提交信息：`feat(kSpaceClean): add 3D galaxy renderer`

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
- iStat Menus（菜单栏监控标杆，kWatch 灵感）
- BuhoCleaner（华人独立开发标杆）
- Apple Design Awards 2025（推荐方向）

---

## 7. 当前进度

- [x] 项目可行性分析
- [x] 竞品调研（CleanMyMac / DaisyDisk / iStat Menus / Gemini 2 / BuhoCleaner）
- [x] 拆分方案锁定（A：4 款精品矩阵）
- [x] 技术架构（Workspace + kFoundation + Swift 全新）
- [x] kSpaceClean v1 完整设计
- [ ] kWatch 设计
- [ ] kDupe 设计
- [ ] kUninstall 设计
- [ ] 汇总设计文档（docs/superpowers/specs/）
- [ ] 规格自审
- [ ] 用户复核
- [ ] 转入 writing-plans 编写实施计划

> ⚠️ **现阶段不要写实现代码**。所有设计待汇总到 spec 文档并通过后，再通过 writing-plans 技能拆解为可执行任务。

---

最后更新：2026-07-25（kSpaceClean 设计定稿）