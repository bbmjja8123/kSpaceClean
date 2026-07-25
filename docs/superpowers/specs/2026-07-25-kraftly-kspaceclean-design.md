# kSpaceClean v1 设计规格

**项目**：Kraftly Mac App Suite
**App**：kSpaceClean（磁盘清理）
**作者**：独立开发者
**日期**：2026-07-25
**状态**：v1 设计定稿，待实施

---

## 1. 概述

### 1.1 一句话定位
让 Mac 存储空间回到"足够"，最聪明的磁盘清理。

### 1.2 目标用户
- **主**：MacBook 256GB / 512GB 用户，频繁弹"磁盘已满"告警
- **次**：创意工作者（视频/摄影），需要定期清理临时文件
- **不服务**：开发者（→kDupe）、极客玩家（→kDupe）、系统监控需求者（→kWatch）

### 1.3 与同类产品的差异点
| 维度 | CleanMyMac X | DaisyDisk | kSpaceClean 差异点 |
|---|---|---|---|
| 主界面 | 模块拼盘 | 磁盘可视化 | **3D 磁盘星系图（Metal 渲染）** |
| 智能分类 | 规则匹配 | 无 | **CoreML 本地 AI 自动分类** |
| 扫描速度 | 中等 | 慢 | **Apple Silicon 神经引擎加速 perceptual hash** |
| 隐私 | 上报统计 | 本地 | **零网络上报，所有计算在本地** |
| 一键清理 | ✅ | ❌ | ✅ + Interactive Widget 一键清理（macOS 14+） |
| App Store 集成 | ✅ | ❌ | ✅ + Shortcuts 集成 |

---

## 2. 工程组织

### 2.1 Workspace 位置
`/Users/mengjianjun/Documents/ai/aicoding/macapp/KraftlyWorkspace.xcworkspace`

### 2.2 kSpaceClean target 结构
```
kSpaceClean/
├── App/
│   ├── kSpaceCleanApp.swift              # @main
│   ├── RootView.swift                    # NavigationSplitView
│   └── AppCoordinator.swift
├── Features/
│   ├── DiskGalaxy/                       # 3D 磁盘星系可视化（差异化核心）
│   │   ├── GalaxyRenderer.swift          # Metal 渲染
│   │   ├── GalaxyScene.swift             # SceneKit 场景
│   │   └── GalaxyView.swift              # SwiftUI 容器
│   ├── SmartScan/                        # 扫描引擎
│   │   ├── ScanEngine.swift              # 文件枚举、Hash、相似度
│   │   ├── AIClassifier.swift            # CoreML 模型加载与推理
│   │   └── CategoryRule.swift            # 分类规则
│   ├── Cleanup/                          # 清理动作
│   │   ├── TrashMover.swift              # 移入废纸篓
│   │   └── CleanupHistory.swift          # 清理历史 + 回滚
│   └── Onboarding/                       # FDA 引导流程
│       ├── FDAGuideView.swift
│       └── FDAGuideController.swift
├── Widgets/                              # 桌面 Widget
│   ├── kSpaceCleanWidget.swift           # 基础版（macOS 13）
│   └── kSpaceCleanInteractiveWidget.swift # Interactive 版（macOS 14+）
├── Intents/                              # App Intents（Shortcuts）
│   ├── ScanIntent.swift
│   ├── CleanCacheIntent.swift
│   └── ShowLargeFilesIntent.swift
├── FinderExtension/                      # Finder 右键扩展
│   ├── FinderSync.swift
│   └── Info.plist
├── Spotlight/                            # Spotlight 集成
│   └── CoreSpotlightIntegration.swift
├── LiveActivity/                         # Live Activities（macOS 14+）
│   └── CleanupActivityAttributes.swift
├── Resources/
│   ├── Models/                           # .mlmodel 文件
│   ├── Assets.xcassets
│   └── Localizable.xcstrings             # en / zh-Hans / ja
└── Info.plist
```

### 2.3 依赖
- **kFoundation**（本地 Swift Package）：FileScanner / PrivacyShield / AppCatalog / Capabilities / DesignSystem / CommonUtils
- **第三方依赖**：无（最小依赖原则，避免供应链风险）

### 2.4 编译配置
| 项 | 值 |
|---|---|
| 部署目标 | macOS 13.0 |
| 编译 SDK | macOS 14 |
| Swift | 5.9+ |
| 严格并发 | `SWIFT_STRICT_CONCURRENCY = complete` |
| App Sandbox | 强制开启 |
| Hardened Runtime | 开启 |
| 代码签名 | Mac App Distribution |
| 类别 | `public.app-category.utilities` |

### 2.5 Entitlements
```xml
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.files.user-selected.read-write</key><true/>
<key>com.apple.security.files.bookmarks.app-scope</key><true/>
<key>com.apple.security.application-groups</key>
<array><string>group.app.kraftly.shared</string></array>
```

---

## 3. 功能规格（v1 全功能首发）

