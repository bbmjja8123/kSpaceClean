# kSpaceClean v2 — 扫描与清理综合设计 Spec

> **状态**：设计中（基于 Lemon 源码 + 5 个头部竞品研究）
> **创建日期**：2026-07-27
> **目标**：将扫描与清理功能提升到 **Lemon 级别深度** + 融合 5 个头部 Mac 清理 App 的优秀模式

---

## 0. 执行摘要

### 0.1 问题陈述

当前 kSpaceClean v1 编译通过，但用户反馈**质量仍远低于预期**：

- 扫描结果展示过于简陋，缺少 Lemon 的核心 4 级树形控件
- 缺少级联 checkbox 与推荐/谨慎/危险标签系统
- 缺少警告项（运行中应用、不可逆操作）
- 整体交互细节与 Lemon 差距大

### 0.2 目标

复刻 Lemon 全部扫描/清理功能 + 融合竞品优点，达到 **行业头部质量**。

### 0.3 核心设计决策（基于研究）

| 维度 | 来源 | 决策 |
|---|---|---|
| 树形结构 | Lemon 源码 | **4 级树**：Category → SubCategory → Action → Result |
| 树控件 | Lemon 源码 | NSOutlineView 风格 + SwiftUI `List` + 自定义 `OutlineGroup` |
| 级联 Checkbox | Lemon 源码 + 改进 | **3 态（On/Off/Mixed）+ 推荐策略**（父级 On → 子级按 recommend 状态决定） |
| 风险标签 | Lemon + 改进 | **4 级**：推荐（绿）/ 可选（灰）/ 谨慎（橙）/ 危险（红）— 比 Lemon 多 1 级 |
| 警告项 | Lemon（修复）+ 改进 | **修复 Lemon 注释掉的 warning 主流程**，增加 toast 弹窗 + 强制终止确认 |
| 扫描进度 | CleanMyMac X | **阶段化进度**（System Junk → Photo Junk → ...）+ 圆环可视化 |
| 实时绘环 | DaisyDisk | **渐进式填充** + 当前路径实时显示 |
| 扫描完成 | CleanMyMac X | **总量 + 来源分类 + Safe to Remove / Review Required 分组** |
| 清理确认 | OnyX | **按风险分级确认**（低风险不弹 / 中风险解释 / 高风险强确认） |
| 卸模块 | AppCleaner | **单对象流**：拖入 App → 残留检测 → 选择 → 废纸篓 |
| 维护功能 | OnyX | **版本化能力矩阵** + 步骤级任务引擎 |
| 视觉风格 | DaisyDisk | **暗色背景 + 鲜艳强调色**（避免过家家均匀配色） |

---

## 1. Lemon 源码深度研究（核心发现）

### 1.1 树形控件真实结构

Lemon 用 **NSOutlineView**（不是 NSTableView 模拟），4 级可变深度树：

```
Category（系统垃圾/应用垃圾/上网垃圾）
└── SubCategory（某种垃圾或某个 App）
    ├── [可选] Action（缓存/日志/历史归档/微信图片/视频等）
    │   └── Result（具体文件或结果分组）
    │       └── Result...（可继续嵌套）
    └── Result（当 SubCategory 不显示 Action 时直接挂 Result）
        └── Result...（可继续嵌套）
```

关键属性：
- `SubCategory.showAction` 决定是否插入 Action 层
- `Result` 自身可递归包含 `Result`（用于"应用 → 语言"等不固定结构）
- 1 级 Category 默认自动展开

### 1.2 Checkbox 级联算法（核心）

**向下传播**（`QMBaseItem.setState:`）：

```swift
func setState(_ newState: CheckState) {
    if state == .mixed { return }  // mixed 不向下传播

    state = newState

    if isSubCategory && showAction {
        if newState == .off {
            // 父级取消 → 全部 Action 取消
            actions.forEach { $0.setState(.off) }
        } else {
            // 父级勾选 → 按 recommend 策略选择
            actions.forEach {
                $0.setState($0.recommend ? .on : .off)
            }
        }
    } else {
        // 普通向下传播
        children.forEach { $0.setState(newState) }
    }
}
```

**关键产品策略**：父级 On 不会无条件选择所有子级——只自动选择 recommended 子级。

**向上聚合**（`refreshStateValue`）：

```swift
func refreshState() {
    let onCount = children.filter { $0.state == .on }.count
    let mixedCount = children.filter { $0.state == .mixed }.count

    if onCount == children.count {
        state = .on
    } else if onCount == 0 && mixedCount == 0 {
        state = .off
    } else {
        state = .mixed
    }
}
```

### 1.3 风险标签系统（实际只有 2 级）

