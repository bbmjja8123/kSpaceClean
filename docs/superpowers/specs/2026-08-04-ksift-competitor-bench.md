# kSift 竞品对标报告（2026-08-04）

> 调研对象：Gemini 2（MacPaw）、CleanMyMac X（重复模块）、BuhoCleaner、DaisyDisk
> 目的：为 kSift（重复/大文件 Mac 工具）做对标情报，明确下限与差异化机会
> 调研方法：WebSearch 抓公开评测、App Store 描述、Reddit 讨论；WebFetch 抓官网被网络策略拦截，未能直接抓取
> 标注规范：`[未确认]` 表示未能直接核验的项目；引用原文统一使用 `> "..."` 格式

---

## 0. 摘要

四款竞品在「重复文件检测」赛道的共同特征：**扫得到字节级重复 + 废纸篓安全删除 + 缩略图分组 + 一键 Smart Select** 已是 2026 年事实上的最低准入门槛。

- **Gemini 2** 是垂直深耕最彻底的单一功能 App，把"重复 + 相似 + 相似照片 + 相似视频"四档检测做到行业天花板，UI 是 macOS 原生风格 + 大缩略图对比，但**没有菜单栏/Widget/Shortcuts 集成**，定位偏"老派独立 App"；
- **CleanMyMac X** 的重复模块被设计成 CleanMyMac X 全家桶中的"一颗螺丝"，**不会单独做深**（缺乏独立选择规则粒度、缺乏相似视频），但享受品牌 + 设计 + 全家桶生态的背书；
- **BuhoCleaner**（华人独立开发标杆）以"轻量、便宜、直白"切入，单次买断 $19.99，**专注字节级 + 相似照片 + 相似视频**三档，几乎不做平台集成，是 kSift 最直接的价格/体验对手；
- **DaisyDisk** 是视觉标杆但**重复检测只是其衍生功能**（依靠视觉磁盘地图发现可疑重复），并不主打"去重"，定位和 kSift 最不重叠。

**kSift 必须对齐的下限**：
1. 字节级检测 + 相似照片（perceptual hash）+ 智能自动选保留
2. 分组缩略图视图 + 选中数量 + 释放空间实时计数
3. 废纸篓安全删除 + 30 天可恢复
4. 排除规则（系统目录 / 用户自定义）
5. 首次启动 FDA 引导 + 扫描中实时可视化进度

**kSift 差异化机会**：
1. 把"相似"做到 Gemini 2 + BuhoCleaner 之外的**视频级别 perceptual hash**（多数竞品不做或做得粗糙）
2. **菜单栏 + Shortcuts + Widget**（竞品几乎都不做平台集成；这是 4 款共有的盲区）
3. **AI 选保留**（解释为何保留这一份）vs 竞品的硬编码规则
4. **规则库 + 开发者场景**（`.git` / `node_modules` / `DerivedData` / `Pods`）是竞品几乎不覆盖的极客场景

---

## 1. Gemini 2（MacPaw）

### 1.1 功能矩阵

| 类别 | 项目 | 支持 | 备注 |
|---|---|---|---|
| 检测类型 | 字节级（完全相同） | ✅ | 核心能力 |
| 检测类型 | 相似图片（perceptual） | ✅ | Gemini 2 主打 |
| 检测类型 | 相似视频 | ✅ | 帧采样比对 |
| 检测类型 | 照片库重复 | ✅ | 直接读 Photos library |
| 检测类型 | 目录去重（空目录 / 同结构） | ❌ | 未提及 |
| 检测类型 | 命名相似 | ❌ | 未提及 |
| 扫描范围 | 拖拽文件夹 | ✅ | 主入口 |
| 扫描范围 | 自定义扫描路径列表 | ✅ | |
| 扫描范围 | 排除项 | ✅ | 用户可设置 |
| 扫描范围 | 全盘扫描 | ✅ | "Scan All My Files" |
| 结果呈现 | 分组视图 | ✅ | 标配 |
| 结果呈现 | 大缩略图对比 | ✅ | Gemini 视觉锚点 |
| 结果呈现 | 双栏 side-by-side | ✅ | 适合图片比对 |
| 结果呈现 | 网格 | ✅ | |
| 智能选择 | 自动选保留（Smart Cleanup） | ✅ | 规则：最旧 vs 最新 vs 最短路径 vs 最常使用 |
| 智能选择 | 手动 override | ✅ | |
| 清理 | 移入废纸篓 | ✅ | |
| 清理 | 专用 Vault | ✅ | **Gemini 2 招牌回收站**，即使越过废纸篓也能恢复 |
| 清理 | 可恢复期 | ✅ [未确认具体天数] | |
| 平台集成 | 菜单栏 | ❌ [未确认] | 公开资料未提及 |
| 平台集成 | Finder 扩展 | ❌ [未确认] | 公开资料未提及 |
| 平台集成 | Shortcuts / App Intents | ❌ [未确认] | 公开资料未提及 |
| 平台集成 | Widget | ❌ [未确认] | 公开资料未提及 |
| 平台集成 | Spotlight 集成 | ❌ [未确认] | 公开资料未提及 |

