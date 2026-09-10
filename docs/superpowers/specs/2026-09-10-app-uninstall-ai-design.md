# 应用卸载 · AI 深度优化设计（v2.6 R2-AI）

日期：2026-09-10
状态：设计已批准，待实施
对标：AppCleaner / CleanMyMac Uninstaller

## 1. 背景与目标

「应用卸载」已完成引擎级能力（4 源目录、1141 cask 规则、孤儿残留、拖入 .app、App Reset、残留备份 30 天、来源筛选/搜索/未使用排序）。本轮目标：**把残留列表从"路径堆"升级为"AI 理解的可读视图"**，交互达到苹果精品推荐水准。

**AI 硬件约束**：目标机 Intel + macOS 15，Apple Intelligence 不可用。可用的苹果端上 AI：NaturalLanguage（NLEmbedding 词向量）、Vision、CoreML。全部纯本机、零网络。

**已锁定决策**：
- AI 引擎 = 方案 1「规则优先 + NLEmbedding 兜底」
- 交互载体 = 列表 + 右侧详情面板（与主扫描双栏一致）
- AI 功能四件：语义分组、残留解释器、归属推断、健康摘要

## 2. 架构

```
AppUninstallView（列表 + 右侧详情面板 AppUninstallDetailPanel）
        │ 选中 App
        ▼
AppUninstallDetailPanel
  ├─ 健康摘要卡（HealthSummaryBuilder）
  ├─ 语义分组卡（ResidueGroupingEngine → [ResidueGroup]，组级勾选级联）
  └─ 残留解释列表（ResidueExplainer 白话说明 + 单项勾选）
        │ 底部动作：卸载 / App Reset / 备份
        ▼
CleanupEngine（不变：废纸篓 + 历史 + 配额）
```

新增类型（`kWise/Features/AppUninstall/`）：
- `ResidueGroupingEngine.swift` — 分组引擎 + `ResidueGroup` / `ResidueGroupKind`
- `HealthSummaryBuilder.swift` — 健康摘要卡模型与构建
- `ResidueExplainer.swift` — 残留白话解释器
- `AppUninstallDetailPanel.swift` — 右侧详情面板视图

修改：`AppUninstallView.swift`（双栏：左列表 / 右面板）、`AppUninstallViewModel.swift`（选中条目发布 + 分组懒计算 + 分组勾选级联）。

## 3. AI 分组引擎（ResidueGroupingEngine）

### 3.1 类目

`ResidueGroupKind`（8 类，固定顺序渲染）：

| kind | 标题 | 图标 | 对应 ResidueType |
|---|---|---|---|
| preferences | 偏好设置 | gearshape | .preferences |
| caches | 缓存数据 | cpu | .caches |
| appData | 应用数据 | shippingbox | .appSupport, .groupContainer |
| webData | 网页数据 | globe | .webKit, .cookie |
| launchAgents | 启动项 | power | .launchAgent, .launchDaemon, .startupItem |
| plugins | 插件与面板 | puzzlepiece | .plugin, .prefPane |
| savedState | 窗口状态 | rectangle.stack | .savedState |
| other | 其他 | shippingbox | 其余 + 兜底 |

### 3.2 两遍算法

1. **规则遍**：`ResidueType` 直接映射到 kind（上表）。零成本、零错误、可解释。
2. **NLEmbedding 遍**：规则未覆盖或 `other` 类的路径——把路径拆成 COMPONENT 词（按 `/`、`-`、`_`、空格拆分，去 `WK`/数字后缀），每个词经 `NLEmbedding.wordEmbedding(for: .simplifiedChinese) ?? NLEmbedding.wordEmbedding(for: .english)` 取向量；与 6 组锚点词组的平均向量算余弦相似度；**≥0.45 归入最高分组**，否则留「其他」。
   - 锚点词组（每类 4-6 词）：缓存 = [cache, 缓存, 临时, temp]，聊天数据 = [chat, 消息, 微信, 会话]，文档数据 = [document, support, 数据, 文件]……
   - 词向量按词缓存（NSCache，上限 2000 词）。
   - NLEmbedding 为 nil 或单次查询失败 → 该词跳过，残留落「其他」（诚实降级）。

### 3.3 输出

```swift
struct ResidueGroup: Identifiable {
    let kind: ResidueGroupKind
    let residues: [ResidueFile]      // 组内残留（ResidueFile 不可变，来源 AppCatalogCore）
}

/// 勾选态**唯一来源** = 面板持有的 `selectedResiduePaths: Set<String>`（键 = 残留路径）。
/// 不写入 ResidueFile，也不存 ResidueGroup —— 组勾选态在渲染时从
/// selectedResiduePaths 推导（全选/部分/未选），避免两处状态失步。
/// 每个条目独立持有自己的选中集合（按 entryID 隔离），切回 Tab/条目不丢。
```

分组是**展示层**：清理仍以扁平选中 URL 提交 `CleanupEngine.cleanup(targets:)`——安全网（废纸篓/历史/配额）不变。

### 3.4 性能

- 规则遍 O(n)；embedding 仅对规则未覆盖的词调用，组件词 NSCache 缓存；几百条残留 <100ms。
- 分组在**选中 App 时惰性计算**（纯内存），不阻塞扫描。

## 4. 健康摘要卡（HealthSummaryBuilder）

输出 `HealthSummary`：

