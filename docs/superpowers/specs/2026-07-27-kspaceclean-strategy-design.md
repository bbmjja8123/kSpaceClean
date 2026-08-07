# kSpaceClean 战略设计文档 v2 — 「无感融入 macOS」

> **背景**：基于 3 项调研结论（App Store 竞品 / Apple Design Awards 0-2026 / 护城河评估）形成的 kSpaceClean 产品战略再设计。
>
> **调研日期**：2026-07-27
>
> **战略方向**：方案 C — 实用主义型 / 中间路线
>
> **核心转向**：从「3D 视觉差异化驱动」转向「macOS 平台集成 + 实用清理功能驱动」，3D 视觉降级为辅助叙事。

---

## 1. 战略定位

### 1.1 一句话定位

> **Mac 上的「无感清理」— 不弹窗、不恐吓、不卡顿，融入 macOS 像系统自带。**

### 1.2 三大战略锚点（基于调研证据）

| 锚点 | 调研证据 | 战略含义 |
|---|---|---|
| **清理品类从未拿过 ADA** | ADA 2020-2026 全部获奖者无清理工具 | 这是"开创性新品类"机会窗口，Uniqueness 条款天然满足 |
| **平台集成是真实护城河** | Top 10 竞品（CleanMyMac/DaisyDisk/BuhoCleaner 等）均未做透 Widget/Shortcuts/Live Activity | "无感融入 macOS"是模仿成本最高的差异化 |
| **Apple Silicon + Metal + 零上传是评语点** | grug 评语："no login, no cloud, nothing extraneous"；RE Village 因 Metal 拿奖 | 把 3D 保留作为「About / 营销素材」，主视觉用 2D |

### 1.3 用户认知目标

| 不是 | 而是 |
|---|---|
| "它清掉了 5 GB" | "我的 Mac 又变快了" |
| "防病毒 + 安全扫描" | "我不用懂 macOS，它帮我保持干净" |
| "3D 旋转星系图" | "Finder 右键扫描 / 桌面 Widget 一键" |

---

## 2. 产品差异化矩阵

| 差异化点 | v1 定位 | 投入等级 | 评语可写性 |
|---|---|---|---|
| **2D Sunburst 主视觉** | 主界面 / 扫描结果可视化 | ⭐⭐⭐⭐ | 可写 "Apple Design Award–worthy data visualization" |
| **3D 磁盘星系图（降级）** | 「About / 营销视频 / ProductHunt 物料」独立 Tab | ⭐⭐ | 可写 "Metal-rendered galaxy on Apple Silicon" |
| **Finder 右键扩展** | 一等公民，P0 | ⭐⭐⭐⭐⭐ | 可写 "feels native to macOS" |
| **Shortcuts / App Intents** | 一等公民，P0 | ⭐⭐⭐⭐ | 可写 "automate with Apple Shortcuts" |
| **Interactive Widget (macOS 14+)** | 一等公民，P0 | ⭐⭐⭐⭐ | 可写 "operable Widgets" |
| **CoreML 本地分类** | 实用功能，不强叙事 | ⭐⭐ | 接口预留 Foundation Models（v2 升级） |
| **零网络 / 无账号 / 无遥测** | 核心价值观，App Privacy 写 "No Data Collected" | ⭐⭐⭐⭐⭐ | 可写 "nothing leaves your Mac"（grug 同款） |
| **Accessibility 四件套** | P0（VoiceOver / Dynamic Type / Increased Contrast / Differentiate Without Color） | ⭐⭐⭐⭐⭐ | 可写 "flawless VoiceOver implementation"（oko/Guitar Wiz 同款） |
| **废纸篓 + 30 天回滚** | P0 | ⭐⭐⭐ | "no destructive ops, fully reversible" |
| **中文母语审校** | 英中日本地化（非机器翻译） | ⭐⭐⭐ | Duolingo 因本地化获奖 |

### 2.1 反向定义（不做什么）