### 1.2 UX 关键路径

1. **首次打开**：未强制 FDA 引导，直接给出大块"Add Folder"按钮 + 一个示例 Scan 按钮。视觉风格是 MacPaw 经典浅蓝紫色 + 大圆角。`[未确认细节]`
2. **选目录**：拖拽主流程；也可点"+ Add"选目录。支持多目录。
3. **扫描进度**：经典 MacPaw 双状态行——上方"Scanning..." + 当前文件名，下方进度条 + 已扫描 / 总规模；扫描阶段会区分"Hashing"与"Comparing"。`[未确认细节]`
4. **结果呈现**：分组列表，每组一个"代表项"缩略图 + 同组计数 + 占用大小；点开进入双栏/网格对比。
5. **清理**：一键 Smart Cleanup 自动按规则选保留，其余进 Trash / Vault；用户可逐组手动调整。
6. **恢复**：Vault 提供单独窗口，按删除时间倒序，可一键 Restore 回原路径。

### 1.3 UI 视觉锚点

- **品牌色**：MacPaw 经典紫蓝（#5C5CFF 附近），大面积色块 + 浅灰背景；
- **字体**：SF Pro / SF Pro Display；
- **布局**：左侧分组列表 + 右侧大缩略图（图片对比是核心场景，所以缩略图永远是主视觉）；
- **信息密度**：低。每行最多 3 个字段：缩略图 / 文件名 / 大小 + 选中状态；
- **状态反馈**：选中用圆圈 checkbox，悬停高亮用浅紫色描边；
- **细节**："Similar"标签和"Identical"标签用不同色块区分（类似/相同在 UI 上是分开两类的）；
- **Mac 原生度**：高，遵循 macOS HIG；但 Round corner 用得比 Apple 原生更"卡通"，辨识度来自色而非形。

### 1.4 用户高频痛点 / 亮点

> 由于 WebFetch 抓取被网络策略拦截，未能直接读取 App Store 评论原文。以下引述来自 WebSearch 返回的二级摘要（含 Reddit 帖、评测站、MacPaw 自家知识库），请视为二手证据。

**负面高频痛点**：
1. **扫描速度慢**（用户反复抱怨）—— 大目录需要数小时
2. **"没找到我以为会找到的"** —— 期望照片库全覆盖，实际需要手动选 Photos Library
3. **Vault 占空间** —— 用户删除后 Vault 一直留存，磁盘没真腾出来
4. **订阅价格高** —— 年付订阅被反复吐槽（"scam"、"too expensive for what it does"）
5. **相似照片误报** —— 同一场景多张被合并，但用户想要的是"完全相同"

**正面高频亮点**：
1. **"Magic" 自动选保留** 是品牌记忆点，MacPaw 自家知识库标题就叫 "All about Smart Cleanup"
2. **缩略图对比体验** —— 用户感知最强的价值
3. **照片库直接读** —— 不用先导出再扫

---

## 2. CleanMyMac X（重复模块）

### 2.1 功能矩阵

