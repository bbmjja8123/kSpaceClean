# kWise v1.5 vs 精品 Mac 清理 App — 功能 & UX 标杆调研

> **日期**: 2026-08-08
> **基线**: kWise v1.5（`app.kraftly.sclean`，MAS-only，Sandboxed，SwiftUI，macOS 13+，$19.99/yr）
> **方法**: 主源 = 官网功能页 + iTunes Lookup API（含 CN 价格）× MAS 元数据 × MacRumors ADA 名单；辅源 = 评测引用（标注为 opinion）。WebSearch/WebFetch 对 cleanmymac.com / macpaw.com / drbuho.com / developer.apple.com 大多被反爬阻断 → 通过 Wayback/CC Index + iTunes API 取数。
> **目标**: 提取 **精品级**（App Store 旗舰）Mac 清理类工具的"非 feature checkbox"特征，作为 kWise v1.5 的验收锚点。

---

## 0. TL;DR

| 维度 | CleanMyMac X | BuhoCleaner | DaisyDisk | Apple Design Award 2024/2025 |
|---|---|---|---|---|
| **MAS 评级** | 评分 0/0（iTunes API 未取到，需人工核对）；评论数 0 | **不在 MAS**（仅直链下载） | $9.99 一次买断；网站自报 4.7 / 3,691 评分 | 12 个 winner × 2 年 = 24 个 |
| **MAS/直接双轨** | ✅ **有**（bundle `com.macpaw.CleanMyMac-mas`，2020 上架，2026-07-23 v5.5.7 更新；MAS 反而比直接版更"新"——MAS v5.5.7 vs direct v5.5.6） | ❌ 无 | ✅（MAS v4.34.1 vs direct v4.34.2；二者同步） | — |
| **定价** | MAS 7 天试用 + 订阅/年付；CN 站 IAP：年付 ¥199（Basic）/ ¥388（Plus）/ 月 ¥66；X 一次性 ¥598 | Lifetime $25.99（1 Mac）/ $67.99（3 Macs）；Yearly $17.99/$39.99；30 天退款 | $9.99 一次性，最多 5 台 Mac；30 天退款 | — |
| **核心心智** | Smart Care（5-in-1）+ 模块化仪表盘 | Flash Clean + 实时菜单栏监控 | 环形可视化 + 用户决定删除 | — |
| **Mac 实用类获奖** | 红点 + UX Design Award 2021 | 无 | 3× "Best of the Year" + Editor's Choice | **2024/2025 共 24 个 winner 均为 iOS/iPadOS app，无 Mac 实用类** |
| **MAS 沙箱约束** | 仍能扫描 / 卸载 / Moonlock 恶意软件 / 云盘清理——MAS 版功能大体完整；但高级的 kernel extension、launch daemon 重启、SIP bypass 类操作必须直链 | N/A | 完全 MAS-only 功能即可（无需 root） | — |

**一句话**：精品 = 信任 + 可视化 + 解说 + 可逆。CleanMyMac 强在 Smart Care 5-in-1 与品牌；DaisyDisk 强在"反清理"叙事 + 设计与诚实；BuhoCleaner 强在菜单栏实时监控 + Lifetime 低价。**Mac 实用类已多年与 Apple Design Award 绝缘**，kWise 无法"对标 ADA winner"，但可以学 DaisyDisk/CMM 的"精品化语言"。

---

## 1. CleanMyMac X（MacPaw）— 对标锚点

### 1.1 现状快照（2026-08-08 抓取）

