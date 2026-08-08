# Kraftly Mac App Suite — 项目指南

> 这是基于腾讯柠檬清理（`/Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon`）独立开发者启动的新一代 Mac App 矩阵。**所有代码全新 Swift 编写，仅核心逻辑参考 Lemon 实现思路，绝不复用 Lemon 任何 Objective-C / C++ 代码。**

---

## 1. 项目总览

### 1.1 目标
打造 **4 款精品 Mac App**，独立开发者运营，全球 + 中国 App Store 同步上架，通过订阅 + 买断盈利，并争取苹果编辑推荐。

### 1.2 4 款 App 一览

| App | Bundle ID | 主轴 | 定价 | 状态 |
|---|---|---|---|---|
| **kWise**（Mac 管家 / CMM 对标） | `app.kraftly.sclean` | 对标 CleanMyMac X：Smart Care + 启动项 + 隐私 + 磁盘健康 + 基础卸载/粉碎 | Free Trial 7 天 → $19.99/年 | 🔄 **v1.5 路线定稿** |
| **kWatch**（菜单栏监控） | `app.kraftly.kwatch` | 平台集成 + Widget | 待设计 | 📋 Backlog |
| **kSift**（重复/大文件/粉碎） | `app.kraftly.ksift` | 极客 + AI（开发者场景） | $9.99 买断 | 📋 Spec 定稿 |
| **kUninstall**（应用卸载） | `app.kraftly.kuninstall` | 平台集成 + 自动化 | 待设计 | 📋 Backlog |

### 1.3 品牌
- 命名规范：所有 App 以 `k` 前缀开头（kWise, kWatch, kSift, kUninstall）
- 统一品牌：**Kraftly**（App Store 元数据、官网、社交账号统一）
- Slogan 候选：`Kraft — Cleaner Mac tools, made with care`
- **历史改名**：原 `kSpaceClean` 已重命名为 `kWise`（2026-08-03 锁定）。bundle ID `app.kraftly.sclean` 保持不变以保留 App Store 历史评分、评论、内购项目。详见 §3.10。

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
| kWise | ✅ | Full Disk Access + Automation |
| kWatch | ✅ | 无（只读系统 API） |
| kDupe | ✅ | Full Disk Access + 用户授权目录 |
| kUninstall | ✅ | Full Disk Access + Automation |

### 2.5 与 Lemon 的关系
- ✅ **参考**：扫描算法（两阶段 size→hash）、Daemon 架构思路、Helper 思路（但新写不部署）
- ❌ **不复用**：任何 Objective-C / C++ 代码、UI 代码、上报/统计逻辑
- ❌ **不接**：腾讯上报后台 / QQ / 微信相关 SDK
- ✅ **重新做**：所有 Swift 代码、所有 SwiftUI UI、所有 TCC 权限处理、所有 XPC Service

---

## 3. kWise 详细设计（v1.5 路线定稿）

> **v1 → v1.5 演进**：原 kSpaceClean v1（2026-07-25 定稿）已重命名为 kWise，对标 CleanMyMac X。v1 已完成模块（4 级扫描树 / 150+ 应用缓存规则 / FDA 引导 / Widget / Shortcuts 等）全部继承。v1.5 新增 6 个模块作为 App Store 上架硬门槛。详细 roadmap 见 `docs/superpowers/specs/2026-08-03-kwise-cmm-parity-roadmap.md`。

### 3.0 命名与定位

- **产品名**：kWise（CN: 智洁）
- **bundle ID**：`app.kraftly.sclean`（不变，保留 App Store 历史）
- **Slogan**：Smarter care for your Mac / 智能清理，焕然如新
- **对标**：CleanMyMac X
- **产品矩阵**：kWise 主 + kWatch / kSift / kUninstall 独立 App（双层矩阵，B1a）

### 3.1 一句话定位
让 Mac 回到"最佳状态"——一键智能清理 + 启动项 + 隐私 + 磁盘健康，对标 CleanMyMac X 的全能 Mac 管家。

### 3.2 目标用户
- **主**：MacBook 256GB/512GB 用户，频繁弹"磁盘已满"告警
- **次**：创意工作者（视频/摄影），需要定期清理临时文件
- **不服务**：开发者（→kDupe）、极客玩家（→kDupe）、系统监控需求者（→kWatch）

### 3.3 核心差异化
| 维度 | CleanMyMac X | DaisyDisk | kWise 差异点 |
|---|---|---|---|
| 主界面 | 模块拼盘 | 磁盘可视化 | **3D 磁盘星系图（Metal 渲染）** |
| 智能分类 | 规则匹配 | 无 | **CoreML 本地 AI 自动分类** |
| 扫描速度 | 中等 | 慢 | **Apple Silicon 神经引擎加速 perceptual hash** |
| 隐私 | 上报统计 | 本地 | **零网络上报，所有计算在本地** |
| 一键清理 | ✅ | ❌ | ✅ + Interactive Widget 一键清理（macOS 14+） |
| App Store 集成 | ✅ | ❌ | ✅ + Shortcuts 集成 |