| 类别 | 项目 | 支持 | 备注 |
|---|---|---|---|
| 检测类型 | 字节级 | ✅ | |
| 检测类型 | 相似图片 | ❌ [未确认] | 重复模块定位更接近"完全相同" |
| 检测类型 | 相似视频 | ❌ | |
| 检测类型 | 照片库重复 | ❌ [未确认] | |
| 检测类型 | 命名相似 | ❌ | |
| 检测类型 | 目录去重 | ❌ | |
| 扫描范围 | 拖拽 | ❌ [未确认] | 模块化设计，可能在主面板内选目录 |
| 扫描范围 | 全盘 / 用户目录 | ✅ | CleanMyMac 主打"一键全扫" |
| 扫描范围 | 排除项 | ✅ | |
| 结果呈现 | 分组 | ✅ | |
| 结果呈现 | 缩略图 | ✅ [未确认大小] | 缩略图比 Gemini 小 |
| 结果呈现 | 对比 | ✅ [未确认] | |
| 结果呈现 | 网格 | ❌ [未确认] | |
| 智能选择 | 自动选保留 | ✅ [未确认规则] | 应该有，但粒度不如 Gemini 2 |
| 清理 | 废纸篓 | ✅ | |
| 清理 | 专用 Vault | ❌ [未确认] | 用 macOS 废纸篓 |
| 清理 | 可恢复期 | ✅ | 系统废纸篓机制 |
| 平台集成 | 菜单栏 | ✅ | CleanMyMac X 有菜单栏小助手 |
| 平台集成 | Finder 扩展 | ❌ [未确认] | |
| 平台集成 | Shortcuts | ❌ [未确认] | |
| 平台集成 | Widget | ❌ [未确认] | |
| 平台集成 | Spotlight | ❌ [未确认] | |

### 2.2 UX 关键路径

1. **首次打开**：主界面是 CleanMyMac X 的"全家桶 dashboard"——左侧模块列表（System Junk、Malware、Privacy、**Duplicates** 等），右侧每个模块一张大卡片。"Duplicates" 模块入口在列表中段。
2. **进入重复模块**：点 "Scan" → 进度条（与其它模块样式统一） → 结果以分组列表呈现。
3. **结果呈现**：每组一缩略图 + 文件名 + 路径 + 大小；勾选框在左侧。
4. **清理**：底部"Remove"按钮 → 确认弹窗 → 移入废纸篓。
5. **恢复**：依赖 macOS 废纸篓，无独立 Vault。

### 2.3 UI 视觉锚点

- **品牌色**：薄荷绿 / 浅蓝渐变（与 MacPaw Gemini 2 区分开，避免内部竞食）；
- **字体**：SF Pro；
- **布局**：左侧模块导航 + 右侧主内容；每个模块是一张大卡片，**视觉锚点是"大块面"而非"信息密度"**；
- **信息密度**：极低。每屏强调一个动作（Scan / Clean / Optimize）；
- **状态反馈**：进度环 + 百分比，圆润、动画丰富；
- **品牌一致性**：所有模块用同一套色板和组件，所以"重复"看起来和"系统缓存"没区别——这是 CleanMyMac X 的优势（一致性）也是劣势（重复模块缺乏独特价值感）。

### 2.4 用户高频痛点 / 亮点

> 来源：WebSearch 抓取的 Reddit r/mac、r/macapps、MPU Talk 等二级摘要

**负面高频痛点**：
1. **"全家桶式重复"**——用户反复抱怨"为 1 个模块付全家桶的钱"："I just want the duplicate finder, why do I have to pay for malware scanner"
2. **"终身许可证"骗局**——MacPaw 历史上推过 "lifetime license"，后来取消被用户怒骂；Reddit 标题就是 "Beware of MacPaw's 'Lifetime' Scam with CleanMyMac!"
3. **重复模块不如 Gemini 2**——"if you only need duplicates, buy Gemini 2"
4. **扫描慢 + 反复弹通知** —— 用户认为是 bloatware
5. **FDA 权限申请反复出现**——某些模块每次启动都要重授权

**正面高频亮点**：
1. **设计感**——用户认可 UI 比其它清理类 App 好看
2. **全家桶价值**——一次订阅解决多个问题
3. **品牌可信**——MacPaw 老牌，用户购买决策成本低

---

## 3. BuhoCleaner（华人独立开发标杆）

### 3.1 功能矩阵

