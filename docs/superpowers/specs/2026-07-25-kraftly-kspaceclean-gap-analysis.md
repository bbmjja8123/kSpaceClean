# kSpaceClean Spec Gap Analysis

**日期**：2026-07-25
**方法**：通读主 spec + 详细设计 + CLAUDE.md，按 10 个维度梳理遗漏项
**目的**：在进入 writing-plans 之前，识别 spec 缺失，决定补哪些

---

## 维度 A：业务 / 合规 / 法律

### A1. Apple Developer Program 注册策略 ⚠️ **P0**
- **现状**：未提及
- **关键决策**：Individual ($99/年，绑定个人身份证/SSN) vs Organization ($99/年，需 D-U-N-S 编号 + 法律实体)
- **影响**：决定收款主体、报税方式、品牌展示（中国 App Store 显示"个人开发者"）
- **建议**：作为中国独立开发者，先以**个人**注册（中国身份证 + 银联收款），后续出海有规模再转 Organization

### A2. 税务处理 ⚠️ P2
- **现状**：未提及
- **关键点**：IAP 苹果抽成 30%（小型企业计划首年降至 15%，需申请）、中国增值税、个人所得税
- **建议**：V1.1 详细处理，V1 阶段使用苹果自动代扣代缴

### A3. 隐私政策 + 服务条款 ⚠️ **P0**
- **现状**：§5.3 提到"链接到 App Store 元数据"，但未指定 URL
- **缺失**：URL 在哪托管？内容包含什么？
- **建议**：
  - 用 GitHub Pages 托管静态页面（免费、私密性好）
  - 内容包含：收集的数据（"零"）、TCC 权限说明、订阅条款、未成年人政策、联系方式

### A4. 退款政策 UX ⚠️ P1
- **现状**：未提及
- **缺失**：用户如何申请退款？in-app 引导？
- **建议**：在订阅管理页面添加说明："退款请联系 Apple 支持 → reportaproblem.apple.com"，不在 App 内处理退款（避免违规）

### A5. 订阅条款 ⚠️ **P0**
- **现状**：未提及
- **缺失**：订阅前必须展示的 Terms of Service 文本
- **建议**：订阅确认弹窗前显示条款链接 + "订阅将自动续费，可在 Apple ID 设置中关闭"标准文案

### A6. Restore Purchase 流程 ⚠️ **P0**
- **现状**：未提及
- **缺失**：订阅恢复按钮（App Store 审核必查项）
- **建议**：在订阅页面加 "Restore Purchase" 按钮，调用 `AppStore.sync()`

### A7. App Store 审核指南合规 ⚠️ P1
- **现状**：未提及
- **关键条款**：
  - 2.1 App 完整性（功能必须能跑）
  - 2.3 准确元数据（截图必须真实）
  - 5.1.1 隐私（权限说明）
  - 4.0 设计（不能太简陋）
- **建议**：上架前 checklist 逐条对照

### A8. 隐私标签（Nutrition Labels）⚠️ **P0**
- **现状**：§7.3 简单写了"不收集数据 / 仅本地分析"
- **缺失**：App Store Connect 隐私标签 8 个维度需精确勾选
- **建议**：明确勾选：
  - Contact Info: No
  - Financial Info: No
  - Health & Fitness: No
  - Location: No
  - Sensitive Info: No
  - Contacts: No
  - User Content: ⚠️ **可能 Yes**（扫描文件路径）
  - Browsing History: No
  - Search History: No
  - Identifiers: No
  - Usage Data: No
  - Diagnostics: No (we said MetricKit is local only)
  - Purchases: ⚠️ **Yes**（订阅状态）

---

## 维度 B：上架与发布流程

### B9. App Store Connect 设置清单 ⚠️ **P0**
- **现状**：未提及
- **缺失**：
  - Bundle ID 注册
  - Capabilities（App Groups、In-App Purchase、Push Notifications）
  - 协议签署（付费应用 + 订阅）
  - 银行账户 + 税务信息
- **建议**：上架前 2 周开始设置

### B10-B11. 代码签名证书 / Provisioning ⚠️ P1
- **现状**：详细设计 §13 提到签名但未详细
- **缺失**：Apple Development / Distribution 证书、Provisioning Profile 管理
- **建议**：用 Xcode 自动管理（Sign in to Apple ID → Automatically manage signing）

### B12. TestFlight 测试计划 ⚠️ **P0**
- **现状**：时间表 W12 提到 TestFlight，未详细
- **缺失**：
  - 内部测试者（最多 100 人）：亲友 + 自己
  - 外部测试者（最多 10,000 人，需 Apple 审核）：公开招募？
  - 测试周期（建议至少 2-4 周）