### 3.1 3D 磁盘星系图（差异化核心）
- **主视觉**：进入 App 第一眼看到的 3D 场景
- **渲染**：Metal + SceneKit，60fps 流畅
- **交互**：根目录 → 子目录球体化，点击下钻
- **配色**：根据文件类型上色（图片紫、视频蓝、文档绿、缓存灰、代码橙）
- **动效**：扫描中球体缓慢旋转，清理后淡出消失
- **降级**：macOS 13 上仍可用 Metal，但动效减少；不支持 Metal 的设备回退 2D 饼图

### 3.2 智能扫描引擎
- **扫描类型**：
  - 系统缓存（`~/Library/Caches`、`/Library/Caches`）
  - 应用残留（已卸载 App 的 Library 残留）
  - 大文件（>100MB，可配置阈值）
  - 重复文件（按 size → hash 两阶段）
  - 浏览器缓存（Safari / Chrome / Firefox）
  - 日志文件
  - 垃圾桶
- **算法**：
  - 文件枚举使用 Swift Concurrency + URLResourceKey
  - Hash 计算使用 CryptoKit（SHA-256），并行 TaskGroup
  - 重复文件检测使用 **两阶段 size→hash** 算法（参考 Lemon 逻辑，新写）
- **UI 进度**：实时进度条 + 当前扫描目录 + 已发现可清理大小
- **取消友好**：任意时刻取消，已扫描结果保留可手动清理

### 3.3 CoreML AI 分类
- **模型**：自定义 CoreML 模型，输入文件元数据 + 扩展名 + 采样内容指纹
- **输出分类**：图片 / 视频 / 文档 / 音频 / 缓存 / 开发文件 / 应用 / 其他
- **推理位置**：完全本地（Apple Neural Engine 加速）
- **降级**：模型加载失败时回退到规则匹配（扩展名白名单）
- **隐私**：任何文件内容不上传

### 3.4 一键清理 + 废纸篓回滚
- **清理动作**：默认移入系统废纸篓，可选"永久删除"
- **安全机制**：
  - 高风险文件二次确认（系统文件、外接磁盘文件）
  - 清理前快照（保留原路径元数据）
  - 30 天清理历史可在 App 内"恢复"
- **批量操作**：多选 / 全选当前分类

### 3.5 Full Disk Access 引导
- **入口**：首次启动 + 权限失效时
- **流程**：
  1. 解释为什么要 FDA（"为了扫描系统缓存以保护你的隐私"）
  2. 跳转系统设置 → 隐私与安全 → 完全磁盘访问权限
  3. 用户授权后自动回到 App 并触发首次扫描
- **UX**：教育性插画 + 进度清晰，绝不静默申请

### 3.6 菜单栏图标
- **图标**：自定义 NSStatusItem，显示已用空间百分比
- **下拉菜单**：快速扫描、最近清理、打开主窗口、退出
- **颜色状态**：<70% 绿 / 70-90% 黄 / >90% 红

### 3.7 桌面 Widget
- **基础版**（macOS 13+）：显示已用空间饼图 + 一键扫描按钮（点击唤起 App）
- **Interactive 版**（macOS 14+）：同上 + 直接执行扫描 + 一键清理缓存按钮
- **尺寸**：小 / 中 / 大 三种
- **数据刷新**：App 主动 `WidgetCenter.shared.reloadAllTimelines()`

### 3.8 Shortcuts App Intents
- **ScanIntent**："扫描 Mac 存储" → 触发扫描 → 返回当前已用空间
- **CleanCacheIntent**："清理系统缓存" → 执行清理 → 返回释放大小
- **ShowLargeFilesIntent**："显示最大文件 Top 10" → 返回文件列表
- **集成点**：Siri、Spotlight、菜单栏服务、自动化

### 3.9 Live Activities（macOS 14+）
- **触发**：长清理任务（>30 秒）
- **显示内容**：进度条 + 已释放空间 + 当前扫描目录
- **结束**：自动消失，留下系统通知

### 3.10 Finder 扩展
- **右键菜单**：在选中的文件夹上显示"用 kSpaceClean 扫描此文件夹"
- **行为**：扫描选中目录 → 在主窗口打开结果

### 3.11 Spotlight 集成
- **索引项**：扫描动作、清理动作、显示大文件
- **搜索词**："Mac 空间"、"清理 Mac"、"大文件"

### 3.12 本地化
- **支持语言**：英文（基础）、简体中文、日文
- **优先级**：英文 > 简中 > 日文
- **资源**：`Localizable.xcstrings`（Xcode 15+ 新格式）

---

## 4. 数据模型

> 注：SwiftData 仅 macOS 14+ 支持，本 App 部署到 macOS 13，使用 **Core Data** 兼容写法。Capabilities.swiftData 用于未来检测升级。

