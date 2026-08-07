# kUninstall 产品交互设计 — 完整对话记录

**项目**: Kraftly Mac App Suite
**App**: kUninstall（应用卸载）
**日期**: 2026-07-26
**参与**: 独立开发者（用户） + Claude（AI 设计助手）
**状态**: v1 设计已定稿，待 writing-plans 拆解实施计划

---

## 会话概览

本次会话跨越 2 次上下文续接，完整覆盖了 kUninstall 从 0 到 1 的交互式产品设计全过程：

1. **Phase 1 — 探索与澄清**：从 Backlog 中"待设计"状态起步，经过 4 轮问答锁定产品方向
2. **Phase 2 — 商业模式设计**：反复迭代免费/付费分界，确定卸载免费+Pro 买断模型
3. **Phase 3 — 全量技术设计**：架构、检测原理、Sandbox 策略、类图、数据层
4. **Phase 4 — UX 交互设计**：信息架构、页面流程、操作流程图、时序图
5. **Phase 5 — 补充完善**：安全保护、Sandbox 明细、前置检查流程、备份位置修正
6. **Phase 6 — 自审与修复**：Spec 文档自审、3 处问题修复

---

## Phase 1: 探索与澄清

### 启动

**用户**: 类似 kSpaceClean 的流程，现在开始对 kUninstall 进行展开

**AI**: 首先检查了项目现状——kSpaceClean v1 已完成设计，CLAUDE.md 中 kUninstall 标注为"待设计"Backlog。发现一个关键待定问题，开始提问。

---

### Q1: 独立 App 还是合入 kSpaceClean？

**AI** 提出：

| 选项 | 优势 | 劣势 |
|---|---|---|
| **A: 独立 App** | 品牌矩阵更丰富、收入独立、功能可做深 | 多一个 App 要维护/推广 |
| **B: 并入 kSpaceClean V2** | 用户存量复用、一次安装提供更多价值 | 弱化品牌矩阵、kSpaceClean 定位变模糊 |

**用户反问**: 查看苹果上面，是否有这个类别的应用？多不多？什么定价

**AI** 进行大量 WebSearch + WebFetch 调研，覆盖：
- Mac App Store 卸载类 App 搜索结果（20-30 个）
- 主要竞品定价：AppCleaner（免费 $0）、Cleaner One Pro（$19.99/年）、CleanMyMac X（$39.95/年）、BuhoCleaner（$12-29/年）、Delete Apps（$4.99 买断）、Nektony App Cleaner（$19.99/年）
- 发现缺口：**纯卸载 + 漂亮 UI + App Store 合规 + Shortcuts/Widget 集成** 无人在做

**用户决策**: 独立，后续可以考虑把这几个综合合并为一个大套件，目前暂时保持 4 个 app 独立

**结论**: ✅ 独立 App

---

### Q2: 功能边界

**AI** 提出三个范围选项：

| 选项 | 范围 | 推荐度 |
|---|---|---|
| **A. 纯卸载工具** | 列 App → 选残留 → 删除 | 最窄，付费意愿低 |
| **B. 卸载 + 应用健康管理** | A + 启动项管理 + 体积可视化 + 残留检测 | ⭐ 推荐 |
| **C. 全生命周期管理** | B + 更新检测、评分查看、启动统计 | 过广，偏离主轴 |

**用户决策**: B

**结论**: ✅ 卸载 + 应用健康管理

---

### Q3: 杀手锏（差异化）

**AI** 提出四个差异化方向：

| 选项 | 核心卖点 | 落地形式 |
|---|---|---|
| **A. 平台集成** | 所有动作可通过 Shortcuts/Widget/Finder 右键/菜单栏触发 | 全平台化 |
| **B. 本地 AI 智能建议** | 学习使用习惯，预测"多久没用了、可以卸载了" | CoreML 周报 |
| **C. 应用体积可视化** | App Icon 拼贴的"应用星系" | 3D 星系变体 |
| **D. 一键深度清理** | 不只是删 App，清除所有系统指纹 | 彻底卸载 |