- **建议**：W10-W12 内部测试，W12-W13 提交审核前最后修复

### B13. 分阶段发布 ⚠️ P1
- **现状**：未提及
- **缺失**：上架后 7 天分阶段推出的策略
- **建议**：默认开启分阶段发布（1%/2%/5%/10%/20%/50%/100%），降低首发风险

### B14. App Store 拒绝应急 ⚠️ P1
- **现状**：§11 提到"FDA 描述拒"，未详细应急流程
- **缺失**：appeal 流程、修复后重新提交流程
- **建议**：
  - 收到拒绝 → 读清楚拒绝理由
  - 如政策合规问题：appeal（写清楚为什么符合）
  - 如技术问题：修复 + 重新提交
  - 通常 24-48 小时二次审核

### B15. 版本号策略
- **现状**：详细设计 §13.3 已有
- **状态**：✅ 覆盖

### B16. CI/CD 流水线 ⚠️ P1
- **现状**：详细设计 §13.2 有 bash 脚本，但未提 GitHub Actions
- **缺失**：
  - PR 自动跑测试
  - 自动构建 Archive
  - 自动上传 TestFlight
- **建议**：V1 上架后第二个月接入 GitHub Actions，先手动 ship

### B17. Fastlane / 构建自动化 ⚠️ P2
- **现状**：详细设计 §13.2 手动 xcodebuild
- **建议**：V1.1 接入 Fastlane（match、gym、pilot）

---

## 维度 C：客户体验

### C18. 首次启动 Onboarding ⚠️ P1
- **现状**：§3.5 只有 FDA 引导
- **缺失**：首次启动的整体引导：
  - 第 1 屏：价值介绍（"让你的 Mac 始终有足够空间"）
  - 第 2 屏：核心功能预告（3D 星系、AI 分类）
  - 第 3 屏：权限说明
  - 第 4 屏：开始扫描
- **建议**：V1.1 加，V1 用 FDA 引导 + 简短的欢迎页

### C19. 帮助文档 ⚠️ P1
- **现状**：未提及
- **缺失**：in-app help？网站文档？
- **建议**：
  - 极简：设置页加 "Help & Support" 链接到 GitHub Pages
  - 进阶：做一个 help center（CommonQuestions.md）

### C20. 客户支持渠道 ⚠️ **P0**
- **现状**：未提及
- **缺失**：用户如何联系你？
- **建议**：
  - 邮箱：support@kraftly.app（专用支持邮箱）
  - 或 Discord 频道
  - App 内设置页加 "Contact Support" 按钮（调用邮件 app）

### C21-C23. 状态 UI（空 / 加载 / 错误）⚠️ P1
- **现状**：未提及
- **缺失**：
  - 空状态：从未扫描过
  - 加载状态：扫描中
  - 错误状态：FDA 失效、磁盘不可访问
- **建议**：每个 Feature 都要有三种状态的 SwiftUI 视图

### C24. 应用图标设计 ⚠️ **P0**
- **现状**：未提及
- **缺失**：
  - 1024×1024 主图标（App Store）
  - 各尺寸：16, 32, 64, 128, 256, 512
  - 多个图标变体（深色 / 浅色 / 单色）
- **建议**：
  - 用 SF Symbols 设计理念
  - 委托设计师（Fiverr / 找 Mac 设计师）
  - 概念：星系 + 字母 K

### C25. 品牌设计系统 ⚠️ P1
- **现状**：未提及
- **缺失**：logo、配色、字体规范
- **建议**：定义 Design Tokens（颜色、字号、间距），用 kFoundation/DesignSystem 共享

### C26. 应用内反馈机制 ⚠️ P1
- **现状**：未提及
- **缺失**：用户在 App 内如何报告 Bug / 提建议？
- **建议**：设置页加：
  - "Report a Problem" → 邮件
  - "Suggest a Feature" → 邮件
  - "Rate kSpaceClean" → App Store 评论页

---

## 维度 D：可访问性（Accessibility）

### D27. VoiceOver 支持 ⚠️ **P0**
- **现状**：未提及
- **缺失**：3D 星系对盲人用户不友好
- **建议**：
  - 给每个球 `accessibilityLabel`（如 "Documents, 64 GB"）
  - 提供"列表视图"作为 VoiceOver 用户替代
  - 隐藏的 screen reader 专用 UI

### D28. 键盘导航 ⚠️ **P0**
- **现状**：未提及
- **缺失**：全功能可纯键盘操作？
- **建议**：所有按钮 `accessibilityTraits = .button`、Tab 顺序合理、Cmd+? 显示快捷键列表