### 4.1 Core Data Schema
```swift
@objc(ScanRecord)
public class ScanRecord: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var startedAt: Date
    @NSManaged public var finishedAt: Date?
    @NSManaged public var totalBytes: Int64
    @NSManaged public var freedBytes: Int64
    @NSManaged public var category: String
    @NSManaged public var entries: NSSet?  // -> FileEntry
}

@objc(FileEntry)
public class FileEntry: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var path: String
    @NSManaged public var size: Int64
    @NSManaged public var category: String
    @NSManaged public var confidence: Double  // AI 分类置信度
    @NSManaged public var scanRecord: ScanRecord?
}

@objc(CleanupRecord)
public class CleanupRecord: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var cleanedAt: Date
    @NSManaged public var totalBytes: Int64
    @NSManaged public var entries: NSSet?
    @NSManaged public var isRestored: Bool
}
```

### 4.2 Codable 配置
- 用户偏好（清理阈值、忽略路径、自动清理规则）：JSON 存 `Application Support/`
- Widget 快照数据：JSON 存 App Group Container

---

## 5. 隐私与安全

### 5.1 零网络上报
- 默认不集成任何第三方分析 SDK（无 Firebase、无 Sentry、无 Umami）
- 如需崩溃收集，使用 **Apple MetricKit**（仅本地数据，不上报）
- 网络请求白名单：仅苹果 App Store 验证收据

### 5.2 沙箱与权限
- App Sandbox 强制
- Full Disk Access（TCC）由用户手动授予
- 不使用 Privileged Helper / SMJobBless（App Store 不允许）

### 5.3 透明权限说明
- 首次扫描前显示权限用途插画
- 隐私政策链接到 App Store 元数据
- 设置页可查看当前授权状态

---

## 6. 盈利设计

### 6.1 定价
- **价格**：Free Trial 7 天 → **$19.99/年**
- **免费层**：扫描功能 + 清理额度限制 1GB
- **无买断版**：纯订阅，便于独立开发者现金流稳定

### 6.2 地区定价
| 地区 | 价格 |
|---|---|
| 美国 | $19.99 |
| 欧盟 | €19.99 |
| 英国 | £17.99 |
| 中国 | ¥98 |
| 日本 | ¥2,400 |

### 6.3 内购 SKU
- **Auto-Renewable Subscription**：年付，App Store 自动续订
- **Trial**：7 天免费试用，到期前 24 小时提醒
- **管理**：链接到 App Store 订阅管理

---

## 7. ASO 与上架策略

### 7.1 关键词（美区主目标）
- **主关键词**：`mac cleaner`、`disk cleaner`、`storage cleaner`、`clean my mac`、`mac storage`
- **辅关键词**：`cache cleaner`、`system junk`、`free up space`、`apple silicon cleaner`、`metal renderer`、`duplicate finder`
- **避坑**：不使用 CleanMyMac 商标名（App Store 拒）

### 7.2 截图与预览
- 截图 1：3D 磁盘星系图（主视觉冲击）
- 截图 2：扫描结果分类展示
- 截图 3：一键清理前后对比
- 截图 4：Widget 在桌面
- 截图 5：Shortcuts 集成
- 预览视频：30 秒动效展示（必须有，App Store 算法加权）

### 7.3 元数据
- **副标题**："Smart Storage Cleaner for Apple Silicon"
- **类别**：Utilities
- **年龄分级**：4+
- **隐私标签**：
  - 不收集数据（默认）
  - 仅本地分析

### 7.4 申请苹果推荐
- 上架后立即在 Apple 开发者后台填推荐申请
- 强调 Apple Silicon 原生 + Metal 渲染 + Live Activities + 隐私优先
- 联系 Mac 编辑博主评测

---

## 8. 测试策略

### 8.1 单元测试
- 覆盖率目标 > 70%
- 关键模块：ScanEngine、AIClassifier、TrashMover、PermissionCenter
- 框架：XCTest + Swift Testing

### 8.2 集成测试
- 权限引导流程（mock TCC）
- Core Data 持久化
- App Group 跨进程数据共享

### 8.3 UI 测试
- 关键用户路径：首次启动 → FDA 授权 → 扫描 → 清理
- XCUITest

### 8.4 性能测试
- 扫描 100GB 文件夹 < 5 分钟（Apple Silicon M2）
- 3D 渲染 60fps（M1 及以上）
- 内存占用 < 200MB

---

## 9. 上架时间表

| 阶段 | 周次 | 交付物 |
|---|---|---|
| **阶段 0** | W1-W2 | kFoundation 骨架 + 权限层 + 2D 扫描原型 |
| **阶段 1** | W3-W5 | 扫描引擎 + CoreML 分类 + 清理动作 + TCC 引导 |
| **阶段 2** | W6-W8 | 3D 磁盘星系图（Metal）+ 菜单栏图标 |
| **阶段 3** | W9-W10 | Widget + Shortcuts + Finder 扩展 + Spotlight |
| **阶段 4** | W11-W12 | Live Activities + 多语言 + App Store 元数据 + TestFlight |
| **阶段 5** | W13 | App Store 提交 + 申请苹果推荐 |
| **阶段 6** | W14-W18 | V1.1 修复评论 + 性能优化 + 小迭代 |

