# Klaris（明澈）· 看得懂的磁盘 — vNext 设计（B 底座 + A/C 融合）

日期：2026-09-27
状态：设计已完成，待用户评审
前置调研：竞品格局 / 用户原声（HN·Reddit·Ask Different·少数派）/ 苹果端上 AI API 边界 / 2026 本地 Agent 形态 / kWise 代码家底盘点（5 份报告，结论已内化至本文）
对标：CleanMyMac（信任塌方）、DaisyDisk（只答 WHERE）、Gemini 2（伪 AI）

---

## 0. 一句话

**从「Mac 清理工具」重构为「看得懂的磁盘 + 安全回收」**：新建「归因引擎」回答每一块空间的三件事——谁拥有它、为什么在这、**删了会不会回来**；「信任契约」横切一切删除面（预演、逐条理由、拒答清单、规则可查、30 天回滚）；现有扫描/清理引擎全部复用，不重写。

**核心理念**：用户的问题不是「磁盘满了清不掉」，而是「有 135–300GB 我看不见、看不懂、不敢碰」。我们不卖「删得多」，卖「看得懂、才敢动」。

---

## 1. 调研结论（设计依据，已验证）

| # | 结论 | 来源 |
|---|---|---|
| 1 | TOP1 痛点 = System Data 黑盒（135/220/288/300GB 原话跨站点一致） | HN 46763592/47218288、sspai 108986 |
| 2 | 品类信任塌方：数据丢失差评、被叫 scam、AI 删家目录成 2026 集体创伤 | r/ableton、HN 46268222/48865230 |
| 3 | 「一键清理 + 聊天框」在 2026 已证伪；新意共识 = 可持续、可调度、带记忆、可审计 | Agent 形态调研 |
| 4 | 「AI 清理」品类内 90% 是营销话术（Gemini=偏好记忆），空位存在但用户警惕 | 竞品调研 §5 |
| 5 | 愿付费的是确定性：*「I'm happy to pay for an AI that doesn't accidentally delete my files」* | HN 44651485 |
| 6 | Foundation Models：需 M1+/macOS 26+；**中国区完全不工作**；设备端 4096 token（中文 1 字符/token） | support 121115、FM 文档 |
| 7 | macOS 27 纯 Apple Silicon；HIG 明文禁止自动化破坏性动作；审核 2.3.1(a) 点名病毒扫描类误导 | apple.com/os/macos、HIG GenAI |
| 8 | 订阅是该品类被骂第一；被接受区间 = 免费扫描 + $5.99–19.99 买断 | HN 47502408、r/macapps |
| 9 | 机器已有资产与叙事错配：真 AI（NLEmbedding/Vision）未进叙事，假 AI（AIClassifier 死代码、两个空开关）挂在设置页 | 代码盘点 §6 |
| 10 | MAS 上架是稀缺渠道（Buho/MacKeeper/OnyX/Sensei/AppCleaner 均不在 MAS），但受 2.5.1/2.5.2 约束 | 竞品调研 §1.2 |

---

## 2. 产品定位与命名

### 2.1 命名

| | |
|---|---|
| 英文 | **Klaris**（Klar 造词变体——可注册、可搜索；原 Klar 因四字母词典词重名风险被否） |
| 中文 | **明澈**（míng chè） |
| 日文 | Klaris（拉丁名直用，与 DaisyDisk 同款策略） |
| 主 Tagline | **看得懂，才敢动** / *See clearly. Act safely.* |
| 品类脊柱 | **不删错，比删得多重要** |
| 首屏标题 | **你的 NNN GB，去哪了** |

**ASO 策略**：品牌名不扛关键词，**副标题扛**——「Disk space, explained」/「看得懂的磁盘」。关键词字段保留 `disk cleaner / mac cleaner / storage` 入口；截图与预览视频讲归因与安全，不讲一键。

**⚠️ 硬门禁**：商标与 App Store 重名核查未通过前，名称不进入任何上架物料。

### 2.2 定价（用户已拍板）