- ❌ **不做 CleanMyMac 式"模块拼盘"**（隐私 / 恶意软件 / 文件粉碎 / 性能 — 全砍或仅留痕迹）
- ❌ **不做 DaisyDisk 式"单饼图"**（不只做可视化，必须有清理动作）
- ❌ **不做恐吓营销**：禁用红字"警告"、禁用"您有 X GB 垃圾"夸大展示、禁用扫描耗时对比图
- ❌ **不做账号系统**：用户首次启动即用，无登录、无注册、无云同步
- ❌ **不做应用商店外的付费渠道**：仅 Mac App Store，不做 DMG / 官网 / Notarized

---

## 3. 定价与盈利

### 3.1 价格矩阵

| SKU | 价格 | 定位 |
|---|---|---|
| **月付订阅** | $1.99/月 | 低首付门槛，引导试用 |
| **年付订阅** | $14.99/年 | 主推（vs CleanMyMac $39.99/年，便宜 60%） |
| **买断** | $39.99 一次性 | 服务不愿订阅用户（中国 / 欧洲 / 日本必需） |
| **地区定价** | 美 $14.99 / 欧 €14.99 / 中 ¥78 / 日 ¥1,800 | 跟随 App Store 等级 2 |

### 3.2 免费额度（关键变化）

**v1 原设计**：1GB 清理额度限制 → **调研判定为"骗我"感最强设计**

**v2 新设计**：不限清理量，但**限制每周扫描次数（每周 1 次）**
- 优点：用户首次扫描清出 5 GB 也不会立刻撞墙 → 不会有"骗我"差评
- 缺点：每周只能扫一次 → 重度用户会订阅
- 配套：解锁订阅后扫描次数无限 + 实时清理

### 3.3 Free Trial

7 天（行业标准，CleanMyMac / BuhoCleaner / Sensei 均用 7 天）。

### 3.4 收入预期（基于调研）

| 阶段 | 预期 |
|---|---|
| 上架 1-3 月 | 主要靠 7 天试用 → 年付转化（行业平均 5-10%） |
| 上架 4-12 月 | 编辑推荐（如获）+ ASO 累积 → 月活增长 |
| 12 个月目标 | 累计下载 5-10 万，月活 1-2 万，年付转化 8% → 年化收入 $9.6k-$19.2k |

> ⚠️ 独立开发者年收入预期偏低（vs CleanMyMac 的母公司年收入估算 $50M+）。kSpaceClean 不是"辞主业"产品，是「高 ASP 副业」。

---

## 4. App Store 上架叙事

### 4.1 主标语（App Store 元数据 + 产品页标题）

> **kSpaceClean — The cleanest Mac cleaner. Built into macOS, not bolted on.**

### 4.2 三句话产品页副标题

1. **Zero uploads, zero accounts, zero telemetry.** Nothing leaves your Mac.
2. **Right-click any folder in Finder** to scan it. **Add a Widget** to your desktop for one-tap cleanup.
3. **Weekly scan stays free.** Unlock unlimited scans and real-time cleanup with Pro.

### 4.3 关键应用截图场景（App Store 截图必备 5 张 + 视频 1 个）

1. **首屏**：2D sunburst 主视觉（展示实时数据）
2. **Finder 集成**：Finder 右键菜单"用 kSpaceClean 扫描"
3. **桌面 Widget**：Interactive Widget 一键清理动画
4. **Shortcuts 集成**：Shortcuts App 中显示"扫描缓存" Action
5. **VoiceOver 演示**：旁白 + 屏幕录制演示无障碍体验
6. **App Preview 视频**：30 秒演示「右键扫描 → 一键清理 → 完成」全流程

### 4.4 推荐申请策略

- **时机**：上架后第 30 天（积累首批评论后）
- **路径**：App Store Connect → Featuring Nominations → "Apps We Love" 或 "New Apps We Love"
- **核心话术**：突出 Accessibility + Finder 集成 + 零上传（三个最易让评委写评语的点）

### 4.5 雷区（绝对不能做）

| 行为 | 后果 |
|---|---|
| 任何形式的账号注册 | 评语不会夸 + 隐私评分差 |
| 任何网络上报（含崩溃分析） | App Privacy 必须 "No Data Collected"，第三方 Crashlytics 也禁用 |
| 弹窗恐吓"磁盘已满" | 编辑推荐直接否决 |
| App 内展示 CleanMyMac / DaisyDisk 比较图 | App Store 拒审（商标 + 不正当竞争） |
| 清理后夸大展示"清理了 X GB" | 用户差评首因 |