⏱️ 总计 13 周，每周一汇报进度。

---

## 10. 上架后第一周关键动作

1. **ProductHunt 启动** + X/小红书 同步发布
2. **联系 5-10 位 Mac 评测博主**送 Pro 兑换码
3. **申请 App Store 编辑推荐**（提交后立即在 Apple 开发者后台填推荐申请）
4. **建立 Discord/Telegram 用户群**收集反馈
5. **监控崩溃率 + 评论**，48 小时内回复每条评论

---

## 11. 风险与缓解

| 风险 | 影响 | 缓解 |
|---|---|---|
| v1 功能过宽导致 Bug 密度高 | 首发评分被拖 | 分阶段测试（W6 W9 W11 各一轮） |
| 3D Metal 开发延期 | 进度拖延 | W6 开始前先用 2D fallback 验证逻辑 |
| CoreML 模型训练 | 无现成数据 | 用 VNClassifyImageRequest + 自定义规则混合 |
| App Store 审核被拒（TCC 描述） | 上架延期 | FDA 文案参考 CleanMyMac 通过案例，提前给苹果审核团队看 |
| 多语言同步发布 | 文案工作量大 | 简中自己写，英文先上线，日文 V1.1 |

---

## 12. 不做什么（Out of Scope）

明确排除在 v1 之外，避免范围蔓延：
- ❌ 云存储清理（Dropbox / Google Drive）
- ❌ 应用卸载（→kUninstall）
- ❌ 菜单栏系统监控（→kWatch）
- ❌ 重复文件查找高级功能（→kDupe）
- ❌ iOS 同步 / iCloud Drive 清理
- ❌ 网络测速
- ❌ 相似照片检测（参考 Lemon 的，但不在 v1）

---

## 13. 后续版本路线图

- **v1.1**（W14-W18）：评论修复 + 性能优化 + 小功能
- **v1.2**：3D 视图增强（动画 + 主题）
- **v1.3**：规则引擎（用户自定义清理规则）
- **v2.0**：AI 助手（自然语言指令"清理我三个月没用的文件"）

---

## 14. 业务合规与法律

### 14.1 Apple Developer Program 注册 ⚠️ P0
- **类型**：**Individual（个人开发者）**
- **注册材料**：中国大陆身份证 + 信用卡/借记卡（Visa/Mastercard/银联）
- **费用**：$99 USD/年
- **收款**：Apple 打款到关联银行账户（支持中国大陆银联）
- **抽成**：自动加入小型企业计划（年营收 < $1M），首年降至 **15%**（vs 标准 30%）
- **品牌展示**：App Store 开发者名显示"个人开发者姓名"
- **行动项**：W2 之前完成注册并通过 D-U-N-S 验证（如未来转 Organization 需要）

### 14.2 隐私政策 + 服务条款 ⚠️ P0
- **托管方式**：**GitHub Pages + 自写模板**
- **域名**：可绑 `privacy.kraftly.app`（DNS 指向 GitHub Pages）
- **仓库结构**：`kraftly-legal/`（独立仓库，方便多 App 复用）
- **必备条款**：
  - 数据收集声明（明确"零网络上报，仅本地处理"）
  - TCC 权限说明（Full Disk Access、Automation 各用于什么功能）
  - 订阅条款（自动续费机制、取消方式、退款政策）
  - 第三方 SDK 清单（明确"无第三方分析 SDK"）
  - 儿童隐私（COPPA 合规："不向 13 岁以下儿童提供服务"）
  - 联系信息（support@kraftly.app）
  - 法律适用（中国大陆法律）
- **更新机制**：修改 → git commit → GitHub Pages 自动部署
- **行动项**：W4 完成 v1 版本，V1.1 时请法律朋友 review

### 14.3 订阅条款展示 ⚠️ P0
- **触发点**：用户点击"开始试用"前
- **展示形式**：Sheet 弹窗，包含：
  - 价格（如"¥98/年"）
  - 试用时长（"7 天免费试用"）
  - 自动续费说明（"试用结束后自动续费，可在 Apple ID 设置中随时取消"）
  - 链接到完整 Terms（GitHub Pages）
  - 链接到 Privacy Policy（GitHub Pages）
- **按钮**：
  - 主按钮："Continue"（继续）
  - 副按钮："Restore Purchase"（恢复购买）
- **文案**：参考 Apple 官方推荐标准文案（中英文各一套）

### 14.4 Restore Purchase 流程 ⚠️ P0
- **入口**：
  - 订阅 Sheet 中的 "Restore Purchase" 按钮
  - 设置页 → 订阅管理 → "Restore Purchase"
- **实现**：
  ```swift
  try await AppStore.sync()
  // 检查 Transaction.currentEntitlements
  ```
- **UI 反馈**：
  - 成功：Toast "订阅已恢复"
  - 失败：Toast "未找到订阅记录"