- **免费**：扫描 + 归因可视化 + 拒答清单（完整可看，不可执行回收）
- **买断 $9.90**：回收执行 + 迁出/归档 + 空间变化归因 + 规则固化 + Widget/菜单栏叙事
- 明确不做：订阅、为「AI 聊天」加价、试用陷阱（取消地狱是品类差评重灾区）
- 现有 1 GB/月免费清理配额（`CleanupQuota`）**废除**，改为上述免费/付费切分

### 2.3 bundle ID

App 未上架、无历史包袱：**改名为 `app.kraftly.klaris`**，须在任何 TestFlight 之前完成（Widget App Group、深链 scheme 同步改）。

---

## 3. 总体架构

```
┌─ 呈现层 ──────────────────────────────────────────┐
│ 解剖视图（NNN GB 去哪了）· 空间变化归因（谁涨了） │
│ 清理预演 Rehearsal · 拒答清单 · 规则可查           │
│ 迁出/归档(P2 可选) · 菜单栏一句话 · QuickLook 内嵌 │
└──────────────────────────────────────────────────┘
┌─ 信任契约层（横切一切删除面）────────────────────┐
│ 白名单准入 · dry-run 默认 · 逐条理由链             │
│ 置信度三档（确定/推测/拒答）· 30 天回滚 · 零网络   │
└──────────────────────────────────────────────────┘
┌─ 归因引擎（新建，唯一核心件）────────────────────┐
│  ① 归属 Owner   App / 系统 / 用户 / 不明           │
│  ② 存在原因 Cause  缓存/快照/开发缓存/AI模型/聊天… │
│  ③ 可回收性 Reclaimability（★全品类无人做★）       │
│      recycles / resurrects / permanent / uncertain │
└──────────────────────────────────────────────────┘
┌─ AI 分层（通用栈；中国区 + Intel 全可用）────────┐
│  L0 规则表 ——— 永远兜底，输出带 ruleID 可引用     │
│  L1 NLEmbedding 句向量 + CreateML 文本分类器       │
│  L2 FM contentTagging（M1+/macOS26+/非中国区）    │
└──────────────────────────────────────────────────┘
┌─ 现有引擎（复用不重写）──────────────────────────┐
│ ScanOrchestrator · CleanupEngine · DetectionCore   │
│ AppCatalogCore · PowerScope · SMARTReader(diskutil)│
└──────────────────────────────────────────────────┘
```

### 3.1 停止做什么（砍旧与加新同等重要）

| 停止 | 处置 |
|---|---|
| 「一键清理」英雄位 | 降级为**「安全项快捷回收」**：仅 `recycles` 项 + 30 天回滚兜底，入口不深（保住 r/CleanMyMac「77 岁用户」人群），不再当叙事 |
| Assistant 聊天框 | 重构为**扫描树节点内嵌问答**（右键「为什么」），不开对话窗 |
| `AIClassifier` 全家 + `aiClassificationEnabled` + `assistantEnabled` 空开关 | **删除**（代码盘点确认：从未实例化 / 无读取方 / 恒 true 桩） |
| CLAUDE.md 假卖点（CoreML 分类 / 3D Metal 星系图 / FDA 引导） | 修正文档；**上架物料按真实能力写**（2.3.1(a) 虚假宣传风险） |
| 1 GB/月清理配额 | 废除，换 §2.2 免费切分 |
| 双引擎分裂 | Shortcuts Intents 切到 `ScanOrchestrator`，`LegacyScanEngine` 退役 |

---

## 4. 归因引擎（核心设计）

### 4.1 数据模型