Lemon 实际只有"建议清理"（recommend == YES）和"谨慎清理"（recommend == NO）：
- **建议清理**：深灰色 `0x515151`，默认勾选
- **谨慎清理**：橙红色 `0xE6704C`，默认不勾选

XML 中的 `recommend` 属性控制。

**我们升级到 4 级**（融合 BuhoCleaner 的三级 + 增加 Dangerous）：
- 🟢 **推荐（Recommended）**：可安全清理（recommend == YES）
- ⚪ **可选（Optional）**：默认不勾选，需用户决定
- 🟠 **谨慎（Caution）**：可能影响功能（recommend == NO）
- 🔴 **危险（Dangerous）**：不可逆或系统级

### 1.4 警告项机制（已注释，但架构完整）

Lemon 的 `QMWarnResultItem` 和 `canRemoveWarnItem` 完整存在：
- 检测被选中路径是否属于运行中应用
- 检查 BundleID、PID、冲突路径
- `canRemoveWarnItem` 尝试 `terminate` 应用
- **问题**：主清理路径已注释 warning 检查

**我们修复并强化**：
- Warning 检测集成到主清理流程（不像 Lemon）
- 检测后弹 toast 提示 + 二次确认
- 提供"跳过警告项" / "强制终止应用" 选项

### 1.5 Lemon 的问题（我们要避免）

1. ❌ 树接口不完全统一（Controller 有大量 `isKindOfClass:` 分支）
2. ❌ 状态逻辑依赖具体类型（`QMBaseItem` 直接引用子类）
3. ❌ `isCautious` 命名与实际语义不一致
4. ❌ 结果页无交互式筛选器
5. ❌ 排序能力有限（仅大小降序）
6. ❌ **Warning 主流程被注释**（重大缺陷）
7. ❌ Result 全选收集存在结构假设
8. ❌ 扫描线程直接写共享模型（数据竞争风险）
9. ❌ 0 字节强制记为 1000 字节（兼容逻辑）

---

## 2. 5 个竞品研究核心要点

### 2.1 CleanMyMac X

- **Smart Scan 流程**：单一入口 → 多阶段后台任务 → 阶段化进度 → 总量 + 来源分类 → Review Items
- **风险标签 5 级**：Safe to Remove / Usually Safe / Review Required / Potentially Unsafe / Never Auto-remove
- **Review Items 二次确认**：避免全自动删除 vs 用户手动逐文件的二选一
- **菜单栏轻量面板**：只显示状态 + 快捷入口，**不可在菜单栏执行不可逆操作**
- **优先级建议**：
  1. 阶段化扫描
  2. 默认安全 + 危险人工审查
  3. 按语义而非路径分组
  4. 删除前显示后果
  5. 结果数字具动效

### 2.2 DaisyDisk

- **核心交互**：双圈 Sunburst chart（父扇区 + 子扇区），角度 = 大小占比
- **黑魔法**：**渐进式绘环**（边扫边画，扫描变演出）
- **Collector 篮筐**：永远悬浮的"暂存区"，未直接删除；可拖回原扇区撤销
- **删除走系统 Trash**：不 syscall，把撤销责任外包给 Finder
- **删除前 sheet**：左边文件清单 + 右边操作摘要（"Move X items to Trash. This action cannot be undone in DaisyDisk."）
- **状态指示**：Default/Hover/Selected/In Collector/Drilled-into/System Locked 6 种状态
- **动画曲线**：Hover 240ms easeOutQuart / 钻入 500ms easeInOutSine / 扇区出现 300ms easeOutBack
- **配色**：近黑背景 + HSB 均匀分布 + 12 o'clock 锚定最大扇区
- **状态栏主动告警**：颜色随使用率（<70% 绿，70-90% 橙，>90% 红）

### 2.3 BuhoCleaner

- **导航结构**：侧边栏 + 模块图标 + 副标题描述（比 Lemon 顶部 tab bar 更现代）
- **三档安全标签**：🟢 安全 / 🟡 警告 / 🔴 危险（我们要扩展到 4 档）
- **启动项管理**：LaunchAgents/Daemons/LoginItems（Pro 付费内）— Lemon 没做，我们做
- **App 预览卡片式**：图标 + bundleID + 版本 + 上次使用日期
- **卸载撤销**：Toast + 30 天回收站可恢复
- **重复文件智能选择器**：保留"最早创建"/"位于 Downloads"/"最短路径"
- **2000+ 中文 App bundleID → 显示名映射表**（微信、QQ、钉钉、企业微信、网易云音乐、QQ 音乐、爱奇艺、腾讯视频、优酷、Bilibili、迅雷、百度网盘、WPS、有道词典、欧路词典、Typora、向日葵、ToDesk 等）

