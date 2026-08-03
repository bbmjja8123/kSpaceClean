# kWise v1.5 CMM Parity Roadmap — Spec

> **Status:** LOCKED 2026-08-03 (grill-me session). Cross-references: `CLAUDE.md` §3.10.

**Goal:** Ship kWise as a CleanMyMac X-grade all-in-one Mac care app to the App Store, while keeping kWatch / kSift / kUninstall as independent Power-User specialist apps.

## 1. Naming & positioning

| Field | Value |
|---|---|
| Display name | **kWise** (CN: 智洁) |
| Previous name | kSpaceClean (archived — kept in git history) |
| Bundle ID | `app.kraftly.sclean` (UNCHANGED — preserves App Store continuity) |
| Brand | Kraftly (parent brand, k-prefix family) |
| Tagline (EN) | "Smarter care for your Mac" |
| Tagline (CN) | "智能清理，焕然如新" |

**Rationale:** kWise 对位 CleanMyMac X 的"专业 + 智能"高端感；CN "智洁"自然；隐喻"智能地清理"。Bundle ID 不变以保留 App Store 历史评分、评论、内购项目。

## 2. Product matrix (LOCKED B1a — 双层矩阵)

### 2.1 kWise — 主入口（CMM X 对标）

**模块：**
- Smart Care（一键智能清理）
- 清理（应用缓存 / 大文件 / 旧文件）
- 启动项管理
- 隐私清理（浏览器历史 / 应用权限概览）
- 磁盘健康卡片（S.M.A.R.T. + 卷状态）
- 应用卸载（基础版）
- 文件粉碎（基础版）

**定价：** Free Trial 7 天 → **$19.99/年**（订阅，无买断——继承 kSpaceClean v1 定价策略）

### 2.2 kWatch — 独立 App（实时监控）

- 实时菜单栏（CPU / RAM / 网络 / 磁盘 I/O / 电池）
- Widget（基础 + Interactive）
- Live Activities（macOS 14+）
- 系统健康仪表盘

### 2.3 kSift — 独立 App（深度文件工具）

- 深度重复查找（perceptual hash + AI 分组）
- 大文件分析（可视化）
- 高级文件粉碎（多 pass / DoD 标准）

### 2.4 kUninstall — 独立 App（深度应用管理）

- 深度应用卸载 + 残留扫描
- 多 App 批量卸载
- 卸载回滚（30 天历史）
- 启动项详细管理（vs kWise 的概览版）

**定价（3 款副 App）：** 继续按各自 spec 锁定的 $7.99-9.99 买断（详见各自 design spec）。

## 3. App Store 提交硬门槛（v1.5）

**⛔ kWise v1.5 必须完成全部 6 个模块才能提交 App Store：**

| # | 模块 | 状态 | 来源 |
|---|---|---|---|
| M1 | **Smart Care**（一键智能清理） | 🔴 待实现（本会话主轴） | 优先做 |
| M2 | **启动项管理** | 🔴 待实现 | 优先做 |
| M3 | **隐私清理**（浏览器历史 + 应用权限概览） | 🔴 待实现 | 优先做 |
| M4 | **磁盘健康卡片**（S.M.A.R.T. + 卷状态） | 🔴 待实现 | 优先做 |
| M5 | **应用卸载（基础版）** | 🟡 预留位 | 由 kUninstall 集成 |
| M6 | **文件粉碎（基础版）** | 🟡 预留位 | 由 kSift 集成 |

**v1.5 强烈建议（非阻塞）：**

| # | 模块 | 来源 |
|---|---|---|
| O1 | 定时自动清理 | 新增 |
| O2 | 3D 磁盘星系图（Metal） | kSpaceClean v1 差异化路线图 |
| O3 | CoreML 本地 AI 分类 | kSpaceClean v1 差异化路线图 |
| O4 | Apple Design Awards 申报材料 | 上架后 |

**v1.5 可选：**

| # | 模块 | 来源 |
|---|---|---|
| F1 | 实时菜单栏空间监控 | kWatch 整合（不重复造轮子） |

## 4. 阶段划分

### 阶段 A：清理引擎 + 4 级树（已完成 2026-07-25，commit 109fcb5）

- 4 级扫描树
- 应用级缓存规则（v1: 108 条）
- CoreData 历史 / 30 天回滚

### 阶段 A.5：扫描 UX v2（已完成 2026-08-02，commit f1976d2）