### 3.4 v1.5 完整功能（首发即包含全部）

> v1 已完成模块（标记为 ✅）全部继承；v1.5 新增模块（标记为 🆕）为 App Store 上架硬门槛。

| 模块 | v1.5 内容 | 状态 |
|---|---|---|
| 4 级扫描树 | 实时合成 + ETA + 应用级粒度（150+ App 规则） | ✅ 继承 v1 |
| 智能扫描引擎 | 系统缓存 / 应用残留 / 大文件 / 重复文件 | ✅ 继承 v1 |
| CoreML AI 分类 | 本地 embedding 分组（图片/视频/文档/缓存/开发文件） | ✅ 继承 v1 |
| 一键清理 | 移入废纸篓 + 30 天清理历史可回滚 | ✅ 继承 v1 |
| 🆕 **Smart Care** | 一键智能清理（扫描→展示→一键确认清理） | 🔴 v1.5 新增 |
| 🆕 **启动项管理** | login items / launch agents / daemons | 🔴 v1.5 新增 |
| 🆕 **隐私清理** | 浏览器历史 / 应用权限概览 | 🔴 v1.5 新增 |
| 🆕 **磁盘健康卡片** | S.M.A.R.T. 状态 + 卷诊断 | 🔴 v1.5 新增 |
| 🆕 **应用卸载（基础）** | CMM X parity 级别 | 🔴 v1.5 新增 |
| 🆕 **文件粉碎（基础）** | CMM X parity 级别 | 🔴 v1.5 新增 |
| FDA 引导 | 教育性 Full Disk Access 引导流程 | ✅ 继承 v1 |
| 菜单栏图标 | 显示已用空间 + 一键扫描入口 | ✅ 继承 v1 |
| 桌面 Widget | 基础版（13）+ Interactive 版（14+） | ✅ 继承 v1 |
| Shortcuts App Intents | 扫描 / 清理缓存 / 显示大文件 | ✅ 继承 v1 |
| Live Activities | macOS 14+，清理进度长任务显示 | ✅ 继承 v1 |
| Finder 扩展 | 右键"用 kWise 扫描" | ✅ 继承 v1 |
| Spotlight 集成 | 搜"Mac 空间"出现操作 | ✅ 继承 v1 |
| 本地化 | 英文 + 简体中文 + 日文 | ✅ 继承 v1 |

### 3.5 kWise 内部模块
```
kWise/
├── App/
│   ├── kWiseApp.swift                # @main
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

**强烈建议（非阻塞）：** 定时自动清理 / 3D 磁盘星系图 / CoreML 本地 AI 分类。

**功能范围待 grill：** UI 重做方案 / Smart Care 具体行为 / 启动项 UI 位置 / 隐私权限数据源 / 基础 vs 深度卸载切分线。

详细 spec：`docs/superpowers/specs/2026-08-03-kwise-cmm-parity-roadmap.md`。

---

## 4. Backlog（待设计）

### 4.1 kWatch（菜单栏监控）
- **主轴**：平台集成 + Widget + Live Activities
- **目标用户**：极客 / 设计师 / 视频创作者
- **定价**：Free + $7.99 Pro 买断（vs iStat Menus $11.99）
- **详细规格**：`docs/superpowers/specs/2026-07-26-kraftly-kwatch-design.md`
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
- **4 个永久 worktree**：`kWise` / `kWatch` / `kSift` / `kFresh`，每个独占一个 App 目录
  - 路径：`/Users/torsys/Documents/aicoding/<app>`（与主 worktree 同级）
  - 分支：`worktree-<app>-v1`（例如 `worktree-kwise-v1`）
  - 永久保留，禁止 `git worktree remove`
  - 边界严格：用 `scripts/commit-app.sh <app>` stage，跨 App 路径会被拒绝
- 开发分支：`feature/<app>-<feature>`、`fix/<app>-<bug>`（短期 feature 分支在对应 worktree 内使用）
- 提交信息：`feat(kWise): add 3D galaxy renderer`
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
- iStat Menus（菜单栏监控标杆，kWatch 灵感）
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

### kWatch v1 — Spec 定稿 ✅
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

### Backlog（待设计）
- [ ] kDupe 设计 — 重复/大文件
- [ ] kUninstall 设计 — 应用卸载

> ⚠️ **现阶段不要写实现代码**。所有设计待汇总到 spec 文档并通过后，再通过 writing-plans 技能拆解为可执行任务。

---

最后更新：2026-07-25（kSpaceClean 设计定稿）