```swift
struct SpaceAttribution: Sendable {
    let id: UUID
    let scope: Scope                    // .fileTree / .volumeLayer
    let paths: [URL]                    // 卷层时为空（快照/purgeable 无路径）
    let bytes: Int64
    // ① 归属
    let owner: Owner                    // .app(bundleID,appName?) / .system / .user / .unknown
    // ② 存在原因
    let cause: Cause
    // ③ 可回收性（★差异化核心★）
    let reclaim: Reclaimability
    // 信任契约
    let confidence: Confidence          // .certain / .probable / .refused
    let source: Source                  // .rule(id) / .nlEmbedding / .createML / .fmTagging
    let evidence: [Evidence]            // 理由链：最后访问时间/来源App/占用方/规则原文
}

enum Reclaimability: Sendable {
    case recycles(expectedDays: Int)    // 会回来：缓存类，标「预期 N 天后回来」
    case resurrects(via: String)        // 会复活：TM 快照等，给正确解法（tmutil 引导）
    case permanent                      // 不会回来：旧导出/安装包/归档 —— 真空间
    case uncertain                      // 不敢判 → 进拒答清单，绝不进清理建议
}

enum Cause: String, Codable, Sendable {
    case cache, snapshot, developerCache, aiModel, chatFiles
    case renderCache, download, archive, backup, log, mailAttachment
    case iOSBackup, containerData, appBinary, unknown
}

struct Evidence: Codable, Sendable {
    let kind: Kind      // .lastAccess / .ownerApp / .pathPattern / .ruleCitation / .sizeDistribution
    let textKey: String // 本地化 key + 参数，拒绝拼接英文句子
}
```

### 4.2 卷层通道（文件扫描器看不见的黑盒，本轮新建）

**黑盒数学**（归因的地基公式）：

```
黑盒 ≈ volumeUsed(DF 用量) − visibleFileTotal(文件层合计)
黑盒分解 = APFS本地快照(个数/日期) + purgeable + 系统保留(诚实区间)
```

- `VolumeLayerReader`：子进程 `diskutil apfs listSnapshots -plist`、`diskutil info -plist /`（**先例**：`SMARTReader.swift` 已用 `diskutil info`，沙箱内合法）
- 快照体量拿不到精确值 → **输出区间 + 个数 + 日期**，绝不知不确不言（C-5）
- 快照处置 = **引导 `tmutil deletelocalsnapshots`**（Maintenance 模式的既有诚实模式，不代执行——清倒时机由 macOS 管理，代删是错误承诺）
- Docker.raw / AI 模型等**大单文件**属文件层但需专项规则识别（见 4.4）

### 4.3 文件层接缝（复用现有引擎）

| 接缝 | 现状 | 用法 |
|---|---|---|
| `ScanOrchestrator` 扫描流 | 8 类目 + bundleIDMapping 150 app | 扫描产物（`ScanTreeNode` 森林）**喂给** `AttributionService` 后处理，不改树模型 |
| `FileEntry.confidence` | Core Data 已预留 | 存归因置信度 |
| `ResidueGroupingEngine.systemEmbeddingProvider` | 可注入 NLEmbedding seam | 同款注入模式建 `AttributionEngine.embeddingProvider`（测试 mock） |
| `ClassifierProtocol` | 协议在、无人实现 | L1 分类器实现它 |
| `CleanupEngine` | 配额/历史/回滚/四 sink | **不动**。删除动作永远走它 |
| `DiskSampleStore` + 月报 | 日采样 + OLS | 承接空间变化归因（C） |

### 4.4 归因语料（质量下限 = 本语料深度）

新资源 `kWise/Resources/attribution_rules.json`，**用户可查**（信任契约的「规则开放」落在实体上）：

```json
{
  "schemaVersion": 1,
  "rules": [{
    "id": "xcode.derived-data",
    "match": {"pathGlob": "~/Library/Developer/Xcode/DerivedData/**"},
    "owner": "app:com.apple.dt.Xcode",
    "cause": "developerCache",
    "reclaim": {"kind": "recycles", "expectedDays": 30},
    "evidenceKeys": ["ev.dev_cache.title", "ev.dev_cache.body"],
    "notes": "Xcode 会在下次构建时重建；删除安全"
  }]
}
```

**P0 首批语料清单**（按用户原声频次排序）：
1. Xcode 三件套（DerivedData / iOS DeviceSupport / 模拟器）
2. Docker.raw（稀疏镜像：`*.raw` + `~/Library/Containers/com.docker.docker`）
3. TM 本地快照（卷层）
4. **AI 模型占用**（macOS 27 强制下载的 Apple Intelligence 模型路径 —— 2026-09 最新愤怒点，竞品全无）
5. 微信/企业微信/飞书/钉钉 聊天文件（中文护城河；P0 只做归因，迁出在 P2）
6. iMessage 附件 / Apple Podcasts 下载 / 邮件附件
7. 渲染缓存（FCP/Adobe）、浏览器缓存、iOS 备份