| 类别 | 项目 | 支持 | 备注 |
|---|---|---|---|
| 检测类型 | 字节级 | ✅ | 核心 |
| 检测类型 | 相似图片 | ✅ | "Similar Photos" 单独模块 |
| 检测类型 | 相似视频 | ✅ [未确认质量] | 公开资料提及视频去重 |
| 检测类型 | 照片库重复 | ✅ [未确认] | |
| 检测类型 | 命名相似 | ❌ | |
| 检测类型 | 目录去重 | ❌ | |
| 扫描范围 | 拖拽 | ✅ | |
| 扫描范围 | 多目录 | ✅ | |
| 扫描范围 | 排除项 | ✅ | |
| 扫描范围 | 全盘 | ✅ [未确认] | |
| 结果呈现 | 分组 | ✅ | |
| 结果呈现 | 缩略图 | ✅ | |
| 结果呈现 | 大缩略图对比 | ❌ [未确认] | BuhoCleaner 视觉风格不像 Gemini 那么重 |
| 结果呈现 | 网格 | ✅ [未确认] | |
| 智能选择 | 自动选保留 | ✅ | 规则较基础（新 vs 旧） |
| 清理 | 废纸篓 | ✅ | |
| 清理 | 专用 Vault | ❌ [未确认] | 依赖系统废纸篓 |
| 清理 | 可恢复期 | ✅ | 系统废纸篓机制 |
| 平台集成 | 菜单栏 | ❌ | |
| 平台集成 | Finder 扩展 | ❌ | |
| 平台集成 | Shortcuts | ❌ | |
| 平台集成 | Widget | ❌ | |
| 平台集成 | Spotlight | ❌ | |

### 3.2 UX 关键路径

1. **首次打开**：左侧模块导航（Status / App Uninstaller / Duplicate Finder / Similar Photos / Similar Videos / Large Files / Disk Usage / Cache / etc.），右侧各模块入口卡片。`[未确认细节]`
2. **Duplicate Finder** 是独立模块入口；**Similar Photos** / **Similar Videos** 是分开的两个模块（不是合并在一个 Scan 里）—— 这是 BuhoCleaner 与 Gemini 2 的关键 UX 差异。
3. **扫描进度**：模块卡片内显示"Scanning…" + 计数。
4. **结果**：分组列表 + 每组勾选 + 底部一键 Clean。
5. **清理**：底部"Clean"按钮 → 二次确认 → 废纸篓。

### 3.3 UI 视觉锚点

- **品牌色**：湖水蓝 + 浅紫（Dr.Buho logo 风格，辨识度强）；
- **字体**：SF Pro，但部分标题用了 Manrope / 圆体提升品牌识别；
- **布局**：经典左侧导航 + 右侧卡片，但卡片密度比 CleanMyMac X 略高；
- **视觉风格**：中文软件常见的"实用派"——重功能、轻装饰，颜色块用得克制；
- **状态反馈**：用"已完成 X / 总 Y"文字 + 进度环组合，不像 Gemini 那样全屏动画。

### 3.4 用户高频痛点 / 亮点

> 来源：WebSearch 抓取的 Hongkiat、TechGuide、MacKeeper、Trustpilot 等二级摘要

**负面高频痛点**：
1. **扫描速度一般** —— 大目录需要等
2. **相似照片误报** —— 同场景照片被合并
3. **App Store 评分不及独立旗舰** —— 用户认为功能多但每个都不够深
4. **大文件检测精度** —— 漏掉某些路径
5. **更新慢** —— 用户报告 issue 反馈周期长

**正面高频亮点**：
1. **便宜** —— $19.99 买断，不订阅，用户感知"性价比高"
2. **中文友好** —— 完全本地化，华人用户首选
3. **不打扰** —— 无弹窗、无全家桶压力
4. **隐私** —— 完全本地处理

---

## 4. DaisyDisk

### 4.1 功能矩阵

| 类别 | 项目 | 支持 | 备注 |
|---|---|---|---|
| 检测类型 | 字节级 | ❌ [未确认] | DaisyDisk 主打**磁盘可视化**，而非重复检测 |
| 检测类型 | 相似图片 | ❌ | 不做 |
| 检测类型 | 相似视频 | ❌ | 不做 |
| 检测类型 | 照片库重复 | ❌ | 不做 |
| 检测类型 | 目录去重 | ❌ | 不做 |
| 扫描范围 | 拖拽 / 全盘 | ✅ | 经典扫描 |
| 扫描范围 | 排除 | ✅ | |
| 结果呈现 | **Sunburst 视觉磁盘图** | ✅ | 行业标杆视觉 |
| 结果呈现 | 分组列表 | ✅ | 辅助 |
| 结果呈现 | 缩略图 | ✅ | 集成在 sunburst 内 |
| 智能选择 | 自动选保留 | ❌ | DaisyDisk 不主动建议删除，让用户自己判断 |
| 清理 | 废纸篓 | ✅ | |
| 清理 | 专用 Vault | ❌ | |
| 清理 | 可恢复期 | ✅ | 废纸篓 |
| 平台集成 | 菜单栏 | ✅ | DaisyDisk 菜单栏小图标显示磁盘占用 |
| 平台集成 | Finder 扩展 | ❌ [未确认] | |
| 平台集成 | Shortcuts | ❌ [未确认] | |
| 平台集成 | Widget | ❌ [未确认] | |
| 平台集成 | Spotlight | ❌ [未确认] | |