---

## 5. v1/v1.1/v2 功能分级

### 5.1 v1（13-16 周，2026 Q4 提交）

| 类别 | 功能 | 优先级 |
|---|---|---|
| **核心清理** | 智能扫描（系统缓存 / 应用残留 / 临时文件） | P0 |
| | **大文件 Top N**（⭐ 新增，调研 C 判定为 P0） | P0 |
| | **应用残留检测**（⭐ 新增，调研 C 判定为 P0） | P0 |
| | 一键清理（移入废纸篓 + 30 天回滚） | P0 |
| | 白名单（信任感，微信聊天 / Photoshop 暂存不可清） | P0 |
| **视觉** | 2D sunburst 主视觉（替代 3D） | P0 |
| | 3D 磁盘星系图降级为「About / 营销素材」独立 Tab | P1 |
| **平台集成** | **Finder 右键扩展**（⭐ 调研 A/B 双料 P0） | P0 |
| | **Shortcuts / App Intents**（扫描 / 清理 / 显示大文件） | P0 |
| | **桌面 Widget**（基础版 macOS 13 + Interactive 版 macOS 14+） | P0 |
| | 菜单栏图标（显示已用空间 + 扫描入口） | P0 |
| **权限** | FDA 引导（教育性引导流，文案严格按 Apple 模板） | P0 |
| **可达性** | **VoiceOver / Dynamic Type / Increased Contrast / Differentiate Without Color** | P0 |
| **本地化** | 英中日母语审校（非机器翻译） | P0 |
| **隐私** | App Privacy Details = "No Data Collected" | P0 |
| **盈利** | StoreKit 2 订阅（月/年）+ 买断 IAP | P0 |
| **上架** | App Store Connect 元数据 + 截图 + App Preview 视频 | P0 |

### 5.2 v1.1（v1 上架后 2-3 月）

| 类别 | 功能 | 备注 |
|---|---|---|
| **核心清理** | 重复文件（轻量版，集成进 v1 扫描；size+hash 两阶段） | 为 kDupe 做能力积累 |
| **平台集成** | Live Activities（macOS 14+，清理进度长任务） | 用户认知成本高，需教育 |
| | Spotlight 集成（搜"Mac 空间"出现操作） | 实际效果弱，推迟到 v1.1 |

### 5.3 v2（v1.1 上架后 3-6 月）

| 类别 | 功能 | 备注 |
|---|---|---|
| **核心清理** | Foundation Models "AI 安全删除建议"（macOS 15+ / Apple Intelligence） | 2026 ADA 趋势标配 |
| | 启动项管理 / 后台进程可视化 | 与 kWatch 联动 |
| | 浏览器隐私清理（历史 / cookies / 缓存） | P2，市场缺口但实现复杂 |
| | 维护脚本（DNS 缓存、字体缓存、Launch Services） | P2，极客向 |
| **平台集成** | 多账户支持（家庭共享） | App Store Family Sharing |
| **盈利** | Setapp 上架（收入分成 70/30） | 渠道扩展 |

### 5.4 不做（明确砍掉）

- ❌ 防病毒 / 恶意软件扫描（CleanMyMac 的 Moonlock — 太重，独立 dev 难闭环）
- ❌ 文件粉碎（合规风险 + 用户需要程度低）
- ❌ 磁盘健康监控（SMART）→ 留给 kWatch
- ❌ iCloud 清理（系统层集成风险 + App Store 审核风险）
- ❌ 应用商店优化工具（超出清理范畴）

---

## 6. 视觉与交互设计语言

### 6.1 核心隐喻

**"星系"作为视觉隐喻的边界**：
- 主视觉：**2D sunburst**（信息密度优先，类似 DaisyDisk 风格但更现代化）
- 次视觉：**3D 磁盘星系图**（降级到 About / 营销物料，不作为主界面）
- 进度动画：**粒子收敛**（扫描中星点向中心聚拢，清理完成扩散回去）

### 6.2 色彩 Token

