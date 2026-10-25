# Klaris — Mac App Store 版扫描范围契约（MasScanScope）

> P3 双渠道定稿。本文件是 **产品承诺**，不是实现备忘：任何改动必须同步
> 修改 `kWiseTests/ScanScopeContractTests.swift`（契约测试）与设置页 /
> Onboarding 的授权文案。

## 渠道模型

| | **Mac App Store 版**（target `kWise`） | **直营版**（target `KlarisDirect`，Developer ID） |
|---|---|---|
| 沙盒 | 开启（App Sandbox 强制） | 关闭（Hardened Runtime + 公证） |
| ScopeLevel | `containerOnly` → `homeGranted`（PowerScope 书签授权） | `fullAccess`（`DirectScopeProvider`，无授权流程） |
| 授权交互 | 一次性 NSOpenPanel 选主目录 → security-scoped bookmark 持久化 | 无（Full Disk Access 语义由系统 TCC 自管） |
| 付费 | StoreKit 非消耗买断 `app.kraftly.klaris.buyout` | 无内购；买断墙引导去 MAS 购买 |

## MAS 版：三层可读性（唯一事实来源 = `ScopeCapability.canRead`）

### 1. 始终可读（无需授权）
- 应用容器本身；
- `ScopeProbe` 当次探测确认可读的公共目录（如 `~/Library/Caches`、
  `~/Library/Logs`、`/private/var/folders`、`/System/Library/Caches`）；
- `/Applications` 清单（AppCatalogCore；沙盒下按 MAS 收据诚实分级）；
- 用户通过 open panel 显式授予的任意目录（含拖入 `.app`）。

### 2. 需主目录授权（`homeGranted` 后可读）
- `~/Library` 深处：Application Support、Containers、Mail、Safari、
  Developer、MobileSync、Cookies、DiagnosticReports；
- 用户级 LaunchAgents/LaunchDaemons（启动项管理 M2）；
- 卸载残留（M5）位于授权根外的条目必须**过滤或禁用并给原因**，
  不得计入可清理体积。

### 3. MAS 版永远不可得（→ 诚实跳过，不假装已扫）
- 其他用户的主目录、`/Library` 系统级缓存、`/private/var/log` 作为
  扫描根 —— ScanOrchestrator 将其归入 `restrictedPaths` 并原样上画布
  （"已跳过"区域），**绝不**计入已扫描体积，也不归因为"干净"。

## 诚实性红线（审核与口碑）

1. 空扫描 ≠ 干净 Mac：`containerOnly` 时启动扫描 → 授权引导态
   （`needsFullDiskAccess`），不渲染"无垃圾"结果。
2. 每张组卡可追溯扫描覆盖：受限类目必须可见地落在跳过区，不得静默消失。
3. 直营版永不出现在 MAS 渠道文案里提"授权"；MAS 渠道文案不提
   "完整磁盘访问"。FDA 一词在 MAS 版 UI 中禁止出现（PowerScope 语义
   已完全替代）。
4. 直营版买断墙不得渲染无效的购买按钮（无 StoreKit 内购）。