### 2.4 AppCleaner + OnyX

**AppCleaner 借鉴**：
- **单对象流**：拖入 App → 残留检测 → 选择 → 删除
- **大拖放目标** + 接收 App 后立即切换为对象结果页
- **自动预选高置信度残留** + 删除前允许逐项取消
- **主操作保持单一** + 完成后自动回到初始态
- **信任感设计**：免费、无账户、无常驻后台

**残留检测算法**（工程模型）：
- **主键**：Bundle ID（应用名只能辅助）
- **强匹配（+100 分）**：文件名精确匹配 Bundle ID / plist Label 匹配 / 主程序路径匹配
- **中匹配（+50 分）**：签名 Team ID / App Group entitlement / 标准化应用名
- **弱匹配**：只含常见产品名 / 同厂商目录（**不应自动选择**）
- **共享组件**：负分（-100）
- **系统保护路径**：直接排除

**OnyX 借鉴**：
- **维护清单**（版本化能力矩阵）：
  | 维护项 | 风险 | 推荐级别 |
  |---|---|---|
  | DNS 缓存刷新 | 低 | 常用 |
  | Launch Services 重建 | 中 | 故障修复 |
  | Spotlight 索引重建 | 中高 | 高级 |
  | 字体缓存重建 | 中 | 故障修复 |
  | Quick Look 缓存重建 | 中 | 常用 |
  | Finder/Dock 缓存刷新 | 中 | 高级 |
  | 系统/用户缓存清理 | 低 | 可选 |
  | 日志清理 | 低 | 可选 |
  | APFS 快照管理 | 高 | 专家 |
  | S.M.A.R.T. 检查 | 只读 | 推荐 |

- **任务生命周期**：Preflight → Plan → Authorize → Execute → Verify → Report
- **按风险分级确认**：低风险不弹 / 中风险解释影响 / 高风险强确认
- **步骤级反馈**：✓ 检查权限 / ✓ 停止相关服务 / ✓ 清除字体缓存 / ... 等待系统后台完成
- **错误分类**：不支持当前 macOS / 缺少 Full Disk Access / 管理员取消授权 / 目标文件被占用 / SIP 保护 / 部分成功
- **技术日志**：时间戳、Task ID、stdout/stderr、退出码、脱敏

---

## 3. 综合设计

### 3.1 扫描结果树形控件（核心）

#### 3.1.1 层级结构（继承 Lemon + 改进）

```
4-Level Tree
├── Level 1: Category（系统缓存、应用缓存、上网垃圾、邮件附件、iOS 备份、开发者垃圾）
│   ├── Level 2: SubCategory（某种垃圾类型 / 某个 App）
│   │   ├── Level 3: Action（缓存/日志/语言包/二进制/...）— 可选
│   │   │   └── Level 4: Result（具体文件 / 文件组）
│   │   │       └── Result...（可继续嵌套，分组用）
│   │   └── Result（无 Action 时直接挂）
│   └── ...
└── ...
```

#### 3.1.2 节点模型（统一协议 + 数据驱动）

**核心协议**：

```swift
/// 所有扫描树节点的统一协议
protocol ScanTreeNode: Identifiable, Hashable, Sendable {
    var id: UUID { get }
    var title: String { get }
    var tooltip: String? { get }
    var totalSize: Int64 { get }
    var selectedSize: Int64 { get }
    var state: CheckState { get set }
    var children: [any ScanTreeNode] { get }
    var riskLevel: RiskLevel { get }
    var isRecommended: Bool { get }
    var showAction: Bool { get }

    func setState(_ newState: CheckState)  // 向下传播
    func refreshState()                    // 向上聚合
    func collectSelected() -> [URL]        // 收集所有勾选 URL
}

/// 三态 checkbox
enum CheckState: Sendable {
    case off
    case on
    case mixed  // 部分选中，仅作为聚合结果，不向下传播
}

/// 风险等级（4 级，比 Lemon 多 1 级）
enum RiskLevel: Int, Comparable, Sendable {
    case recommended = 0  // 推荐：可安全清理
    case optional = 1     // 可选：默认不勾选，需用户决定
    case caution = 2      // 谨慎：可能影响功能
    case dangerous = 3    // 危险：不可逆或系统级

    var color: Color { ... }
    var iconName: String { ... }
    var label: String { ... }
}
```

**具体节点实现**：