**AI 推荐**: A + D 组合（平台集成 + 深度清理）

**用户决策**: 可以，先 AD

**结论**: ✅ 差异化 = 平台集成 + 深度清理

---

## Phase 2: 商业模式设计

### Q4: 定价模型

**AI** 最初推荐 $19.99/年 订阅（与 kSpaceClean 一致，为未来套件合并铺路）。

**用户质疑**: 是不是可以先免费试用，然后一次性买断？这种做订阅应该不好

**AI** 重新思考：卸载是低频动作，订阅心理负担重。提出折中方案 C（$14.99 买断 kUninstall 单独 + $39.99/年 全 Kraftly 套件订阅）。

**用户进一步追问**: 买断是不是 4.99 就行了？这块的普遍定价是多少？需要给免费试用吗？

**AI** 进行第二轮定价调研，覆盖 Mac App Store 卸类定价分布：

| 价位 | 代表 App |
|---|---|
| $0 免费 | AppCleaner（但不在 App Store） |
| $0.99-$4.99 | Delete Apps 等低价小工具 |
| $5.99-$9.99 | TrashMe 系 — **主流价位** |
| $14.99-$19.99 | Nektony、TrashMe 3 — 溢价区 |
| $19.99+/年 | CleanMyMac、Cleaner One Pro |

**AI 推荐**: $9.99 一次性买断 + 免费层/Pro 升级。免费层能卸载+扫残留，Pro 解锁深度清理+启动项+AI+批量。

---

### Q5: 免费/付费分界（关键迭代）

**第一版分界（AI 初始方案）**:

| 功能 | 免费 | 付费 |
|---|---|---|
| 卸载 App + 扫残留 | ✅ | ✅ |
| 应用列表 + 体积查看 | ✅ | ✅ |
| AI 分析 | ✅ | ✅ |
| 深度清理 + 启动项管理 | ❌ | ✅ |
| 批量操作 | ❌ | ✅ |

**用户反馈**: 免费的功能，是不是太多了，付费的是不是不足？

**AI 调整方案**: 改为"免费看，付费干"模型——浏览和扫描免费，**真正卸载需要付费**。

**用户再次反馈**: 免费部分，不让卸载感觉也不行，你还有什么好注意？可以多看看竞品

**AI** 深入研究竞品分界模式（AppCleaner 免费、Nektony 免费可卸载 Pro 解锁扩展、TrashMe 3 纯付费），发现关键结论：**成功的竞品没有限制卸载本身**。

**最终分界（定稿）**:

| 功能 | 免费 | Pro ($9.99) |
|---|---|---|
| 卸载 App + 基础残留 | ✅ **核心免费** | ✅ |
| 应用列表 + 大小查看 | ✅ | ✅ |
| 撤销回滚 | ✅ | ✅ |
| 深度系统清理 | ❌ | ✅ |
| 启动项管理 | ❌ | ✅ |
| 批量卸载 | ❌ | ✅ |
| 应用体积可视化 | ❌ | ✅ |
| AI "很少用"分析 | ❌ | ✅ |
| Widget | ❌ | ✅ |
| Shortcuts | ❌ | ✅ |

**用户确认**: 是否包括了扩展清理？在付费里面？

**AI**: 对。免费只扫 App 自身的 ~/Library/ 标准位置；付费包含系统级残留（/Library、LaunchDaemons、PreferencePanes、Extension 注册、XPC Service、多用户残留）。

**结论**: ✅ 卸载免费 + 扩展清理/启动项/可视化/集成付费 = **$9.99 Pro 一次性买断**

---

## Phase 3: 全量技术设计

### 3.1 架构方向确认

**AI** 提出 3 个架构方案：

| 方案 | 特点 |
|---|---|
| **A. Clean Utility（推荐）** | 点击扫描→列出 App→卸载/深度清理，稳快，Apple 编辑喜欢 |
| **B. App 星系图** | 延续 kSpaceClean 3D 视觉，App Icon 交互式可视化 |
| **C. 智能监控** | 菜单栏常驻 + Widget，自动推送不常用 App |

