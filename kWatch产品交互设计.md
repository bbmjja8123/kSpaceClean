# kWatch 产品交互设计 — Session 记录

**项目**：Kraftly Mac App Suite — 第二款 App（kWatch 菜单栏监控）
**Session 日期**：2026-07-26
**最终规格**：`docs/superpowers/specs/2026-07-26-kraftly-kwatch-design.md`（2890 行，19 节）
**Git 提交**：`d98c593` + `55c4443`

---

## 目录

1. [Session 启动背景](#1-session-启动背景)
2. [用户输入与决策时间线](#2-用户输入与决策时间线)
3. [产品定位与定价决策](#3-产品定位与定价决策)
4. [功能范围与差异化](#4-功能范围与差异化)
5. [技术架构讨论](#5-技术架构讨论)
6. [完整 Spec 编写过程](#6-完整-spec-编写过程)
7. [Spec 自我审查](#7-spec-自我审查)
8. [全面优化改进](#8-全面优化改进)
9. [最终成果汇总](#9-最终成果汇总)

---

## 1. Session 启动背景

### 1.1 起点状态

- **kSpaceClean v1** 已完成（19 个 Task、39 个文件，2026-07-25 提交）
- **kWatch** 在 Backlog 中等待设计
- **kSift / kFresh** 仍在 Backlog

### 1.2 用户初始需求

> 我们即将开始 kWatch（菜单栏监控 App）的设计工作。这是 Kraftly 品牌下 4 款 Mac App 中的第二款。
>
> **背景信息**：
> - kWatch 定位：菜单栏系统监控工具
> - 主轴：平台集成 + Widget + Live Activities
> - 目标用户：极客 / 设计师 / 视频创作者
> - Bundle ID: `app.kraftly.kwatch`
> - 技术栈：SwiftUI + AppKit（菜单栏），macOS 13+
> - 不需 TCC 权限（只读系统 API）
> - 竞品标杆：iStat Menus（$11.99）、Stats（开源免费）
> - 参考 Lemon 中的 LemonMonitor（CPU/内存/磁盘/网络/温度/风扇监控）和 LemonNetSpeed（进程网络流量）

### 1.3 当前待决策项

1. 定价模式（订阅/买断？价格带？）
2. iStat Menus 主战场切入角度（差异化方向）
3. v1 功能范围（哪些监控项先做，哪些后做）
4. 平台集成深度（Widget、Live Activities、Shortcuts 等）

---

## 2. 用户输入与决策时间线

### 2.1 完整用户输入列表

| # | 用户输入 | 决策点 |
|:-:|:--------|:-------|
| 1 | "查看下CLAUDE.md，准备执行下一个应用的开始工作" | 启动 kWatch 设计 |
| 2 | "继续" | 继续之前的对话 |
| 3 | 选择方向 A（design-first）+ B（platform integration）融合 | 定位策略 |
| 4 | "如果这个应用需要面向大部分用户，而且需要有亮点有创意，并且需要能最大机会得到苹果推荐，需要使用哪个方案？或者是哪个融合方案？" | 寻求最优势方案 |
| 5 | "可以，按推荐的来" | 接受推荐方案 |
| 6 | "全部7+项" | 选择完整监控指标 |
| 7 | "是不是可以支持多种，并且有缺省的，用户也可以自定义配置？这样更好？" | 要求自定义配置 |
| 8 | "这款的定价，和kSpaceClean一样可以吗？这个分类，苹果上面的定价都是怎么样的？" | 询问定价模式 |
| 9 | "1和2哪个好？" | 比较订阅 vs 买断 |
| 10 | "可以" | 接受 Freemium + $7.99 |
| 11 | "kWatch" | 命名 |
| 12 | "可以" | 接受 Part 1 产品定位 |
| 13 | "可以" | 接受 Part 2 功能规格 |
| 14 | "这部分还不够，需要深入展开全面的设计，包括架构、设计模式、通讯方式、核心功能（这几项如何检测）、类图设计、数据层、以及还有完整全面的UX交互设计等" | 要求深入技术设计 |
| 15 | "可以" | 接受扩展技术设计 |
| 16 | "写好spec，再全面Review检查一遍" | 要求 spec + 全面审查 |
| 17 | "我切换了kimi模型，使用kimi模型，全面审视下spec，提出优化改进建议" | 要求深度审查 |
| 18 | "需要" | 同意合并改进到 spec |
| 19 | "把这个session的所有会话，我的输入，保存为 kWatch产品交互设计" | 导出本 session |

### 2.2 关键决策节点

```
W1 启动 → A+B 融合方案 → 全部 7 指标 → 自定义配置
       ↓
W2 定价：Freemium + $7.99 Pro → 命名 kWatch
       ↓
W3 Part 1 产品定位 → Part 2 功能规格
       ↓
W4 Part 3 深度技术设计（架构/模式/通讯/检测/类图/UX）
       ↓
W5 Spec 完成 → 自我审查 → 6 处修复
       ↓
W6 kimi 深度审查 → 15 项改进合并
       ↓
W7 完整 spec 2890 行，19 节
```

---

## 3. 产品定位与定价决策

### 3.1 定位讨论

#### 三种方向探索

| 方案 | 描述 | 优势 | 劣势 |
|:-----|:-----|:-----|:-----|
| **A. design-first** | Apple 设计语言优先，菜单栏图表 + 毛玻璃 UI | 视觉差异大，用户感知强 | 技术门槛低、易被复制 |
| **B. platform integration** | Widget + Live Activities + Shortcuts 深度集成 | 苹果推荐概率高 | 用户教育成本 |
| **A+B 融合**（推荐）| 视觉差异化 + 平台深度集成 | 兼顾美感与功能、苹果推荐两手抓 | 工程量大 |

#### 用户决策

> **用户问题**："如果这个应用需要面向大部分用户，而且需要有亮点有创意，并且需要能最大机会得到苹果推荐，需要使用哪个方案？或者是哪个融合方案？"

> **推荐**：A+B 融合方案（菜单栏图表美观 + 平台集成创新）

> **用户**："可以，按推荐的来"

### 3.2 定价决策

#### 探索过程

1. **候选 1**：与 kSpaceClean 一致 → Free Trial 7 天 + $19.99/年订阅
2. **候选 2**：Freemium + $7.99 Pro 买断

#### 竞品调研

| 竞品 | 定价 |
|:-----|:-----|
| iStat Menus | $11.99 买断 |
| Stats（开源） | 免费 |
| MenuBar Stats | $7.99 |
| TG Pro | $24 |

#### 用户决策

> **用户问题**："1和2哪个好？"

> **推荐**：候选 2（Freemium + $7.99）—— 与 iStat 价差本身就是购买理由，且买断符合"监控一次性价值"心智

> **用户**："可以"

### 3.3 最终定位

> **一句话定位**：菜单栏上最优雅的 Mac 系统监控。

| 用户群体 | 核心痛点 | 使用方式 |
|:---------|:---------|:---------|
| **Mac 全人群** | 想知道 Mac "卡不卡" | Widget 一眼看状态 |
| **设计师/创意工作者** | 渲染/导出时监控资源瓶颈 | 菜单栏图表 + Dashboard |
| **极客/效率追求者** | 需要温度/风扇数据 | 完整 7 类指标 + Shortcuts |

---

## 4. 功能范围与差异化

### 4.1 监控指标范围

> **用户**："全部7+项" —— 包括温度/风扇/电池

最终 7 类指标：

| # | 指标 | Free | Pro |
|:-:|:-----|:----:|:---:|
| 1 | CPU | ✅ | ✅ |
| 2 | 内存 | ✅ | ✅ |
| 3 | 磁盘 | ✅ | ✅ |
| 4 | 网络 | ✅ | ✅ |
| 5 | 温度 | ❌ | ✅ |
| 6 | 风扇 | ❌ | ✅ |
| 7 | 电池 | ❌ | ✅ |

### 4.2 自定义配置

> **用户**："是不是可以支持多种，并且有缺省的，用户也可以自定义配置？这样更好？"

**决策**：
- **3 种默认风格**（Free）：图表 / 数字 / 极简
- **完全自定义**（Pro）：任意组合 + 拖拽排序

### 4.3 差异化矩阵

| 维度 | iStat Menus | Stats（开源） | kWatch |
|:-----|:-----------:|:-------------:|:------:|
| 定价 | $11.99 买断 | 免费 | **Freemium $7.99 Pro** |
| 视觉设计 | 传统 UI | 粗糙 | **Apple 设计语言 + 毛玻璃** |
| 菜单栏图表 | ✅ 数字/图标 | ✅ 数字 | **✅ 微型趋势图引擎** |
| Interactive Widget | ❌ | ❌ | **✅ (macOS 14+)** |
| Live Activity | ❌ | ❌ | **✅ (macOS 14+)** |
| Spotlight 集成 | ❌ | ❌ | **✅** |
| Shortcuts | ❌ | ❌ | **✅ 8 个 Intents** |

### 4.4 v1 不做范围（YAGNI）

- ❌ 远程监控
- ❌ 多机管理
- ❌ GPU 详细监控
- ❌ Finder 扩展
- ❌ 风扇控制（只读）
- ❌ 自定义脚本/插件

---

## 5. 技术架构讨论

### 5.1 深度技术设计需求

> **用户**："这部分还不够，需要深入展开全面的设计，包括架构、设计模式、通讯方式、核心功能（这几项如何检测）、类图设计、数据层、以及还有完整全面的UX交互设计等"

**回应**：扩展 spec 至 19 节，包含：

#### 5.1.1 架构模式（16 种应用）
- **MVVM**：DashboardViewModel 等
- **Coordinator**：AppCoordinator / OnboardingCoordinator
- **Repository**：MetricsRepository / HistoryRepository
- **Strategy**：SamplingStrategy（fixed/adaptive）
- **Observer (AsyncStream)**：多消费者订阅
- **Producer-Consumer**：单生产者多消费者
- **Singleton + Service Locator**：AppContainer
- **State Machine**：AppState / LiveActivityState
- **Adapter**：SMCAdapter / IOKitAdapter
- **Decorator (Gated)**：ProGatedAggregator
- **Flyweight**：HistoryRingBuffer
- **Builder**：DashboardBuilder / WidgetConfigBuilder

#### 5.1.2 核心检测实现
- **CPU**：host_processor_info 差分计算
- **内存**：host_statistics64 + vm_statistics64
- **磁盘**：statfs + IOKit
- **网络**：getifaddrs
- **SMC**：IOKit AppleSMC
- **风扇**：SMC FNum/F{id}Ac/Mn/Mx
- **电池**：IOPS + SMC
- **进程**：libproc proc_listallpids

#### 5.1.3 类图设计
- AppContainer / MetricsAggregator / MetricsProvider 协议体系
- ViewModel 层次
- State Machine

#### 5.1.4 通讯方式
- 进程内：AsyncStream + UserDefaults + NotificationCenter
- 跨进程：App Group + ActivityKit + App Intents + CoreSpotlight
- Widget / Live Activity 数据流

#### 5.1.5 数据层
- Core Data 模型（MetricSample / AlertEvent / Preferences）
- App Group 共享
- 历史数据保留策略（三层时间分辨率）

---

## 6. 完整 Spec 编写过程

### 6.1 Spec 章节结构（最终 19 节）

| 节 | 标题 | 行数（估） |
|:--:|:-----|:----------:|
| 1 | 产品定位 | ~40 |
| 2 | 定价与盈利模式 | ~50 |
| 3 | 完整功能规格 | ~85 |
| 4 | 技术架构 | ~240 |
| 5 | 数据层设计 | ~325 |
| 6 | 类图与模块职责 | ~305 |
| 7 | 核心检测实现细节 | ~495 |
| 8 | 通讯方式 | ~135 |
| 9 | 完整 UX 交互设计 | ~570 |
| 10 | 错误处理与边界条件 | ~125 |
| 11 | 本地化策略 | ~30 |
| 12 | ASO 策略 | ~55 |
| 13 | 上架时间表 | ~40 |
| 14 | 开放问题与风险 | ~20 |
| 15 | 隐私与合规 | ~70 |
| 16 | 崩溃监控与诊断 | ~55 |
| 17 | 测试策略 | ~80 |
| 18 | 营销与发布节奏 | ~50 |
| 19 | 风险缓解 Plan B | ~65 |

### 6.2 代码示例数量

- **18+ 代码示例**：actor、protocol、JSON、SwiftUI、UI 设计 ASCII
- **60+ 表格**：功能矩阵、决策表、对比表

---

## 7. Spec 自我审查

### 7.1 审查过程

> **用户**："写好spec，再全面Review检查一遍"

### 7.2 四项审查结果

| 检查项 | 状态 | 问题数 |
|:-------|:----:|:------:|
| ✅ 内部一致性 | 无矛盾 | 0 |
| ✅ Scope 聚焦度 | v1 边界清晰 | 0 |
| ⚠️ Placeholder 检查 | 发现 3 处 | 3 |
| ⚠️ 歧义性检查 | 发现 4 处 | 4 |

### 7.3 修复清单（6 处）

1. **Support URL**：占位符 "toss" → `https://kraftly.app/support/kwatch`
2. **菜单栏折叠行为**：从"自适应宽度"改为"系统折叠时自动切换极简模式（单一圆点）"
3. **Apple Silicon SMC 降级**：扩展为三级 fallback + UI 表现说明
4. **CPU 温度 Free/Pro 归属**：新增脚注明确边界
5. **磁盘 I/O 速度代码占位**：标记 v1.1 实现，v1 显示 N/A
6. **电池 + 进程 I/O 代码占位**：明确推迟到 v1.1

---

## 8. 全面优化改进

### 8.1 切换 kimi 深度审查

> **用户**："我切换了kimi模型，使用kimi模型，全面审视下spec，提出优化改进建议"

### 8.2 改进建议清单（15 项）

#### P0 严重风险（3 项）

1. **Apple Silicon SMC 兼容性是核心商业风险**
   - 80% 设备可能是 Apple Silicon
   - Pro 卖点（温度/风扇/电池）在多数设备不可用
   - 建议：方案 A（Intel 完整 + Apple Silicon 降级）/ 方案 B（去掉高级监控）/ 方案 C（投入调研）

2. **App Group Core Data 跨进程文件锁风险**
   - Widget / App / Live Activity 同时读写同一 SQLite
   - 建议：改用 **App Group atomic JSON snapshot**

3. **SMC 读取的 App Store 合规性未验证**
   - 历史上多次被 App Store 审核退回
   - 建议：详细 App Review Notes 模板 + Plan B

#### P1 重要补充（5 项）

4. **缺失 Privacy Policy & 数据采集声明**
   - 新增 Section 15 隐私与合规

5. **崩溃与性能监控方案空白**
   - 新增 Section 16 崩溃监控与诊断（MetricKit）

6. **进程排行 Pro 边界问题**
   - 从 Top 5 vs 完整，改为 Top 5 vs Top 50 + 搜索 + 分组

7. **测试策略完全缺失**
   - 新增 Section 17 测试策略

8. **Bundle 策略需扩展**
   - Duo / Trio / Suite 演进路径

#### P2 改进建议（7 项）

9. 定价/商业模型微调（$4.99 首发 + 7 天试用 + 学生折扣 + Family Sharing）
10. 架构可改进点（协议化 DI + bufferingPolicy）
11. CPU 实现细节修正（vm_deallocate 防泄漏）
12. UX 改进点（菜单栏拖拽、Popover Free/Pro 区分）
13. Dashboard 窗口退出行为矛盾
14. 新增 Section 15-19 完整覆盖
15. Apple Silicon 监控的可选增强

### 8.3 用户决策

> **用户**："需要" —— 同意合并到 spec

### 8.4 最终合并的改动

**新增章节（5 节）**：
- Section 15 隐私与合规
- Section 16 崩溃监控与诊断
- Section 17 测试策略
- Section 18 营销与发布节奏
- Section 19 风险缓解 Plan B

**现有章节扩展（8 处）**：
- Section 2.3-2.4：Bundle 演进 + 首发优惠
- Section 3.3：进程 Pro 价值重新定义
- Section 4.4：AsyncStream bufferingPolicy
- Section 4.5（新增）：Apple Silicon 兼容性策略
- Section 4.7：协议化 DI
- Section 5.4：App Group JSON snapshot
- Section 7.1：CPU vm_deallocate 示例
- Section 8.6：App Store 审核合规模板
- Section 9.4：Popover Free/Pro 区分 + 窗口生命周期

---

## 9. 最终成果汇总

### 9.1 Spec 统计

| 指标 | 数值 |
|:-----|:----:|
| **总章节数** | 19 节（从 14 节扩展 +35.7%）|
| **总行数** | 2890 行（从 2345 行扩展 +23.2%）|
| **新增章节** | 5 节（15-19）|
| **代码示例数** | 18+ 个 |
| **表格数** | 60+ |
| **风险 Plan B** | 5 个具体场景 |
| **决策表** | 16+ |

### 9.2 Git 提交记录

```
d98c593 docs(kWatch): add comprehensive v1 spec with privacy, testing, marketing, risk mitigation
55c4443 docs(CLAUDE.md): mark kWatch v1 spec as complete
```

### 9.3 关键决策摘要

| 决策领域 | 最终方案 |
|:---------|:---------|
| **App 名称** | kWatch |
| **Bundle ID** | app.kraftly.kwatch |
| **定位** | 菜单栏上最优雅的 Mac 系统监控 |
| **目标用户** | Mac 全人群 / 设计师 / 极客 |
| **定价** | Free + $7.99 Pro 买断 |
| **监控指标** | 7 类（4 Free + 3 Pro）|
| **平台集成** | Widget + Live Activity + Spotlight + 8 Shortcuts |
| **架构** | Clean Architecture + MVVM + Coordinator + actor + AsyncStream |
| **App Group 共享** | atomic JSON snapshot（非 Core Data）|
| **最低系统** | macOS 13.0 |
| **本地化** | 英 / 中 / 日 |
| **首发优惠** | $4.99 限时首月 + 7 天试用 + 学生折扣 |
| **Bundle** | Kraftly Duo → Trio → Suite 演进 |

### 9.4 下一步

按 brainstorming 流程：
1. ✅ Spec 写好
2. ✅ Spec 自审 + 修复
3. ✅ kimi 深度审查 + 改进合并
4. ⏳ **用户 review spec 后** → 调用 writing-plans 技能创建实施计划
5. ⏳ writing-plans 拆解为可执行 Task
6. ⏳ 启动 v1 实施（预计 13 周）

---

## 附录 A：用户输入原文（按时间顺序）

### A.1 启动阶段

> 查看下CLAUDE.md  准备执行下一个应用的开始工作

> 我们即将开始 kWatch（菜单栏监控 App）的设计工作。这是 Kraftly 品牌下 4 款 Mac App 中的第二款。
> [详细背景见上文 1.2]

### A.2 方向决策

> 继续

> 如果这个应用需要面向大部分用户，而且需要有亮点有创意，并且需要能最大机会得到苹果推荐，需要使用哪个方案？或者是哪个融合方案？

> 可以，按推荐的来

### A.3 范围与配置

> 是不是可以支持多种，并且有缺省的，用户也可以自定义配置？这样更好？

### A.4 定价

> 这款的定价，和kSpaceClean一样可以吗？这个分类，苹果上面的定价都是怎么样的？

> 1和2哪个好？

> 可以

### A.5 命名

> kWatch

### A.6 Spec 阶段

> 可以（接受 Part 1 产品定位）

> 可以（接受 Part 2 功能规格）

> 这部分还不够，需要深入展开全面的设计，包括架构、设计模式、通讯方式、核心功能（这几项如何检测）、类图设计、数据层、以及还有完整全面的UX交互设计等

> 可以（接受扩展技术设计）

> 写好spec，再全面Review检查一遍

### A.7 审查与改进

> 我切换了kimi模型，使用kimi模型，全面审视下spec，提出优化改进建议

> 需要（同意合并改进）

### A.8 导出

> 把我这个session的所有会话，我的输入，保存为 kWatch产品交互设计

---

## 附录 B：关键设计原则（用户认可）

### B.1 平台集成优先

- 平台集成是 kWatch 的核心差异化
- Widget + Live Activity + Shortcuts + Spotlight 四个集成都要做

### B.2 Freemium 不阉割体验

- Free 用户 4 项基础指标 + 平台集成（已能满足日常）
- Pro 用户深度监控 + 历史 + 自定义

### B.3 Apple Silicon 兼容

- 不能因硬件差异让 80% 用户无法享受 Pro 功能
- 降级策略必须做（详见 4.5 + Plan B）

### B.4 不接 Lemon 任何代码

- 所有 Swift 代码全新编写
- 仅参考扫描算法、Daemon 架构思路

### B.5 仅 Mac App Store 分发

- 不做 DMG / 官网 / Notarized
- App Store 提交 + 苹果推荐

### B.6 零上报 / 零追踪

- 默认零分析、零上报
- 崩溃收集用 Apple MetricKit（本地）
- Privacy Policy 完备 + GDPR/CCPA 合规

---

**会话结束 — kWatch v1 设计定稿，待用户 review 后进入 writing-plans 阶段**