```swift
final class ScanCategory: ScanTreeNode {  // Level 1
    let categoryID: String
    var subItems: [ScanSubCategory]
}

final class ScanSubCategory: ScanTreeNode {  // Level 2
    let subCategoryID: String
    let bundleID: String?
    let appName: String?
    var actions: [ScanAction]
    var directResults: [ScanResult]
    let showAction: Bool
}

final class ScanAction: ScanTreeNode {  // Level 3
    let actionID: String
    let actionType: ScanActionType
    var results: [ScanResult]
    let recommend: Bool
}

final class ScanResult: ScanTreeNode {  // Level 4（可嵌套）
    let url: URL
    let path: String
    let iconImage: NSImage?
    let fileSize: Int64
    let modificationDate: Date?
    let cleanType: CleanType
    let cautionID: String?
    var nestedResults: [ScanResult]  // 用于"应用 → 语言"等分组
}
```

#### 3.1.3 级联 Checkbox 算法（核心）

**向下传播（继承 Lemon + 改进）**：

```swift
extension ScanTreeNode {
    func setState(_ newState: CheckState) {
        guard state != newState else { return }
        state = newState

        // mixed 是聚合结果，不向下传播
        guard newState != .mixed else { return }

        // 应用 recommend 策略
        if let subCategory = self as? ScanSubCategory, subCategory.showAction {
            for action in subCategory.actions {
                if newState == .off {
                    action.setState(.off)
                } else {
                    // 父级 On → 按 recommend 自动选择
                    action.setState(action.recommend ? .on : .off)
                }
            }
        } else {
            // 普通向下传播
            for child in children {
                child.setState(newState)
            }
        }
    }

    func refreshState() {
        let childStates = children.map(\.state)
        let total = childStates.count
        guard total > 0 else {
            // 叶子节点，state 由用户设置
            return
        }
        let onCount = childStates.filter { $0 == .on }.count

        if onCount == total {
            state = .on
        } else if onCount == 0 {
            state = .off
        } else {
            state = .mixed
        }
    }
}
```

**关键产品规则**（来自 Lemon + 改进）：
1. 父级 On → 子级按 recommend 决定（推荐自动选，谨慎不自动选）
2. 父级 Off → 全部子级取消
3. 子级修改后，向上 `refreshState()` 形成 Mixed
4. 叶子 Result 直接接受用户状态

#### 3.1.4 风险标签显示

每个节点显示 `RiskLevel` 徽标：

| Level | 颜色 | Icon | Label | 默认状态 |
|---|---|---|---|---|
| Recommended | 🟢 `#34C759` | `checkmark.circle.fill` | "推荐" | ✅ On |
| Optional | ⚪ `#8E8E93` | `circle` | "可选" | ⬜ Off |
| Caution | 🟠 `#FF9500` | `exclamationmark.triangle.fill` | "谨慎" | ⬜ Off |
| Dangerous | 🔴 `#FF3B30` | `flame.fill` | "危险" | ⬜ Off |

**Cell 表现**（参考 Lemon CellView + 改进）：
- **Category Cell**：图标 + 标题 + 总大小 + 选中大小 + RiskLevel 徽标（如果非空）
- **SubCategory Cell**：标题 + 上次使用时间（atime） + "共 X，建议清理" / "共 X，谨慎清理" + RiskLevel 徽标
- **Action Cell**：actionType 图标 + "共 X，Y 清理" + RiskLevel 徽标
- **Result Cell**：文件图标 + 路径 + 文件大小 + Finder 定位按钮

#### 3.1.5 警告项检测（修复 Lemon + 强化）

**检测时机**：
1. 扫描完成后（建立 warnItem 集合）
2. 用户点击"清理"时（重新检查，因为用户可能启动了应用）
3. 清理过程中遇到（暂停 → 询问用户）

**检测内容**：

```swift
struct WarnItem: Identifiable, Sendable {
    let id: UUID
    let appName: String
    let bundleID: String
    let processID: Int32
    let conflictingPaths: [String]
    let totalSize: Int64
    var canTerminate: Bool
}
```

**UX 流程**：

1. 用户点击"清理"
2. CleanupEngine 调用 `detectWarnItems(selectedURLs)` → `[WarnItem]`
3. 如果 `warnItems.isEmpty` → 直接进入清理
4. 如果 `warnItems.count > 0` → 弹 toast/sheet：
   - "检测到 X 个运行中应用涉及您选择的清理项"
   - 列出每个 warnItem（appName + 冲突路径数 + 总大小）
   - 提供选项：
     - "**跳过这些项**"（推荐）
     - "**强制关闭应用并清理**"（高风险，需要再次确认）
     - "取消清理"

**API**：

```swift
public protocol CleanupEngine {
    func detectWarnItems(for paths: [String]) -> [WarnItem]
    func cleanup(
        urls: [URL],
        warnHandling: WarnHandling  // .skip / .terminate / .abort
    ) -> AsyncStream<CleanupProgress>
}

enum WarnHandling {
    case skip                  // 跳过警告项
    case terminate             // 强制 terminate 后清理
    case abort                 // 取消清理
}
```