**AI 推荐 A**：卸载是目的驱动行为，快稳顺手比炫酷更重要。

**用户确认**: 继续

**结论**: ✅ Clean Utility 架构

---

### 3.2 检测原理与 Sandbox 策略

**AI** 详细展开检测原理：

**FDA 依赖矩阵**（共 10 类检测项，每个标注 API、是否需要 FDA、无 FDA 时的降级行为）：

| 检测项 | 需要 FDA | 无 FDA 降级 |
|---|---|---|
| 获取 App 列表 | 部分 | LaunchServices 缓存列表 |
| App 图标/元数据 | ❌ | 可用 |
| App 占用大小 | ✅ | 不可用 |
| ~/Library 残留 | ✅ | 不可用 |
| /Library 系统级残留 | ✅ | 不可用 |
| 移入废纸篓 | ❌ | 可用（仅 App 本体） |
| LaunchAgents 操作 | ✅ | 不可用 |
| Login Items | ✅ | 不可用 |

**FDA 状态机**:
```
[app启动] → 检查 ~/Library/ 可读性
  → 不可读 → 基础模式（列 App+基础卸载+FDA 引导）
  → 可读 → 全功能模式（残留扫描+深度清理+启动项管理）
```

**残留文件推理算法**: Bundle ID 路径模板匹配，每条路径带置信度（0.0~1.0），高置信度默认选中。

**用户确认**: 可以，下一步

**结论**: ✅ 检测策略确认

---

### 3.3 架构模式 + 模块划分

**Clean Architecture 五层**:
1. UI Layer（SwiftUI）
2. Presentation Layer（ViewModels）
3. Domain Layer（Use Cases / Models）
4. Data Layer（Services / Repositories）
5. System Interface（低级 API）

**完整模块结构**（~30 个文件，5 大 Features + 3 个 Core 模块 + 平台集成）：

```
kUninstall/
├── App/               # @main, RootView, AppCoordinator
├── Features/
│   ├── AppList/       # 应用列表主页
│   ├── Detail/        # 应用详情 + 卸载
│   ├── DeepClean/     # 深度清理（Pro）
│   ├── StartupItems/  # 启动项管理（Pro）
│   └── Onboarding/    # FDA 引导
├── Core/
│   ├── Detect/        # InstalledApp, AppCatalogService, ResidueDetector
│   ├── Clean/         # TrashMover, DeepCleanEngine
│   └── Startup/       # StartupItemManager
├── Intents/           # Shortcuts (3 Actions)
├── Widgets/           # 2 Widgets
├── FinderExtension/
├── Store/             # IAP 内购
├── MenuBar/
└── Resources/
```

**核心类图**（7 个核心类 + 枚举）:
- `InstalledApp` — App 模型（url, name, bundleID, size, source, residues）
- `ResidueFile` — 残留文件模型（url, type, confidence, size, isSystemLevel）
- `AppCatalogService (actor)` — 扫描已安装 App
- `ResidueDetector (actor)` — 推理残留文件
- `TrashMover (actor)` — 移入废纸篓 + 备份 + 回滚
- `DeepCleanEngine (actor, Pro)` — 深度清理
- `StartupItemManager (actor, Pro)` — 启动项管理
- `UninstallHistoryRepository` — Core Data 历史记录

**并发策略**: Service 层使用 `actor` 隔离状态，ViewModel 使用 `@MainActor`，扫描使用 `TaskGroup` 并行化。

**用户确认**: 可以

---

### 3.4 数据层设计

**Core Data 模型**（2 个 Entity）:
- `UninstallHistory`: id, appName, bundleID, appPath, appSize, residueCount, uninstalledAt, isRestored, backupPath
- `AppAnalysis`: bundleID (unique), displayName, lastUsedDate, firstDetectedDate, usedCount, suggestedAction

**存储策略**（6 类数据各指定存储方式）:
- App 列表：不持久化，实时构建
- 卸载历史：Core Data（30 天保留）
- AI 分析：Core Data（累积）
- 用户偏好：UserDefaults
- 付费凭证：StoreManager + Keychain
- FDA 书签：Security-Scoped Bookmark