- **App Store 审核必查**：必须有此功能

### 14.5 退款政策 UX ⚠️ P1
- **不在 App 内处理退款**（避免违反 App Store 指南 3.1.5）
- **引导文案**：在订阅管理页加：
  > "退款申请请前往 Apple 支持：reportaproblem.apple.com"
- **按钮**：链接到该 URL

### 14.6 App Store 隐私标签 ⚠️ P0
- **后台位置**：App Store Connect → App Privacy
- **勾选规则**（基于"数据是否离开设备"）：

| 数据类型 | 是否收集 | 用途 | 关联身份 |
|---|---|---|---|
| Contact Info | ❌ No | — | — |
| Financial Info | ❌ No | — | — |
| Health & Fitness | ❌ No | — | — |
| Location | ❌ No | — | — |
| Sensitive Info | ❌ No | — | — |
| Contacts | ❌ No | — | — |
| **User Content** | ❌ **No**（仅本地处理，不上传） | — | — |
| Browsing History | ❌ No | — | — |
| Search History | ❌ No | — | — |
| Identifiers | ❌ No | — | — |
| Usage Data | ❌ No | — | — |
| Diagnostics | ❌ No（MetricKit 仅本地） | — | — |
| **Purchases** | ✅ **Yes** | App 功能 | Yes（Apple ID） |

- **重要承诺**：未来如改变"零上报"原则，必须先更新隐私标签再实施，否则审核拒绝

### 14.7 App Store 审核指南合规 ⚠️ P1
- **2.1 App 完整性**：所有截图/视频必须真实展示 App 功能
- **2.3 准确元数据**：描述与实际一致，无误导
- **5.1 隐私**：权限说明透明，隐私政策链接有效
- **4.0 设计**：基本质量门槛，不接受 demo 级别 UI
- **检查清单**：上架前逐条对照

---

## 15. 上架与发布流程

### 15.1 App Store Connect 设置清单 ⚠️ P0
- **W11 任务**：
  1. 注册 Bundle ID：`app.kraftly.sclean`
  2. 创建 App 记录（SKU、Primary Language）
  3. 开启 Capabilities：
     - App Groups（`group.app.kraftly.shared`）
     - In-App Purchase
     - Push Notifications（V1.1）
  4. 签署协议：
     - Paid Applications Agreement
     - Apple Developer Program License Agreement（年度更新）
  5. 设置银行账户 + 税务信息（绑定银联卡）
  6. 填写 App 信息（名称、副标题、类别、年龄分级）
  7. 上传截图 + 预览视频
  8. 填写隐私标签（§14.6）
  9. 填写 App 描述 + 关键词
  10. 设置定价（含地区定价）

### 15.2 代码签名 + Provisioning ⚠️ P1
- **方式**：Xcode 自动管理（Signing Certificate → Apple Development）
- **证书**：
  - Apple Development（开发）
  - Apple Distribution（发布）
- **Provisioning Profile**：
  - Development（开发设备绑定）
  - App Store Distribution（发布）
- **本地存储**：使用 Keychain Access 备份证书（避免丢失）

### 15.3 TestFlight 测试计划 ⚠️ P0
- **内部测试**（W10-W11，无需审核）：
  - 团队成员：自己 + 亲友 5-10 人
  - 用途：核心功能验证、崩溃发现
  - 周期：1-2 周密集测试
- **外部测试**（W11-W12，需 Apple 审核 1-3 天）：
  - 公开招募 50-100 名 beta 测试者
  - 渠道：Discord / 社交媒体 / 邮件列表
  - 用途：兼容性测试、不同 macOS 版本验证
  - 周期：1-2 周
- **测试重点**：
  - FDA 权限引导流程
  - 3D 渲染性能（多设备）
  - 扫描准确性（误报率）
  - 清理安全性（误删率）
  - Widget 交互
- **反馈收集**：TestFlight 内置反馈 + Discord 频道

### 15.4 分阶段发布 ⚠️ P1
- **默认开启**：上架后 7 天分阶段推出
- **比例**：1% → 2% → 5% → 10% → 20% → 50% → 100%
- **监控指标**：崩溃率、评论评分
- **暂停机制**：任一日崩溃率 > 1% 自动暂停

### 15.5 App Store 拒绝应急 ⚠️ P1
- **常见拒绝原因**：
  - FDA 权限描述不清
  - 截图与实际不符
  - 隐私标签错误
  - 订阅条款缺失
- **应急流程**：
  1. 收到拒绝邮件 → 仔细读 rejection reasons
  2. 如属政策合规 → 写 Appeal（详细说明符合条款）
  3. 如属技术问题 → 修复 → 重新提交（通常 24-48 小时二次审核）
  4. 如多次拒绝 → 联系 App Review Board（通过 Apple 开发者支持）