### D29-D31. Dynamic Type / Reduce Motion / 高对比度 ⚠️ P1
- **现状**：未提及
- **建议**：
  - Dynamic Type：尊重用户字号偏好
  - Reduce Motion：检测系统设置、动效降级
  - 高对比度：支持 macOS Increase Contrast

> 💡 **苹果推荐偏好**：可访问性是 Apple Design Award 评审重要维度，不可忽视。

---

## 维度 E：国际化

### E32. 多语言策略
- **现状**：§3.12 决定 en/zh-Hans/ja
- **状态**：✅ 决策已定，细节待补

### E33. 字符串资源估算 ⚠️ P1
- **现状**：未提及
- **缺失**：估算多少字符串？如何在多语言间同步？
- **建议**：
  - 用 Xcode 15+ 的 `Localizable.xcstrings` 集中管理
  - 估算：~300-500 个字符串
  - 简中自写，英文优先，日文 V1.1

### E34-E36. 复数形式 / RTL / 其它语言
- **现状**：未提及
- **建议**：V1 不支持 RTL、不加欧洲语言

---

## 维度 F：运营与质量

### F37. 崩溃监控策略 ⚠️ **P0**
- **现状**：§5.1 提到"如需崩溃收集，使用 Apple MetricKit"
- **缺失**：MetricKit 具体配置、MXMetricManager 订阅
- **建议**：
  ```swift
  // App 启动时订阅
  let manager = MXMetricManager.shared
  let subscriber = MetricKitSubscriber()
  manager.add(subscriber)
  ```
  - 注意：MetricKit 数据仅本地，不上传
  - 如需上传：必须用户 opt-in 且隐私政策明确

### F38. 性能监控 ⚠️ P2
- **现状**：详细设计 §11 有性能预算
- **建议**：V1 用 Instruments 手动测量，V2 接入自动化性能监控

### F39. macOS 版本支持窗口 ⚠️ P1
- **现状**：决定 macOS 13 最低
- **缺失**：何时停止支持 macOS 13？
- **建议**：当 macOS 13 用户占比 < 5% 时（参考 App Store Connect 数据）

### F40. 更新频率策略 ⚠️ P1
- **现状**：未提及
- **建议**：
  - 大版本：6-12 月一次
  - 小版本：2-4 周一次（bug 修复）
  - 不强制节奏，按需发布

### F41. Bug 优先级分级 ⚠️ P1
- **现状**：未提及
- **建议**：
  - **P0**：核心功能崩溃、数据丢失 → 24h 内修复
  - **P1**：功能降级但不阻塞 → 1 周内
  - **P2**：UI 小问题 → 下版本
  - **P3**：feature request → backlog

### F42. 故障应急流程 ⚠️ P1
- **现状**：未提及
- **缺失**：核心扫描崩溃怎么办？误删文件怎么办？
- **建议**：
  - 扫描崩溃：自动保存已扫描部分，下次启动恢复
  - 误删：30 天清理历史可回滚（已设计）
  - App 崩溃：MetricKit 记录，下次启动反馈

### F43. 备份 / 数据导出 ⚠️ P2
- **现状**：未提及
- **建议**：V1.1 加"导出清理历史"功能（CSV/JSON）

### F44. 数据迁移 ⚠️ P2
- **现状**：未提及
- **建议**：Core Data 用 lightweight migration（默认开启）

---

## 维度 G：营销与增长

### G45. GTM 详细计划 ⚠️ **P0**
- **现状**：§10 简略提到
- **缺失**：完整 GTM plan
- **建议**：
  - **T-30**：landing page 上线、收集邮箱
  - **T-14**：开始社交媒体预热（X/小红书）
  - **T-7**：联系评测博主、送兑换码
  - **T-1**：Product Hunt 准备、新闻稿
  - **T-0**：上架 + 同步发布
  - **T+1**：跟进评论、社群互动
  - **T+7**：申请苹果推荐
  - **T+30**：第一次小迭代

### G46. Press Kit ⚠️ P1
- **现状**：未提及
- **建议**：
  - 准备：logo (SVG + PNG)、截图（多尺寸）、产品说明、媒体联系人
  - 托管：press.kraftly.app 或 GitHub Pages

### G47. 社交媒体策略 ⚠️ P1
- **现状**：§10 提到 X/小红书
- **建议**：
  - X（英文）：@kraftlyapp
  - 小红书（中文）：Kraftly
  - Mastodon（开源向）
  - 内容策略：每周 2-3 帖（开发日记 / Mac 技巧 / 新功能）