**备份策略**:
```
~/Library/Application Support/app.kraftly.kuninstall/Backups/<bundleID>/
  30 天后自动删除，恢复后立即删除
```

**回滚机制**: 废纸篓 → 原位 + 备份 → 原位，写入 Core Data 记录

---

## Phase 4: UX 交互设计

### 信息架构

全 App 共 8 个页面层级：

```
App Launch
├─ [首次] FDA 引导（Welcome → 系统设置引导 → 跳过）
├─ [每次] 主页 AppList（搜索+分类筛选+排序+已卸载折叠组）
├─ App Detail（Hero+大小概况+残留列表+AI分析+卸载按钮）
├─ 卸载确认 Sheet（5 步安全检查→确认→执行）
├─ [Pro] 深度清理视图
├─ [Pro] 启动项管理视图
├─ 卸载历史（30 天可回滚）
└─ 设置（付费+FDA+备份+关于）
```

### 关键交互细节

**卸载撤销 Toast**:
```
┌──────────────────────────────────────────────┐
│  ✅ 已卸载 Xcode (1.2 GB)         [撤销]  5s │
└──────────────────────────────────────────────┘
```
10 秒倒计时自动消失，点击撤销→自动回滚。

**卸载确认 Sheet**:
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

### 视觉设计原则

| 维度 | 原则 |
|---|---|
| 品牌色 | 冷色调（深蓝/蓝灰渐变），与 kSpaceClean 统一 |
| 排版 | SF Pro，大标题+清晰层级，留白充足 |
| App Icon | 提取系统 icon，大尺寸圆角，柔和背景模糊 |
| 动效 | 卸载流畅过渡、骨架屏加载、触感反馈 |
| 付费锁 | 模糊透明效果+"解锁 Pro"按钮 ≤2 处/页 |

### 平台集成入口

| 入口 | 付费 | 功能 |
|---|---|---|
| 菜单栏 | 免费 | 快速搜索 + 卸载最近 App |
| Widget | Pro | "磁盘占用大户 Top 4" |
| Shortcuts | Pro | 3 Action：卸载 / 扫描残留 / 深度清理 |
| Finder 右键 | 免费 | "用 kUninstall 深度卸载" |
| Spotlight | 免费 | 搜"卸载 X" → kUninstall 动作 |

---

## Phase 5: 补充完善（Review 后修复）

**用户要求**: 补充操作流程图、时序图

**AI** 补充：
- **总用户流图**：Launch → FDA Guide/自动扫描 → 主界面 → 各页面分支
- **卸载流程图**：5 步安全检查（安全→运行→来源→残留→确认）→ TrashMover → 撤销回滚
- **App 检测时序图**：User → UI → AppCatalogService → ResidueDetector → System
- **卸载时序图**：User → UI → DetailVM → TrashMover → System（含撤销回滚）
- **深度清理时序图**：User → UI → DeepCleanVM → DeepCleanEngine → System

**用户要求**: 从头到尾 Review 一遍

**AI 全面 Review** 发现 4 个缺失项：

### 1. 卸载安全保护

新增不可卸载 App 规则：
- `/System/*` → 受保护
- 系统保护列表（Finder, Terminal, SystemPreferences, Dock 等）
- 通配匹配（`com.apple.CoreServices.*`, `com.apple.launchd.*`）

### 2. Sandbox 策略明细

Entitlements 完整定义，含 `com.apple.security.temporary-exception`。无 FDA 各功能降级行为明确。

### 3. 卸载前置检查流程（完整 5 步）

```
tap "卸载" →
  Step 1: 安全检查（isProtected?）
  Step 2: 运行检查（isRunning? → terminate）
  Step 3: 来源确认（MAS→可重下载，direct→确认有备份）
  Step 4: 残留预扫描（显示残留数+大小）
  Step 5: 确认 Sheet → TrashMover.moveToTrash()
    → App 废纸篓 → 残留备份 → Core Data → Toast
```

### 4. 备份位置修正

**发现问题**: 原方案使用 `$TMPDIR` 作为备份根目录，但 `$TMPDIR` 可能被系统随时清除。