| Token | 用途 | 色值（暗色） |
|---|---|---|
| `brandPrimary` | 主操作按钮、选中态 | macOS systemBlue |
| `brandSecondary` | 进度环、装饰 | systemPurple |
| `textPrimary` | 标题、文件名 | label |
| `textSecondary` | 副标题、路径 | secondaryLabel |
| `success` | "可安全清理"标签 | systemGreen |
| `warning` | "请确认"标签 | systemOrange |
| `danger` | "危险 / 不可逆"标签 | systemRed（仅在真正危险时使用，不滥用） |
| `surfaceBackground` | 卡片背景 | secondarySystemBackground |

### 6.3 关键交互（macOS 融入）

| 场景 | 交互 | Apple 设计语言对应 |
|---|---|---|
| 启动 | 不弹欢迎页，直接进主界面；首次启动只显示「FDA 引导」 | macOS "open and use" 哲学 |
| 扫描 | 点击"Scan" → 全屏进度环 + 实时分类展示 | 类似 Time Machine / Photos 扫描 |
| 选中 | 单击切换 checkbox，shift 多选 | Finder 风格 |
| 清理 | 二次确认（仅对 risk=danger 项） | macOS 删除确认对话框 |
| 设置 | 标准 macOS Settings 窗口 | NSWindow / SwiftUI Settings |
| 退出 | cmd+Q 退出 + 菜单栏图标保留（菜单栏可关闭） | 标准 macOS App |

### 6.4 动画原则

- 所有动画 200-400ms
- 缓动：easeInOut（标准）
- 进度环：continuous（不跳变）
- 清理完成：粒子扩散 + 轻微 haptic
- **禁用**：弹跳、夸张旋转、震动反馈（独立 dev 易过度动画被扣分）

---

## 7. 技术架构（基于现有方案微调）

### 7.1 总体架构（沿用 CLAUDE.md v1 决策）

```
KraftlyWorkspace.xcworkspace
├── kFoundation/         # 本地 Swift Package（共享层）
├── kSpaceClean/         # App target
└── Tools/               # 共享脚本
```

### 7.2 kSpaceClean 模块（v2 微调）

```
kSpaceClean/
├── App/
│   ├── kSpaceCleanApp.swift
│   ├── RootView.swift              # 主视觉改 2D sunburst
│   └── AppCoordinator.swift
├── Features/
│   ├── DiskGalaxy/                 # ⭐ 2D sunburst 主 + 3D 降级
│   │   ├── SunburstView.swift      # ⭐ 新主视觉
│   │   ├── GalaxyView3D.swift      # 降级到 About
│   │   └── DiskUsageBar.swift
│   ├── SmartScan/                  # 扫描引擎 + 分类
│   ├── LargeFiles/                 # ⭐ P0 新增
│   ├── AppResidue/                 # ⭐ P0 新增（应用残留检测）
│   ├── Cleanup/                    # 清理动作 + 废纸篓 + 30 天回滚
│   ├── Onboarding/                 # FDA 引导
│   └── Accessibility/              # ⭐ P0 集中模块
├── Widgets/                        # 基础 + Interactive 双版本
├── FinderExtension/                # ⭐ P0 右键扫描
├── Intents/                        # App Intents / Shortcuts
├── Resources/
│   ├── Models/                     # .mlmodel 文件（CoreML）
│   └── Assets.xcassets
└── Info.plist
```

### 7.3 关键技术决策（与 v1 对齐）

| 项 | 决策 |
|---|---|
| 语言 | Swift 5.9+ |
| UI | SwiftUI 为主 + AppKit 兜底 |
| 最低系统 | macOS 13.0（覆盖 90%+ 用户，Interactive Widget 自动降级） |
| 编译目标 | macOS 14 SDK |
| 持久化 | Core Data + Codable |
| 并发 | Swift Concurrency (async/await + TaskGroup) |
| 图形 | SwiftUI Charts (2D sunburst) + SceneKit (3D 降级) |
| AI | CoreML 本地分类 |
| 分发 | 仅 Mac App Store |

---

## 8. 时间表（独立开发者，25-30h/周）

### 8.1 现实时间表