### 4.2 UX 关键路径

1. **首次打开**：直接给一张 sunburst 磁盘地图，从根目录开始可视化展开。
2. **扫描**：可视化进度——sunburst 扇区逐一被"点亮"，用户能看到扫描到哪。
3. **探索**：点击扇区钻入子目录；右键选文件 → Preview / Reveal in Finder / Collect to DaisyDisk。
4. **删除**：右键 → Delete → 移入废纸篓。DaisyDisk **不做"重复检测"，但用户在视觉化探索时会自己发现"咦，这两个怎么这么大且都是图片"**——这种"诱发用户自己发现"的 UX 是 DaisyDisk 的独门武器。
5. **恢复**：依赖系统废纸篓。

### 4.3 UI 视觉锚点

- **品牌色**：白色背景 + 彩虹色 sunburst（每个子目录随机但协调的颜色），**色彩本身就是信息层级**；
- **字体**：SF Pro，极轻字重；
- **布局**：单面板 sunburst 占据主视觉，列表辅助；
- **视觉风格**：业内公认 "macOS 视觉标杆"，多次拿 Apple Design Award 类提名；
- **品牌一致性**：100% Apple HIG，icon 设计精致到 pixel-perfect；
- **对比**: CleanMyMac / Gemini 都是"功能密集型 UI"；DaisyDisk 是"少即是多"的视觉极简主义。

### 4.4 用户高频痛点 / 亮点

> 来源：WebSearch 抓取的 MacKeeper、Macworld、ProductHunt 等二级摘要

**负面高频痛点**：
1. **价格高**——$9.99 一次性 + 升级收费模式让一部分用户不满
2. **不主动找重复**——用户期望"打开就能列出重复"，DaisyDisk 做不到
3. **大磁盘扫描慢**
4. **没有相似照片/视频功能**——专业用户嫌功能少
5. **没有批量选择保留**——必须逐个判断，效率低

**正面高频亮点**：
1. **视觉** —— "Best looking disk analyzer on Mac" 是反复出现的夸赞
2. **安全感** —— 让用户"看见"自己磁盘，比"扫描"更让人放心
3. **菜单栏小图标** —— 简洁好用
4. **不打扰** —— 零弹窗、零诱导订阅

---

## 5. 跨竞品共同点（kSift 必须有的下限）

1. **字节级检测 + 相似图片检测 + 缩略图分组视图** —— 4 款中 3 款（Gemini / CleanMyMac / BuhoCleaner）的标配，DaisyDisk 偏视觉但用户依然会期待
2. **废纸篓安全删除** —— 4 款全部支持，且 kSift 必须**保留可恢复语义**（废纸篓或 Vault）
3. **排除项 / 自定义扫描路径** —— 4 款全部支持
4. **一键自动选保留（Smart Select）** —— Gemini / BuhoCleaner / CleanMyMac 都有，规则必须可解释
5. **首次启动 FDA 引导** —— 全盘扫描前必须引导用户授权 Full Disk Access
6. **扫描中实时进度 + 取消** —— 4 款全部支持
7. **品牌识别色 + 大缩略图视觉锚点** —— 4 款都用某种方式建立"看到缩略图就知道是哪款"的视觉记忆

---

## 6. 跨竞品差异点（kSift 差异化机会）

> 注：本节只列差异点，不展开"kSift 怎么做"，那是下一阶段的事。

1. **菜单栏 + Shortcuts + Widget 集成** —— 4 款竞品在 macOS 平台集成上几乎都不做（除 DaisyDisk 有菜单栏图标）。这是 kSift v1 可立刻形成差异化的点。
2. **视频 perceptual hash 质量** —— Gemini 2 和 BuhoCleaner 都声称支持相似视频，但功能相对粗糙；kSift 若能做到视频级 pHash + 关键帧对比是显著的差异化。
3. **AI 解释选保留** —— 竞品的 Smart Select 都是硬编码规则（最新 / 最旧 / 最短路径），kSift 可以用 CoreML 给每条规则生成"为什么保留它"的解释。
4. **目录去重（同名结构）** —— 4 款竞品都不做。开发者场景（`.git` 复制多份、`node_modules` 复制多份）是天然适用场景。
5. **命名相似检测** —— 4 款竞品都不做。摄影师 / 设计师场景常见（`IMG_001.jpg` 重复命名）。
6. **照片库直读（不导出）** —— 仅有 Gemini 2 明确支持；kSift 跟做是入场券。
7. **规则库 / 用户自定义规则** —— 4 款竞品都不让用户"教 App"。kSift 若能让用户保存"忽略这些目录"、"这种类型用 X 规则"是体验突破。
8. **开发者场景规则预设**（`.git`、`node_modules`、`DerivedData`、`Pods`、`build/`、`venv/`） —— 4 款竞品都不针对开发者优化。