**修复**: 改为 `~/Library/Application Support/app.kraftly.kuninstall/Backups/<bundleID>/`

---

## Phase 6: Spec 自审与修复

### 自审发现 3 个问题

| 问题 | 原文 | 修复后 |
|---|---|---|
| **FDA 书签路径模糊** | `./fda_bookmark` | `~/Library/Application Support/app.kraftly.kuninstall/Bookmarks/` |
| **通配符匹配未说明** | `com.apple.CoreServices.*`（伪通配符） | 改用 `hasPrefix` 说明 |
| **entitlement 审核风险** | 未说明 `temporary-exception` 需要提交用途 | 补充：App Store 审核需提交视频演示 |

### 当前会话（自审后）

**用户**: 继续 → 把本次 session 的所有交互对话，保存到 kUninstall产品交互设计.md

---

## 最终产出

### 设计规格文档

`docs/superpowers/specs/2026-07-26-kraftly-kuninstall-design.md`

完整 16 章节覆盖：

| 章节 | 内容 |
|---|---|
| 1. 概述 | 定位、目标用户、差异化、竞品对比表 |
| 2. 工程组织 | Workspace 位置、30+ 文件目录结构 |
| 3. 检测原理与 Sandbox 策略 | Entitlements、FDA 状态机、残留推理算法、置信度模型 |
| 4. 架构模式+模块划分 | Clean Architecture 五层、7 个核心类图、并发策略 |
| 5. 数据层设计 | Core Data 模型、存储策略、备份策略、回滚机制 |
| 6. UX 交互设计 | 信息架构、关键交互细节（Toast/Sheet）、视觉原则、平台集成 |
| 7. 操作流程图 | 总用户流、5 步卸载流程 |
| 8. 时序图 | App 检测、卸载（含撤销）、深度清理 3 张时序图 |
| 9. 卸载安全保护 | 不可卸载规则、系统保护列表、运行中 App 处理 |
| 10. App 来源识别 | system/appleBuiltIn/mas/userInstalled/unknown 分类逻辑 |
| 11. 定价与商业模型 | Free + $9.99 Pro 一次性买断，4 地区定价 |
| 12. 测试策略 | 6 层测试 + 沙箱测试矩阵（7 场景） |
| 13. 上线时间线 | 6 阶段 14 周 W1-W14 |
| 14. 无障碍 | VoiceOver、动态字体、键盘导航 |
| 15. 隐私与合规 | 零网络、本地计算、Data Not Collected |
| 16. 实施计划过渡 | 下一步 writing-plans |

### 关键设计决策日志

| # | 决策 | 方案 | 备选方案 | 选定原因 |
|---|---|---|---|---|
| 1 | App 独立性 | 独立 App | 并入 kSpaceClean | 品牌矩阵+收入独立，未来可合并 |
| 2 | 功能范围 | 卸载 + 应用健康管理 | 纯卸载/全生命周期 | 与 kSpaceClean 互补，高频刚需 |
| 3 | 差异化 | 平台集成 + 深度清理 | AI/可视化 | 不可替代的价值点 |
| 4 | 商业模式 | Free + $9.99 Pro 买断 | 订阅/$4.99 低价 | 低频动作不适合订阅，品质感要求合理定价 |
| 5 | 免费/付费分界 | 卸载免费，健康管理付费 | 免费看付费干 | 竞品验证：限制卸载会赶走用户 |
| 6 | 架构 | Clean Utility | 可视化/智能监控 | 卸载是目的驱动，快稳比炫酷重要 |
| 7 | 残留算法 | Bundle ID 路径模板匹配+置信度 | 纯规则匹配 | 减少误判，UI 展示可信度 |
| 8 | 备份位置 | ~/Library/Application Support/ | $TMPDIR | $TMPDIR 可能被系统清除 |
| 9 | iOS 最低版本 | macOS 13 | 14/15 | 用户本地机器版本 |

---

*本文件由 AI 自动整理，完整记录了 kUninstall v1 产品设计的全部交互过程。*