| 阶段 | 周次 | 交付物 | 现实预估 |
|---|---|---|---|
| **Phase 1: 骨架** | W1-W3 | kFoundation 6 模块 + kSpaceClean target + App Store 项目配置 | 3 周（Xcode 15 + SPM 首跑就要 1 周） |
| **Phase 2: 核心清理** | W4-W7 | 扫描引擎 + 大文件 + 应用残留 + 废纸篓回滚 | 4 周（扫描规则覆盖 80%+ 用例） |
| **Phase 3: 视觉** | W8-W10 | 2D sunburst + 3D 降级 + 动画系统 | 3 周（Charts API 性能调优） |
| **Phase 4: 平台集成** | W11-W13 | Finder 扩展 + Shortcuts + Widget + Menu Bar + Accessibility 四件套 | 3 周（每个集成都要单独签名/Entitlement） |
| **Phase 5: 盈利 + 本地化** | W14 | StoreKit 2 + 本地化三语 | 1 周 |
| **Phase 6: 内测** | W15-W16 | TestFlight 内部 + 外部测试 + 反馈修复 | 2 周 |
| **Phase 7: 提交** | W17 | App Store 元数据 + 截图视频 + 提交 | 1 周（含被拒 1 次兜底） |
| **总预估** | **17 周** | 上架 | 比 v1 时间表多 3 周（含现实风险缓冲） |

### 8.2 营销最低预算（无预算方案）

| 项 | 成本 |
|---|---|
| App Store 元数据 + 截图 + 视频（自产） | $0 |
| ProductHunt 发布 | $0 |
| 小红书 + X 同步发 5 篇（自写） | $0 |
| 10 位 Mac KOL 送码（Apple 允许 100 个 Promotional Code） | $0 |
| Reddit r/macapps 投稿 | $0 |
| Setapp 申请上架 | $0 |
| **总现金预算** | **$0** |

**关键**：营销从 W11 起同步启动（不能临时抱佛脚），重点是 KOL 关系经营。

---

## 9. 风险与应对

### 9.1 Top 5 风险

| 风险 | 概率 | 影响 | 应对 |
|---|---|---|---|
| **App Store 审核被拒（1-2 次）** | 高（独立 dev 首过率约 50%） | 致命（拖延 4-6 周） | W16 前完成 Apple Pre-Submission 邮件咨询；准备 sandbox 权限理由说明 + FDA 引导「教育性」文案 |
| **Accessibility 四件套投入不足** | 中 | 严重（拿不到 Inclusivity 类提名） | W11-W13 专设 1 周 sprint；对照 oko/Guitar Wiz 评语做 checklist |
| **Finder 扩展签名 / 沙箱配置坑** | 中高 | 中（功能可做但上架被拒） | 提前研究 Apple 文档；预算 1 周 buffer |
| **月付 $1.99 订阅 vs 年付 $14.99 用户分流** | 低 | 低（数据分析可知） | v1 上线 1 个月后看转化漏斗数据再调整 |
| **3D 投资被浪费（用户不访问 About Tab）** | 中 | 低（投入可控） | 3D 仍可作为营销视频 / ProductHunt 物料，不算浪费 |

### 9.2 Plan B

| 触发条件 | Plan B |
|---|---|
| App Store 审核 3 次仍被拒 | 转向直接发布 DMG + Notarized（违背 CLAUDE.md 决策，需用户授权） |
| Accessibility 投入产出比低 | 不强求 Inclusivity 类，专注 Visuals 类（3D 视觉评语） |
| 月活增长不达预期 | 调整价格 / 调整免费额度逻辑 |

---

## 10. 验证标准（v1 上架 checklist）

### 10.1 功能验证

- [ ] 智能扫描 8 大类全部完成（系统缓存 / 应用残留 / 大文件 / 用户缓存 / 日志 / 临时 / 开发文件 / 浏览器）
- [ ] 大文件 Top N ≥ 50 个文件正确列出
- [ ] 应用残留检测 ≥ 80% 准确率（人工抽样 20 个已卸载应用）
- [ ] 废纸篓 30 天回滚可恢复任意清理项
- [ ] 白名单至少包含：微信聊天记录 / Photoshop 暂存 / Time Machine 本地快照

### 10.2 平台集成验证

- [ ] Finder 右键"用 kSpaceClean 扫描"可触发扫描
- [ ] Shortcuts 中显示"扫描缓存" / "清理缓存" / "显示大文件" 三个 Action
- [ ] 桌面 Widget（基础版）显示磁盘已用空间
- [ ] 桌面 Widget（Interactive）点击触发扫描 / 清理
- [ ] 菜单栏图标实时显示已用空间