### 15.6 CI/CD 流水线 ⚠️ P1
- **V1 阶段**：手动 release（xcodebuild + 手动上传 App Store Connect）
- **V1.1 升级**：GitHub Actions
  - PR → 自动跑测试 + SwiftLint
  - Merge to main → 自动 Archive
  - Tag → 自动上传 TestFlight
- **工具**：Fastlane（V1.1 评估）

---

## 16. 客户体验

### 16.1 客户支持渠道 ⚠️ P0
- **主渠道**：**Discord 服务器**（`discord.gg/kraftly`）+ 邮箱 `support@kraftly.app`
- **Discord 频道结构**：
  ```
  Kraftly Discord Server
  ├── 📢 announcements   新版本通知
  ├── 💬 general          用户闲聊
  ├── 💡 feature-requests 功能建议
  ├── 🐛 bug-reports      Bug 报告
  ├── 🍎 mac-tips        Mac 使用技巧
  └── 🎨 show-and-tell   用户晒清理成果
  ```
- **中国用户**：微信公众号「Kraftly 助理」+ 备用小红书账号
- **响应 SLA**：
  - P0（崩溃）：24 小时内
  - P1（功能问题）：3 个工作日
  - P2（一般咨询）：7 个工作日

### 16.2 应用内反馈机制 ⚠️ P1
- **入口**：设置页 → "反馈"
- **选项**：
  - "报告 Bug" → 调用邮件 App，预填诊断信息
  - "建议功能" → 调用邮件 App，标题预填
  - "评价 kSpaceClean" → 跳转 App Store 评论页
- **App Store 评论引导**：扫描完成后弹窗"喜欢 kSpaceClean？去 App Store 评价"（仅在清理成功后）

### 16.3 应用图标设计 ⚠️ P0
- **委托设计师**：Fiverr / 99designs / Behance 找 Mac 工具类设计师
- **概念方向**：星系（差异化核心）+ 字母 K
- **交付清单**：
  - 1024×1024 主图标（App Store）
  - 各尺寸：16, 32, 64, 128, 256, 512, 1024
  - macOS App Icon Set（Assets.xcassets）
  - 单色版本（用于菜单栏）
- **设计原则**：
  - 简洁（避免细节过多）
  - 在小尺寸下可识别
  - 色彩饱和度高（深色背景也清晰）
- **预算**：$100-300 一次性委托

### 16.4 品牌设计系统 ⚠️ P1
- **品牌色**：
  - Primary：#7c3aed（紫）
  - Secondary：#3b82f6（蓝）
  - Accent：#f59e0b（橙）
  - Success：#10b981（绿）
  - Danger：#ef4444（红）
- **字体**：
  - UI：SF Pro（系统默认）
  - 代码：SF Mono（系统默认）
- **Logo 字体**：自定义（与委托图标一起设计）
- **Design Tokens**：全部进 kFoundation/DesignSystem

### 16.5 状态 UI（空 / 加载 / 错误）⚠️ P1
- **空状态**：从未扫描 → "点击扫描开始清理"（引导插画）
- **加载状态**：扫描中 → 进度环 + 当前目录 + 已发现大小
- **错误状态**：
  - FDA 失效 → "权限失效，请重新授权"
  - 磁盘不可访问 → "无法读取此磁盘，请检查连接"
  - 扫描失败 → "扫描失败，点击重试"
- **通用组件**：每个 Feature 强制使用三种状态

### 16.6 首次启动 Onboarding ⚠️ P1
- **第 1 屏**：价值介绍（"让你的 Mac 始终有足够空间"）+ 视觉示意
- **第 2 屏**：核心功能预告（3D 星系 + AI 分类 + 一键清理）
- **第 3 屏**：权限说明（"我们需要权限才能扫描系统缓存，**所有处理在本地完成**"）
- **第 4 屏**：FDA 引导（§3.5）
- **第 5 屏**：开始首次扫描
- **跳过机制**：第 1 屏可跳过，后续必须完成

---

## 17. 可访问性设计

### 17.1 VoiceOver 支持 ⚠️ P0
- **核心要求**：所有交互元素必须有 `accessibilityLabel`
- **3D 球体**：
  ```swift
  sphere.accessibilityLabel = "Documents, 64 GB total"
  sphere.accessibilityHint = "Activate to view files in this category"
  sphere.accessibilityTraits = .button
  ```
- **替代视图**：提供 **List View** 作为 Accessible Alternative
  - macOS 提供 Accessibility Rotor 切换 3D ↔ List
  - List 视图是普通 SwiftUI `Table`，完整 VoiceOver 支持
- **测试**：用 VoiceOver 走完核心流程（扫描 → 选中 → 清理）

### 17.2 键盘导航 ⚠️ P0
- **所有功能可纯键盘操作**（不依赖鼠标）
- **快捷键**：
  - `Cmd + S` → 开始扫描
  - `Cmd + Shift + C` → 一键清理
  - `Cmd + ,` → 设置
  - `Cmd + ?` → 显示快捷键列表