### 3.2 扫描进度展示（融合 CleanMyMac + DaisyDisk）

#### 3.2.1 阶段化进度

```swift
struct ScanProgress: Sendable {
    var state: State
    var currentCategory: String?    // 当前扫描的 Category
    var currentPath: String?        // 当前扫描路径（DaisyDisk 风格）
    var completedCategories: Int
    var totalCategories: Int
    var totalBytes: Int64
    var rateBytesPerSec: Int64
}

enum State {
    case idle
    case scanning
    case completed
    case failed(String)
}
```

#### 3.2.2 UI 布局（参考 CleanMyMac X + DaisyDisk）

**主视图（Smart Scan / Galaxy 模式）**：
- 顶部：圆环扫描进度（DaisyDisk 渐进式填充 + CleanMyMac 中央百分比）
- 中部：当前扫描路径实时显示（`Scanning ~/Library/Caches/Google/Chrome/...`）
- 下部：阶段列表（✓ System Junk / ● Mail Attachments / ○ Photo Junk / ○ iOS Backups）

**Galaxy 模式**（kSpaceClean 差异化）：
- 3D 星球图，按 Category 分色
- 扫描完成的 Category 球体出现
- 边扫边画（参考 DaisyDisk）

### 3.3 清理确认（融合 OnyX + CleanMyMac）

**风险分级确认**：

| 风险等级 | 确认方式 | 默认焦点 |
|---|---|---|
| Recommended + Optional | 不弹，直接清理 | N/A |
| 包含 Caution | 单确认 sheet + 解释 | Cancel |
| 包含 Dangerous | 双确认 + 输入"DELETE" | Cancel |
| 永久删除（Empty Trash） | 三确认 + 高亮按钮 + 默认焦点 Cancel | Cancel |

**Sheet 内容**：
- 标题：清晰的动词描述（"Remove 47 cached files" 而非"Clean"）
- 数量 + 总大小
- 风险等级摘要（"Includes 2 items marked Caution"）
- 后果说明（"These files will be moved to Trash. The first launch after cleanup may take slightly longer."）
- 两个按钮：Cancel（默认）/ Confirm（危险操作用红色 + 加粗）

### 3.4 模块详细设计

#### 3.4.1 Smart Scan（统一入口）

**入口**：Galaxy 主视图 → 点击"开始扫描"
**流程**：
1. 调用 `ScanEngine.startScan()` → 返回 `AsyncStream<ScanProgress>`
2. UI 显示圆环进度 + 阶段列表 + 当前路径
3. 完成后跳转到 **Scan Results View**（树形展示）
4. 用户勾选/取消 → 点击"清理"
5. 警告检测 → 清理确认 → 执行

**包含 Category**（默认）：
- 系统缓存
- 应用缓存
- 上网垃圾
- 邮件附件
- iOS 备份
- 开发者垃圾
- 应用残留

#### 3.4.2 Large Files（继承 Lemon + 改进）

**入口**：独立 Tab "大文件"
**算法**：
1. Phase 1：Spotlight mdfind（已实现）
2. Phase 2：FileManager 回退（已实现）
3. 阈值：默认 50MB，可选 100MB / 500MB / 1GB
4. Age filter：默认 90 天以上
5. 排序：大小降序 / 修改时间 / 名称 / 路径
6. 筛选：按文件类型、按大小范围、仅显示 N 天以上

**展示**：扁平列表（非树形，Lemon 也用扁平）
- Checkbox + 图标 + 文件名 + 路径 + 大小 + 修改日期
- 全选 / 反选 / 排序按钮
- 底部 Summary Bar（总数 + 已选数 + 已选大小 + 清理按钮）

#### 3.4.3 Duplicates（继承 Lemon + 改进）

**入口**：独立 Tab "重复文件"
**算法**：两阶段（size → hash），已实现

**展示**：树形（Group → Files）
- Group Header：图标 + 文件名（共有） + 副本数 + 每文件大小 + 总浪费
- File Row：图标 + 路径 + 修改日期 + 大小
- 默认勾选：保留"最新修改"的一个，其他勾选
- "Smart Select"：基于规则（最早创建 / 位于 Downloads / 最短路径）

**筛选**：仅显示可节省 > 10MB 的组

#### 3.4.4 App Uninstall（融合 AppCleaner + Lemon）