### 10.3 可达性验证

- [ ] VoiceOver 完整朗读主界面、扫描结果、清理流程
- [ ] Dynamic Type 在最大字号下 UI 不破版
- [ ] Increased Contrast 模式下所有 UI 元素可辨识
- [ ] Differentiate Without Color 模式下风险等级可辨识（不只靠颜色）

### 10.4 隐私验证

- [ ] App Privacy Details = "No Data Collected"
- [ ] 抓包确认无任何对外网请求
- [ ] 崩溃日志用 MetricKit 本地保存（不上传）

### 10.5 盈利验证

- [ ] Free Trial 7 天正确触发
- [ ] 月付 $1.99 / 年付 $14.99 / 买断 $39.99 三 SKU 均可购买
- [ ] 退款流程正常

### 10.6 上架前 checklist

- [ ] App Store 元数据 5 张截图 + 1 个 App Preview 视频（≤ 30s）
- [ ] 本地化三语（英中日）母语审校完成
- [ ] App Privacy Details 填写完整
- [ ] TestFlight 外部测试 ≥ 20 人、≥ 1 周

---

## 11. 设计自审（spec self-review）

### 11.1 Placeholder 扫描

✅ 已扫：所有 "P0 / P1" 标签均有明确定义；所有 "⭐ 新增" 均有调研引用；无 "TBD / TODO / 待定"。

### 11.2 内部一致性

✅ 已检：
- 定价三 SKU 在 Section 3.1 与 Section 5.1 一致
- 时间表 W1-W17 与 Section 8.2 营销启动时机（W11）一致
- v1/v1.1/v2 功能分级与 Section 5.4 不做项无冲突

### 11.3 范围检查

✅ 聚焦 kSpaceClean 一款 App；不涉及 kWatch / kDupe / kUninstall。

### 11.4 歧义检查

- ✅ "无感融入 macOS" → 用 §6.3 关键交互表格具体化
- ✅ "3D 降级" → 用 §6.1 核心隐喻边界具体化
- ✅ "扫描次数限制" → §3.2 明确为"每周 1 次"，解锁订阅无限

---

## 12. 关键决策记录

| 决策 | 原 v1 设计 | v2 设计 | 调研依据 |
|---|---|---|---|
| 主视觉 | 3D 磁盘星系图 | **2D sunburst**（3D 降级 About） | Agent C 判定 3D = 装饰差异化 |
| 定价 | $19.99/年（无买断） | **$14.99/年 + $1.99/月 + $39.99 买断** | Agent C：单一订阅是转化杀手 |
| 免费额度 | 1GB 清理限制 | **每周扫描次数限制** | Agent C：1GB 是"骗我"感最强设计 |
| App Intents | 3 个（扫描 / 清理 / 大文件） | **保留 + Finder 扩展** | Agent A：Finder 集成是市场空白 |
| Live Activities | v1 | **v1.1** | Agent C：认知成本高 |
| Spotlight | v1 | **v1.1** | Agent C：效果弱 |
| 大文件 Top N | ❌ 缺失 | **v1 P0 新增** | Agent C：缺失必被 1 星刷屏 |
| 应用残留 | ❌ 缺失 | **v1 P0 新增** | Agent C：用户每天都问 |
| Accessibility 四件套 | ❌ 未明确 | **v1 P0** | Agent B：Inclusivity 类入场券 |
| 营销叙事 | "最聪明的磁盘清理" | **"无感融入 macOS"** | Agent B：ADA 趋势 + 规避恐吓营销雷区 |

---

## 13. 待用户复核

请审阅本设计文档，特别关注：

1. **战略方向**（§1）：「无感融入 macOS」是否符合你预期？
2. **定价三 SKU**（§3.1）：$14.99/年 + $1.99/月 + $39.99 买断 是否可接受？
3. **免费额度**（§3.2）：改"每周扫描次数"取代 1GB 限额，是否合理？
4. **v1 功能清单**（§5.1）：是否有遗漏或不需要的项？
5. **时间表**（§8.1）：17 周是否可接受？
6. **3D 降级决策**（§6.1）：是否同意 3D 不再作为主视觉？

> 复核通过后，进入 writing-plans 拆解为可执行任务。