```swift
struct HealthSummary {
    let daysInstalled: Int?        // installDate 距今天数；nil = 未知
    let lastUsedText: String       // "7 天前" / "未知"
    let totalSizeText: String      // 残留+本体
    let residueRatio: Double       // 残留/本体 比
    let grade: Grade               // .clean / .normal / .bloated
    let gradeText: String          // 干净 / 正常 / 臃肿
}
```

评级规则（可解释、无 AI 玄学）：
- 残留/本体 < 0.1 或残留 < 50MB → `.clean`
- 0.1 ~ 0.5 → `.normal`
- \> 0.5 → `.bloated`
- 孤儿条目（本体 size = 0）→ 固定 `.bloated`（残留即全部，需用户处置）

摘要卡文案（fun 语气、无恐吓）：
> 「这个 App 在你的 Mac 上住了 **342 天**，最近使用是 **7 天前**。残留 **1.2 GB**，偏多。」

## 5. 残留解释器（ResidueExplainer）

规则表：`ResidueType` + 路径模式 → 白话说明。

| 模式 | 解释 |
|---|---|
| Preferences/*.plist | 「应用的偏好设置，删除后 App 恢复首次启动的默认配置」 |
| Caches/* | 「缓存文件，删除后 App 会自动重建」 |
| Application Support/<name>/Chat | 「聊天记录数据，删除后聊天图片不再显示」 |
| Saved State | 「窗口状态记录，删除后无影响」 |
| HTTPStorages | 「网络缓存数据，删除后 App 重新登录可能需要」 |
| LaunchAgents | 「开机自启动配置，删除后 App 不再自动启动」 |

未命中模式 → 「应用的支撑文件」。解释由规则 + 路径模式生成（确定性），**不调用生成式模型**——可解释、可测试。

## 6. 归属推断（复用既有能力）

启动项/孤儿残留的「这是 XX 的后台助手」推断已实现（`StartupItemsViewModel.inferUsage`，反查 zh_app_mappings 219 条）。本轮把它提为 `ResidueExplainer.ownerHint(for label:)` 共享 API，启动项与应用卸载共用。

## 7. 详情面板交互（AppUninstallDetailPanel）

- 左列选中 App → 右侧面板出现；未选中 → 面板显示 EmptyStateView「选择一个应用查看详情」。
- 孤儿条目（App 本体不存在）的摘要卡显示「应用已删除，仅剩残留 N MB」，且**无卸载按钮**（无可卸载本体），只有「清理残留」与「备份」。
- 三段布局：摘要卡（顶部固定高度）→ 分组卡列表（滚动）→ 动作栏（卸载 / App Reset / 备份，固定底部）。
- 组级勾选 → 级联组内全部残留；单项可反调。组全不勾 → 该组不清理。
- 「卸载」提交语义（消歧）：
  - 条目级勾选（AppRow checkbox）= 整 App 选中 → 提交 App 本体 + **全部**残留。
  - 面板内残留勾选（明细勾选过至少一项）→ 提交 App 本体 + **仅选中的**残留。
  - 两者互斥规则：面板里出现过任何显式勾选 → 以面板选中集为准；清空面板勾选 → 回退整 App 语义。
- App Reset 按钮只清 preferences/caches/httpStorage/savedState 组（组卡片上直接标注「Reset 会清理此组」）。
- 行内展开的残留清单保留为"快速一览"（只读），明细编辑统一在右侧面板 —— 消除两处勾选状态失步的可能。

## 8. 数据流与错误处理

- `AppUninstallViewModel` 增加 `@Published var selectedEntryID: UUID?` 与 `@Published private(set) var groupedResidues: [UUID: [ResidueGroup]]`（按条目缓存，选中时惰性计算）。
- 分组勾选写回：勾选态存 `selectedResiduePaths: Set<String>`（面板持有）；卸载提交 = App 本体 + `entry.residues.filter { selectedResiduePaths.contains($0.url.path) }`。
- 错误处理：
  - NLEmbedding 不可用 → 全落「其他」+ 面板顶部一行「语义分组不可用（词向量缺失），已按其他归类」——不假装成功。
  - 残留文件消失（扫描后删除）→ 分组渲染时过滤不存在路径。
  - 分组计算 >50ms（极端大目录）→ 后台 Task 计算 + 主线程发布，面板显示「分析中…」骨架。

## 9. 测试

| 测试 | 断言 |
|---|---|
| ResidueGroupingEngineRuleTests | 8 类规则映射正确；未知路径落 other |
| ResidueGroupingEngineEmbeddingTests | mock embedding 下锚点归组；阈值边界 0.45；NLEmbedding nil → 全 other |
| ResidueExplainerTests | 每 ResidueType 文案快照；未知模式通用文案 |
| HealthSummaryBuilderTests | 天数计算、三档评级边界、nil lastUsed |
| DetailPanelSelectionTests | 组勾选级联；清理管道读取选中态；App 本体必删 |

## 10. 验收清单（用户手验）

- [ ] 扫描后点任一 App → 右侧出现详情面板：摘要卡 + 分组卡 + 解释列表
- [ ] 摘要卡显示安装天数/最近使用/残留评级，数字与真实文件一致
- [ ] 分组卡按 类型×大小 排序，组勾选级联组内残留
- [ ] 每条残留有白话解释；Cookie/Login Data 类有登录态警示
- [ ] NLEmbedding 缺失时面板顶部出现诚实降级提示，全部归「其他」
- [ ] 卸载/App Reset/备份行为与现状一致（回归）
- [ ] 断网 + 无 Apple Intelligence 环境全部功能可用