语料治理：版本化 + 随 App 更新；`AttributionRuleAuditTests` 强制每条规则字段完整（owner/cause/reclaim/evidenceKeys 三语齐）。

### 4.5 AI 三层执行与置信度渲染

```
路径/文件 → L0 规则命中？ ── 是 → .certain + .rule(id)，理由链引用规则原文
                │ 否
                ▼
           L1 句向量近邻（NLEmbedding.sentenceEmbedding，
                对齐已知 cause 样本）→ ≥阈值 → .probable + .nlEmbedding
                │ 低分
           L1.5 CreateML 分类器（MLTextClassifier maxEnt+staticEmbedding，
                语料=归因规则路径样本，KB 级入包，Intel+中国区可用）
                │ 仍低
                ▼
           L2（仅 M1+/macOS26+/非中国区）FM contentTagging
                │ 仍不确定
                ▼
           .uncertain → 拒答清单（绝不出现在清理建议）
```

- **渲染三档**：确定（引用规则）/ 推测（明标「可能」）/ 不知道（明确说缺什么权限/数据）
- 每个 `.probable` 断言可点击跳回对应文件（对抗「AI embellish」不信任）
- L2 的 FM 输出只做**标签/归因候选**，永不生成删除决策（HIG 硬约束）

---

## 5. 信任契约层（B 底座，横切）

| 机制 | 设计 | 现有地基 |
|---|---|---|
| **预演 Rehearsal** | 任何回收执行前出变更清单：项/字节/**理由链**/可回收性徽章，逐项可勾 | SelectionPlanner、确认面板 |
| **拒答清单** | 第三张列表：「这 N 项我判断不了，所以不进建议」+ 缺什么权限的提示 | 无（新建） |
| **规则可查** | 「查看归因规则」页：渲染 `attribution_rules.json` 为人话表格 | 无（新建；对抗 vibe-coding 替代） |
| **回滚** | 30 天时间线整场回滚，预演页固定入口 | TimelineView/RestoreFromTrashService ✅ |
| **零网络** | `network.client=false` 保持；AI 全端上 | entitlements ✅ |
| **文案防线** | 恐吓/夸大禁语扩展到归因文案（「你的磁盘正在被吞噬」类禁） | ScarewareCopyAuditTests 模式扩展 |

---

## 6. 呈现层组件

1. **解剖视图（新首屏）**：卷层卡（快照 N 个 / purgeable / 系统保留区间）+ 文件层按 cause 分组；每组徽章 = 可回收性四色；点开 = 逐条理由链。首屏标题「你的 NNN GB，去哪了」
2. **空间变化归因（C）**：周粒度「这周 +8.4GB：Xcode 缓存 +3.1 / 微信 +2.9 / 快照 +1.2」（DiskSampleStore 差分 + 归因标签）
3. **Explain→Rule（C）**：采纳建议 → 「固化为规则」→ 本地规则库 + 可选 Shortcuts 自动化（可审计、可删除）
4. **菜单栏一句话（C）**：现有 MenuBarManager 加周叙事行 + 点开下钻
5. **安全项一键**：仅 `recycles` 项聚合入口（保留大众用户习惯，不再是英雄位）
6. **QuickLook 内嵌**：扫描行空格预览 + 行内「为什么」徽章

---

## 7. 降级与错误处理矩阵

| 场景 | 行为 | 禁止 |
|---|---|---|
| NLEmbedding 不可用（Intel 旧机） | 纯 L0 规则 +「规则判定」标注 | 静默降级不标注 |
| CreateML 模型加载失败 | 落 L0 | 崩溃/空转 |
| FM 不可用（Intel / 中国区 / 8GB） | 自动 L1，设置页如实显示「本机使用规则+本地模型」 | 显示灰色 AI 开关 |
| `diskutil` 调用失败 / 无卷权限 | 卷层卡显示「无法读取卷信息」+ 重试，文件层照常 | 用文件层合计冒充全盘 |
| 黑盒数学为负/异常 | 显示区间 + 「样本不足」 | 编数字（对齐月报 r²<0.5 先例） |
| 微信等目标 App 运行中（P2 迁出） | InUseChecker 拦截 + 请求退出引导 | 带病迁移 |
| 权限缺失（PowerScope 未授权） | 拒答清单展示「授权后我能判断这些」 | 空结果页装作干净 |