- A1: 实时扫描进度合成器（per-file deltas + 节流快照）
- A2: 进度环 + ETA 数学（ScanProgressMath）
- B1: 未匹配文件夹 → 伪应用行（pseudo-app split）
- B2: 伪应用豁免小文件折叠
- B3: 应用规则库扩展 108 → 150 条

### 阶段 A.6：本会话（2026-08-03）

- 用户反馈收集 + 痛点调研（已完成）
- 产品命名锁定 kWise（已完成）
- 产品矩阵锁定 B1a（已完成）
- 本 spec 文档（已完成）

### 阶段 B：CMM Parity 主轴（未来 4-6 周）

- M1: Smart Care（一键智能清理）
- M2: 启动项管理
- M3: 隐私清理
- M4: 磁盘健康卡片
- M5/M6: 基础卸载/粉碎（从 kUninstall/kSift 集成）
- 配套 UI 大改：消除"右上角四个控件与左侧重复"问题；优化"扫描中文字闪烁"

### 阶段 C：差异化 + 长期（v2+）

- O2/O3: 3D 磁盘星系图 + CoreML AI 分类
- O1: 定时自动清理
- App Store 提交 + 苹果编辑推荐申请

## 5. 三大用户痛点（来自 grill-me 调研）

### 痛点 1：扫描过程"带文字部分闪烁得厉害" + "进度环没动" + "没 ETA"
**已部分解决：** A1 + A2 提供了实时进度、ETA、当前文件路径。但用户仍感到"闪烁厉害"——这是 UI 层问题（不是引擎层），需要本会话主轴 UI 改造继续打磨。

### 痛点 2：整体布局差——"右上角四个控件与左侧四个控件作用一样"、"右边的预览/结果/建议不大适用"
**未解决：** UI 整体需要重做。需要 grep 出当前布局缺陷，对标 CMM X 模块化布局（DaisyDisk 单屏可视化作为"扫描中"页参考）。

### 痛点 3：功能范围太少
**解决路径：** 见 §3 硬门槛。Smart Care + 启动项 + 隐私 + 磁盘健康是 CMM X 用户评价中点名的核心缺失项。

## 6. 风险与约束

| 风险 | 影响 | 缓解 |
|---|---|---|
| TCC Full Disk Access 未授予 | 扫描/卸载/隐私清理全部失效 | FDA 引导流程（CLAUDE.md §3 v1 已规划） |
| macOS sandbox 内多 App 协作 | kWise 调用 kSift 粉碎能力受限 | 通过 XPC + App Group 共享；或各自独立实现 |
| 启动项管理可能误操作 | 用户误关关键服务导致系统异常 | 高风险操作需二次确认 + 操作历史可回滚 |
| 磁盘健康 S.M.A.R.T. 在 Apple Silicon 上的可用性 | 可能读不到数据 | 优雅降级——读不到时显示"不可用"卡片，不报错 |
| Bundle ID 不可变 | 改名无法迁移老用户评价 | 保留 `app.kraftly.sclean`，仅改展示名 |

## 7. 已锁定的设计决策（来自 grill-me 2026-08-03）

| ID | 决策 | 决策日 |
|---|---|---|
| D1 | 产品名 kSpaceClean → **kWise** | 2026-08-03 |
| D2 | bundle ID 保持 `app.kraftly.sclean` 不变 | 2026-08-03 |
| D3 | CN 译名 "智洁" | 2026-08-03 |
| D4 | 对标 CMM X | 2026-08-03 |
| D5 | 产品矩阵 = 双层（kWise 主 + kWatch/kSift/kUninstall 独立） | 2026-08-03 |
| D6 | kWise 含基础卸载/粉碎（CMM parity） | 2026-08-03 |
| D7 | App Store 上架硬门槛 = M1-M6 全部完成 | 2026-08-03 |

## 8. 待 grill 的下一批决策（本会话之后）

1. UI 重做方案：CMM X 模块化布局 vs DaisyDisk 单屏布局 vs BuhoCleaner sidebar 布局
2. Smart Care 的"一键"具体行为：扫描 → 展示 → 一键确认清理（3 步），还是直接扫描 → 直接清理（1 步）
3. 启动项管理 UI：是单独一个 Tab 还是放在 Smart Care 里
4. 隐私清理的"应用权限概览"数据源：TCC.db 读取 + 用户授权
5. 基础卸载 vs 深度卸载的功能切分线

---

**Owner:** torsysmeng（solo indie dev）
**Last updated:** 2026-08-03
**Next step:** UI 重做方案 grill → writing-plans 拆解阶段 B 任务