- **Tab 顺序**：合理（顶部 → 内容 → 操作栏 → 设置入口）
- **Focus Ring**：所有按钮、输入框有清晰 focus 指示

### 17.3 动效偏好 ⚠️ P1
- **Reduce Motion 检测**：
  ```swift
  if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      // 关闭 3D 旋转、淡出等动效
  }
  ```
- **降级效果**：扫描结果直接呈现，无过渡动效

### 17.4 文字大小 ⚠️ P1
- **支持 Dynamic Type**：使用 `.font(.body)` 等语义化字号
- **不要硬编码 px**：所有字号走系统 token

### 17.5 高对比度 ⚠️ P1
- **检测**：系统 Increase Contrast / Reduce Transparency 设置
- **配色调整**：在 Dark Mode + Increase Contrast 下保证 ≥ 4.5:1 对比度

### 17.6 包容性差异化亮点
- 苹果 Design Award 评审重要维度：**Inclusivity**
- App Store 推荐偏好可访问性完善的产品
- 把"3D 视觉冲击 + 列表视图替代"作为包容性叙事：
  > "We believe powerful tools should be accessible to everyone. kSpaceClean offers both a stunning 3D galaxy view and a fully accessible list view."

---

## 18. 运营与质量监控

### 18.1 崩溃监控（MetricKit）⚠️ P0
- **实现**：
  ```swift
  // App 启动时
  final class MetricKitSubscriber: NSObject, MXMetricManagerSubscriber {
      func didReceive(_ payloads: [MXMetricPayload]) { /* 本地存储 */ }
      func didReceive(_ payloads: [MXDiagnosticPayload]) { /* 本地存储 */ }
  }
  MXMetricManager.shared.add(subscriber)
  ```
- **数据流向**：仅本地存储（如 SQLite 或 JSON 文件），不上传
- **查看方式**：开发者本地读取分析
- **优势**：完全符合"零网络上报"原则

### 18.2 更新频率策略 ⚠️ P1
- **大版本**：6-12 月一次（重大新功能）
- **小版本**：2-4 周一次（Bug 修复 + 小功能）
- **不强制节奏**：按需发布
- **紧急修复**：24-48 小时内（关键 Bug）

### 18.3 macOS 版本支持窗口 ⚠️ P1
- **当前**：macOS 13.0+
- **停止支持时机**：macOS 13 用户占比 < 5%（参考 App Store Connect 数据）
- **决策节奏**：每年评估一次

### 18.4 Bug 优先级分级 ⚠️ P1
| 级别 | 定义 | SLA |
|---|---|---|
| **P0** | 核心功能崩溃、数据丢失 | 24h 内修复 |
| **P1** | 功能降级但不阻塞 | 1 周内 |
| **P2** | UI 小问题 | 下版本 |
| **P3** | feature request | backlog |

### 18.5 故障应急 ⚠️ P1
- **扫描崩溃**：自动保存已扫描部分，下次启动恢复
- **App 启动崩溃**：保留 MetricKit 记录，简化下版本复现
- **误删文件**：30 天清理历史可回滚（§3.4 已设计）

### 18.6 数据迁移 ⚠️ P2
- **Core Data Lightweight Migration**：默认开启
- **重大 schema 变更**：手动 mapping model

---

## 19. 营销与增长

### 19.1 GTM 详细计划 ⚠️ P0
- **T-30**（W11）：landing page 上线、收集邮箱
- **T-21**（W12）：社交媒体预热（X / 小红书）
- **T-14**（W12）：联系 Mac 评测博主（10-15 人）
- **T-7**（W13）：Product Hunt 准备、新闻稿定稿
- **T-1**：上架前最终检查 + 团队待命
- **T-0**（上架日）：上架 + 同步发布
- **T+1**：跟进评论、社群互动
- **T+3**：申请苹果推荐（Apple 开发者后台）
- **T+7**：第一次小迭代
- **T+30**：V1.1 发布
- **T+60**：回顾 KPI，调整策略

### 19.2 Product Hunt 发布 ⚠️ P1
- **发布时间**：上架日 T-0（北京时间晚 9 点 = 旧金山时间早 6 点，PH 日历新一天）
- **材料准备**：
  - Logo + 4 张截图
  - 30 秒视频
  - 描述（英文，简短有故事性）
  - 首发优惠（"前 100 名订阅者终身 8 折"）
- **推广**：
  - 邀请 5-10 个朋友首发点赞
  - Discord / 邮件列表同步发布
  - 当天在线回复评论

### 19.3 Press Kit ⚠️ P1
- **托管**：`press.kraftly.app`（GitHub Pages）
- **内容**：
  - Logo（SVG + PNG，多背景色）
  - 截图（5 张主截图 + 各尺寸）
  - 产品说明（200 字 / 500 字 / 1000 字 三版）
  - 媒体联系人（press@kraftly.app）
  - 关键事实（公司、成立时间、技术亮点）