**入口**：独立 Tab "应用卸载"
**流程**（AppCleaner 风格单对象流）：
1. 拖入 App / 选择 App（从 /Applications 或 ~/Applications）
2. AppUninstallScanner 检测残留（13 处 Library 路径 + 多 BundleID 变体）
3. 评分模型（Bundle ID 主键，+100/+50/-100）
4. 结果展示：
   - App 主体大小
   - 残留文件列表（按来源分组：Preferences / Caches / Application Support / Logs / Saved State / Containers / LaunchAgents / Cookies / WebKit）
   - 置信度标签（高/中/低）
   - 共享组件警告
5. 卸载确认 → 移入废纸篓

**清理后**：保留 30 天可恢复（基于废纸篓）

#### 3.4.5 Privacy（融合 CleanMyMac + Lemon）

**入口**：独立 Tab "隐私清理"
**类别**：
- 浏览器：Safari / Chrome / Firefox / Edge / Brave / Arc
  - 历史 / Cookie / 缓存 / LocalStorage / 登录数据 / 自动填充
- Quick Look 缓存
- Recent Items（最近的应用/文档/下载）
- Download History
- 系统日志

**展示**：分组列表（按浏览器）
**警告**：Cookie 清理前弹 toast 提示"将退出所有网站登录"

#### 3.4.6 Photo Cache（继承 Lemon）

**入口**：独立 Tab "照片清理"
**类别**：
- Photos App 缓存
- iPhoto 库
- iOS 备份
- Photo Stream 缓存

**特殊处理**：
- 识别已失效的缩略图
- 识别与当前资源不匹配的预览
- 不动原始照片（**Never Auto-remove**）
- 重复照片需单独 Review

#### 3.4.7 Maintenance（继承 OnyX）

**入口**：独立 Tab "维护"
**清单**（版本化能力矩阵）：

| 维护项 | 风险 | 推荐级别 | 是否需要 FDA |
|---|---|---|---|
| DNS 缓存刷新 | 低 | 常用 | 否 |
| Quick Look 缓存清理 | 低 | 常用 | 是 |
| Launch Services 重建 | 中 | 故障修复 | 是 |
| Spotlight 索引重建 | 中高 | 高级 | 是 |
| 字体缓存重建 | 中 | 故障修复 | 是 |
| Finder/Dock 缓存刷新 | 中 | 高级 | 否 |
| 系统/用户缓存清理 | 低 | 可选 | 是 |
| 日志清理 | 低 | 可选 | 是 |
| APFS 快照管理 | 高 | 专家 | 是 |

**执行模型**（OnyX 任务引擎）：
- Preflight → Plan → Authorize → Execute → Verify → Report
- 步骤级反馈（✓ / ● / ✗ / ⚠）
- 技术日志 + 用户摘要分层

### 3.5 视觉风格（融合 DaisyDisk + CleanMyMac）

**配色**（DaisyDisk 暗色基底 + CleanMyMac 品牌色）：

| 用途 | 颜色 | 备注 |
|---|---|---|
| 背景 | `#0F1012` | DaisyDisk 近黑 |
| 主品牌 | `#0A84FF` | macOS 系统蓝 |
| 强调 | `#5AC8FA` | 亮蓝（球体高光） |
| 风险 - 推荐 | `#34C759` | macOS 系统绿 |
| 风险 - 可选 | `#8E8E93` | macOS 系统灰 |
| 风险 - 谨慎 | `#FF9500` | macOS 系统橙 |
| 风险 - 危险 | `#FF3B30` | macOS 系统红 |
| 文字主 | `#FFFFFF` | 主文字 |
| 文字副 | `#999999` | 次要文字 |

**字体**：
- 主标题：`San Francisco Display` 22-28pt / 600
- 模块标题：`SF Pro Text` 17-20pt / 600
- 结果数字：`SF Pro Display` 28-40pt / 600
- 行标题：`SF Pro Text` 13-15pt / 500
- 文件路径：`SF Mono` 12pt / 400

**动画曲线**（DaisyDisk tokens）：

| 场景 | 曲线 | 时长 |
|---|---|---|
| Hover | `cubic-bezier(0.165, 0.84, 0.44, 1)` | 240ms |
| 树展开/折叠 | `easeInOut(0.2)` | 200ms |
| 扇区出现 | `easeOutBack` | 300ms |
| 删除完成 | `cubic-bezier(0.7, 0, 0.3, 1)` | 1200ms |

### 3.6 状态栏图标（融合 DaisyDisk）

- 常驻菜单栏小环图标
- 颜色随磁盘使用率：<70% 绿 / 70-90% 橙 / >90% 红
- 点击显示轻量面板（不可执行不可逆操作）
  - 磁盘剩余空间
  - 垃圾空间估算
  - 最近一次扫描时间
  - "运行 Smart Scan" 按钮