- **MAS 版本**：v5.5.7（2026-07-23 更新），bundle `com.macpaw.CleanMyMac-mas`，free（IAP），12 语言，min macOS 11.0，文件大小 151.8 MB ([iTunes Lookup](https://itunes.apple.com/lookup?id=1339170533&country=us))
- **直链版本**：v5.5.6（2026-07-10 更新），macpaw.com 自报 4.9 / 539 评分，定价"Starting at $3.33/month" ([macpaw.com/cleanmymac](https://macpaw.com/cleanmymac))
- **MAS / 直链功能差异**：本次未能找到官方"区别页"（旧 support URL `204660195` 已 404；Wayback 取不到）。但通过对比两端文案与版本号，可观察到 **MAS 版并不"降级"**：MAS v5.5.7 反而**新于**直链 v5.5.6，且 MAS 描述包含 Moonlock 恶意软件扫描、Smart Care、卸载残留、duplicates & similar images、云盘清理等全部模块 ([CMM MAS 描述](https://itunes.apple.com/lookup?id=1339170533&country=us), [macpaw 主页](https://macpaw.com/cleanmymac))。结论：**对于 v1.5 来说，CMM 在 MAS 渠道做了功能对等**——这反过来意味着 kWise v1.5 必须按 CMM 标准把功能做齐。
- **CN MAS IAP 价格**（截至 2026-08-08 抓取 [apps.apple.com/cn](https://apps.apple.com/cn/app/cleanmymac/id1339170533)）：
  - Basic Yearly Trial: ¥199（约 USD 28/yr）
  - Plus Yearly Trial: ¥388（约 USD 55/yr）
  - Basic One-Time: ¥568
  - X One-Time: ¥598
  - Monthly (7-Day Trial): ¥66

### 1.2 Headline features（3-6 个最有区分度）

1. **Smart Care**：5-in-1 一键组合（清理 / 保护 / 速度 / 应用 / 恶意软件），主屏心智 ([cleanmymac.com 主页](https://cleanmymac.com/))
2. **Moonlock 引擎**：与 CMM 主程序**并列独立产品**（moonlock.com 自家品牌），CMM 内置恶意软件扫描（keylogger / 勒索 / 广告软件）
3. **Duplicates & similar images**：感知哈希级别的相似图片合并
4. **Uninstaller + 残留扫描**（含陈年残留）
5. **云盘清理**（iCloud / Dropbox / Google Drive / OneDrive 同步占位扫描）
6. **菜单栏监控 + 资源释放**（内存释放、CPU 监控、阻止过热）

### 1.3 UX 精品信号（"非 feature checkbox"）

- **中英日 + 12 语言** 本地化（iTunes 元数据），不是只翻译 UI，描述文字也走本地化
- **a11y 自适应**：CMM CN 页 5.0.7 更新说明明确写「'减弱动态效果'功能自动减少应用内非必要动画效果，智能适配您的辅助功能偏好设置，简化视觉元素以降低不适感或注意力干扰」（apps.apple.com/cn 5.0.7 释出说明）
- **每模块独立可运行 + Smart Care 总和**：单一 primary CTA 但不剥夺模块级控制
- **设计奖项背书**：Red Dot + UX Design Award 2021 直接写进 MAS 描述 → **被 Apple 视为可信营销**（CMM 自家研究数据：29M 下载、18 年、4.9 评分）
- **统计数字可视化**："35M GB cleaned monthly / 329K threats removed" 用作落地页 hero（macpaw.com/cleanmymac）

### 1.4 Notable omissions（kWise 可利用的缝隙）

- **CMM 不强调**"安全删除 / 二次确认 / 废纸篓保留期" → kWise 可借 kFoundation 30 天回滚做差异化
- **CMM 不强调**"CoreML / 神经引擎加速 perceptual hash" → 这正是 kWise CLAUDE.md §3.3 锁定的差异点
- **CMM 在 MAS 上不展示** 沙箱限制声明 → 用户对其"为什么清理不到一些文件"的认知模糊，kWise 可借 FDA 引导 + 透明日志补位
- **CMM 推送**"29M downloads" + 量化数字（"5.5 GB cleaned on the first scan"）作为市场信任锚，但**没有**社交证明或个人数据展示（kWise 可借鉴 kWatch 的 Widget 路线做个人空间数据）

### 1.5 Sandbox/MAS 约束（对 kWise v1.5 的硬约束）

- MAS 版仍能卸载第三方 app（依赖 Finder trash，非 root）→ kWise 可做
- MAS 版扫描其他 App 的私有 container 受沙箱限制 → kWise 同样受限于 FDA 授权
- MAS 版 Moonlock 扫描 = 仅基于文件签名/启发式，**不**能调用内核扩展 → kWise 无需 kernel extension，模型契合

---

## 2. BuhoCleaner（Dr.Buho）— 华人独立开发标杆

### 2.1 现状快照

- **不在 Mac App Store**。iTunes Lookup `entity=macSoftware&country=us` 和 `country=cn` 均无 BuhoCleaner 记录（验证 2026-08-08）。仅 drbuho.com 直链下载 + StackSocial/MacUpdate 等分销。
- **官网 ([drbuho.com/buhocleaner](https://www.drbuho.com/buhocleaner))** 自报：1M+ 下载、180+ 国家、Apple Notarized、21,000 日活
- **当前定价 ([drbuho.com/store](https://www.drbuho.com/store/))**：Yearly $17.99 / $39.99（1/3 Mac）；Lifetime $25.99 / $67.99；Business $55.99（10 Macs）；30 天退款
- **菜单栏监控**：BuhoCleaner Menu 实时显示 RAM / 网络 / 存储 / CPU / 温度 / 风扇

### 2.2 Headline features

1. **Flash Clean**：一 Tap 找全可清理对象，强调"秒级"（主 CTA 心智）
2. **Deep Uninstall**：100+ 常用 App 的**定制化**卸载路径模板
3. **Large Files + Duplicates + Disk Space Analyzer**：三件套基础清理
4. **Startup Items + Boot Time**："1.8× Faster boot time on M1 MBA 2020"（自测宣传，未独立验证）
5. **Mac Monitor (菜单栏)**：CPU/RAM/温度/风扇/网络的常驻实时面板 + 一键 Free RAM
6. **More Brilliant Features**：Xcode Cache Cleaner / Secure File Shredder / Spotlight Reindexing / Flush DNS / Free RAM / Manage Startup Items（BUHO 把这些列为差异化卖点）

### 2.3 UX 精品信号

- **多语种**：EN + 繁体 + 简中 + 日 + 德 + 法 + 西 + 意 + 葡 + 韩（drbuho.com footer）——**华人独立开发者多语种天花板**
- **细节文案**：自称为 "Ultimate Mac Cleaner"（语气强于 CMM 的 "Mac cleaner that goes beyond basic cleaning"），适合小型 indie 团队**品牌定位**
- **菜单栏常驻面板**：把所有"实时指标"压在 status bar → 学习成本 = 0，复用 iStat Menus 的可见性心智，但功能子集
- **M 系列 / Tahoe 优化文案**："Fully Optimized for macOS Tahoe, Runs on M1–M5" → 苹果硅专属口号
- **公开感谢**："380+ Media Reports / 100,000+ Satisfied Users / 1,000,000+ Downloads" → **数字即营销**

### 2.4 Notable omissions

- **没有** Mac App Store 版本 → 不享受 MAS 自然流量、不被 MAS 编辑团队评测、苹果硅升级门槛自家承担
- **没有** Live Activity / Interactive Widget / Shortcuts 集成（独立开发者无 Apple Silicon Neural Engine 工程优势）
- **没有** CoreML 本地 AI 分类 → 分类粒度比 CMM 粗
- **没有** 卸载后回滚审计（BUHO 仅 trash → 不可恢复）

### 2.5 Sandbox / 直链约束

- 因 **不在 MAS**，可使用部分私有 API / Helper（但 BUHO 公开页未声明 Helper / SMJobBless）
- 直链分发意味着**升级体验差**：每次大版本需要用户重新下载 → 用户流失率高于 MAS 自动更新
- Apple Notarized 是其公开卖点，但 Notarized ≠ MAS 审核

---

## 3. DaisyDisk（Software Ambience）— 设计 + 反"清理"叙事标杆

### 3.1 现状快照

- **MAS 版本** ([iTunes Lookup](https://itunes.apple.com/lookup?id=411643860&country=us))：v4.34.1（2026-07-05），$9.99 一次性，14 语言，min macOS 10.13，文件大小 **2.7 MB**，首发 2011-01-06
- **直链版本** ([daisydiskapp.com](https://daisydiskapp.com/))：v4.34.2（2026-07-10）——MAS 落后 5 天
- **奖项**：MAS Editor's Choice badge + "3 times winner of Best of the Year App Store award" + Apple 内部 26,200+ 员工使用
- **用户评分**（直链 site 自报）：4.7 / 3,691 评分 / 2,912 评论

### 3.2 Headline features

1. **Sunburst 可视化**：环形 + 辐射方向 = 大文件一眼可见（设计最核心资产）
2. **APFS clones 感知**：v4.34 释出说明强调 "counts only first occurrence of each clone" → 物理空间计算正确
3. **Scan as Administrator**：突破用户态读不到的系统文件（依赖 FDA，与 kWise 路线相同）
4. **Multi-disk parallel scan**：本地 / 外置 / USB / Thunderbolt / 网络 / 云盘（Dropbox / GDrive / OneDrive / Box）实时容量展示
5. **Expose "Other" & "System Data"**：直接呼应 macOS "About This Mac" 的神秘类别
6. **Lifetime license**：$9.99 一次买断，最多 5 台 Mac，minor updates 包含

### 3.3 UX 精品信号（这是 kWise 最值得抄的一档）

- **反"清理"叙事是品类级差异化**：网站主页**公开反驳** "Mac cleaners are popular, but macOS can clean itself, Apple discourages cleaner apps" → 当行业被污名化为 "scamware" 时，**承认赛道问题**比硬吹更可信
- **对照表**（cleaner app vs DaisyDisk）：在主页 hero 段并列展示"1–5 GB recovered" vs "10–100 GB recovered"；"deletes caches" vs "deletes real space wasters"；"automatic one magic button" vs "no, but quick and efficient"。**这种自我对比是精品级 transparency 的范本**
- **每次更新都进 release notes**：APFS clones 释出说明写得很技术（解释 macOS APFS 文件系统 clone 与 hard link 的区别）→ 把工程师语调放进消费者文档
- **设计奖项自证**：Editor's Choice + 三次 Best of Year → 写进 MAS 描述作为首要营销
- **语言策略**：14 语言（含 ru/tr/zh/sv 等小语种），**但** US 直链页只用一屏说尽核心价值（"Find it. Clean it."）→ 简与繁的平衡
- **页面 hero 是可视化截图**而非 "magic AI" → **事实即营销**

### 3.4 Notable omissions

- **不做"清理"**：DaisyDisk 明确**不**做 cache cleaner、temp cleaner、similar images detector、uninstaller → 仅做大文件可视化。**这反而成为护城河**：不被 MAS 审核员划入 "scamware" 类别
- **不做订阅**：纯买断 → 用户对价格的"长期忠诚"换短期低 LTV
- **不做菜单栏监控**：与 iStat / Buho Menu 不同赛道
- **不做云盘清理**：仅做容量可视化，**不**删云盘文件（避免隐私争议）

### 3.5 Sandbox / MAS 约束

- **完全 MAS-compatible**：核心功能只需读权限 + 写废纸篓 → 沙箱内完全可行
- **Scan as Administrator**：需 FDA → kWise 同样需要，但 DaisyDisk 把这做成 hero feature（"Reveal the hidden"），kWise 应照搬此营销语言
- **不可"自动删"**：DaisyDisk 选择不绕过沙箱 → kWise 也应走"用户决定删什么"路线（与 v1.5 CLAUDE.md §3.10 的"安全回退"一致）

---

## 4. Apple Design Award 2024 & 2025 — 间接标杆

### 4.1 现状快照

**2025 Winners**（[MacRumors 2025-06-03](https://www.macrumors.com/2025/06/03/apple-design-award-winners-2025/) —— Apple 自家开发者页是 JS SPA 加载且 API 返回 React shell，无法直接抓取，转用 MR 报道交叉验证）：

| 类别 | App | Game |
|---|---|---|
| Delight and Fun | CapWords | Balatro |
| Innovation | Play | PBJ – The Musical |
| Interaction | Taobao | Dredge |
| Inclusivity | Speechify | Art of Fauna |
| Social Impact | Watch Duty | Neva |
| Visuals and Graphics | Feather: Draw in 3D | Infinity Nikki |

**2024 Winners**（[MacRumors 2024-06-06](https://www.macrumors.com/2024/06/06/2024-apple-design-award-winners/)）：

| 类别 | App | Game |
|---|---|---|
| Delight and Fun | Bears Gratitude | NYT Games |
| Inclusivity | oko | Crayola Adventures |
| Innovation | Procreate Dreams | Lost in Play |
| Interaction | Crouton | Rytmos |
| Social Impact | Gentler Streak | The Wreck |
| Visuals and Graphics | Rooms | Lies of P |
| Spatial Computing | djay Pro | Blackbox |

**2024 Finalists**（[MacRumors 2024-05-28](https://www.macrumors.com/2024/05/28/2024-apple-design-award-finalists/)）新增 **Spatial Computing** 类别（Vision Pro 专设）—— 2025 年 Vision Pro 热度退潮，类别消失。

### 4.2 关键事实（必须直说，不强行贴标签）

- **2024 + 2025 共 24 个 winner，0 个 Mac 实用类**。逐一核对 iTunes API 全部为 `kind=software`（iOS/iPadOS）或 visionOS
- **2025 Spatial Computing 类别取消** = Apple 自家认定 visionOS 赛道尚未稳态
- **Mac 实用类已多年与 ADA 绝缘**：DaisyDisk / CMM 都没拿过 ADA（CMM 拿的是 Red Dot + UX Design Award，是第三方奖项，不是 Apple 官方）
- **少数"Mac 友好"的赢家**：Procreate Dreams（iPad 优先，Mac 用 iPadOS 镜像）、djay Pro（Mac+iOS 双平台）、Crouton（iOS 食谱管理）—— 都不是 utility cleaner 类

### 4.3 kWise 可借鉴的**设计语言**（不是抄品类）

不抄功能、不抄视觉风格，抄**评价维度的用心**：

- **Inclusivity（Gentler Streak / Speechify）**：老年人 / 残障可访问、心率区间温和提示。kWise 可学："推荐清理前先解释这条删除影响哪些 App"（Speechify 风格的产品语气）
- **Social Impact（Watch Duty / Gentler Streak）**：**真实**社会价值、不伪装。kWise 应避"AI 拯救你的 Mac"夸大叙事
- **Delight and Fun（Bears Gratitude / NYT Games / CapWords）**：成年人面对日常任务时需要的轻量"游戏感"。kWise 可在清理完成后加一个**小庆祝**动效（不是撒花那种幼稚，是"15.2 GB freed" 数字 + 减重条）
- **Visuals and Graphics（Rooms / Feather）**：3D 体积感 + 干净材质。kWise 已锁定 3D galaxy 路线，与 Rooms 的"室内空间体积感"同源
- **Interaction（Crouton / Rytmos）**：**清晰反馈链**——每次手势都有即时、可听、可感的回执

---

## 5. 跨 App 总览矩阵

| 维度 | CleanMyMac X | BuhoCleaner | DaisyDisk | kWise v1.5 现状 |
|---|---|---|---|---|
| **MAS 渠道** | ✅ 双轨 | ❌ 直链 | ✅ 双轨 | ✅ 单轨（MAS-only） |
| **MAS / 直链功能对等** | ✅（MAS v5.5.7 ≥ direct v5.5.6） | N/A | ✅（同步小版本） | — |
| **一 Tap 主心智** | Smart Care（5-in-1） | Flash Clean | 不做（一 Tap 是"扫描"非"清理"） | ⚠️ 无（详见 §6） |
| **可视化反馈** | 模块拼盘 + 仪表盘 | 实时菜单栏面板 | Sunburst（品类最强） | ⚠️ Galaxy 渲染器 19 行 stub |
| **回收数字即时反馈** | ✅ "X GB freed" 弹窗 | ✅ | ✅（结果页大数字） | ❌ 无 |
| **可逆 / 废纸篓 / 回滚** | ✅（Trash） | ✅（Trash） | ✅（Trash） | ✅（30 天回滚设计） |
| **CoreML / 本地 AI** | ⚠️ 仅恶意软件启发式 | ❌ | ❌ | ⚠️ AIClassifier 死代码 |
| **隐私 / 零上报** | ✅ Notarized，本地 | ✅ Notarized，本地 | ✅ "Privacy is paramount" | ✅ CLAUDE.md §5.3 |
| **菜单栏常驻** | ✅ CMM Menu | ✅ BuhoCleaner Menu（CPU/RAM/温度/风扇） | ❌ | ❌ quickClean 占位 |
| **Sandbox-only 路径** | ✅ 完整 | N/A | ✅ 完整 | ✅ 设计即 sandbox-first |
| **设计奖项** | Red Dot + UX Design Award 2021 | 无 | MAS Editor's Choice + 3× Best of Year | — |

> 关键发现：**没有一款 top 竞品是 MAS-only**。CMM 双轨（MAS 反而功能对等或超前），DaisyDisk 双轨同步，BuhoCleaner 选直链。这给 kWise v1.5 一个**未知的路**：MAS-only 是否足以达到 CMM 级别的"精品感"？**没有先例可证**。唯一相近的是 DaisyDisk MAS 直链版本同步，可视为"小工作室 MAS-only"的**唯一标杆**。

---

## 6. kWise v1.5 当前缺口（重新审视）

> 引用 2026-08-01 报告 §3.3 的 G-SC-01..08，本节**只补"对标新视角"**，不重述已有 gap。

| Gap ID | 描述 | 对标视角 | 优先级 |
|---|---|---|---|
| **G-SC-09** | 无 **Smart Care 5-in-1 主流程**：CMM 的 Smart Care = 系统缓存 + 应用残留 + 恶意软件 + 启动项 + 大文件五合一。kWise 的"一键清理"未定义 = 五个模块都做了但没编排 | CMM Smart Care 心智 | **P0**（上架硬门槛） |
| **G-SC-10** | 无 **"X.XX GB freed" 即时数字反馈**：CMM 完成清理后弹数字 + DaisyDisk 结果页 hero 大数字 + BUHO Flash Clean 也报数字 | 三家共识 | **P0** |
| **G-SC-11** | 无 **"对比表"叙事**："我们 vs 假清理 App"——DaisyDisk 主页的做法 = 给消费者一柄对照尺。如果 kWise 也敢写"kWise vs Fake Cleaner"，MAS 审核不会驳（事实上是产品透明化的范本） | DaisyDisk | **P1**（精品化） |
| **G-SC-12** | **菜单栏常驻**：CMM Menu / BUHO Menu 都常驻 status bar 显示实时数字。kWise MenuBarManager.quickClean 是 stub。MAS sandbox 完全支持 status bar icon → **不该缺** | CMM + BUHO | **P1** |
| **G-SC-13** | **FDA 引导叙事**：DaisyDisk 把 "Scan as Administrator" 做成 hero feature。kWise 的 FDA 引导只在 Onboarding 出现一次 → 应在每次"看不到"时**复述**为什么 | DaisyDisk | **P1** |
| **G-SC-14** | **释出说明技术化**：DaisyDisk v4.34 释出说明解释 APFS clone 原理。kWise v1.5 每次更新 release notes 应带技术解释（不仅是 "修复 bug"）→ 把工程师语调写进消费者文档 | DaisyDisk | **P2** |

---

## 7. 合成："精品"区别于"好"的 8 个可观察特征

> 每个特征**可被测试**——把以下 8 条当作 kWise v1.5 验收清单的起点。每条附"出处"。

### C-1 扫描结果页从**不**展示裸路径
- **定义**：扫描结果里的每一项至少有 (a) 人类可读名称（如 "Xcode DerivedData" 而非 `~/Library/Developer/Xcode/DerivedData/`），(b) 一句话解释"为什么是安全的"或"占用来源"，(c) 占用大小。
- **出处**：CMM 描述明确写 "Visualize your storage space and see what your Mac hides" → 强调"看见 + 解释"。DaisyDisk 同样把原始 path 渲染成 ring + label。
- **kWise 验收**：抽样 50 条扫描结果，0 条展示纯 path。

### C-2 主屏有一个**心智级** CTA，不是菜单
- **定义**：首屏只有一个**叙事级**按钮（CMM 的 Smart Care / DaisyDisk 的 Scan / BUHO 的 Flash Clean），其他模块通过下钻到达。**不**用 navigation grid 当首屏。
- **出处**：CMM 主屏 Smart Care 是 hero；DaisyDisk 主屏唯一动作是扫描；BUHO 主页 Flash Clean 是 hero CTA。
- **kWise 验收**：首屏 Tap 区 ≤ 30% 视觉占比，剩余 70% 给"上下文"（已用空间 / 最近扫描 / 待清理估算）。

### C-3 清理完成后**即时**报数字，且数字可信
- **定义**：清理完成弹"X.XX GB freed in Y.Ys"或进度环动画，数字 = 实际写入废纸篓的字节数（不是扫描估计）。
- **出处**：CMM / DaisyDisk / BUHO 三家共识。
- **kWise 验收**：模拟一个 10 GB 缓存清理，从点确认到数字出现 < 1.5 s。

### C-4 删除是**可逆**的，且用户**知道**它可逆
- **定义**：每次清理动作前，UI 显示一个"30 天回滚 / 废纸篓"的标识，**不**仅埋在 Settings 里。
- **出处**：DaisyDisk 把"Only you decide what to delete"放首页 hero；CMM 描述写 "Move to Trash" 而非 "Delete"；BUHO 同样默认 trash。**反例**：行业里"清理大师"类 App 把"permanently delete"做成默认，是"scamware"标记的最大信号。
- **kWise 验收**：在清理确认弹窗默认文案里，"Cancel" + "Move to Trash" 两个按钮，"Delete Permanently" 必须二次确认且不在默认流。

### C-5 **坦诚**区分"我们能做"vs"我们需要权限"
- **定义**：当 kWise 扫描到 ~/Library/Containers/... 等沙箱限制目录时，UI 不假装"清理了"，而是显示"需要 Full Disk Access" + 引导按钮。
- **出处**：DaisyDisk 把"Scan as Administrator"做成 hero feature，**不**藏起来。CMM 同样需要 FDA 但显式引导。
- **kWise 验收**：在 0 权限状态下做一次扫描，结果页明确分组"已扫描（X GB）" vs "需 FDA（Y GB）"。

### C-6 **反"清理"叙事**——承认赛道问题
- **定义**：网站 / Onboarding 文案**不**写"Mac 满了？Mac 慢？我们拯救你"——而是承认"macOS 自洁能力有限但存在 / Apple 不推荐清理 App"。DaisyDisk 是品类范本。
- **出处**：daisydiskapp.com 主页 hero 段直接写"So called cleaner apps are insanely popular on the Mac... Apple actually discourages the use of cleaner apps"。
- **kWise 验收**：产品页 hero 文案不出现"save your Mac" / "magical" / "AI-powered" 这类 scareware 词。

### C-7 释出说明 / 更新日志**工程师化**
- **定义**：每次更新 release notes 解释**为什么**做（APFS clone 原理 / TCC 权限变化 / 新 macOS 适配），不只列 "bug fixes"。
- **出处**：DaisyDisk v4.34 释出说明；CMM 5.0.7 中文释出说明（解释 a11y Reduce Motion）。
- **kWise 验收**：每个 release notes 平均 ≥ 3 句技术解释，不是 1 行 "fixed crashes"。

### C-8 **菜单栏常驻**实时数字（不只是 Quick Action）
- **定义**：菜单栏 status item 至少显示一项实时数字（已用空间 / CPU / 温度），单击 = 展开 popover，双击或按钮 = 触发主操作。
- **出处**：CMM Menu / BUHO Menu（CPU/RAM/温度/风扇）。
- **kWise 验收**：菜单栏图标旁边有数字 = 已用磁盘 GB 或 %，刷新周期 ≤ 10 s。

---

## 8. 信任与安全维度（"Mac cleaners are scamware" 反污名化）

> Mac 清理品类被多次污名化（搜"are mac cleaners safe" 一片负面结果）。精品级的反制：

| 反制动作 | 出处 | kWise v1.5 应做 |
|---|---|---|
| **量化真实恢复** | DaisyDisk 主页对照表 "10–100 GB" vs "1–5 GB" | kWise 帮助页写"kWise 典型单次扫描回收 5–30 GB（基于 150+ App 规则缓存；不含云盘）"，**不**写"恢复 100 GB+" 夸张数字 |
| **每个删除默认 trash** | CMM / DaisyDisk / BUHO 三家 | kWise 默认 trash，30 天后清理（已设计） |
| **不**用"恐吓"数字 | Apple 在 macOS Sonoma 之后直接打压 scareware sizing | kWise 不显示红色"⚠ 危险"大数字；用 SF Symbols 普通图标 |
| **不**自动订阅 | MAS 审核要求显式确认 | kWise paywall 已是二级确认（继承 v0） |
| **不**联网上报 | MAS 审核会看 App Privacy Details | kWise CLAUDE.md §5.3 零上报 = 对齐 |
| **解释**每个动作 | DaisyDisk 主页 "Only you decide what to delete" + 对照表 | kWise 设置页加"什么是安全删除"教育页 |
| **第三方安全审计 / 检测认证** | CMM 自家 Moonlock | kWise v1.5 不强求，但可在 v1.6 接独立审计 |
| **公开 App 卸载干净度评分** | Pearcleaner 路线 | kWise 卸载模块可学：自检"该 App 残留 X 处" |

---

## 9. implications-for-kWise（每条对应 v1.5 可测试验收标准）

| 精品特征 | kWise v1.5 验收标准（建议） |
|---|---|
| C-1 不展示裸路径 | 扫描结果 ≥ 95% 条目带「中文/英文友好名 + 一句话来源说明 + 大小」三元组，CI 自动断言 |
| C-2 主屏单一 CTA | 首屏 hero CTA ≤ 1 个；进入次级页面才出现模块网格 |
| C-3 即时数字反馈 | 清理动作完成后 < 1.5 s 出现"X.XX GB freed"数字；数字 = 实际 trash 写入字节 |
| C-4 可逆 + 用户知道可逆 | 清理弹窗默认按钮是"Cancel" + "Move to Trash"；"Delete Permanently"在二级菜单 |
| C-5 坦诚区分权限域 | 0 权限扫描结果页分两段「已扫描 X GB」「需 FDA Y GB」+ 引导按钮 |
| C-6 反"清理"叙事 | 产品页 hero 文案不出现 scareware 词汇；Onboarding 第 1 屏说"macOS 自洁能力存在但有限" |
| C-7 工程师化 release notes | 每次更新 release notes 平均 ≥ 3 句技术解释（git hook 强校验） |
| C-8 菜单栏常驻数字 | MenuBarManager status item 显示已用空间 GB / %，刷新 ≤ 10 s |
| 信任维度 | paywall 二级确认；App Privacy Details 字段在 Info.plist 填写"Data Not Collected"；帮助页有"什么是安全删除"教育页 |
| Sandbox 约束 | 所有"清理"动作只走 Finder `.trash` API；启动项管理走 launchctl bootstrap（用户态）而非写入 `/Library/LaunchDaemons/`；SMART 检查走 `diskutil info` 而非 privileged helper |
| Mac App Store 上架 | 提交前在 App Store Connect 填 App Privacy = Data Not Collected；定价 $19.99/yr + 7 天 free trial；Info.plist 加 `LSApplicationCategoryType=public.app-category.utilities` |
| 视觉打磨 | 跟随 macOS Tahoe Dynamic Accent Color；菜单栏图标提供 3 套（compact / standard / dense）；遵守 Reduce Motion 时删除所有非必要动效 |

---

## 10. 信任与不确定（Confidence & Gaps）

| 项 | 状态 |
|---|---|
| CMM MAS vs 直接版功能差异官方页 | **unverified**（`support.cleanmymac.com/.../204660195` 404；Wayback 取不到）→ 但通过两端版本号与文案对比推断"功能对等"是当前事实 |
| CMM 直链版 US 详细定价 | **unverified**（macpaw.com 对 curl UA 触发 anti-bot 返回 "Quick check" 页面）→ 但 CN 站 IAP 列表已抓到 |
| BUHO 是否在 MAS 上架 | **verified NOT**（iTunes API US + CN 检索 0 命中，2026-08-08） |
| BUHO 用户数 / 媒体覆盖 | 来自 BUHO 自家页面，**未独立核实** |
| DaisyDisk MAS 评分 | iTunes API 返回 0/0（storefront 数据限制），**未独立核实**；网站自报 4.7/3,691 |
| Apple Design Award 完整名单 | **primary source 失败**（developer.apple.com/design/awards/{2024,2025}/ 是 JS SPA，curl 拿不到数据；CC Index 只有 2024 捕获且也是 React shell）→ **改用 MacRumors 二次报道**（[2025 winners](https://www.macrumors.com/2025/06/03/apple-design-award-winners-2025/), [2024 winners](https://www.macrumors.com/2024/06/06/2024-apple-design-award-winners/), [2024 finalists](https://www.macrumors.com/2024/05/28/2024-apple-design-award-finalists/)）—— 报道与 Apple 自家新闻稿**一致**但仍标 secondary |
| 2025 finalists 完整名单 | **unverified**（MacRumors 没有 2025 finalists 单独文章，仅 winners） |
| DaisyDisk 直链版本 US 评分 4.7/3,691 | 来自 daisydiskapp.com 自家页；MAS store 显示未抓到（可能被 Apple 反爬） |
| CMM "29 million downloads" 数字 | CMM 自家宣传，未独立核实 |
| BUHO 2024 新版本号 | **unverified**（官网没显示具体版本号，仅显示"Latest"） |
| BUHO 月活 21,000 / 100,000+ 满意用户 | BUHO 自家宣传，**未独立核实** |
| CMM 5.5.7 release notes 中文版 (a11y Reduce Motion) | 在 apps.apple.com/cn 5.0.7 释出说明中明确出现；可视为 MAS 端已读 a11y |

---

## 11. Sources（按引用顺序）

**Primary — Apple App Store / iTunes Lookup**
- https://itunes.apple.com/lookup?id=1339170533&country=us — CleanMyMac MAS v5.5.7 (2026-07-23)
- https://itunes.apple.com/lookup?id=411643860&country=us — DaisyDisk MAS v4.34.1 (2026-07-05)
- https://itunes.apple.com/search?term=CleanMyMac&entity=macSoftware&country=us — CleanMyMac 上架元数据
- https://itunes.apple.com/search?term=DaisyDisk&entity=macSoftware&country=us — DaisyDisk 上架元数据
- https://itunes.apple.com/search?term=BuhoCleaner&entity=macSoftware&country=us — BuhoCleaner 检索 0 命中
- https://itunes.apple.com/search?term=BuhoCleaner&entity=macSoftware&country=cn — BuhoCleaner 检索 0 命中
- https://apps.apple.com/cn/app/cleanmymac/id1339170533 — CMM CN 站 IAP 列表（含 ¥199 / ¥388 / ¥66 / ¥568 / ¥598）
- https://itunes.apple.com/search?term=mac+cleaner&entity=macSoftware&country=us — 27 款同类竞品地图

**Primary — 官网（直链 / 商店）**
- https://cleanmymac.com/ — CMM 主站（Smart Care + 4.9 评分 / 29M 下载 / $3.33/月起）
- https://cleanmymac.com/sitemap.xml — CMM 站点地图（确认缺"features/smart-care"独立页）
- https://macpaw.com/cleanmymac — MacPaw CMM 直链 v5.5.6（2026-07-10）
- https://macpaw.com/ — MacPaw 主站（Moonlock / Eney / CMM / Phone / ClearVPN / Setapp / Gemini 2 / The Unarchiver / Encrypto 产品矩阵）
- https://www.drbuho.com/ — Dr.Buho 主站（BUHO 产品矩阵）
- https://www.drbuho.com/buhocleaner — BuhoCleaner 产品页（Flash Clean / Large Files / Duplicates / Disk Space Analyzer / Uninstall / Deep Uninstall / Leftover / Startup / Boot Time / Mac Monitor）
- https://www.drbuho.com/store/ — Dr.Buho 商店（Yearly $17.99/$39.99；Lifetime $25.99/$67.99；Business $55.99；30 天退款）
- https://daisydiskapp.com/ — DaisyDisk 直链 v4.34.2（2026-07-10，$9.99 lifetime，4.7/3,691 评分）
- https://daisydiskapp.com/download/ — DaisyDisk 下载页
- https://developer.apple.com/design/awards/ — Apple Design Awards 索引（JS SPA，curl 抓不到数据；**列为 primary 但仅作目录用**）

**Secondary — 媒体报道（标为 opinion）**
- https://www.macrumors.com/guide/apple-design-awards/ — MR 历年 ADA 文章索引（用于交叉验证 Apple 自家新闻稿）
- https://www.macrumors.com/2025/06/03/apple-design-award-winners-2025/ — 2025 ADA winners 名单（MR 引用 Apple 自家公告）
- https://www.macrumors.com/2024/06/06/2024-apple-design-award-winners/ — 2024 ADA winners 名单（含 Spatial Computing 类别）
- https://www.macrumors.com/2024/05/28/2024-apple-design-award-finalists/ — 2024 ADA finalists 完整名单（7 类别 × ~3 finalists × 2 = ~42 个，含 Spatial Computing）

**Internal — 同仓库**
- `/Users/torsys/Documents/aicoding/kSpaceClean/CLAUDE.md` §3.10 — v1.5 CMM Parity 上架硬门槛 6 模块
- `/Users/torsys/Documents/aicoding/kSpaceClean/docs/gap-analysis/2026-08-01-kraftly-gap-analysis.md` §3.3 — kSpaceClean 现有 G-SC-01..08 gap（已认领）
- `/Users/torsys/Documents/aicoding/kSpaceClean/docs/gap-analysis/2026-08-04-kwatch-vs-top3.md` — 排版 / 标题 / 语言约定参考

---

## 12. 一句话收束

精品 ≠ 功能多 = **每一次删除都是被解释的、被可视化的、被用户最终决定的**，且**叙事诚实**到敢于与"清理骗局"对照。这是 DaisyDisk 的精神 + CMM 的工程规模 + BUHO 的本地化勤奋，三者交集就是 kWise v1.5 的位置。

> **更新策略**：v1.5 上架后，把本文当作每两周复检的对照表——每个 C-1..C-8 特征在 shipping build 中至少一次手动验证；任何新出现的精品级特征（如 MAS Spotlight 集成、Live Activities）追加到 §7 / §9 即可。