### 19.4 社交媒体 ⚠️ P1
- **X（英文）**：@kraftlyapp（开发日记 + Mac 技巧 + 新功能）
- **小红书（中文）**：Kraftly（教程 + 案例）
- **Mastodon**：@kraftly@macodon.social（开源向）
- **内容节奏**：每周 2-3 帖

### 19.5 社区建设 ⚠️ P1
- **Discord 服务器**（§16.1 已详述）
- **运营节奏**：每周至少 1 次开发者互动
- **种子用户**：早期招募 20-50 名活跃用户

---

## 20. 成功指标（KPI）⚠️ P0

### 20.1 V1 上市 90 天目标

| 指标 | 目标值 | 衡量方式 |
|---|---|---|
| **下载量** | 5,000 | App Store Connect |
| **试用→订阅转化率** | > 5% | StoreKit 2 数据 |
| **评分** | > 4.5 ⭐ | App Store 平均 |
| **崩溃率** | < 0.1% | MetricKit |
| **MRR（首月）** | $1,000 | App Store Connect |
| **T+30 留存** | 40% | 自有统计 |

### 20.2 北极星指标
**每周活跃清理用户数（Weekly Active Cleaning Users）**
- 综合反映：用户粘性 + 清理使用频次 + 实际价值感知
- 目标：T+90 = 1,500 WACU

### 20.3 监控仪表盘
- **每日查看**：App Store Connect（下载、收入、评分）
- **每周查看**：崩溃率 + 评论趋势
- **每月复盘**：KPI 进度 + 用户反馈 + 路线图调整

---

## 附录 A：与 CLAUDE.md 的关系

本文档是 `CLAUDE.md` 第 3 章节的完整展开版。所有架构决策（Workspace 结构、技术选型、能力降级策略、沙箱与权限）以 `CLAUDE.md` 为准。

**UI 交互设计**：[2026-07-25-kraftly-kspaceclean-ui-design.md](./2026-07-25-kraftly-kspaceclean-ui-design.md)

包含：
- 设计系统基础（品牌色板 / 明暗模式 / 字体层级 / 间距网格 / 圆角阴影 / 图标体系）
- 窗口架构（Toolbar / Sidebar / Status Bar）
- 15+ 屏幕文字 Wireframe（Disk Galaxy / Smart Scan / Cleanup / History / Onboarding 5 屏 / Paywall / Settings / Menu Bar / List View / Finder Extension）
- 导航图（Mermaid）
- 键盘快捷键映射（18 组）
- VoiceOver 标签映射（每页面）
- 动画规格（12 组时长曲线）
- Widget 三尺寸设计 + Live Activity 设计
- 空/加载/错误状态矩阵
- 响应式行为（窗口自适应）
- 设计系统文件结构

**详细实现方案**：[2026-07-25-kraftly-kspaceclean-detailed-design.md](./2026-07-25-kraftly-kspaceclean-detailed-design.md)

包含：
- 分层架构与模块依赖图
- 12 种设计模式应用说明
- 6 个核心流程图（Mermaid）
- 5 个类图（App/SmartScan/Cleanup/Galaxy/Permission）
- ER 图 + 值对象模型
- 3 个状态机（扫描/清理/Widget）
- 3 个时序图（端到端/Widget/LiveActivity）
- 模块详细代码骨架（FileScanner/CoreML/Metal/PermissionCenter/WidgetSnapshot）
- 错误处理策略
- 性能预算 + 测试策略
- **§15 可访问性架构**（双视图设计 + ListView + Reduce Motion）
- **§16 MetricKit 监控架构**（本地崩溃监控）
- **§17 CI/CD 架构**（GitHub Actions + Fastlane）
- **§18 Discord 社区架构**（服务器结构 + 运营节奏）

**Gap Analysis**：[2026-07-25-kraftly-kspaceclean-gap-analysis.md](./2026-07-25-kraftly-kspaceclean-gap-analysis.md)

包含：
- 47 项遗漏项分析
- P0/P1/P2 三级优先级
- 10 维度全面审查（A-J）

---

## 附录 B：参考但不复制

Lemon 项目位于 `/Users/mengjianjun/Documents/ai/aicoding/macapp/Lemon`。仅参考以下逻辑：
- 扫描算法（两阶段 size→hash）
- Daemon 架构思路（新写为 Swift XPC Service）
- 大文件查找策略
- 重复文件检测算法

不复用 Lemon 任何 Objective-C / C++ 代码、XIB、SDK 集成。

## 附录 C：术语表

| 术语 | 含义 |
|---|---|
| **FDA** | Full Disk Access（macOS 完全磁盘访问权限） |
| **TCC** | Transparency, Consent, and Control（macOS 权限框架） |
| **Perceptual Hash** | 感知哈希，用于相似图片/视频检测 |
| **ADA** | Apple Design Award（苹果年度设计奖） |
| **ASO** | App Store Optimization（应用商店优化） |
| **SKU** | Stock Keeping Unit（最小存货单位，此处指内购商品） |