---

## 4. 架构与文件变更

### 4.1 新增/重写文件

**核心域模型**：
- `Features/SmartScan/Models/ScanTreeNode.swift`（统一协议）
- `Features/SmartScan/Models/ScanCategory.swift`
- `Features/SmartScan/Models/ScanSubCategory.swift`
- `Features/SmartScan/Models/ScanAction.swift`
- `Features/SmartScan/Models/ScanResult.swift`
- `Features/SmartScan/Models/RiskLevel.swift`（4 级）
- `Features/SmartScan/Models/CheckState.swift`
- `Features/SmartScan/Models/WarnItem.swift`

**扫描树 UI（核心新组件）**：
- `Features/SmartScan/Views/ScanResultsView.swift`（主视图）
- `Features/SmartScan/Views/CategoryRow.swift`
- `Features/SmartScan/Views/SubCategoryRow.swift`
- `Features/SmartScan/Views/ActionRow.swift`
- `Features/SmartScan/Views/ResultRow.swift`
- `Features/SmartScan/Views/RiskBadge.swift`（4 级风险徽标）
- `Features/SmartScan/Views/IndeterminateCheckbox.swift`（3 态 checkbox）

**扫描引擎增强**：
- `Features/SmartScan/ScanEngine.swift`（改为支持 4 级树输出）
- `Features/SmartScan/ScanProgressView.swift`（圆环 + 阶段列表 + 当前路径）

**清理引擎增强**：
- `Features/Cleanup/CleanupEngine.swift`（集成 warning 主流程）
- `Features/Cleanup/WarningDetectionService.swift`
- `Features/Cleanup/CleanupConfirmationSheet.swift`（风险分级确认）

**OnyX 任务引擎**：
- `Features/Maintenance/MaintenanceTaskEngine.swift`
- `Features/Maintenance/MaintenanceTaskRunner.swift`
- `Features/Maintenance/MaintenanceTaskLog.swift`

**AppCleaner 卸载**：
- `Features/AppUninstall/AppUninstallScanner.swift`（重写评分模型）
- `Features/AppUninstall/UninstallConfidence.swift`

**辅助**：
- `Features/Common/RiskColors.swift`（DesignSystem 扩展）
- `Features/Common/IndeterminateCheckmarkStyle.swift`

### 4.2 核心 API

```swift
// 扫描树（统一）
public protocol ScanTreeNode: Identifiable, Hashable, Sendable {
    var state: CheckState { get set }
    var riskLevel: RiskLevel { get }
    var children: [any ScanTreeNode] { get }
    func setState(_ newState: CheckState)
    func refreshState()
    func collectSelected() -> [URL]
}

// 扫描引擎
public final class ScanEngine: @unchecked Sendable {
    func startScan(config: ScanConfig) -> AsyncStream<ScanProgress>
    func results() -> [ScanCategory]  // 4 级树
}

// 清理引擎（含 warning 主流程）
public final class CleanupEngine: @unchecked Sendable {
    func detectWarnItems(for paths: [String]) -> [WarnItem]
    func cleanup(
        urls: [URL],
        warnHandling: WarnHandling = .skip
    ) -> AsyncStream<CleanupProgress>
}

// 卸载扫描器（含评分）
public final class AppUninstallScanner: @unchecked Sendable {
    func scan(appURL: URL) -> UninstallScanResult
    func uninstall(appURL: URL, leftovers: [LeftoverItem]) async throws
}

// 维护任务引擎
public final class MaintenanceTaskEngine {
    func run(script: MaintenanceScript) -> AsyncStream<TaskEvent>
}
```

---

## 5. 实施阶段（按优先级）

### Phase 1: 核心扫描树（P0 - 必须）
- [ ] ScanTreeNode 统一协议 + 4 级节点模型
- [ ] CheckState + RiskLevel 枚举
- [ ] 级联 Checkbox 算法（含 recommend 策略）
- [ ] 风险徽标组件（RiskBadge）
- [ ] 扫描结果主视图（4 级树 UI）
- [ ] 4 类行视图（Category / SubCategory / Action / Result）

### Phase 2: 扫描引擎重写（P0）
- [ ] ScanEngine 改为输出 4 级树
- [ ] 圆环扫描进度 + 阶段列表
- [ ] 当前路径实时显示
- [ ] 阶段化 progress 回调

### Phase 3: 清理引擎强化（P0）
- [ ] 集成 warning 主流程（修复 Lemon 注释问题）
- [ ] 风险分级确认 sheet
- [ ] 警告项 UI（WarnItemSheet）
- [ ] 可恢复性显示