---

## 8. 测试策略与 P0 验收

**测试增量**（对齐现有 522 用例基线，全绿纪律）：
- `AttributionRuleAuditTests`：语料每条规则字段完整性 + 三语 evidenceKeys
- `AttributionGoldenTests`：合成文件树 → 断言 owner/cause/reclaim 逐节点正确（L0 确定性，无模型依赖）
- `VolumeLayerReaderTests`：diskutil plist fixture 解析（快照/purgeable/失败三态）
- `BlackBoxMathTests`：used − visible 一致性，异常输入出区间不出数字
- `RehearsalTests`：预演 diff 与实际执行逐项一致（预演撒谎 = 信任崩塌）
- `ConfidenceRenderingTests`：三档渲染 + 拒答永不进建议
- `RecurrenceCopyAuditTests`：可回收性文案禁语（「彻底释放永不复返」类）
- FM/NLEmbedding 全部 protocol 注入 mock（`systemEmbeddingProvider` 模式）

**P0 验收（「为什么」合格线）**——不达标不进 P1：
1. 合成语料 + 真机 checklist 上，**Top-20 空间项 100% 由 L0 规则判定**（不依赖模型），每项含 owner+cause+reclaim
2. 黑盒数学在真机上闭合到「快照数 + purgeable + 残差解释」且残差 < 5%
3. 任何建议行可展开理由链；拒答清单在权限缺失时非空且文案诚实
4. 归因文案通过扩展后的恐吓禁语审计

---

## 9. 上架合规映射

| 条款 | 本设计对位 |
|---|---|
| 2.3.1(a) 误导营销 | 无病毒/威胁叙事；「不敢判」明示；假卖点全部移除 |
| 2.4.2 SSD 过度写入 | 粉碎保持 1-pass（已合规），文案诚实 |
| 2.5.1/2.5.2 沙盒 | 零 FDA、零私有 API、卷层仅 diskutil（SMARTReader 先例） |
| 3.1.2(a) 订阅持续价值 | **买断制，条款不适用**（规避品类最大雷区） |
| 5.1.1(i) 第三方 AI 披露 | 零网络 + 全端上 → 免检；隐私页写明「数据不出机」 |
| HIG GenAI | AI 标注三档 / 禁自动破坏 / 预演确认 / Undo 全有 |

---

## 10. 分期路线（长任务规划骨架）

> 每期独立可交付、可验证；P0 是全案心脏，先证伪「语料深度」假设。

| 期 | 内容 | 关键验收 |
|---|---|---|
| **P0 归因引擎** | 数据模型 + 卷层通道 + 归因语料首批 + L0 全链路 + 黑盒数学 + 规则可查页 | §8 四条验收全绿；TestFlight「为什么」满意度为唯一北极星 |
| **P1 信任契约 + 解剖视图** | 预演 / 拒答清单 / 置信度三档渲染 / 新首屏 / L1(L1.5) 接入 / 旧资产清理（§3.1 停止项） | 预演=执行逐项一致；复制审计全绿 |
| **P2 空间治理** | 空间变化归因 / Explain→Rule / 菜单栏叙事 / QuickLook 内嵌 / L2 探索 | 周归因准确；规则固化可撤销 |
| **P2 可选：迁出引擎** | 微信等聊天文件迁出/归档 | **触发条件**：P0 TestFlight 反馈证明归因价值成立后另行评估（风险最高，默认不做） |

---

## 11. 开放决策点（不阻塞 P0）

1. **商标核查**：Klaris / 明澈 的商标与 App Store 重名（用户执行，硬门禁）
2. **迁出引擎去留**：P0 验证后决定
3. **kSift/kFresh/kMonitor 品牌联动**：Klaris 定名后是否统一 Kraftly 矩阵命名（本期不动）