### G48. 社区建设 ⚠️ P1
- **现状**：§10 提到 Discord/Telegram
- **建议**：
  - Discord 频道（首选，国际化）
  - 频道分类：#general / #feature-requests / #bug-reports / #mac-tips
  - 招募 5-10 个种子用户

### G49. 邮件列表 ⚠️ P2
- **现状**：未提及
- **建议**：用 Buttondown / Substack，发布月报
  - 注意：这与"零网络上报"不冲突，邮件列表是用户主动订阅

### G50. 合作伙伴 ⚠️ P2
- **现状**：未提及
- **建议**：与 5-10 个独立开发者 App 互推（推荐位交换）

### G51. Setapp 分发 ⚠️ P2
- **现状**：未提及
- **建议**：V1.1 评估 Setapp 入驻（额外曝光，但抽成高）

---

## 维度 H：度量与成功

### H52. KPI 定义 ⚠️ **P0**
- **现状**：未提及
- **缺失**：v1 上市 3 个月目标是什么？
- **建议**：
  - **下载量**：T+30 = 1,000 / T+90 = 5,000
  - **试用→订阅转化率**：> 5%
  - **评分**：> 4.5 ⭐
  - **崩溃率**：< 0.1%
  - **收入**：T+90 = $1,000 MRR（最低目标）
  - **留存**：T+30 = 40% 用户仍活跃

### H53-H55. A/B 测试 / 转化漏斗 / 北极星指标 ⚠️ P2
- **现状**：未提及
- **建议**：V1.1 接入产品分析（Posthog/Plausible 自托管）

---

## 维度 I：安全

### I56-I59. 代码混淆 / 证书锁定 / Hardened Runtime / 安全审计 ⚠️ P2
- **现状**：未提及
- **建议**：V1 用 Swift 默认编译即可，V1.1 加：
  - Hardened Runtime entitlements 配置
  - 启用代码签名 hardened runtime
  - 订阅收据验证用本地 StoreKit 2

---

## 维度 J：技术规范

### J60. 依赖管理策略 ⚠️ P1
- **现状**：§2.3 说"无第三方依赖"
- **缺失**：未来怎么加？用 SPM？CocoaPods？
- **建议**：统一用 Swift Package Manager

### J61. SwiftLint 规则集 ⚠️ P1
- **现状**：CLAUDE.md 提到文件但无规则
- **建议**：用社区标准 + 自定义规则：
  - line_length: 120
  - function_body_length: 60
  - cyclomatic_complexity: 10
  - force_unwrapping: error
  - todo: warning

### J62. 代码覆盖率门槛 ⚠️ P1
- **现状**：§8.1 提到 70% 但无 CI 强制
- **建议**：CI 必须通过覆盖率门槛才能 merge

### J63. Git 分支策略 ⚠️ P1
- **现状**：CLAUDE.md 提到 main + feature/* 但不详细
- **建议**：
  - `main`：保护，仅 PR merge
  - `develop`：日常开发分支
  - `feature/*`：新功能
  - `fix/*`：bug 修复
  - `release/v1.x.x`：发版分支

### J64. 提交规范 ⚠️ P1
- **现状**：CLAUDE.md 提到格式但未强制
- **建议**：Conventional Commits + commitlint

### J65. Code Review 流程 ⚠️ P1
- **现状**：未提及（独立开发者无 reviewer）
- **建议**：
  - 自己 PR 自己 review
  - 用工具（danger / swift-review）
  - 关键模块请朋友 review

---

## 总结与优先级

| 优先级 | 数量 | 必须补到 spec |
|---|---|---|
| **P0（阻塞）** | 13 项 | A1, A3, A5, A6, A8, B9, B12, C20, C24, D27, D28, F37, G45, H52 |
| **P1（应该）** | 21 项 | A4, A7, B10-11, B13, B14, B16, C18, C19, C21-23, C25, C26, D29-31, E33, F39-42, G46-48, J60-65 |
| **P2（可缓）** | 13 项 | A2, B17, F38, F43-44, G49-51, H53-55, I56-59 |

**建议**：
- **必须**：在进入 writing-plans 前，把所有 P0 项写进 spec（新增 1-2 节）
- **应该**：P1 项可以分散到 V1.1 实施计划里
- **可缓**：P2 项在 V2 设计时考虑

---

## 下一步

1. 我先把 P0 项补充到主 spec，形成 v1.1 版本
2. 完成后给你过目
3. 然后才进入 writing-plans

确认这个优先级划分？或者你想调整某些项到 P0？