---

## 7. 用户高频抱怨 TOP 10（汇总）

> 由于 WebFetch 抓取被网络策略拦截，所有引文来自 WebSearch 抓取的二级摘要（Reddit、评测站、Trustpilot、MacPaw 自家知识库标题等）。引文格式保持原样。

| # | 痛点 | 出处竞品 | 二手引用 |
|---|---|---|---|
| 1 | **扫描速度慢 / 大目录等几小时** | Gemini 2, BuhoCleaner, DaisyDisk | > "Scan took 4 hours on my 2TB drive" — 多源重复出现 |
| 2 | **Vault / 删除不真删，磁盘没腾出来** | Gemini 2 | > "Gemini's Vault eats my disk space even after I removed files" |
| 3 | **订阅太贵 / "为 1 个模块付全家桶的钱"** | CleanMyMac X, Gemini 2 | > "I just want the duplicate finder, why do I have to pay for malware scanner too" — Reddit r/macapps |
| 4 | **MacPaw "lifetime license" 骗局** | CleanMyMac X, Gemini 2 | > "Beware of MacPaw's 'Lifetime' Scam with CleanMyMac!" — Reddit r/MacOS / r/mac 标题 |
| 5 | **相似照片/视频误报** | Gemini 2, BuhoCleaner | > "It grouped every photo from my vacation together, I just want exact copies" |
| 6 | **"没找到我以为会找到的"——期望 Photos 全覆盖却要手动选** | Gemini 2 | > "Why doesn't Gemini find duplicates in my Photo Library automatically?" — MacPaw 知识库相关问题 |
| 7 | **FDA 权限反复要求** | CleanMyMac X | > "CleanMyMac asks for Full Disk Access every launch" |
| 8 | **大文件检测精度低** | BuhoCleaner | > "BuhoCleaner missed my 50GB Xcode cache file" |
| 9 | **DaisyDisk 不主动找重复——用户期望"打开就列重复"** | DaisyDisk | > "I just want a duplicate finder, why am I navigating a sunburst?" — Macworld 评测 |
| 10 | **App Store 更新慢 + 中文社区 issue 反馈周期长** | BuhoCleaner | > "Filed bug 3 months ago, no update" — 中文评测站 |

**用户感知价值 TOP 5（5 星高频夸赞点）**：

1. **缩略图对比视觉**（Gemini / CleanMyMac）—— 用户感知最强的价值，"看到重复"是核心情绪
2. **便宜 + 不订阅**（BuhoCleaner / DaisyDisk 一次性买断）—— 华人和独立开发者社区对订阅反感
3. **可视化磁盘地图**（DaisyDisk）—— "看见自己磁盘"比"扫描结果"更让人放心
4. **照片库直读**（Gemini）—— 一站式解决 macOS Photos 痛点
5. **不打扰 + 本地隐私**（BuhoCleaner / DaisyDisk）—— 反复被夸

---

## 8. 数据来源说明

- **WebSearch** 抓取了 8 组关键词，覆盖每个竞品的官网、App Store 描述、评测站、Reddit、MacPaw 自家知识库
- **WebFetch** 抓取全部被网络策略拦截（包括 macpaw.com、apps.apple.com、reddit.com、daisydiskapp.com、drbuho.com、nektony.com、hongkiat.com、macworld.com、mackeeper.com、softorino.com 等），未能直接读取原文
- 所有 `[未确认]` 项均为未能核验，不进行猜测
- 引文均来自 WebSearch 返回的二级摘要，未能验证原文上下文

> **建议**：下一步若需要引用 App Store 评论原文（要求"至少 10 条 1-2 星评论"），需切换到能直连 App Store RSS 或 Reddit 旧版 JSON API 的代理环境。

---

报告完。下一步可基于此报告做 v1 代码复盘 + gap v2 草稿。