### Phase 4: 现有模块适配（P0）
- [ ] Large Files：扁平 + 风险标签
- [ ] Duplicates：树形 Group + Smart Select
- [ ] App Uninstall：评分模型 + 置信度显示
- [ ] Privacy：分组 + 警告文案
- [ ] Photo Cache：缩略图 + 风险标签
- [ ] Maintenance：任务引擎 + 步骤级反馈

### Phase 5: 视觉与动画（P1）
- [ ] 风险配色 token
- [ ] 动画曲线（DaisyDisk tokens）
- [ ] 菜单栏小环图标（颜色随使用率）
- [ ] 悬停 / 选中状态切换

### Phase 6: 中文 App bundleID 映射（P1）
- [ ] 2000+ 中文 App 映射表
- [ ] 多 BundleID 变体识别（腾讯系、阿里系、字节系）

### Phase 7: 验证与打磨（P1）
- [ ] 编译 BUILD SUCCEEDED
- [ ] 端到端流程（扫描 → 警告检测 → 清理确认 → 执行）
- [ ] 边界场景（运行中应用、不可逆操作、共享组件）

---

## 6. 验证清单

- [ ] 4 级树形控件完整工作（Category → SubCategory → Action → Result）
- [ ] 级联 checkbox 父子联动 + 三态 + recommend 策略正确
- [ ] 4 级风险标签显示正确（推荐/可选/谨慎/危险）
- [ ] 警告项检测生效（不像 Lemon 注释掉），运行中应用弹 toast
- [ ] 警告项提供"跳过 / 强制终止 / 取消"三选项
- [ ] 大文件 / 重复文件 / 卸载 / 隐私 / 照片清理达到 Lemon 同级
- [ ] 维护功能 9 个脚本 + 步骤级反馈 + 技术日志
- [ ] 风险分级确认（低不弹 / 中单确认 / 高双确认 / 永久三确认）
- [ ] UI 动画流畅（DaisyDisk tokens）
- [ ] 菜单栏小环 + 颜色随使用率
- [ ] 编译 BUILD SUCCEEDED

---

## 7. 关键文件路径索引（参考）

### 7.1 Lemon 源码（仅作逻辑参考）

```
/Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon/LemonClener/LemonClener/Controller/LMCleanBigViewController.m
/Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon/LemonClener/LemonClener/View/CleanBigViewCell/BigCleanParaentCellView.m
/Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon/LemonClener/LemonClener/View/CleanBigViewCell/CategoryCellView.m
/Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon/LemonClener/LemonClener/View/CleanBigViewCell/SubCategoryCellView.m
/Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon/LemonClener/LemonClener/View/CleanBigViewCell/ActionItemCellView.m
/Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon/LemonClener/LemonClener/View/CleanBigViewCell/ResultCellView.m
/Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon/LemonClener/LemonClener/libcleaner/QMXMLItem/QMBaseItem.h
/Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon/LemonClener/LemonClener/libcleaner/QMXMLItem/QMBaseItem.m
/Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon/LemonClener/LemonClener/libcleaner/QMXMLItem/QMCategoryItem.h
/Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon/LemonClener/LemonClener/libcleaner/QMXMLItem/QMCategorySubItem.h
/Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon/LemonClener/LemonClener/libcleaner/QMXMLItem/QMActionItem.h
/Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon/LemonClener/LemonClener/libcleaner/QMXMLItem/QMResultItem.h
/Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon/LemonClener/LemonClener/libcleaner/QMScanCategory.m
/Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon/LemonClener/LemonClener/QMCleanerManager/QMRemoveManager.m
```

### 7.2 我们的项目结构（待变更）

```
/Users/mengjianjun/Documents/ai/aicoding/macapp/kWise/
├── Features/
│   ├── SmartScan/         # 扫描引擎 + 4 级树 UI（核心重写）
│   │   ├── Models/
│   │   ├── Views/
│   │   ├── ScanEngine.swift
│   │   └── ScanProgressView.swift
│   ├── Cleanup/           # 清理引擎 + 警告主流程
│   │   ├── CleanupEngine.swift
│   │   ├── WarningDetectionService.swift
│   │   └── CleanupConfirmationSheet.swift
│   ├── LargeOldFile/      # 已实现，需适配 RiskLevel
│   ├── DuplicateFile/     # 已实现，需树形 Group + Smart Select
│   ├── AppUninstall/      # 重写评分模型
│   ├── PrivacyClean/      # 已实现，需适配警告文案
│   ├── PhotoClean/        # 已实现，需缩略图
│   ├── Maintenance/       # 重写任务引擎
│   └── Common/
│       └── RiskColors.swift
```

---

> Spec 已完成。请审阅，确认后进入 writing-plans 拆解为可执行任务。