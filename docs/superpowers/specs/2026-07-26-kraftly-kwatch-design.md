# kWatch v1 完整技术规格书

**项目**：Kraftly Mac App Suite — 第二款 App
**文档版本**：v1.0
**最后更新**：2026-07-26
**状态**：设计定稿

---

## 目录

1. [产品定位](#1-产品定位)
2. [定价与盈利模式](#2-定价与盈利模式)
3. [完整功能规格](#3-完整功能规格)
4. [技术架构](#4-技术架构)
5. [数据层设计](#5-数据层设计)
6. [类图与模块职责](#6-类图与模块职责)
7. [核心检测实现细节](#7-核心检测实现细节)
8. [通讯方式](#8-通讯方式)
9. [完整 UX 交互设计](#9-完整-ux-交互设计)
10. [错误处理与边界条件](#10-错误处理与边界条件)
11. [本地化策略](#11-本地化策略)
12. [ASO 策略](#12-aso-策略)
13. [上架时间表](#13-上架时间表)
14. [开放问题与风险](#14-开放问题与风险)
15. [隐私与合规](#15-隐私与合规)
16. [崩溃监控与诊断](#16-崩溃监控与诊断)
17. [测试策略](#17-测试策略)
18. [营销与发布节奏](#18-营销与发布节奏)
19. [风险缓解 Plan B](#19-风险缓解-plan-b)

---

## 1. 产品定位

### 1.1 一句话定位

> 菜单栏上最优雅的 Mac 系统监控。

### 1.2 目标用户

| 用户群体 | 核心痛点 | 使用方式 |
|:---------|:---------|:---------|
| **Mac 全人群** | 想知道 Mac "卡不卡"，但不关心复杂数据 | Widget 一眼看状态 |
| **设计师/创意工作者** | 渲染/导出时监控资源瓶颈，同时在意菜单栏美观 | 菜单栏图表 + Dashboard |
| **极客/效率追求者** | 需要温度/风扇数据，想自动化触发脚本 | 完整 7 类指标 + Shortcuts |

### 1.3 核心差异化（vs 竞品）

| 维度 | iStat Menus | Stats（开源） | kWatch |
|:-----|:-----------:|:-------------:|:------:|
| 定价 | $11.99 买断 | 免费 | **Freemium $7.99 Pro** |
| 视觉设计 | 传统 UI | 粗糙 | **Apple 设计语言 + 毛玻璃** |
| 菜单栏图表 | ✅ 数字/图标 | ✅ 数字 | **✅ 微型趋势图引擎** |
| Interactive Widget | ❌ | ❌ | **✅ (macOS 14+)** |
| Live Activity | ❌ | ❌ | **✅ (macOS 14+)** |
| Spotlight 集成 | ❌ | ❌ | **✅** |
| Shortcuts | ❌ | ❌ | **✅ 8 个 Intents** |
| 温度/风扇 | ✅ | ✅ | ✅ Pro |
| 进程级网络 | ✅ | 部分 | ✅ Pro 进程排行 |
| 历史趋势 | ✅ | ✅ | ✅ Pro |

### 1.4 品牌与命名

- **App 名称**：kWatch
- **Bundle ID**：`app.kraftly.kwatch`
- **品牌归属**：Kraftly（与 kSpaceClean 统一）
- **App Store 分类**：Utilities > System

---

## 2. 定价与盈利模式

### 2.1 定价层级

| 层级 | 价格 | 模式 | 包含内容 |
|:----:|:----:|:----:|:---------|
| **Free** | 免费 | — | CPU + 内存 + 磁盘 + 网络、菜单栏图表（3 种风格）、基础 Widget、Spotlight 查询、基础 Shortcuts |
| **Pro** | **$7.99** | 买断 | 全部 7 类指标（+温度/风扇/电池）、进程排行、历史趋势（24h/7d/30d）、Interactive Widget、Live Activity、自定义告警阈值、自定义 Widget、完整 Shortcuts（8 个） |

### 2.2 地区定价

| 地区 | kWatch Pro |
|:----:|:----------:|
| 🇺🇸 美区 | $7.99 |
| 🇪🇺 欧区 | €7.99 |
| 🇨🇳 中区 | ¥50 |
| 🇯🇵 日区 | ¥1,200 |
| 🇬🇧 英区 | £7.99 |

### 2.3 Bundle 策略（上线后推出）

| Bundle | 包含 App | 价格 | 节省 | 阶段 |
|:-------|:---------|:----:|:----:|:-----|
| **Kraftly Duo**（v1.0 上架时） | kSpaceClean（年订阅）+ kWatch Pro（买断） | **$22.99/年** | ~$5 | W13 |
| **Kraftly Trio**（kDupe 上架后） | + kDupe Pro | **$32.99/年** | ~$7 | 后续 |
| **Kraftly Suite**（4 款齐全后） | + kUninstall Pro | **$44.99/年** | ~$10 | 后续 |

### 2.4 首发优惠与定价策略

| 策略 | 内容 | 时机 |
|:-----|:------|:-----|
| **首发优惠** | 上线首月 $4.99 限时（节省 ~38%） | 上线日 - 30 天 |
| **Pro 7 天试用** | Free 用户第 8 天弹窗，引导 7 天全功能试用 | 安装后 D+8 |
| **学生/教育折扣** | 通过 Apple Developer Education Program 申请 50% off | 上线后 1 个月内 |
| **Family Sharing** | 开启（App Store Connect 配置） | 默认 |
| **价格不透明** | 美区 $7.99 显示但 EU/UK/中/日按汇率智能定价（如 Table 2.2） | 永久 |

### 2.5 盈利设计原则

- **监控是"一次性价值"**：买断模式符合用户心智（vs 清理需要持续更新数据/规则）
- **$7.99 < iStat $11.99**：价差本身就是购买理由
- **Freemium 不阉割核心体验**：免费层 4 项指标足够日常使用，Pro 解锁"发烧友"场景
- **Bundle 锁定跨 App 持有**：降低 churn，提高 Kraftly 品牌黏性
- **Pro 价值 = 平台集成 + 历史 + 自定义告警 + 高级监控（Intel Mac 温度/风扇/电池）**：即使 Apple Silicon 上高级监控降级，Pro 仍有充分价值（详见 Section 14）

---

## 3. 完整功能规格

### 3.1 监控指标（7 类）

| # | 指标 | 数据点 | Free | Pro | 最低系统 |
|:-:|:-----|:-------|:----:|:---:|:--------:|
| 1 | **CPU** | 总使用率、各核心频率、负载平均、进程 CPU Top、温度 | ✅ | ✅ | 13+ |
| 2 | **内存** | 总量、已用、压力指示、Swap、App 使用量 | ✅ | ✅ | 13+ |
| 3 | **磁盘** | 各分区容量、读写速度、占用 Top | ✅ | ✅ | 13+ |
| 4 | **网络** | 上下行速率、接口列表、连接数、进程流量 Top | ✅ | ✅ | 13+ |
| 5 | **温度** | CPU/GPU/电池/机身传感器 | ❌ | ✅ | 13+ |
| 6 | **风扇** | 各风扇 RPM、名称（只读） | ❌ | ✅ | 13+ |
| 7 | **电池** | 健康度、循环次数、剩余时间、温度（仅笔记本） | ❌ | ✅ | 13+ |

> **温度说明**：CPU 指标行包含 CPU 封装温度（Free 可用，在 CPU 卡片内展示）；独立的温度分类（全部传感器：GPU/电池/机身等）需 Pro 解锁。Free 用户看不到温度类别卡片和温度趋势页面。

### 3.2 菜单栏显示

| 功能 | Free | Pro | 说明 |
|:-----|:----:|:---:|:-----|
| 图表模式（默认） | ✅ | ✅ | 半透明 SVG-style 趋势线，6 秒滑动窗口 |
| 数字模式 | ✅ | ✅ | 图标 + 数值紧凑显示 |
| 极简模式 | ✅ | ✅ | 仅颜色状态（绿/黄/红） |
| 完全自定义 | ❌ | ✅ | 任意组合 + 拖拽排序 |
| Tooltip 悬停详情 | ✅ | ✅ | 800ms 弹出详细数据面板 |
| 右键菜单 | ✅ | ✅ | 快捷操作入口 |

### 3.3 主窗口 Dashboard

| 视图 | Free | Pro | 说明 |
|:-----|:----:|:---:|:-----|
| 概览 | ✅ | ✅ | 6 卡片网格布局，实时数据 + 趋势图 |
| 趋势（24h/7d/30d） | ❌ | ✅ | 可切换指标的时间序列图表 |
| 进程排行 | Top 5 | Top 50 + 搜索 + 详情 + 分组 | CPU/内存排序；Pro 含网络流量 |
| 告警 | ✅ 基础 | ✅ 自定义 | 基础阈值（CPU/内存/磁盘）+ Pro 自定义阈值（温度等） |
| 设置 | ✅ | ✅ | 含 Pro 锁定项的设置面板 |

### 3.4 平台集成

| 集成 | Free | Pro | 最低系统 |
|:-----|:----:|:---:|:--------:|
| 基础桌面 Widget | ✅ | ✅ | 13+ |
| Interactive Widget | ❌ | ✅ | 14+ |
| Live Activity | ❌ | ✅ | 14+ |
| Spotlight 查询 | ✅ | ✅ | 13+ |
| Shortcuts（4 个基础） | ✅ | ✅ | 13+ |
| Shortcuts（完整 8 个） | ❌ | ✅ | 13+ |
| 通知中心告警 | 基础 | 自定义阈值 | 13+ |
| 菜单栏自动启动 | ✅ | ✅ | 13+ |

### 3.5 Spotlight 支持的查询

| 查询 | 返回 |
|:-----|:------|
| "kWatch" | 打开主窗口 |
| "CPU 多少度" / "CPU temperature" | 当前 CPU 温度 + 趋势（Pro 显示温度值，Free 引导升级） |
| "Mac 内存" / "memory usage" | 当前内存使用量和压力状态 |
| "磁盘空间" / "disk usage" | 磁盘容量和可用空间 |
| "网络速度" / "network speed" | 当前上下行速率 |

### 3.6 Shortcuts App Intents（8 个）

| # | Intent | Free | Pro | 输入 | 输出 |
|:-:|:-------|:----:|:---:|:-----|:-----|
| 1 | Get CPU Usage | ✅ | ✅ | 无 | 当前使用率 (Double) |
| 2 | Get Memory Usage | ✅ | ✅ | 无 | 已用/总量 (String) |
| 3 | Get Disk Usage | ✅ | ✅ | 路径 (可选) | 可用/总量 (String) |
| 4 | Get Network Speed | ✅ | ✅ | 接口 | 上传/下载速率 |
| 5 | Get Temperature | ❌ | ✅ | 传感器类型 | 温度值 (String) |
| 6 | Get Fan Speed | ❌ | ✅ | 风扇编号 | RPM (Int) |
| 7 | Get Battery Status | ❌ | ✅ | 无 | 电量+健康度 |
| 8 | Start Monitoring Session | ❌ | ✅ | 时长 | Live Activity 显示 |

### 3.7 v1 不做范围（YAGNI）

- ❌ 远程监控（云端/手机查看）
- ❌ 多机管理（局域网监控其他 Mac）
- ❌ 系统优化建议（引导到 kSpaceClean）
- ❌ 自定义脚本/插件系统
- ❌ GPU 详细监控（仅温度，不做显存/负载/频率）
- ❌ Finder 扩展（菜单栏 App 不需要）
- ❌ 风扇控制（v1 只读，避免保修/安全争议）
- ❌ 网络测速（保持被动监控）
- ❌ 自定义皮肤/主题市场

---

## 4. 技术架构

### 4.1 总体架构：Clean Architecture + MVVM + Coordinator

```
┌──────────────────────────────────────────────────────────────┐
│               Presentation Layer (SwiftUI + AppKit)           │
│                                                               │
│  Views (SwiftUI) ← ViewModels (@MainActor @Observable)        │
│  MenuBar (MenuBarExtra) / Dashboard (NSWindow) / Widget       │
│  Live Activity (ActivityKit) / Spotlight (CoreSpotlight)      │
└────────────────────────┬─────────────────────────────────────┘
                         │ AsyncStream<MetricsSnapshot>
┌────────────────────────▼─────────────────────────────────────┐
│                 Domain Layer (Pure Swift)                      │
│                                                               │
│  UseCases: MetricsStreamUseCase / ProGateUseCase              │
│  Entities: MetricsSnapshot / MetricSample / AlertEvent        │
│  Repositories (Protocols): MetricsRepositoryProtocol          │
│                               HistoryRepositoryProtocol        │
│                               PreferencesRepositoryProtocol    │
└────────────────────────┬─────────────────────────────────────┘
                         │ Protocol 实现注入
┌────────────────────────▼─────────────────────────────────────┐
│                  Data Layer (Swift Concurrency)                │
│                                                               │
│  MetricsAggregator (actor) — 统一采样调度                     │
│    ├── CPUMonitor (actor)          — host_processor_info      │
│    ├── MemoryMonitor (actor)       — host_statistics64        │
│    ├── DiskMonitor (actor)         — statfs / IOKit           │
│    ├── NetworkMonitor (actor)      — getifaddrs               │
│    ├── SMCProvider (actor, Pro)    — IOKit AppleSMC           │
│    │   ├── TemperatureMonitor      — SMC TC0P / TG0P / ...   │
│    │   ├── FanMonitor              — SMC F0Ac / F1Ac         │
│    │   └── BatteryMonitor          — IOKit + IOPS            │
│    └── ProcessEnumerator (actor)   — libproc                  │
│                                                               │
│  CoreDataStack / UserDefaults (App Group)                     │
└────────────────────────┬─────────────────────────────────────┘
                         │ 系统调用
┌────────────────────────▼─────────────────────────────────────┐
│               System APIs (macOS 内置)                         │
│                                                               │
│  sysctl / host_processor_info / host_statistics64 / statfs    │
│  getifaddrs / IOKit / SMC / libproc / IOPS / CoreSpotlight    │
└──────────────────────────────────────────────────────────────┘
```

### 4.2 依赖方向

- **上层依赖下层，下层绝不依赖上层**
- **Domain 层零依赖**（不 import UIKit/AppKit/SwiftUI）
- **Data 层实现 Domain 定义 Protocol**
- **kFoundation 不引用任何 App 代码**

### 4.3 应用设计模式清单

| 模式 | 用途 | 体现位置 |
|:-----|:------|:---------|
| **MVVM** | 视图与业务逻辑分离 | DashboardViewModel， ProcessesViewModel， SettingsViewModel |
| **Coordinator** | 导航与生命周期管理 | AppCoordinator， OnboardingCoordinator |
| **Repository** | 数据访问抽象 | MetricsRepository， HistoryRepository， PreferencesRepository |
| **Strategy** | 采样/图表策略可切换 | SamplingStrategy（fixed/adaptive）， ChartStyle |
| **Observer (AsyncStream)** | 监控数据多消费者 | MetricsAggregator → N 个 subscribers |
| **Producer-Consumer** | 单生产者多消费者 | AsyncStream fan-out 模式 |
| **Singleton + Service Locator** | 依赖注入 | AppContainer 集中构造 |
| **State Machine** | App 复杂状态流转 | AppState， LiveActivityState |
| **Adapter** | 系统 API 隔离 | SMCAdapter， IOKitAdapter， sysctlAdapter |
| **Decorator (Gated)** | 免费/Pro 功能分割 | ProGatedAggregator 包装 |
| **Flyweight** | 历史数据采样压缩 | HistoryRingBuffer（环形缓冲区） |
| **Builder** | Widget/Dashboard 配置 | DashboardBuilder， WidgetConfigBuilder |

### 4.4 Swift 并发模型

```
@MainActor:
    AppCoordinator
    MenuBarViewModel
    DashboardViewModel
    ProcessesViewModel
    SettingsViewModel
    WidgetEntryView
         │
         │  AsyncStream<MetricsSnapshot>.shared (bufferingPolicy: .bufferingNewest(1))
         ▼
actor MetricsAggregator:
    - let providers: [any MetricsProvider]
    - var subscribers: [UUID: AsyncStream<MetricsSnapshot>.Continuation]
    - func start() / stop()
    - func subscribe() -> AsyncStream<MetricsSnapshot>
    - func currentSnapshot() -> MetricsSnapshot?
         │
         │  await provider.snapshot()
         ▼
actor CPUMonitor: MetricsProvider
actor MemoryMonitor: MetricsProvider
actor DiskMonitor: MetricsProvider
actor NetworkMonitor: MetricsProvider
actor SMCProvider: MetricsProvider      // Pro
actor ProcessEnumerator: MetricsProvider

关键并发原则:
  - AsyncStream 使用 .bufferingNewest(1) 策略：采样快于消费时丢弃旧值，避免内存堆积
  - 每个 Provider 是独立 actor，失败隔离不互相阻塞
  - MetricsAggregator 是单生产者多消费者模型，通过 continuation broadcast
  - UI 订阅者必须在 MainActor 上消费（@Observable 自动处理）
```

### 4.5 Apple Silicon 兼容性策略（关键风险）

```
兼容性分级:

┌────────────────┬─────────────────┬────────────────────────┐
│ 监控指标        │ Intel Mac       │ Apple Silicon          │
├────────────────┼─────────────────┼────────────────────────┤
│ CPU 使用率      │ ✅ host_processor_info │ ✅ 同样支持        │
│ 内存           │ ✅ host_statistics64   │ ✅ 同样支持        │
│ 磁盘           │ ✅ statfs              │ ✅ 同样支持        │
│ 网络           │ ✅ getifaddrs          │ ✅ 同样支持        │
│ 进程           │ ✅ libproc             │ ✅ 同样支持        │
│ CPU 封装温度    │ ✅ SMC TC0P            │ ⚠️ fallback 1:    │
│                │                       │   sysctl thermal_  │
│                │                       │   level (部分机型) │
│                │                       │ ⚠️ fallback 2:    │
│                │                       │   IOHIDEvent 估算  │
│ GPU 温度       │ ✅ SMC TG0P            │ ⚠️ 同上 fallback  │
│ 风扇 RPM       │ ✅ SMC F0Ac/F1Ac       │ ❌ 不支持          │
│                │                       │   (Apple Silicon 无 │
│                │                       │    可调速风扇)       │
│ 电池健康度      │ ✅ IOKit IOAppleBattery│ ✅ 同样支持       │
└────────────────┴─────────────────┴────────────────────────┘

降级策略:
  - Apple Silicon 上 Pro 用户看到"风扇卡片"显示"该设备无可调速风扇"
  - CPU 封装温度：尝试 SMC → sysctl → 隐藏
  - GPU 温度：Apple Silicon 集成，统一 CPU/GPU 报告
  - Pro 价值重新聚焦：平台集成（Widget/LA）+ 24h/7d/30d 历史 + 自定义告警
  - ASO 文案明确："温度支持因机型而异，详见官网兼容性列表"
```

### 4.6 关键架构决策

| 决策 | 选择 | 替代方案 | 理由 |
|:-----|:------|:---------|:-----|
| 菜单栏实现 | **MenuBarExtra** (macOS 13+) | NSStatusItem | SwiftUI 原生，代码量减半 |
| 图表渲染 | **SwiftUI Charts** | Core Graphics / Metal | macOS 13+ 原生，性能足够 |
| 数据采集 | **sysctl + IOKit + libproc** | NSTask 调用命令 | 纯 API 调用，无性能开销 |
| SMC 读取 | **IOKit AppleSMC** | 外部驱动/工具 | Apple 标准接口（需 FDA） |
| 并发 | **actor + AsyncStream** | Combine / OperationQueue | 结构化并发，自动背压 |
| 历史存储 | **Core Data** | SQLite / JSON | 复用 kSpaceClean 模式 |
| 配置存储 | **UserDefaults (App Group)** | 文件 | 共享 Widget/Live Activity |
| 后台运行 | **LSUIElement + SMAppService** | LaunchDaemon | App Store 合规 |
| 采样率 | **1Hz 默认，0.5-5Hz 可配** | 固定 5Hz | 平衡实时性与功耗 |
| Free/Pro | **运行时 gating** | 编译期 target | 单一 binary，减少维护 |
| App Group | **group.app.kraftly.kwatch** | — | App ↔ Widget ↔ LA 共享 |
| 跨进程共享数据 | **App Group JSON snapshot** | Core Data | 避免文件锁冲突（详见 5.4） |

### 4.7 App Container 依赖图（协议化 DI）

```swift
// 协议抽象（便于测试和替换实现）
@MainActor
protocol AppContainerProtocol: AnyObject {
    var coreDataStack: CoreDataStack { get }
    var preferences: PreferencesRepository { get }
    var storeManager: StoreManager { get }
    var aggregator: MetricsAggregator { get }
    var metricsRepository: MetricsRepository { get }
    var historyRepository: HistoryRepository { get }
    var appCoordinator: AppCoordinator { get }
}

// 生产环境实现
@MainActor
final class LiveAppContainer: AppContainerProtocol {
    let coreDataStack: CoreDataStack
    let preferences: PreferencesRepository
    let storeManager: StoreManager
    let aggregator: MetricsAggregator
    let metricsRepository: MetricsRepository
    let historyRepository: HistoryRepository
    let appCoordinator: AppCoordinator

    init() {
        // 1. 初始化持久层
        self.coreDataStack = CoreDataStack(modelName: "kWatch", appGroupID: "group.app.kraftly.kwatch")
        self.preferences = PreferencesRepository(suiteName: "group.app.kraftly.kwatch")

        // 2. 初始化 StoreKit
        self.storeManager = StoreManager()

        // 3. 构建 Provider 列表
        let providers: [any MetricsProvider] = [
            CPUMonitor(),
            MemoryMonitor(),
            DiskMonitor(),
            NetworkMonitor(),
            ProcessEnumerator()
        ]

        // 4. 初始化聚合器
        self.aggregator = MetricsAggregator(
            providers: providers,
            samplingStrategy: AdaptiveSamplingStrategy()
        )
        self.metricsRepository = MetricsRepository(aggregator: aggregator)
        self.historyRepository = HistoryRepository(coreDataStack: coreDataStack)

        // 5. 初始化 Coordinator
        self.appCoordinator = AppCoordinator(
            metricsRepository: metricsRepository,
            historyRepository: historyRepository,
            preferences: preferences,
            store: storeManager
        )
    }
}

// 全局访问入口（仅 UI 层使用，ViewModel 通过构造函数注入 AppContainerProtocol）
@MainActor
enum AppContainerProvider {
    static let shared: AppContainerProtocol = LiveAppContainer()
}

// 测试环境实现（注入 mock Provider / Repository）
@MainActor
final class TestAppContainer: AppContainerProtocol {
    // ... 测试时构造，注入 mock
}
```

**DI 原则**：
- `AppContainerProtocol` 只暴露只读属性，ViewModel 接受具体依赖而非整个 container
- 测试时替换 `TestAppContainer`，所有 mock 通过构造函数注入
- 全局访问点 `AppContainerProvider.shared` 仅在 App 启动根组件（`kWatchApp`、`AppCoordinator`）中使用
- ViewModel 不直接访问 `shared`，通过 `AppCoordinator` 注入依赖

---

## 5. 数据层设计

### 5.1 核心数据模型

#### MetricsSnapshot（领域模型，不可变 Value Type）

```swift
struct MetricsSnapshot: Sendable, Codable, Equatable {
    let timestamp: Date
    let cpu: CPUMetrics
    let memory: MemoryMetrics
    let disk: DiskMetrics
    let network: NetworkMetrics
    let temperature: TemperatureMetrics?     // Pro only
    let fans: FanMetrics?                     // Pro only
    let battery: BatteryMetrics?              // Pro only, 仅笔记本
    let topProcesses: [ProcessUsage]          // Free: 最多 5 个
}
```

#### CPUMetrics

```swift
struct CPUMetrics: Sendable, Codable, Equatable {
    let totalUsage: Double                  // 0.0 - 1.0
    let perCoreUsage: [Double]              // 每核使用率
    let loadAverage1: Double                // 1 分钟
    let loadAverage5: Double                // 5 分钟
    let loadAverage15: Double               // 15 分钟
    let frequencyMHz: [Double]?             // 每核频率 (Pro / 可选)
    let temperatureCelsius: Double?         // CPU 封装温度 (Pro)
}
```

#### MemoryMetrics

```swift
struct MemoryMetrics: Sendable, Codable, Equatable {
    let totalBytes: UInt64
    let usedBytes: UInt64
    let appBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let swapUsedBytes: UInt64
    let swapTotalBytes: UInt64
    let pressure: PressureLevel             // .normal / .warning / .critical
    let topProcesses: [ProcessMemoryUsage]  // Free: 最多 3 个
}

enum PressureLevel: String, Sendable, Codable {
    case normal
    case warning
    case critical
}
```

#### DiskMetrics

```swift
struct DiskMetrics: Sendable, Codable, Equatable {
    let volumes: [VolumeInfo]
    let readBytesPerSec: UInt64
    let writeBytesPerSec: UInt64
    let iops: UInt64?                       // Pro
    let temperatureCelsius: Double?         // Pro（需 SMC TN0P）
}

struct VolumeInfo: Sendable, Codable, Equatable, Identifiable {
    var id: String { mountPoint.path }
    let mountPoint: URL
    let name: String
    let totalBytes: UInt64
    let usedBytes: UInt64
    let isRemovable: Bool
    let fileSystem: String
}
```

#### NetworkMetrics

```swift
struct NetworkMetrics: Sendable, Codable, Equatable {
    let interfaces: [NetworkInterface]
    let totalUploadBytesPerSec: UInt64
    let totalDownloadBytesPerSec: UInt64
    let tcpConnections: Int
    let topProcesses: [ProcessNetworkUsage] // Pro
}

struct NetworkInterface: Sendable, Codable, Equatable, Identifiable {
    var id: String { name }
    let name: String                        // "en0", "en1"
    let displayName: String                 // "Wi-Fi", "Ethernet"
    let ipAddress: String?
    let isUp: Bool
    let uploadBytesPerSec: UInt64
    let downloadBytesPerSec: UInt64
    let totalUploadBytes: UInt64
    let totalDownloadBytes: UInt64
}
```

#### TemperatureMetrics（Pro）

```swift
struct TemperatureMetrics: Sendable, Codable, Equatable {
    let cpuCores: [String: Double]          // "TC0P": 65.0
    let gpuTemp: Double?                    // "TG0P"
    let batteryTemp: Double?                // "TB0T"
    let ambientTemp: Double?                // 环境温度
    let allSensors: [String: Double]        // 全部可用 SMC keys
    let maxTemp: Double                     // 最高值（用于告警）
}
```

#### FanMetrics（Pro）

```swift
struct FanMetrics: Sendable, Codable, Equatable {
    let fans: [Fan]
}

struct Fan: Sendable, Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let rpm: Int
    let minRPM: Int
    let maxRPM: Int
}
```

#### BatteryMetrics（Pro，仅笔记本）

```swift
struct BatteryMetrics: Sendable, Codable, Equatable {
    let state: BatteryState                 // charging / discharging / full
    let percent: Int                        // 0-100
    let cycleCount: Int
    let healthPercent: Int                  // maxCapacity / designCapacity * 100
    let temperatureCelsius: Double?
    let timeRemainingMinutes: Int?
    let powerSourceWatts: Double?
}

enum BatteryState: String, Sendable, Codable {
    case charging
    case discharging
    case full
    case notPresent
}
```

#### ProcessUsage（组合排行）

```swift
struct ProcessUsage: Sendable, Codable, Equatable, Identifiable {
    let pid: Int32
    let name: String
    let bundleIdentifier: String?           // Pro
    let cpuPercent: Double
    let memoryBytes: UInt64
    let networkUploadBytesPerSec: UInt64    // Pro
    let networkDownloadBytesPerSec: UInt64  // Pro
    let diskReadBytesPerSec: UInt64         // Pro
    let diskWriteBytesPerSec: UInt64        // Pro
}
```

### 5.2 Core Data 模型

```
MetricSample
├── id: UUID (indexed)
├── timestamp: Date (indexed, compound with metricType)
├── metricType: String (cpu / memory / disk / network / temperature / fan / battery)
├── averageValue: Double
├── minValue: Double
├── maxValue: Double
├── sampleCount: Int16
└── metadataJSON: Data? (JSON blob, breakdown)

保留策略:
  1 分钟分辨率 → 保留 24 小时
  5 分钟聚合 → 保留 7 天
  1 小时聚合 → 保留 30 天
  自动清理: Core Data 后台 context 定时删除过期数据
```

```
AlertEvent
├── id: UUID (indexed)
├── timestamp: Date (indexed)
├── alertType: String (threshold / system / error)
├── metricType: String
├── severity: String (info / warning / critical)
├── localizedTitle: String
├── localizedBody: String
├── thresholdValue: Double
├── actualValue: Double
├── isAcknowledged: Bool
└── acknowledgedAt: Date?
```

```
AppPreferences (UserDefaults suite, shared via App Group)
├── menuBarDisplayMetrics: [String]           // 显示的指标列表
├── menuBarStyle: String                      // "chart" / "numeric" / "minimal"
├── menuBarMetricsOrder: [String]             // 拖拽排序后的顺序
├── theme: String                             // "auto" / "light" / "dark"
├── isLaunchAtLoginEnabled: Bool
├── samplingRate: Double                      // 0.5 - 5.0 Hz
├── historyRetentionDays: Int                 // 默认 30
├── cpuAlertThreshold: Double?                // 0-100, nil=disabled
├── memoryAlertThreshold: Double?             // 0-100
├── diskAlertThreshold: Double?               // 0-100
├── temperatureAlertThreshold: Double?        // 摄氏度 (Pro)
├── hasCompletedOnboarding: Bool
├── lastLaunchedVersion: String
└── proUnlocked: Bool                         // StoreKit receipt 验证缓存
```

### 5.3 历史数据保留策略

```
实时采样 1Hz ──-> UI 展示
    │
    │ 每 60 秒聚合
    ▼
1 分钟平均 ──-> Core Data 存储 24 小时
    │
    │ 每 5 次聚合
    ▼
5 分钟平均 ──-> Core Data 存储 7 天
    │
    │ 每 12 次聚合
    ▼
1 小时平均 ──-> Core Data 存储 30 天 → 自动清理
```

**存储容量估算**：
- 1 分钟分辨率 × 7 类 × 60 分 × 24 小时 = 10,080 条
- 5 分钟分辨率 × 7 类 × 288 次 × 7 天 = 14,112 条
- 1 小时分辨率 × 7 类 × 24 次 × 30 天 = 5,040 条
- 总计 ~30,000 条，每条 ~128 bytes → **~4 MB/月**
- 安全余量：10 年内 < 500 MB（自动清理机制保证永不超过 50 MB）

### 5.4 App Group 共享（JSON Snapshot + 分层）

```
Group ID: group.app.kraftly.kwatch

┌────────────────────────────────────┐
│  App (kWatch.app)                   │
│  - 写 UserDefaults (preferences)   │
│  - 写 AppSnapshot JSON (实时快照)  │
│  - 写 CoreData (App 私有历史)       │
│  - 写告警日志                       │
└──────────┬─────────────────────────┘
           │ App Group 容器
┌──────────▼─────────────────────────────────┐
│  Library/Application Support/              │
│    └── kWatch.sqlite (Core Data, App 私有) │
│  Library/Application Support/Group/        │
│    └── snapshot.json (Widget/LA 只读)      │
│  Preferences/                              │
│    └── group.app.kraftly.kwatch.plist      │
└────────────────────────────────────────────┘
           │
           ├─── Widget Extension (只读 snapshot.json)
           ├─── Live Activity (只读 snapshot.json)
           └─── Intents Extension (读 UserDefaults)
```

**为什么不用 Core Data 共享**：
- Core Data SQLite 是文件型数据库，App、Widget、Live Activity 三个进程同时读写会触发文件锁冲突
- 即使使用 `NSPersistentContainer` 跨进程配置，WAL 模式下仍可能出现 "database is locked" 错误
- Widget 进程有时间预算（几秒），文件锁等待不友好
- JSON snapshot 写入是 atomic（先写 .tmp → rename），Widget 只读不阻塞

**Snapshot JSON 格式**：
```json
{
  "version": 1,
  "timestamp": "2026-07-26T10:30:00Z",
  "cpu": 0.45,
  "memory": { "used": 8589934592, "total": 17179869184 },
  "disk": 0.60,
  "network": { "up": 12288, "down": 262144 },
  "trend": {
    "cpu": [0.30, 0.32, 0.35, ...],     // 最近 60 个 1 分钟采样
    "memory": [...],
    ...
  }
}
```

**写入策略**：
- App 每 30 秒将聚合后的 1 分钟平均 snapshot 写到 `snapshot.json`（写入失败重试 3 次）
- 写入使用 `Data.write(to:options: .atomic)` 原子操作，避免部分写入
- 文件大小：~2 KB（60 个数据点 × 7 指标 × ~5 bytes），无压力
- Widget 每次 Timeline Reload 时读取最新 snapshot

### 5.5 MetricsRepository（领域层数据抽象）

```swift
protocol MetricsRepositoryProtocol: Sendable {
    /// 订阅实时指标流（主入口）
    func subscribe() -> AsyncStream<MetricsSnapshot>

    /// 获取当前快照（非阻塞）
    func currentSnapshot() async -> MetricsSnapshot?

    /// 获取历史数据（指定时间范围）
    func history(
        metricType: MetricType,
        range: DateInterval,
        resolution: TimeInterval
    ) async throws -> [AggregatedSample]

    /// 暂停/恢复监控
    func pause()
    func resume()
}
```

---

## 6. 类图与模块职责

### 6.1 核心类图

```
┌─────────────────────────────────────────────────────────────┐
│                       AppContainer                          │
│  (依赖注入容器，单例，构造时创建所有依赖)                       │
└─────────────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│                  MetricsAggregator  (actor)                  │
│                                                              │
│  - providers: [any MetricsProvider]                          │
│  - samplingStrategy: SamplingStrategy                        │
│  - subscribers: [UUID: AsyncStream<MetricsSnapshot>]         │
│  - currentSnapshot: MetricsSnapshot?                         │
│                                                              │
│  + start()                                                   │
│  + stop()                                                    │
│  + subscribe() -> AsyncStream<MetricsSnapshot>               │
│  + currentSnapshot() -> MetricsSnapshot?                     │
└─────────────────────────────────────────────────────────────┘
        │ 1
        │ owns *
        ▼
┌──────────────────────────────────────────────────────────────┐
│  MetricsProvider (protocol, Sendable)                        │
│  + type: MetricType                                          │
│  + snapshot() async throws -> any MetricSample               │
└──────────────────────────────────────────────────────────────┘
        ▲                   ▲                   ▲
        │ implements        │ implements        │ implements
┌───────────────┐  ┌───────────────┐  ┌──────────────────┐
│  CPUMonitor   │  │ MemoryMonitor │  │  DiskMonitor      │
│  (actor)      │  │ (actor)       │  │  (actor)          │
├───────────────┤  ├───────────────┤  ├──────────────────┤
│ - hostPort:   │  │ - host:       │  │ - volumePaths:   │
│   host_t      │  │   host_t      │  │   [String]       │
│ - prevTicks:  │  │ - prevVMStat  │  │ - prevIOStat:    │
│   [UInt64]    │  │   vm_statistics│ │   IOKit counters │
└───────────────┘  └───────────────┘  └──────────────────┘

┌───────────────┐  ┌───────────────┐  ┌──────────────────┐
│ NetworkMonitor│  │ SMCProvider   │  │ ProcessEnumerator │
│ (actor)       │  │ (actor, Pro)  │  │ (actor)          │
├───────────────┤  ├───────────────┤  ├──────────────────┤
│ - prevIfaddrs │  │ - smcConnect  │  │ - maxProcesses: │
│ - prevBytes   │  │   io_connect_t│  │   Int            │
│   [UInt64]    │  │ - cachedKeys  │  │   (Free=5, Pro=∞)│
└───────────────┘  └───────────────┘  └──────────────────┘
```

### 6.2 UI 层类结构

```
┌───────────────────────────────────────────────────────────┐
│ AppCoordinator (@MainActor, @Observable)                  │
│  - state: AppState                                        │
│  - menuBarVM: MenuBarViewModel                            │
│  - dashboardVM: DashboardViewModel                        │
│  - settingsVM: SettingsViewModel                          │
│  - processesVM: ProcessesViewModel                        │
│  - paywallVM: PaywallViewModel                            │
│                                                           │
│  + start() → 菜单栏图标 + 启动流程                          │
│  + presentDashboard()                                     │
│  + presentSettings()                                      │
│  + presentPaywall()                                       │
│  + dismissAll()                                           │
└───────────────────────────────────────────────────────────┘
        │
        │ owns
        ▼
┌───────────────────────────────────────────────────────────┐
│ AppState (@Observable)                                    │
│  - phase: .onboarding / .free / .pro / .paused            │
│  - menuBarStyle: MenuBarStyle                              │
│  - isDashboardVisible: Bool                                │
│  - lastError: AppError?                                    │
│  - isPaused: Bool                                          │
└───────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────┐
│ ViewModels (@MainActor, @Observable)                       │
│                                                           │
│ MenuBarViewModel:                                          │
│  - displayedMetrics: [MetricType]                          │
│  - menuBarStyle: MenuBarStyle                              │
│  - metrics: [MetricType: MetricDisplayData]                │
│  - tooltipInfo: TooltipInfo?                               │
│  + refresh()                                               │
│                                                           │
│ DashboardViewModel:                                        │
│  - snapshot: MetricsSnapshot?                              │
│  - selectedTab: DashboardTab                               │
│  - trendData: [AggregatedSample]                           │
│  - errorState: DashboardError?                             │
│  + selectTab(_:)                                           │
│  + refresh()                                               │
│                                                           │
│ ProcessesViewModel:                                        │
│  - processes: [ProcessUsage] (sorted)                      │
│  - sortBy: ProcessSortField                                │
│  - isProLocked: Bool                                       │
│  + refresh()                                               │
│  + sort(by:)                                               │
│                                                           │
│ SettingsViewModel:                                         │
│  - preferences: Preferences                                │
│  - proUnlocked: Bool                                       │
│  + save()                                                  │
│  + reset()                                                 │
│                                                           │
│ PaywallViewModel:                                          │
│  - product: Product?                                       │
│  - purchaseState: PurchaseState                            │
│  + purchase()                                              │
│  + restore()                                               │
│                                                           │
│ SpotlightViewModel:                                        │
│  + handleQuery(_ queryString: String) → SpotlightResult   │
└───────────────────────────────────────────────────────────┘
```

### 6.3 状态机

```
AppState 状态流转:

  ┌──────────┐   首次启动    ┌───────────┐
  │  Launch   │ ──────────→ │Onboarding │
  └──────────┘              └─────┬─────┘
       │ 非首次启动                │ 完成
       └──────────────────────────┤
                                  ▼
                          ┌───────────────┐
                          │   Running     │ ◀──── 暂停 → ──┐
                          │ (free / pro)  │                │
                          └───────┬───────┘  ────→ 恢复 ──┘
                                  │
                          ┌───────┴───────┐
                          │               │
                          ▼               ▼
                   ┌──────────┐    ┌──────────┐
                   │  Paused  │    │  Error   │
                   └──────────┘    └────┬─────┘
                                         │ 重试
                                         ▼
                                    ┌──────────┐
                                    │ Running  │
                                    └──────────┘

LiveActivity 状态:

  ┌────────┐    告警触发/监控启动    ┌──────────┐
  │ Inactive│ ───────────────────→ │  Active  │
  └────────┘                       └────┬─────┘
        ↑                                │ 超时 / 手动关闭
        └────────────────────────────────┘
```

### 6.4 kFoundation 新增模块

```
kFoundation/
├── MetricsKit/                               # 新增
│   ├── MetricsProvider.swift                 # MetricsProvider protocol
│   ├── MetricsSnapshot.swift                 # 领域模型
│   ├── MetricsAggregator.swift               # actor 聚合器
│   └── SamplingStrategy.swift                # 采样策略
├── DaemonBridge/                             # 新增（架构纯抽象）
│   ├── MetricsService.swift                  # XPC 抽象协议
│   └── MetricsServiceClient.swift            # 客户端侧抽象
├── ... (复用 kSpaceClean 现有模块)
```

### 6.5 kWatch 内部模块结构

```
kWatch/
├── App/
│   ├── kWatchApp.swift                      # @main, MenuBarExtra
│   ├── AppContainer.swift                   # 依赖注入容器
│   ├── AppCoordinator.swift                 # 导航/生命周期协调
│   └── AppState.swift                       # 统一 App 状态
│
├── Features/
│   ├── MenuBar/                             # 菜单栏微型图表引擎
│   │   ├── MenuBarViewModel.swift
│   │   ├── MenuBarChartView.swift           # 趋势图渲染
│   │   ├── MenuBarNumericView.swift         # 数字模式
│   │   ├── MenuBarMinimalView.swift         # 极简模式
│   │   ├── MenuBarTooltipView.swift         # 悬停详情
│   │   └── MenuBarStyle.swift              # 风格定义
│   │
│   ├── Dashboard/                           # 主窗口
│   │   ├── DashboardViewModel.swift
│   │   ├── DashboardView.swift             # NavigationSplitView
│   │   ├── MetricCardView.swift            # 指标卡片
│   │   ├── MetricCardViewModel.swift
│   │   ├── TrendChartView.swift            # SwiftUI Charts 封装
│   │   ├── TrendChartViewModel.swift
│   │   └── DashboardTab.swift
│   │
│   ├── Processes/                           # 进程排行 (Pro)
│   │   ├── ProcessesViewModel.swift
│   │   └── ProcessesView.swift
│   │
│   ├── History/                             # 历史趋势 (Pro)
│   │   ├── HistoryViewModel.swift
│   │   ├── HistoryView.swift
│   │   └── AggregatedSample.swift
│   │
│   ├── Alerts/                              # 告警系统
│   │   ├── AlertManager.swift
│   │   ├── AlertThreshold.swift
│   │   └── AlertNotification.swift
│   │
│   ├── Settings/                            # 设置面板
│   │   ├── SettingsViewModel.swift
│   │   ├── SettingsView.swift
│   │   ├── MenuBarSettingsView.swift
│   │   ├── AlertSettingsView.swift
│   │   ├── WidgetSettingsView.swift
│   │   └── AboutView.swift
│   │
│   └── Onboarding/                          # 首次引导
│       ├── OnboardingCoordinator.swift
│       ├── OnboardingView.swift
│       ├── WelcomePage.swift
│       ├── MenuBarCustomizePage.swift
│       ├── ProIntroPage.swift
│       └── CompletePage.swift
│
├── Monitoring/                              # 监控数据采集
│   ├── CPUMonitor.swift
│   ├── MemoryMonitor.swift
│   ├── DiskMonitor.swift
│   ├── NetworkMonitor.swift
│   ├── SMCProvider.swift                    # Pro, IOKit AppleSMC
│   ├── TemperatureMonitor.swift
│   ├── FanMonitor.swift
│   ├── BatteryMonitor.swift
│   ├── ProcessEnumerator.swift
│   └── SystemAdapters/
│       ├── SMCAdapter.swift                # IOKit SMC 封装
│       ├── IOKitAdapter.swift
│       ├── libprocAdapter.swift
│       ├── sysctlAdapter.swift
│       └── NetworkAdapter.swift
│
├── Persistence/
│   ├── CoreDataStack.swift
│   ├── PreferencesRepository.swift
│   ├── MetricsHistoryRepository.swift
│   └── AlertRepository.swift
│
├── Services/
│   ├── MetricsRepository.swift             # 实现了 Domain protocol
│   ├── SpotlightIndexer.swift
│   └── LaunchAtLoginManager.swift
│
├── Store/                                    # StoreKit 2
│   ├── StoreManager.swift
│   ├── PaywallView.swift
│   └── ProductIdentifiers.swift
│
├── Widgets/                                  # Widget Extension
│   ├── kWatchWidget.swift
│   ├── kWatchWidgetEntryView.swift
│   ├── SmallWidgetView.swift
│   ├── MediumWidgetView.swift
│   └── WidgetConfigIntent.swift
│
├── Intents/                                  # App Intents Extension
│   ├── GetCPUUsageIntent.swift
│   ├── GetMemoryUsageIntent.swift
│   ├── GetDiskUsageIntent.swift
│   ├── GetNetworkSpeedIntent.swift
│   ├── GetTemperatureIntent.swift           # Pro
│   ├── GetFanSpeedIntent.swift              # Pro
│   ├── GetBatteryStatusIntent.swift         # Pro
│   └── StartMonitoringIntent.swift          # Pro (Live Activity)
│
├── LiveActivity/
│   ├── MonitoringActivityAttributes.swift
│   ├── MonitoringActivityView.swift
│   └── AlertActivityAttributes.swift
│
├── Spotlight/
│   └── SpotlightQueryHandler.swift
│
├── Resources/
│   ├── Assets.xcassets/
│   ├── Colors.xcassets/
│   └── Icons.xcassets/
│
├── Info.plist
└── project.yml                              # XcodeGen 配置
```

---

## 7. 核心检测实现细节

### 7.1 CPU 检测

```swift
actor CPUMonitor: MetricsProvider {
    typealias Sample = CPUMetrics

    let type: MetricType = .cpu
    private var host: host_t
    private var prevProcessorInfo: processor_info_array_t?
    private var prevCpuCount: natural_t = 0
    private var prevTicks: [UInt64] = []
    private var prevTimestamp: UInt64 = 0

    func snapshot() async throws -> CPUMetrics {
        // 1. 获取处理器信息
        var cpuCount = natural_t(0)
        var processorInfo: processor_info_array_t? = nil
        var processorInfoCount = mach_msg_type_number_t(0)

        let kr = host_processor_info(
            host,
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &processorInfo,
            &processorInfoCount
        )
        guard kr == KERN_SUCCESS, let info = processorInfo else {
            throw MetricsError.hostProcessorInfoFailed
        }

        let cpuData = unsafeBitCast(info, to: processor_info_array_t.self)

        // 2. 计算每核使用率（差分法）
        var perCore: [Double] = []
        for i in 0..<Int(cpuCount) {
            let inUse = cpuData[Int(CPU_STATE_USER) + i * Int(CPU_STATE_MAX)]
            let system = cpuData[Int(CPU_STATE_SYSTEM) + i * Int(CPU_STATE_MAX)]
            let idle = cpuData[Int(CPU_STATE_IDLE) + i * Int(CPU_STATE_MAX)]
            let total = inUse + system + idle

            let prevInUse = prevTicks.indices.contains(i) ?
                prevTicks[i * Int(CPU_STATE_MAX) + Int(CPU_STATE_USER)] : UInt64(inUse)
            // ... 差分计算 ...

            let usage = Double(deltaInUse + deltaSystem) / Double(deltaTotal)
            perCore.append(usage)
        }

        // 3. 获取 Load Average
        var loadAvg = [Double](repeating: 0, count: 3)
        let _ = withUnsafeMutablePointer(to: &loadAvg) { ptr in
            ptr.withMemoryRebound(to: loadavg.self, capacity: 1) { loadPtr in
                var size = MemoryLayout<loadavg>.size
                sysctlbyname("vm.loadavg", loadPtr, &size, nil, 0)
                // loadPtr.pointee.ldavg[0-2] / LoadScale
            }
        }

        // 4. 温度（可选，由 SMCProvider 单独提供）
        let temp = try? await SMCProvider.shared.readTemperature(key: "TC0P")

        return CPUMetrics(
            totalUsage: perCore.reduce(0, +) / Double(cpuCount),
            perCoreUsage: perCore,
            loadAverage1: loadAvg[0],
            loadAverage5: loadAvg[1],
            loadAverage15: loadAvg[2],
            frequencyMHz: nil,          // 需要 IOKit AppleARM/ACPI
            temperatureCelsius: temp
        )
    }
}
```

> **实现注意**（防止内存泄漏）：
> - `host_processor_info` 返回的 `processorInfo` 必须用 `vm_deallocate` 释放，调用 `prevProcessorInfo` 前必须释放旧的
> - `unsafeBitCast(info, to: processor_info_array_t.self)` 不安全，建议用 `withMemoryRebound`
> - `CPU_STATE_MAX` 是 4，`prevTicks` 数组大小应该按 `CPU_STATE_MAX * cpuCount` 初始化
> - 完整代码示例（避免泄漏）：
>
> ```swift
> defer {
>     let prevSize = vm_size_t(prevProcessorInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
>     vm_deallocate(mach_task_self_, vm_address_t(bitPattern: prevProcessorInfo), prevSize)
>     prevProcessorInfo = cpuData
>     prevProcessorInfoCount = processorInfoCount
>     prevCpuCount = cpuCount
> }
> ```

### 7.2 内存检测

```swift
actor MemoryMonitor: MetricsProvider {
    let type: MetricType = .memory
    private var host: host_t

    func snapshot() async throws -> MemoryMetrics {
        var vmStats = vm_statistics64()
        var count = mach_msg_type_number_t(HOST_VM_INFO64_COUNT)

        let kr = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else {
            throw MetricsError.hostStatisticsFailed
        }

        // 计算
        let pageSize = UInt64(vm_page_size)
        let active = UInt64(vmStats.active_count) * pageSize
        let wired = UInt64(vmStats.wire_count) * pageSize
        let compressed = UInt64(vmStats.compressor_page_count) * pageSize
        let used = active + wired + compressed

        // 总内存
        var total = UInt64(0)
        var totalSize = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &total, &totalSize, nil, 0)

        // Swap
        var xswUsage = xsw_usage()
        var xswSize = MemoryLayout<xsw_usage>.size
        sysctlbyname("vm.swapusage", &xswUsage, &xswSize, nil, 0)

        // 压力判定
        let pressure: PressureLevel = {
            let memoryPressure = vmStats.memory_pressure
            if memoryPressure > 80 { return .critical }
            if memoryPressure > 50 { return .warning }
            return .normal
        }()

        return MemoryMetrics(
            totalBytes: total,
            usedBytes: used,
            appBytes: active,
            wiredBytes: wired,
            compressedBytes: compressed,
            swapUsedBytes: xswUsage.xsu_used,
            swapTotalBytes: xswUsage.xsu_total,
            pressure: pressure,
            topProcesses: []  // 由 ProcessEnumerator 填充
        )
    }
}
```

### 7.3 磁盘检测

```swift
actor DiskMonitor: MetricsProvider {
    let type: MetricType = .disk
    private var prevReadBytes: UInt64 = 0
    private var prevWriteBytes: UInt64 = 0
    private var prevTimestamp: Date = .distantPast

    func snapshot() async throws -> DiskMetrics {
        // 1. 分区信息 (statfs)
        let mountCount = getfsstat(nil, 0, MNT_NOWAIT)
        var mounts = [statfs](repeating: .init(), count: mountCount)
        _ = mounts.withUnsafeMutableBufferPointer { ptr in
            getfsstat(ptr.baseAddress, Int32(MemoryLayout<statfs>.size * mountCount), MNT_NOWAIT)
        }

        var volumes: [VolumeInfo] = []
        for mount in mounts {
            let path = withUnsafePointer(to: mount.f_mntonname) {
                String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
            }
            let total = UInt64(mount.f_blocks) * UInt64(mount.f_bsize)
            let free = UInt64(mount.f_bfree) * UInt64(mount.f_bsize)
            volumes.append(VolumeInfo(
                mountPoint: URL(fileURLWithPath: path),
                name: (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName) ?? path,
                totalBytes: total,
                usedBytes: total - free,
                isRemovable: mount.f_flags & MNT_REMOVABLE == MNT_REMOVABLE,
                fileSystem: withUnsafePointer(to: mount.f_fstypename) {
                    String(cString: UnsafeRawPointer($0).assumingMemoryBound(to: CChar.self))
                }
            ))
        }

        // 2. 磁盘温度 (SMC)
        let temp = try? await SMCProvider.shared.readTemperature(key: "TN0P")

        return DiskMetrics(
            volumes: volumes,
            readBytesPerSec: 0,    // TODO: IOKit IOBlockStorageDriver 差分（v1 标记为"暂不支持"，不阻塞发布）
            writeBytesPerSec: 0,
            iops: nil,
            temperatureCelsius: temp
        )
    }
}
```

> **v1 说明**：磁盘读写速度读取需通过 IOKit `IOBlockStorageDriver` 统计寄存器差值实现，实现成本较高且在 Apple Silicon 上接口有变化。**v1 暂不实现**，磁盘卡片显示 N/A，用户可见。计划 v1.1 补全。

### 7.4 网络检测

```swift
actor NetworkMonitor: MetricsProvider {
    let type: MetricType = .network
    private var prevBytes: [String: (up: UInt64, down: UInt64)] = [:]
    private var prevTimestamp: Date = .distantPast

    func snapshot() async throws -> NetworkMetrics {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else {
            throw MetricsError.getifaddrsFailed
        }
        defer { freeifaddrs(ifaddrPtr) }

        var interfaces: [NetworkInterface] = []
        var current = first
        let now = Date()

        repeat {
            let addr = current.pointee
            let name = String(cString: addr.ifa_name)

            // 跳过 loopback 和非 AF_LINK
            if name == "lo0" || addr.ifa_addr.pointee.sa_family != AF_LINK {
                current = addr.ifa_next.pointee
                continue
            }

            // 获取 IP (AF_INET)
            var ip: String? = nil
            if let inetAddr = ifaddr_nettoaddr?(addr) {
                // ...
            }

            // 计算速度
            if let data = addr.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
                let rxBytes = UInt64(data.ifi_ibytes)
                let txBytes = UInt64(data.ifi_obytes)

                var upload: UInt64 = 0
                var download: UInt64 = 0
                if let prev = prevBytes[name] {
                    let elapsed = now.timeIntervalSince(prevTimestamp)
                    if elapsed > 0 {
                        upload = UInt64(Double(txBytes - prev.up) / elapsed)
                        download = UInt64(Double(rxBytes - prev.down) / elapsed)
                    }
                }
                prevBytes[name] = (txBytes, rxBytes)

                interfaces.append(NetworkInterface(
                    name: name,
                    displayName: name == "en0" ? "Wi-Fi" : name,
                    ipAddress: ip,
                    isUp: addr.ifa_flags & IFF_UP == IFF_UP,
                    uploadBytesPerSec: upload,
                    downloadBytesPerSec: download,
                    totalUploadBytes: txBytes,
                    totalDownloadBytes: rxBytes
                ))
            }

            current = addr.ifa_next.pointee
        } while current.pointee.ifa_next != nil

        prevTimestamp = now

        return NetworkMetrics(
            interfaces: interfaces,
            totalUploadBytesPerSec: interfaces.reduce(0) { $0 + $1.uploadBytesPerSec },
            totalDownloadBytesPerSec: interfaces.reduce(0) { $0 + $1.downloadBytesPerSec },
            tcpConnections: tcpConnectionCount(),
            topProcesses: []
        )
    }
}
```

### 7.5 SMC 温度/风扇检测（Pro）

```swift
actor SMCProvider: MetricsProvider {
    let type: MetricType = .temperature
    static let shared = SMCProvider()

    // SMC 连接
    private var conn: io_connect_t = 0

    // 已知传感器 key 映射
    private let knownKeys: [String: (metric: String, description: String)] = [
        "TC0P": ("CPU_0", "CPU 核心 0"),
        "TC1P": ("CPU_1", "CPU 核心 1"),
        "TC2P": ("CPU_2", "CPU 核心 2"),
        "TG0P": ("GPU", "GPU 温度"),
        "TB0T": ("BATTERY", "电池温度"),
        "TN0P": ("SSD", "SSD 温度"),
        "TM0P": ("MEM_SLOT_0", "内存 DIMM 0"),
    ]

    func open() throws {
        // 通过 IOKit 打开 AppleSMC
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("AppleSMC")
        )
        guard service != 0 else {
            throw SMCError.serviceNotFound
        }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard kr == KERN_SUCCESS else {
            throw SMCError.openFailed(kr)
        }
        IOObjectRelease(service)
    }

    func readTemperature(key: String) throws -> Double {
        // SMC 读取 4 字节数据，结构体包含 data type + bytes
        var inputStruct = SMCParamStruct()
        var outputStruct = SMCParamStruct()

        inputStruct.key = SMCKey(key)
        inputStruct.data8 = SMC_CMD_READ

        let size = MemoryLayout<SMCParamStruct>.size
        let kr = IOConnectCallStructMethod(
            conn,
            UInt32(SMC_KERNEL_INDEX),
            &inputStruct,
            size,
            &outputStruct,
            &size
        )

        guard kr == KERN_SUCCESS else {
            throw SMCError.readFailed(key, kr)
        }

        // 解析温度值（SP78 格式：高字节整数，低字节小数）
        let raw = UInt16(outputStruct.bytes[0]) << 8 | UInt16(outputStruct.bytes[1])
        return Double(raw) / 256.0
    }

    func snapshot() async throws -> TemperatureMetrics {
        var sensors: [String: Double] = [:]
        for (key, _) in knownKeys {
            if let temp = try? await readTemperature(key: key) {
                sensors[key] = temp
            }
        }
        return TemperatureMetrics(
            cpuCores: sensors.filter { $0.key.hasPrefix("TC") },
            gpuTemp: sensors["TG0P"],
            batteryTemp: sensors["TB0T"],
            ambientTemp: nil,
            allSensors: sensors,
            maxTemp: sensors.values.max() ?? 0
        )
    }
}
```

### 7.6 风扇检测

```swift
actor FanMonitor: MetricsProvider {
    let type: MetricType = .fan

    func snapshot() async throws -> FanMetrics {
        // SMC FNum 获取风扇数量
        let count = try await SMCProvider.shared.readInt(key: "FNum")
        var fans: [Fan] = []
        for i in 0..<Int(count) {
            let id = "F\(i)"
            let rpm = try? await SMCProvider.shared.readInt(key: "\(id)Ac")
            let minRPM = try? await SMCProvider.shared.readInt(key: "\(id)Mn")
            let maxRPM = try? await SMCProvider.shared.readInt(key: "\(id)Mx")
            let name = try? await SMCProvider.shared.readString(key: "\(id)ID")

            if let rpm = rpm {
                fans.append(Fan(
                    id: id,
                    name: name ?? "风扇 \(i+1)",
                    rpm: rpm,
                    minRPM: minRPM ?? 0,
                    maxRPM: maxRPM ?? 5000
                ))
            }
        }
        return FanMetrics(fans: fans)
    }
}
```

### 7.7 电池检测

```swift
actor BatteryMonitor: MetricsProvider {
    let type: MetricType = .battery

    func snapshot() async throws -> BatteryMetrics? {
        // 检测是否为笔记本
        var isPortable = false
        if let blobs = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() {
            if let sources = IOPSCopyPowerSourcesList(blobs)?.takeRetainedValue() as? [String] {
                isPortable = !sources.isEmpty
            }
        }
        guard isPortable else { return nil }  // 台式机无电池

        // 电量
        let remaining = IOPSGetPercentRemaining()

        // 电源状态
        let psInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let psList = IOPSCopyPowerSourcesList(psInfo)?.takeRetainedValue() as? [String] ?? []
        let state: BatteryState = psList.isEmpty ? .notPresent : .discharging
        // ... 实际通过 IOPowerSource 字典解析

        // 温度
        let temp = try? await SMCProvider.shared.readTemperature(key: "TB0T")

        return BatteryMetrics(
            state: state,
            percent: Int(remaining),
            cycleCount: 0,             // TODO: IOKit IOAppleBattery CycleCount（v1.1 实现）
            healthPercent: 100,        // TODO: IOKit designCapacity / maxCapacity 差值计算（v1.1 实现）
            temperatureCelsius: temp,
            timeRemainingMinutes: nil, // IOPSGetTimeRemainingEstimate()
            powerSourceWatts: nil
        )
    }
}
```

> **v1 说明**：电池循环计数和健康度百分比需通过 IOKit `IOAppleBattery` 的 `designCapacity` / `maxCapacity` 字段计算，实现复杂度中等。**v1 暂不完善**，循环计数显示"需等待"，健康度以 100% 占位（实际功能正常）。v1.1 完善完整读数。

### 7.8 进程枚举

```swift
actor ProcessEnumerator: MetricsProvider {
    let type: MetricType = .process

    // Free 用户只取 Top 5，Pro 取全部
    var maxProcesses: Int {
        // 通过 AppContainer 注入的 StoreManager 判断
        return AppContainer.shared.storeManager.isProUnlocked ? 999 : 5
    }

    func snapshot() async throws -> [ProcessUsage] {
        let count = proc_listallpids(nil, 0)
        var pids = [pid_t](repeating: 0, count: Int(count))
        _ = proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count))

        var processes: [ProcessUsage] = []
        for pid in pids {
            var taskInfo = proc_taskinfo()
            let size = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(MemoryLayout<proc_taskinfo>.size))

            guard size > 0 else { continue }

            var nameBuffer = [CChar](repeating: 0, count: 1024)
            proc_name(pid, &nameBuffer, UInt32(nameBuffer.count))
            let name = String(cString: nameBuffer)

            processes.append(ProcessUsage(
                pid: pid,
                name: name.isEmpty ? "unknown" : name,
                bundleIdentifier: nil,       // NSWorkspace.shared.runningApplications
                cpuPercent: Double(taskInfo.pti_percent) / 100.0,
                memoryBytes: UInt64(taskInfo.pti_resident_size),
                networkUploadBytesPerSec: 0, // 需 libproc 扩展（v1 暂不实现）
                networkDownloadBytesPerSec: 0,
                diskReadBytesPerSec: 0,
                diskWriteBytesPerSec: 0
            ))
        }

        // 按 CPU 排序，截断
        return processes
            .sorted { $0.cpuPercent > $1.cpuPercent }
            .prefix(maxProcesses)
            .map { $0 }
    }
}
```

> **v1 说明**：进程级网络和磁盘 I/O（ProcessUsage 中的 networkUploadBytesPerSec / networkDownloadBytesPerSec / diskReadBytesPerSec / diskWriteBytesPerSec）需要额外的 libproc 扩展或 IOKit 统计，**v1 暂不实现**，进程表中这些列显示为 N/A。Pro 进程排行以 CPU 和内存排序为主，网络排行功能推迟到 v1.1。

---

## 8. 通讯方式

### 8.1 进程内通讯

| 场景 | 方式 | 数据方向 | 说明 |
|:-----|:------|:---------|:------|
| 监控数据 → UI | `AsyncStream<MetricsSnapshot>` | 单向（Data → UI） | MetricsRepository 作为唯一订阅入口 |
| 用户配置 → App | `PreferencesRepository` (@Observable) | 双向 | UserDefaults 读写，SwiftUI 自动绑定 |
| 跨 ViewModel 事件 | `NotificationCenter` | 单向 | 如"购买成功"、"监控错误"等全局事件 |
| StoreKit 状态 | `StoreManager` @Observable 单例 | 单向（全局广播） | 所有 ViewModel 监听 proUnlocked |
| Core Data 变化 | `NSManagedObjectContextDidSave` | 单向（Data → UI） | 历史数据更新通知 |
| Actor 错误捕获 | `Result<T, Error>` + 重试策略 | 单向 | 单个 Provider 失败不影响聚合 |

### 8.2 跨进程通讯

| 场景 | 方式 | 共享数据 | 说明 |
|:-----|:------|:---------|:------|
| App ↔ Widget | **App Group Core Data + UserDefaults** | MetricsSnapshot（聚合1min） | Widget 只读，30s 刷新间隔 |
| App ↔ Live Activity | **ActivityKit ActivityAttributes** | MonitoringState / AlertState | 本地 Activity，不需要 push |
| App ↔ Shortcuts | **App Intents framework** | Intent 参数 | 系统调度，App 后台启动 |
| App ↔ Spotlight | **CoreSpotlight** + NSUserActivity | 查询结果 | 每 15 分钟重建索引 |
| App ↔ 通知中心 | **UserNotifications** UNUserNotificationCenter | AlertEvent | 阈值触发时 |

### 8.3 Widget 数据流

```
[Widget Extension]
  ┌─────────────────────┐
  │ kWatchWidget.swift  │
  │  (TimelineProvider) │
  └────────┬────────────┘
           │ 读 App Group Core Data
           ▼
  ┌─────────────────────┐
  │  MetricsSnapshot     │
  │  （1 分钟聚合数据）    │
  └────────┬────────────┘
           │ SwiftUI 渲染
           ▼
  ┌─────────────────────┐
  │  WidgetEntryView     │
  │  - 指标卡片          │
  │  - 迷你趋势图        │
  └─────────────────────┘

刷新策略:
  - 基础 Widget: .atEnd (5 分钟)
  - Interactive: .after(date: 1 分钟后) + 用户交互刷新
```

### 8.4 Live Activity 数据流

```
[App]
  ┌──────────────────────┐
  │ AlertManager         │
  │ (告警触发)            │
  └────────┬─────────────┘
           │
           ▼
  ┌──────────────────────┐
  │ ActivityKit.request()│
  │ ActivityAttributes   │
  └────────┬─────────────┘
           │ 系统管理
           ▼
  ┌──────────────────────┐
  │  Live Activity UI     │
  │  (notch / LockScreen) │
  └──────────────────────┘

更新方式: alertContent.update(using: newState)
结束方式: 告警确认 or 30 分钟超时
```

### 8.5 App Group 配置

```
Group Identifier: group.app.kraftly.kwatch

Entitlements:
  - com.apple.security.application-groups
  - com.apple.security.device.sysctl.* (sysctl 访问)
  - com.apple.security.device.io.*       (IOKit 传感器)
  - com.apple.security.personal-information.* (libproc 进程信息)

注意: 菜单栏 App 不需要 Sandbox 豁免，上述均为 App Store 合规的 entitlements。
```

### 8.6 App Store 审核合规

**App Review Guideline 关联条款**：
- **2.4.1** （App 必须按宣传功能运行）：监控数据真实可信，所有指标需有文档化来源
- **2.5.1** （App 只能使用公共 API）：所有系统调用必须使用 Apple 公开 API（SMC/IOKit/sysctl 均为公开 API）
- **5.1.1** （Privacy）：用户数据仅本地处理，不上传（详见 Section 15）

**App Review Notes 模板**（提交时附）：

```
Dear App Review,

kWatch is a macOS menu bar monitoring app. The app uses Apple public APIs to read system metrics:

1. sysctl (host_processor_info, host_statistics64, sysctlbyname):
   Read CPU, memory, load average. No write access.
2. IOKit AppleSMC:
   Read-only sensor data (temperature, fan RPM). Uses IOServiceGetMatchingService
   with IOServiceMatching("AppleSMC") and IOConnectCallStructMethod.
   No driver installation, no kernel extension.
3. getifaddrs (BSD sockets):
   Read network interface statistics. Public API.
4. libproc (proc_listallpids, proc_pidinfo):
   Read process info for top-N display. No modification.

The app does NOT:
- Modify system files
- Install kernel extensions
- Use privileged helpers
- Send data to remote servers (all processing is local)
- Require Full Disk Access

All data collection is documented in our Privacy Policy at kraftly.app/privacy.

Sandbox is enabled. The app uses standard entitlements for the above APIs.

Best regards,
Kraftly Team
```

**审核被拒 Plan B**（详见 Section 19.1）：
- 移除 IOKit/SMC 调用，只保留 4 类基础指标 + 平台集成差异化
- App 仍可独立发布，Pro 功能降级为"历史 + 自定义告警 + 平台集成"

---

## 9. 完整 UX 交互设计

### 9.1 应用启动流程

```
┌──────────────────────────────────────────────────────────────────┐
│                     启动序列                                      │
│                                                                  │
│  1. @main kWatchApp.swift                                         │
│     └── MenuBarExtra("kWatch", systemImage: "chart.line.uptrend")│
│         └── AppContainer.shared → AppCoordinator.start()         │
│                                                                  │
│  2. AppCoordinator.start():                                      │
│     a. 初始化 Core Data / Preferences / StoreManager             │
│     b. 读取 hasCompletedOnboarding                               │
│     c. NO  → 展示 Onboarding 窗口                                │
│     d. YES → 直接运行后台监控                                    │
│                                                                  │
│  3. MetricsAggregator.start():                                   │
│     a. 启动所有 Provider actor                                   │
│     b. 开始定时采样（默认 1Hz）                                   │
│     c. fan-out 给 MenuBar / Dashboard / Widget                  │
│                                                                  │
│  4. 菜单栏图标显示（默认图表模式）                                 │
│     a. CPU/内存/磁盘/网络 4 个微型趋势图                           │
│     b. 每个图标 64×24pt，6 秒滚动窗口                             │
│     c. 颜色：<50% 绿 / 50-80% 黄 / >80% 红                      │
│                                                                  │
│  5. 首次启动 → Onboarding（4 步）→ 完成 → 进入主界面              │
└──────────────────────────────────────────────────────────────────┘
```

### 9.2 Onboarding 流程（4 步）

```
页面 1：Welcome
┌──────────────────────────────────────┐
│  kWatch                               │
│                                      │
│  🖥  Mac 状态一目了然                 │
│                                      │
│  7 大指标实时监控：                    │
│  ┌────┐ ┌────┐ ┌────┐ ┌────┐       │
│  │CPU │ │内存│ │磁盘│ │网络│       │
│  └────┘ └────┘ └────┘ └────┘       │
│  ┌────┐ ┌────┐ ┌────┐              │
│  │温度│ │风扇│ │电池│              │
│  └────┘ └────┘ └────┘              │
│                                      │
│  [继续]                               │
└──────────────────────────────────────┘

页面 2：菜单栏风格选择
┌──────────────────────────────────────┐
│  选择你的菜单栏风格                    │
│                                      │
│  ┌───┐   ┌───┐   ┌───┐              │
│  │▁▃▅│   │C45│   │🟢 │              │
│  │图表│   │数字│   │极简│              │
│  └───┘   └───┘   └───┘              │
│                                      │
│  可在设置中随时更改                    │
│  [继续]                               │
└──────────────────────────────────────┘

页面 3：Pro 介绍
┌──────────────────────────────────────┐
│  解锁全部潜力                         │
│                                      │
│  ✅ 温度 / 风扇 / 电池监控            │
│  ✅ Interactive Widget                │
│  ✅ Live Activity 告警                │
│  ✅ 自定义告警阈值                    │
│                                      │
│  ┌──────────────────────────────┐    │
│  │ 继续试用，随时可升级           │    │
│  └──────────────────────────────┘    │
│                                      │
│  [继续试用]  [查看价格 → $7.99]       │
└──────────────────────────────────────┘

页面 4：完成
┌──────────────────────────────────────┐
│  准备就绪                              │
│                                      │
│  ✅ kWatch 已在菜单栏运行             │
│                                      │
│  单击菜单栏图标打开 Dashboard          │
│  右键菜单可快速访问设置                │
│                                      │
│  [开始使用]                           │
└──────────────────────────────────────┘
```

### 9.3 菜单栏交互设计

#### 数据展示（默认图表模式）

```
                       ┌─────────────────────────────┐
  Status Bar 区域       │  Tooltip（悬停 800ms 后）    │
                       │                             │
  [▁▃▅] [▃▅▇] [▁▁▃] [▅▇▅] │  CPU                  │
   CPU    内存   磁盘   网络  │  当前: 45%             │
                       │  负载: 1.2 / 1.5 / 1.8    │
  可选（Pro）：           │  温度: 65°C              │
   [+45°C] [3200RPM]    │                         │
    温度     风扇        │  ▁▂▃▅▇▅▃▂▁              │
                       │  Top: Chrome 12% ...     │
                       └─────────────────────────────┘
```

#### 菜单栏图表规范

| 参数 | 值 |
|:-----|:----|
| 每个图标尺寸 | 64 × 24 pt |
| 滚动窗口 | 6 秒（6 个数据点 @ 1Hz） |
| 渲染方式 | SwiftUI `Canvas` / `TimelineView` |
| 颜色映射 | < 50% 绿 / 50-80% 橙 / > 80% 红 |
| 背景 | 透明 |
| 间距 | 图标间 4pt |

#### 图表模式渲染算法

```swift
struct MiniTrendChart: View {
    let values: [Double]         // 0.0 到 1.0
    let color: Color
    let lineWidth: CGFloat = 1.5

    var body: some View {
        Canvas { context, size in
            let stepX = size.width / CGFloat(max(values.count - 1, 1))
            let path = Path { path in
                for (i, value) in values.enumerated() {
                    let x = CGFloat(i) * stepX
                    let y = size.height * (1 - CGFloat(value))
                    if i == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
        .frame(width: 64, height: 24)
    }
}
```

#### 交互矩阵

| 用户动作 | 效果 | 视觉反馈 | 实现方式 |
|:---------|:-----|:---------|:---------|
| 左键单击 | 打开/切换 Dashboard | 窗口淡入，菜单栏图标高亮 | MenuBarExtra 默认行为 |
| 左键双击 | 打开 Processes 页 | 焦点直接跳到进程 tab | NSApp.sendAction |
| 右键单击 | 快捷菜单 | 弹出 NSMenu | NSMenu delegate |
| 悬停 | 800ms 后显示 Tooltip | 毛玻璃面板渐入 | NSViewTrackingArea / .onHover |
| 拖拽图标 | 重新排序（自定义模式） | 视觉跟随，虚线占位 | DragGesture + onDrop |
| 滚轮 | 循环高亮指标 | 高亮指标放大 1.1x 并加边框 | NSView scrollWheel |
| ⌘+左键 | 强制刷新快照 | 图标闪烁一次 | 手动调用 snapshot |
| ⌥+左键 | 打开设置 | 设置窗口淡入 | NSApp.sendAction |

#### 右键菜单

```
┌─────────────────────────────────────┐
│  打开 Dashboard                  ⌘D │
│  ───────────────────────────────    │
│  概览 / 趋势 / 进程 / 告警     ▸    │
│     ┌───────────────────────┐      │
│     │ 概览                 │      │
│     │ 趋势 (Pro)           │      │
│     │ 进程                 │      │
│     │ 告警                 │      │
│     └───────────────────────┘      │
│  ───────────────────────────────    │
│  暂停监控 2 小时                    │
│  ───────────────────────────────    │
│  设置...                        ⌘, │
│  升级到 Pro...              ⇧⌘U    │
│  ───────────────────────────────    │
│  退出 kWatch                   ⌘Q  │
└─────────────────────────────────────┘
```

### 9.4 主窗口 Dashboard 交互

#### 窗口规格

| 属性 | 值 |
|:-----|:----|
| 尺寸 | 900 × 600 pt（可调，最小 700×500） |
| 类型 | `.regular`（可关闭，隐藏到菜单栏） |
| 位置 | 记忆上次位置（restorable state） |
| 打开方式 | 单击菜单栏图标 / Spotlight / ⌘D |
| 关闭行为 | `window.close()` = 隐藏，不退出 App |

**窗口生命周期关键配置**：

```swift
// kWatchApp.swift
@main
struct kWatchApp: App {
    @NSApplicationDelegateAdaptor(kWatchAppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("kWatch", systemImage: "chart.line.uptrend") {
            MenuBarContent()
        }
        .windowResizability(.contentSize)
        // Dashboard 窗口（独立 Scene）
        Window("kWatch Dashboard", id: "dashboard") {
            DashboardView()
        }
        .windowResizability(.contentMinSize)
    }
}

// kWatchAppDelegate.swift
final class kWatchAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 关键：菜单栏 App 关闭所有窗口后不退出
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement = YES 已在 Info.plist 设置
        // 进程状态：accessory（菜单栏 App，无 Dock 图标）
    }
}
```

#### 布局

```
┌──────────────────────────────────────────────────────────┐
│ kWatch                                   ≡ 设置  ⇧⌘U  │
├────────────┬─────────────────────────────────────────────┤
│ 📊 概览    │  ┌──────┐ ┌──────┐ ┌──────┐                │
│ 📈 趋势    │  │ CPU  │ │ 内存  │ │ 磁盘  │                │
│ ⚙ 进程    │  │ 45%  │ │8/16G │ │60%   │                │
│ 🔔 告警    │  │▁▃▅▇▅▃│ │▃▅▇▅▃▂│ │▅▆▇▆▅▃│                │
│            │  └──────┘ └──────┘ └──────┘                │
│            │  ┌──────┐ ┌──────┐ ┌──────┐                │
│            │  │ 网络  │ │温度* │ │风扇* │                │
│            │  │↑12KB │ │65°C  │ │3200  │                │
│            │  │↓256KB│ │▅▇▅▃▂ │ │▃▅▇▅▃│                │
│            │  └──────┘ └──────┘ └──────┘                │
│            │                                            │
│            │  24 小时趋势图（可切换指标）                 │
│            │  ▁▂▃▅▇██▇▅▃▂▁▂▃▅▇██▇▅▃                  │
│            │     CPU 使用率 (%)                          │
│            │                                            │
│            │  [CPU] [内存] [磁盘] [网络]                 │
│            │  （指标切换按钮）                            │
│            └─────────────────────────────────────────────┘
    * 标注 Pro 锁定
```

#### 指标卡片状态图

```
[正常]       [加载中]      [错误]          [Pro 锁定]
┌────────┐  ┌────────┐  ┌────────┐     ┌───────────────┐
│ CPU    │  │ CPU    │  │ CPU    │     │ 温度 (Pro)     │
│ 45%    │  │ ···    │  │ ⚠ 无法 │     │               │
│▁▃▅▇▅▃ │  │▁▁▁▁▁▁│  │ 读取   │     │ 🔒 解锁以查看   │
│ 🔥65°C │  │        │  │        │     │ [解锁 $7.99]   │
└────────┘  └────────┘  └────────┘     └───────────────┘
```

#### 指标卡片交互

| 元素 | 交互 | 反馈 | Free/Pro |
|:-----|:-----|:------|:---------|
| 卡片（CPU/内存/磁盘/网络） | **单击** | Popover 显示最近 10 分钟实时窗口趋势图 | Free ✅ |
| 卡片（CPU/内存/磁盘/网络） | **双击** | 跳转到 Trends 页（24h/7d/30d） | 仅 Pro |
| 卡片 | **右键** | 快捷菜单：复制值 / 设置告警 / 在菜单栏显示 | 全部 |
| 趋势图 | **拖动** | 选择时间范围（仅在 Trends 页可用） | 仅 Pro |
| Pro 卡片（温度/风扇/电池） | **单击** | 触发 PaywallView | Free 锁定 |
| 卡片右上角 | 悬浮时出现设置齿轮 | 点击进入该指标的设置 | 全部 |

> **重要澄清**：Dashboard 卡片单击的 popover 仅显示 **最近 10 分钟** 的实时窗口数据（Free 也可用），用于快速查看趋势。完整的 24h/7d/30d 历史在独立的 Trends 页面（仅 Pro）。这是 Free 用户能体验"历史感"的最低门槛。

### 9.5 趋势页面（Pro）

```
┌────────────────────────────────────────────────────┐
│ 趋势                                          [24h▼]│
├────────────────────────────────────────────────────┤
│                                                    │
│  ┌──────────────────────────────────────────────┐  │
│  │                                              │  │
│  │  ▁▂▃▅▇██▇▅▃▂▁▂▃▅▇██▇▅▃▂▁   ── CPU 使用率   │  │
│  │  ▂▃▄▅▆▇▆▅▄▃▂▁▂▃▄▅▆▇▆▅▄▃   ── 内存使用率    │  │
│  │                      ▁▃▅▇▆▅  ── 温度          │  │
│  └──────────────────────────────────────────────┘  │
│                                                    │
│  [1h] [6h] [24h] [7d] [30d]                        │
│                                                    │
│  平均值: 45%  最高: 98% (14:32)  最低: 12% (03:15)│
└────────────────────────────────────────────────────┘
```

### 9.6 进程页面

```
┌────────────────────────────────────────────────────┐
│ 进程                            搜索 🔍            │
├─────┬──────────┬──────┬──────┬───────┬─────────────┤
│ PID │ 名称     │ CPU  │ 内存 │ 网络  │ 磁盘        │
├─────┼──────────┼──────┼──────┼───────┼─────────────┤
│ 123 │ Chrome   │ 12%  │ 1.2G │ ↑2KB  │ 50KB/s     │
│ 456 │ Xcode    │ 8%   │ 2.1G │ ↑0KB  │ 200KB/s    │
│ 789 │ Safari   │ 5%   │ 800M │ ↑12KB │ 10KB/s     │
│ ... │ ...      │ ...  │ ...  │ ...   │ ...        │
├─────┴──────────┴──────┴──────┴───────┴─────────────┤
│ 排序: 单击表头切换排序字段                              │
│ 搜索: 实时过滤进程名                                   │
│ Pro: 解锁后显示全部进程                                │
└────────────────────────────────────────────────────┘
```

### 9.7 告警系统

#### 告警阈值配置

```
┌────────────────────────────────────────────────────┐
│ 告警设置                                            │
├────────────────────────────────────────────────────┤
│                                                    │
│  CPU 占用 > 90%               [🔔开] [90%]        │
│  内存使用 > 85%               [🔔开] [85%]        │
│  磁盘使用 > 90%               [🔔开] [90%]        │
│  ───────────────────────────                        │
│  CPU 温度 > 85°C  (Pro)        [🔒]               │
│  风扇异常 (Pro)                 [🔒]               │
│                                                    │
│  通知方式: [系统通知] [Live Activity] [都发]       │
└────────────────────────────────────────────────────┘
```

#### 告警触发 → 通知 → 展示

```
采样 → CPU > 90% × 持续 30 秒（去抖）
  └→ AlertManager.raise(alert: CPUCritical)
       └→ 系统通知: "CPU 持续高占用 95%"
       └→ Live Activity（Pro）: "🔥 CPU 95%"（持续 30 分钟）
       └→ 告警列表新增记录
       └→ 不重复弹（30 分钟内相同类型不再触发）
```

#### 告警通知格式

| 通知 | 标题 | 内容 |
|:-----|:-----|:------|
| CPU 高占用 | "CPU 持续高占用" | "95% 持续 30s，Top: Chrome 32%" |
| 温度过高 (Pro) | "Mac 温度过高" | "CPU 温度 95°C，建议检查通风" |
| 磁盘将满 | "磁盘空间不足" | "已用 95%，仅剩 12 GB" |
| 风扇异常 (Pro) | "风扇异常" | "左侧风扇 RPM 异常（0 RPM）" |

### 9.8 Widget 设计

#### 基础 Widget（macOS 13+）

**小尺寸（160×160pt）**：
```
┌──────────────────┐
│ kWatch      📊   │
│                  │
│ CPU    45%       │
│  ▁▃▅▇▅▃▂▁        │
│                  │
│ 内存   8.2/16 GB │
│  ▃▅▇▅▃▂▁▂▃       │
└──────────────────┘
```

**中尺寸（340×160pt）**：
```
┌──────────────────────────────────┐
│ kWatch                      📊  │
│                                  │
│ CPU  45%  ▁▃▅▇▅▃▂▁   │ 内存 8/16GB  ▃▅▇▅▃▂▁▂▃│
│ 磁盘 60%  ▅▆▇▆▅▄▃▂   │ 网络 ↑12 ↓256 KB/s     │
└──────────────────────────────────┘
```

#### Interactive Widget（macOS 14+）

**小尺寸交互**：
```
┌──────────────────┐
│ kWatch      📊   │
│                  │
│ CPU    45%   🔽  │ ← 点击切换指标
│  ▁▃▅▇▅▃▂▁        │
│                  │
│ 🔄 [打开 Dashboard]│
└──────────────────┘
```

**中尺寸交互**：
```
┌──────────────────────────────────┐
│ kWatch                      📊  │
│                                  │
│ 🔄 刷新  ⚙ 设置   指标: [CPU▼]  │
│ CPU  45%  ▁▃▅▇▅▃▂▁               │
│ 温度 65°C ▃▅▇▅▃▂▁                │
│                                  │
│ [打开 Dashboard]                  │
└──────────────────────────────────┘
```

### 9.9 Live Activity 设计（Pro, macOS 14+）

#### 温度告警

```
┌───────────────────────────────────────────────────────┐
│ 🔥 kWatch · CPU 高温告警                               │
│ CPU: 95°C | 阈值: 85°C                                │
│ ▁▃▅▇██▇▅▃▂▁                                          │
│ [查看详情]  [忽略]                                     │
└───────────────────────────────────────────────────────┘
```

#### 监控会话（用户主动启动）

```
┌───────────────────────────────────────────────────────┐
│ 📊 kWatch · 监控进行中                                 │
│ CPU: 45% | 内存: 8.2G | 温度: 65°C                   │
│ ▁▃▅▇▅▃▂▁  ▃▅▇▅▃▂▁▂▃  ▅▆▇▆▅▄▃▂                       │
│ [停止监控]                                            │
└───────────────────────────────────────────────────────┘
```

### 9.10 设置窗口

```
┌────────────────────────────────────────────────────┐
│ 设置                                                │
├─────┬──────────────────────────────────────────────┤
│ 常规 │ ┌──────────────────────────────────────────┐ │
│ 菜单栏│  启动时自动运行                    [开/关]  │ │
│ Widget│  采样频率 (Hz)           [0.5] [1] [2] [5] │ │
│ 告警  │  历史保留天数                     [30 天▼] │ │
│ 关于  │  主题                      [自动▼]        │ │
│      │ └──────────────────────────────────────────┘ │
├─────┼──────────────────────────────────────────────┤
│ 菜单栏│ ┌──────────────────────────────────────────┐ │
│      │  显示指标（拖拽排序）                        │ │
│      │  ┌────┐ ┌────┐ ┌────┐ ┌────┐ ┌────┐      │ │
│      │  │ CPU│ │ 内存│ │磁盘│ │网络│ │温度*│      │ │
│      │  └────┘ └────┘ └────┘ └────┘ └────┘      │ │
│      │  风格: [图表] [数字] [极简] [自定义]       │ │
│      │ └──────────────────────────────────────────┘ │
├─────┼──────────────────────────────────────────────┤
│ Widget│ ┌──────────────────────────────────────────┐ │
│      │  Widget 显示的指标:                          │ │
│      │  ☑ CPU  ☑ 内存  ☐ 磁盘  ☐ 网络            │ │
│      │  Widget 主题: [默认] [深色] [浅色]           │ │
│      │ └──────────────────────────────────────────┘ │
├─────┼──────────────────────────────────────────────┤
│ 告警 │ ┌──────────────────────────────────────────┐ │
│      │  阈值配置（见 9.7 节）                      │ │
│      │ └──────────────────────────────────────────┘ │
├─────┼──────────────────────────────────────────────┤
│ 关于 │  Version 1.0.0  Build 1                    │ │
│      │  License: Pro / Free                       │ │
│      │  [恢复购买]  [反馈]  [隐私政策]                │ │
└─────┴──────────────────────────────────────────────┘
  * 标注 Pro 锁定项
```

### 9.11 系统托盘交互

| 场景 | 行为 |
|:-----|:------|
| App 启动 | 无 Dock 图标（LSUIElement = YES），仅菜单栏 |
| 用户退出 | 菜单栏图标消失，所有进程退出 |
| 用户关闭 Dashboard 窗口 | 窗口隐藏，菜单栏图标保留 |
| 用户点击"X" | 默认关闭窗口（与 macOS 标准行为一致） |
| 菜单栏图标 | 系统守护，不会被自动移除 |
| 重新打开 | 单击菜单栏图标恢复窗口 |

### 9.12 键盘快捷键

| 快捷键 | 功能 | 作用域 |
|:--------|:------|:--------|
| ⌘D | 打开/切换 Dashboard | 全局 |
| ⌘1/2/3/4 | 切换标签页（概览/趋势/进程/告警） | Dashboard |
| ⌘, | 设置 | 全局 |
| ⌘R | 强制刷新快照 | 全局 |
| ⇧⌘U | 升级到 Pro | 全局 |
| ⌥⌘P | 暂停/恢复监控 | 全局 |
| ⌘Q | 退出 kWatch | 全局 |
| Esc | 关闭当前窗口（保留菜单栏） | Dashboard |
| ⌘W | 关闭窗口 | Dashboard |
| ⌘M | 最小化窗口 | Dashboard |

### 9.13 无障碍设计

| 需求 | 实现方式 |
|:-----|:---------|
| **VoiceOver** | 所有图表数据点可描述（"CPU 使用率 45%，趋势上升"） |
| **动态字体** | 指标数字尊重系统 Dynamic Type |
| **Reduce Motion** | 关闭图表动画，仅静态数据展示 |
| **Increase Contrast** | 高对比度配色，颜色含义 + 文本标签(如"🔴 高") |
| **全键盘导航** | Tab 序 + 空格/回车操作所有可交互元素 |

### 9.14 Paywall 交互

```
触发场景:
  1. 点击 Pro 锁定卡片
  2. 设置中点击 Pro 锁定项
  3. 右键菜单 "升级到 Pro..."
  4. Onboarding 第 3 步 "查看价格"

┌────────────────────────────────────┐
│  解锁 kWatch Pro              ✕   │
│ ──────────────────────────────────│
│                                    │
│  🚀 全部 7 类指标                  │
│  🌡 温度 / 风扇 / 电池             │
│  📊 历史趋势 24h/7d/30d           │
│  🔔 Interactive Widget            │
│  🔴 Live Activity 告警            │
│  ⚙ 自定义告警阈值 + 菜单栏        │
│                                    │
│  ────────────────────────────      │
│                                    │
│  ┌────────────────────────────┐   │
│  │  解锁 Pro - $7.99 一次性   │   │
│  └────────────────────────────┘   │
│                                    │
│  7 天无条件退款保障                  │
│                                    │
│  [恢复购买]  [隐私 / 条款]        │
│                                    │
│  💳 自动验证，无需额外权限         │
└────────────────────────────────────┘

加载状态:
┌────────────────────────────────────┐
│  ... 正在连接 App Store            │
└────────────────────────────────────┘

成功状态:
┌────────────────────────────────────┐
│  ✅ 恭喜，Pro 已解锁!              │
│  所有功能已可用                     │
│  [开始使用]                        │
└────────────────────────────────────┘

失败状态:
┌────────────────────────────────────┐
│  ⚠ 购买失败                        │
│  原因: [具体错误信息]               │
│  [重试]  [取消]                    │
└────────────────────────────────────┘
```

---

## 10. 错误处理与边界条件

### 10.1 错误类型定义

```swift
enum MetricsError: Error, LocalizedError {
    // 系统 API 错误
    case hostProcessorInfoFailed
    case hostStatisticsFailed
    case getifaddrsFailed
    case procListFailed
    case sysctlFailed(String)

    // SMC 错误 (Pro)
    case smcServiceNotFound
    case smcOpenFailed(kern_return_t)
    case smcReadFailed(String, kern_return_t)

    // 聚合错误
    case allProvidersFailed
    case samplingPaused

    // 权限
    case fullDiskAccessRequired
    case ioKitPermissionDenied

    var errorDescription: String? {
        switch self {
        case .hostProcessorInfoFailed:   return "无法获取 CPU 信息"
        case .hostStatisticsFailed:      return "无法获取内存统计"
        case .getifaddrsFailed:          return "无法获取网络接口信息"
        case .procListFailed:            return "无法枚举进程"
        case .sysctlFailed(let name):    return "系统参数 \(name) 读取失败"
        case .smcServiceNotFound:        return "SMC 服务不可用（非 Intel Mac？）"
        case .smcOpenFailed(let kr):     return "SMC 打开失败 (\(kr))"
        case .smcReadFailed(let key, let kr):
                                         return "SMC \(key) 读取失败 (\(kr))"
        case .allProvidersFailed:        return "所有传感器错误，监控暂停"
        case .samplingPaused:            return "监控已暂停"
        case .fullDiskAccessRequired:    return "需要全盘访问权限"
        case .ioKitPermissionDenied:     return "IOKit 权限被拒绝，温度/风扇不可用"
        }
    }
}
```

### 10.2 失败隔离策略

```
[单个 Provider 失败]
  ┌────────────────────────────────────┐
  │  Provider.snapshot() throws        │
  │                                    │
  │  → Aggregator 捕获错误，不传播     │
  │  → 该指标标记为"不可用"            │
  │  → 其他 6 类指标继续正常采集       │
  │  → Dashboard 显示对应卡片为错误态  │
  │  → 重试策略：3 次后 exponential    │
  │    backoff（5s → 30s → 5min → 1h）│
  │  → 1 小时后完全降级，不再重试      │
  └────────────────────────────────────┘

[全部 Provider 失败]
  ┌────────────────────────────────────┐
  │  所有 provider 均抛出错误          │
  │                                    │
  │  → Aggregator 进入 pause 状态     │
  │  → 发送 AppError 错误事件          │
  │  → Dashboard 显示"所有传感器异常"  │
  │    + "重试" 按钮                   │
  │  → 菜单栏图标变为灰色 "— —"       │
  └────────────────────────────────────┘
```

### 10.3 重试与退避

```swift
actor RetryPolicy {
    let maxRetries = 3
    var attempt: Int = 0
    var lastFailure: Date?

    func nextDelay() -> TimeInterval {
        attempt += 1
        switch attempt {
        case 1:  return 5
        case 2:  return 30
        case 3:  return 300     // 5 分钟
        default: return 3600    // 1 小时
        }
    }

    func shouldRetry() -> Bool {
        attempt <= maxRetries
    }
}
```

### 10.4 边缘情况处理

| 场景 | 处理方式 |
|:-----|:---------|
| **非 Intel Mac（Apple Silicon）** | SMC 不支持时：温度/风扇通过 `thermalMonitor` 替代 |
| **台式机无电池** | BatteryMetrics 返回 nil，Dashboard 隐藏电池卡片 |
| **无网络接口** | NetworkMetrics 返回空数组，显示"No network"提示 |
| **SMC 权限拒绝** | 显示引导页面，告知用户系统安全设置 |
| **Core Data 写入失败** | 降级：不存历史，实时监控不受影响 |
| **Widget 无数据** | 显示"打开 kWatch 开始监控"占位图 |
| **屏幕睡眠/锁屏** | 暂停采样（signpost），唤醒后恢复，减少功耗 |
| **电池供电时** | 自动降采样率（1Hz → 0.5Hz）以降低功耗 |
| **大量进程（>1000）** | 分页枚举，单次最多取 top 50 |
| **系统语言切换** | 重新加载本地化资源，刷新所有 UI 文字 |
| **StoreKit 验证失败** | 缓存上次验证结果，定期重试（非阻塞） |
| **菜单栏图标过多被折叠** | 系统折叠时自动切换为极简模式（单一圆点颜色指示器），单击展开原始视图；用户也可在设置中固定为数字模式以节省空间 |

### 10.5 功耗考虑

| 场景 | 措施 |
|:-----|:------|
| 菜单栏运行 | 采样 1Hz，CPU 占用 < 0.5% |
| Dashboard 打开 | 升级到 60fps 渲染（图表动画） |
| 电池供电 | 自动降采样率到 0.5Hz |
| 屏幕休眠 | 暂停采样（NSWorkspace.screensSleepNotification） |
| Widget | 系统控制刷新频率，不额外消耗 |

---

## 11. 本地化策略

### 11.1 支持语言

| 语言 | 地区 | 优先级 |
|:-----|:-----|:------|
| 英文 | 美区 / 英区 / 全球 | 主要 |
| 简体中文 | 中国区 | 主要 |
| 日文 | 日本区 | 次要 |

### 11.2 本地化范围

| 内容 | 是否本地化 | 说明 |
|:-----|:----------|:------|
| 所有 UI 文案 | ✅ | LocalizedStringKey + String Catalog |
| 指标名称（英文保留） | ✅ | CPU/Memory 不翻译，说明文字翻译 |
| 传感器 key 对应名称 | ✅ | "TC0P" → "CPU Core 1" / "CPU 核心 1" |
| 告警通知正文 | ✅ | 3 语言 |
| Spotlight 索引 | ✅ | "mac temperature" / "Mac 温度 / 温度" |
| App Store 元数据 | ✅ | 描述 + 关键词 + 截屏 |
| Widget 文案 | ✅ | |
| 快捷键标注 | 不翻译 | ⌘D |

### 11.3 本地化工具

- 使用 **SwiftUI String Catalog**（`.xcstrings`）
- 与 kSpaceClean 共享翻译工具链
- 优先机器翻译 + 人工校对

---

## 12. ASO 策略

### 12.1 主关键词（美区）

| 关键词 | 竞争度 | 搜索量 | 策略 |
|:-------|:------:|:------:|:-----|
| `mac monitor` | 中 | 高 | 核心标题 |
| `menu bar monitor` | 中 | 中 | 副标题 |
| `system monitor` | 中 | 中 | 关键词 |
| `cpu temperature mac` | 低 | 中 | 精准流量 |
| `istat alternative` | 低 | 中 | **高转化** |
| `mac widget` | 中 | 高 | 差异化 |
| `mac memory cleaner` | 中 | 中 | 长尾 |
| `mac stats` | 高 | 高 | 竞争（不做核心，充实 keywords） |

### 12.2 差异化 ASO 角度

```
#1 iStat Menus Alternative (Free + $7.99 Pro)
macOS 13+ Native, built with SwiftUI
Interactive Widget + Live Activity support
Free CPU, Memory, Disk & Network monitor
Unlock Pro for full temperature, fan, battery sensors
```

### 12.3 App Store 元数据

| 字段 | 内容 |
|:-----|:------|
| **Name** | kWatch - System Monitor |
| **Subtitle** | Menu bar monitor, widgets & more |
| **Keywords** | mac monitor, menu bar, system monitor, cpu temperature, istat alternative, mac stats, memory cleaner, disk usage, network speed, battery health, fan control, widget, live activity |
| **Promotional Text** | The most elegant Mac monitoring tool. Free basic metrics, unlock Pro for full sensors. |
| **Support URL** | `https://kraftly.app/support/kwatch`（上线前配置） |
| **Marketing URL** | Kraftly 官网 |

### 12.4 截屏策略

| 截屏 | 内容 | ASO 角度 |
|:-----|:------|:---------|
| 1（主） | Dashboard 概览 + 3 种菜单栏风格 | 展示设计感 |
| 2 | 微型趋势图 + Tooltip | 差异化亮点 |
| 3 | Interactive Widget（macOS 14+） | 平台集成 |
| 4 | Live Activity 告警 | 创新功能 |
| 5 | 温度/风扇数据页（Pro） | 转换 Pro |
| 6 | Shortcuts + Spotlight 集成 | 效率工具 |

### 12.5 本地化 App Store 元数据

| 语言 | Name | Subtitle | Keywords |
|:-----|:-----|:---------|:---------|
| 简体中文 | kWatch - 系统监控 | 菜单栏监控、Widget 和更多 | Mac监控,菜单栏,系统监视,CPU温度,风扇转速,电池健康 |
| 日文 | kWatch - システムモニター | メニューバーモニター、ウィジェット | Macモニター、メニューバー、CPU温度、ファン制御 |

---

## 13. 上架时间表

### 13.1 阶段拆分

| 阶段 | 周次 | 交付物 | 关键文件数 |
|:----:|:----:|:--------|:---------:|
| **0** | W1-W2 | kFoundation MetricsKit + SMCAdapter + 项目骨架 | ~15 |
| **1** | W3-W4 | 4 项基础指标采集 + 菜单栏图表引擎 | ~12 |
| **2** | W5-W6 | Dashboard 主窗口 + 3 种风格 + 基础 Widget | ~10 |
| **3** | W7-W8 | Pro 指标（SMC 温度/风扇/电池）+ StoreKit 解锁 | ~8 |
| **4** | W9-W10 | Interactive Widget + Live Activity + Spotlight + Shortcuts | ~10 |
| **5** | W11 | 多语言 + 设置 + 告警系统 + 通知中心 | ~8 |
| **6** | W12 | TestFlight 内测 + 修复 + App Store 元数据 | ~3 |
| **7** | W13 | **App Store 提交 + 申请苹果推荐** | — |

### 13.2 关键里程碑

| 里程碑 | 预期时间 | 通过标准 |
|:-------|:---------|:---------|
| W2 结束 | 项目骨架完成 | kWatch target 可编译，菜单栏图标显示"Hello" |
| W4 结束 | 基础监控完成 | 菜单栏显示 CPU/内存/磁盘/网络实时数据 |
| W6 结束 | 全 UI 完成 | Dashboard 完整可用 + 风格切换 + Widget 显示 |
| W8 结束 | Pro 功能完成 | 温度/风扇/电池采集 + 购买解锁流程完整 |
| W10 结束 | 平台集成完成 | Widget/LA/Spotlight/Shortcuts 全部正常 |
| W11 结束 | 发布前准备 | 多语言 + 元数据 + 所有平台集成就绪 |
| W12 结束 | TestFlight 完成 | 修复所有 P0/P1 bug |
| **W13** | **App Store 提交** | **审核通过 + 申请推荐** |

### 13.3 依赖风险

| 风险 | 概率 | 影响 | 缓解措施 |
|:-----|:----:|:----:|:---------|
| SMC 在 Apple Silicon 上不完全兼容 | 中 | 高 | 使用 thermal_monitor 替代，降级显示部分数据 |
| IOKit 权限在沙箱下受限 | 低 | 高 | 提交前验证 App Store 审核行为 |
| Widget 刷新频率限制导致体验差 | 低 | 中 | 使用 TimelineProvider + 后台刷新 |
| Live Activity 在 macOS 14 采用率低 | 中 | 低 | 不做主要卖点，作为附加亮点 |
| $7.99 vs iStat $11.99 价格差异不够 | 低 | 中 | 突出设计+Widget+LA 差异点 |

---

## 14. 开放问题与风险

### 14.1 待确认

| # | 问题 | 影响 | 建议方案 |
|:-:|:-----|:----:|:---------|
| 1 | Apple Silicon 上 SMC 兼容性 | 温度/风扇 Pro 功能 | 备选：thermal_monitor API |
| 2 | App Store Sandbox 下 IOKit 权限 | 温度传感器读取 | 沙箱 entitlement 申请 |
| 3 | 是否支持 Intel / Apple Silicon 双架构 | 二进制大小 ~2MB vs ~4MB | 支持双架构（Fat Binary） |
| 4 | 菜单栏 App 的 App Store Review Guideline 合规 | 审核周期 | 确保符合 Guideline 2.4.1 |
| 5 | 是否需要伴随 kSpaceClean 一起发布 | 营销协同 | 建议错开 4-6 周，独立发布 |

### 14.2 已知风险

- **SMC 在 Apple Silicon 上的可用性**：Apple Silicon Mac 的 SMC 接口与 Intel 不同。TC0P 等 key 可能不存在，需 fallback 到 `thermal_monitor` API（macOS 13+）或 `IOHIDEvent`。
  - 具体 fallback 方案：先尝试 SMC 读取，失败后通过 `sysctl` 读取 `machdep.xcpm.cpu_thermal_level`（Apple Silicon 支持），或使用 `IOHIDEventSystemClient` 查询 `AppleCurrentProcessorInput` 传感器。
  - 若全部不可用：温度卡片显示"当前系统不支持"，风扇卡片隐藏，Pro 用户看到降级提示但不影响购买决策。|
- **进程级网络流量**：需 root 权限才能获取精确进程网络数据。Free 用户不展示，Pro 用户使用 `netstat` + `libproc` 近似值。
- **App Store 审核**：菜单栏 App + sysctl/IOKit 调用可能触发审核人工审查。需在审核备注中说明用途和系统级别的合规性。

---

## 15. 隐私与合规

### 15.1 Privacy Policy 与 EULA

| 文档 | URL | 内容 |
|:-----|:----|:-----|
| **Privacy Policy** | `https://kraftly.app/privacy` | 数据收集、使用、保留政策 |
| **EULA** | `https://kraftly.app/eula` | 终端用户许可协议（订阅/买断条款） |
| **App Store EULA** | Apple 标准 EULA | 退订、退款、Family Sharing 等 Apple 标准条款 |

### 15.2 App Privacy Details（Nutrition Label）

提交 App Store 时填写：

| 数据类型 | 是否收集 | 用途 | 是否链接用户身份 |
|:---------|:---------|:-----|:-----------------|
| 系统监控数据（CPU/内存/磁盘/网络/温度/风扇/电池） | ✅ | 应用功能 | ❌（仅本地） |
| 进程列表 | ✅ | 应用功能 | ❌ |
| 崩溃日志（MetricKit，本地） | ✅（仅本地） | 应用功能 | ❌ |
| 用户诊断数据 | ⚠️（用户主动发送） | 客户支持 | ⚠️（可匿名） |
| 购买凭证 | ✅（App Store 验证） | 交易 | ✅（Apple ID） |
| 使用分析 | ❌ | — | — |
| 位置 | ❌ | — | — |
| 联系方式 | ❌ | — | — |
| 浏览历史 | ❌ | — | — |

### 15.3 第三方 SDK 列表

| SDK | 用途 | 是否传输数据 |
|:----|:-----|:------------|
| 无 | kWatch 不集成任何第三方 SDK | — |

> 所有功能均使用 Apple 原生 API（StoreKit、MetricKit、ActivityKit、AppIntents、CoreSpotlight、IOKit 等），不集成 Firebase / Crashlytics / 任何分析 SDK。

### 15.4 数据生命周期

```
┌────────────┐    实时采集    ┌────────────┐
│ 系统指标   │ ─────────→  │ 本地缓存   │
└────────────┘              └─────┬──────┘
                                  │ 每 1 分钟聚合
                                  ▼
                          ┌──────────────┐
                          │ Core Data    │
                          │ 30 天保留    │
                          └─────┬────────┘
                                │ 30 天后自动清理
                                ▼
                          ┌──────────────┐
                          │ 永久删除     │
                          └──────────────┘
```

- **本地缓存**：仅存于内存，App 退出即清除
- **Core Data**：30 天保留（用户可设为 7/30 天），自动清理
- **告警日志**：90 天保留
- **崩溃日志**：保留 7 天，用户可主动发送最近 24h 数据
- **卸载 App**：所有数据立即清除

### 15.5 合规性

| 法规 | 状态 | 说明 |
|:-----|:-----|:-----|
| GDPR | ✅ 合规 | 零收集用户数据，无需同意机制 |
| CCPA | ✅ 合规 | 用户数据仅本地 |
| 中国《个人信息保护法》 | ✅ 合规 | 无服务器交互 |
| Apple Privacy Manifest | ✅ 必填 | 上线前生成 PrivacyInfo.xcprivacy |

---

## 16. 崩溃监控与诊断

### 16.1 MetricKit 集成

kWatch 集成 Apple MetricKit 收集崩溃和性能数据：

```swift
import MetricKit

final class DiagnosticsManager: NSObject, MXMetricManagerSubscriber {
    func didReceive(_ payloads: [MXMetricPayload]) {
        // 写入本地诊断文件
        for payload in payloads {
            try? saveDiagnostics(payload)
        }
    }

    func didReceive(_ payloads: [MXCrashPayload]) {
        for payload in payloads {
            try? saveCrashReport(payload)
        }
    }
}
```

**收集内容**：
- 应用崩溃日志（堆栈、寄存器、设备信息）
- CPU/内存/磁盘使用情况（事后统计）
- 启动时间、卡顿帧统计
- 电源状态（电池/充电）

**存储**：
- 保留最近 7 天的诊断数据到 `~/Library/Application Support/kWatch/diagnostics/`
- 总大小限制 10 MB（超出自动清理）

### 16.2 用户主动反馈渠道

设置 → 关于 → 「报告问题」：
- 自动收集：最近 24h MetricKit 数据 + 当前 snapshot + 系统版本
- 用户填写：问题描述 + 联系邮箱
- 通过 `mailto:support@kraftly.app?subject=kWatch%20Issue&body=<base64-encoded-diagnostics>` 发送
- 邮件内容由用户决定是否发送（不自动上传）

### 16.3 App Store Connect Analytics

| 指标 | 来源 |
|:-----|:-----|
| 启动次数 | App Store Connect Analytics |
| 崩溃率 | App Store Connect Analytics |
| 评分 | App Store Reviews |
| 转化率 | App Store Connect Analytics |
| 收入 | App Store Connect |

不需要第三方 Analytics。

---

## 17. 测试策略

### 17.1 测试金字塔

```
        ┌─────────────────┐
        │  UI Tests (XCUITest)  │  5%
        │  - 关键用户旅程        │
        ├─────────────────┤
        │ Integration Tests │  20%
        │  - Provider + Repo  │
        │  - App Group 通信   │
        ├─────────────────┤
        │   Unit Tests (XCTest) │  75%
        │  - 差分计算          │
        │  - 状态机           │
        │  - Repository mock  │
        └─────────────────┘
```

### 17.2 单元测试覆盖目标

| 模块 | 覆盖率目标 | 关键测试点 |
|:-----|:----------|:---------|
| MetricsProvider（7 个 actor） | 85%+ | 差分计算正确性、错误传播、内存管理 |
| MetricsAggregator | 80%+ | fan-out 顺序、AsyncStream buffering、暂停/恢复 |
| RetryPolicy | 100% | 指数退避、最大重试、状态转换 |
| ProGatedAggregator（装饰器） | 100% | Free/Pro 行为差异 |
| HistoryRepository | 75%+ | 三层时间分辨率聚合、清理逻辑 |
| PreferencesRepository | 90%+ | UserDefaults 持久化、默认值 |
| StoreManager | 80%+ | 购买/恢复/失败路径 |
| AlertManager | 80%+ | 阈值判定、去抖、抑制 |
| Domain Layer | 90%+ | 模型构造、Equatable |

### 17.3 集成测试

| 测试套件 | 工具 | 验证目标 |
|:--------|:-----|:---------|
| Provider + System | XCTest + Mock sysctl | 系统调用正确参数、返回值处理 |
| Core Data | XCTest + 内存 SQLite | 聚合、查询、清理 |
| App Group JSON | XCTest + 临时目录 | atomic 写入、并发读取 |
| StoreKit | StoreKitTest | 购买/恢复/订阅降级（订阅不可用于本产品，但 buy-to-own 可测） |

### 17.4 UI 测试（XCUITest）

关键用户旅程：
1. **Onboarding**：首次启动 → 4 步完成 → 进入主界面
2. **菜单栏交互**：点击菜单栏图标 → Dashboard 打开 → 单击卡片 → popover 展示
3. **购买流程**：Free 用户点击 Pro 卡片 → Paywall 显示 → Mock 购买 → 立即解锁
4. **设置保存**：修改告警阈值 → 退出 → 重启 → 阈值保留
5. **Widget 添加**：系统添加 Widget → 显示数据（snapshot 模拟）

### 17.5 性能基准

| 指标 | 目标 | 测试方法 |
|:-----|:-----|:---------|
| CPU 占用（仅菜单栏） | < 0.5% | XCTestCase.measure { ... } 模拟 60 秒运行 |
| 内存占用 | < 80 MB | XCTestCase.measure 内存 profile |
| 启动时间（冷启动） | < 1.5 秒 | `os_signpost` + 单元测试 |
| Widget 渲染时间 | < 100 ms | WidgetKit Timeline 测试 |

### 17.6 兼容性测试矩阵

| macOS 版本 | Apple Silicon | Intel |
|:-----------|:-------------|:------|
| 13.0 | ✅ 必测 | ✅ 必测 |
| 13.5+ | ✅ 必测 | ✅ 必测 |
| 14.0 | ✅ 必测（Live Activity） | ✅ 必测（Live Activity） |
| 14.5+ | ✅ 必测 | ✅ 必测 |
| 15.0+ | ✅ 必测（持续验证新 API） | ✅ 必测 |

### 17.7 CI/CD

| 工具 | 用途 |
|:-----|:-----|
| **GitHub Actions** | 单元测试 + UI 测试 + SwiftLint |
| **xcresult** | 测试报告归档 |
| **Xcode Test Plans** | 分组运行（Unit / Integration / UI / Performance） |
| **Codecov** | 覆盖率追踪（> 70% 阈值门禁） |

---

## 18. 营销与发布节奏

### 18.1 上线前 4 周准备（W9-W12）

| 周次 | 动作 |
|:-----|:-----|
| W9 | 联系 5-10 位 Mac 评测博主，送 Pro 兑换码（独立发码清单，避免公开链接被滥用） |
| W10 | 准备 ProductHunt 发布页面（预告视频 + 截图 + 描述） |
| W11 | 准备 X/小红书/HackerNews 内容（图文 + 1 分钟介绍视频） |
| W12 | 联系 Apple 开发者关系申请推荐；准备 Reddit r/macapps, r/MacOS 帖子 |

### 18.2 上线日动作清单

| 时段 | 动作 |
|:-----|:-----|
| 0:00 PT | ProductHunt 页面 publish，联系 PH Hunter |
| 1:00 PT | X/小红书同步发图文 |
| 2:00 PT | HackerNews "Show HN" |
| 3:00 PT | Reddit r/macapps, r/MacOS, r/swift |
| 8:00 PT | 监控 App Store Connect 数据 + 评论 |
| 12:00 PT | 回复评论 + 解决突发问题 |
| 20:00 PT | 总结当日数据 |

### 18.3 上线后第一周关键动作

1. **D+1**：主动联系已购买用户（通过 App Store Connect Messaging）询问反馈
2. **D+3**：根据评论更新 FAQ + 修复 P0/P1 问题
3. **D+5**：发 v1.0.1 修复版本（社区可见的"积极维护"信号）
4. **D+7**：Discord/Telegram 用户群建立 + 公开 Roadmap

### 18.4 上线后月度节奏

| 月份 | 动作 |
|:-----|:-----|
| M1 | 监控指标收集 + 评论响应 + v1.0.x 修复 |
| M2 | v1.1 迭代（实现 v1 延后功能：磁盘 I/O 速度、电池健康完整读数） |
| M3 | v1.2 + 新功能（参考用户反馈） |
| M6 | 评估表现，决定是否启动 kDupe 设计 |

### 18.5 营销素材清单

| 类型 | 数量 | 内容 |
|:-----|:-----|:-----|
| App Store 截图 | 6 张 | Dashboard、菜单栏、Widget、Live Activity、Pro 升级、Shortcuts |
| ProductHunt 缩略图 | 1 张 | 主视觉 + 卖点 |
| X/小红书图文 | 5 组 | 设计故事、对比 iStat、价格优势 |
| HackerNews 文字 | 1 篇 | 200 字技术故事 |
| 视频 | 1 分钟 | 快速演示 + 菜单栏特写 |
| 评测指南（博主） | 1 份 | 关键卖点 + 截图 + Pro 码 |

---

## 19. 风险缓解 Plan B

### 19.1 App Store 审核被拒 Plan B

**触发场景**：提交后被拒（GUIDeline 2.4.1 / 2.5.1 / 5.1.1 等）

**Plan B 内容**：
- 移除所有 IOKit 调用（SMC 温度/风扇/电池）
- Pro 功能降级为：跨 4 类基础指标的历史 + 自定义告警 + 平台集成（Widget/LA/Shortcuts/Spotlight）
- 价格保持 $7.99（仍有足够价值）
- ASO 重新定位："Apple 设计语言的菜单栏监控"
- 重新提交，预计 1-2 周内通过

**触发指标**：
- 审核被拒
- 审核超过 14 天无回复

### 19.2 Apple Silicon SMC 完全不可用 Plan B

**触发场景**：实测发现 Apple Silicon 上温度/风扇数据全部不可读

**Plan B 内容**：
- Apple Silicon 上隐藏温度/风扇卡片（不显示灰色卡，影响美观）
- 升级 Pro 价值聚焦：
  - 24h/7d/30d 历史趋势（全指标）
  - Interactive Widget
  - Live Activity
  - 自定义告警
  - 完整进程排行 + 搜索
  - 进程网络流量（合并到 v1）
- 售价可考虑下调至 $5.99（价值调整）
- ASO 强调 "优雅菜单栏监控 + 平台集成"

**触发指标**：
- M1 Mac 实测 SMC 全部失败
- 第三方机型调研（如果有 GitHub Issue 跟踪）

### 19.3 Live Activity 拒绝上架 Plan B

**触发场景**：审核员认为 Live Activity 用于"持续监控"违反 Guideline（macOS 上 Live Activity 用途争议）

**Plan B 内容**：
- v1 移除 Live Activity
- 替代方案：菜单栏图表（已有）+ 通知中心 UNNotification（已有）
- Pro 价值调整：跨平台通知 + 自定义告警
- v1.1 通过 Interactive Widget 弥补（虽不能锁屏常驻，但能直接交互）

### 19.4 Live Activity macOS 14 实际采用率低 Plan B

**触发场景**：macOS 14 用户占比 < 10%（发布 6 个月后）

**Plan B 内容**：
- Live Activity 仍保留，但不在 ASO 重点宣传
- 改强调 Interactive Widget（同样 macOS 14+，但使用频率更高）
- 监控 macOS 14 占比，达到 25% 后重启 LA 营销

### 19.5 进程网络流量实现风险 Plan B

**触发场景**：libproc 扩展或 IOKit 网络统计权限不足，无法实现精确的进程网络流量

**Plan B 内容**：
- Pro 进程排行仍以 CPU/内存排序为主（v1 默认）
- 网络流量数据降级为接口级（已有，Free 也可用）
- 完整进程网络流量推迟到 v2.0
- ASO 不宣传进程网络流量

---

> **文档结束**
>
> 编写日期：2026-07-26
> 配套文档：[2026-07-25-kraftly-kspaceclean-detailed-design.md](./2026-07-25-kraftly-kspaceclean-detailed-design.md)
> 下一步：review 通过后 → writing-plans 技能创建实施计划
