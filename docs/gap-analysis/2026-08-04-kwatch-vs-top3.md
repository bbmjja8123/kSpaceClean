# kWatch vs Top 3 菜单栏监控 App — 功能 Gap 分析

> **日期**: 2026-08-04
> **维度 A**: 功能（Features）
> **基线**: kWatch v1.0 当前实现（Stage 0+1 完成后）
> **竞品**: iStat Menus 7 / iPulse 3 / Stats 2.x
> **方法**: 每竞品 Top-50 特性盘点 × 5 维度（F/U/V/I/E）→ 交叉对比 → Gap 分级

---

## 1. 竞品能力总览

| 能力域 | iStat Menus 7 | iPulse 3 | Stats 2.x | kWatch v1 |
|---|---|---|---|---|
| **监控指标** | 7 类（CPU/GPU/Mem/Disk/Net/Sensor/Battery）+ Weather + TimeMachine | 6 类（CPU/GPU/Mem/Disk/Net/Battery）| 10 类（+Bluetooth+Sensor）| 7 类（基础）+ GPU(P2) |
| **进程级数据** | ✅ 每类 top-N 进程 | ❌ 仅 CPU 进程列表 | ✅ top-N 进程 | ✅ top-N 进程 |
| **历史趋势** | ✅ CSV/JSON 导出 + 自定义采样间隔 | ❌ 仅实时 | ❌ 仅实时 | ✅ 24h/7d/30d（Pro）|
| **告警规则** | ✅ 规则引擎 + 时间调度 + 滞回 | ❌ | ✅ 基础阈值告警 | ✅ 基础告警（Pro）|
| **WidgetKit** | ✅ 小/中/大 | ❌ | ✅ 小/中 | ✅ 小/中 + Interactive(14+) |
| **Live Activity** | ❌ | ❌ | ❌ | ✅（14+）|
| **Shortcuts** | ✅ 3 个 Intent | ❌ | ❌（社区 PR）| ✅ 8 个 Intent |
| **Spotlight** | ✅ Settings 可搜索 | ❌ | ❌ | ❌ |
| **AppleScript** | ✅ 完整字典 | ❌ | ❌ | ❌ |
| **URL Scheme** | ✅ | ❌ | ❌ | ❌ |
| **定价** | $11.99 买断 + $4.99/年 | $19.99 买断 | 免费 OSS | Freemium + $7.99 Pro |

---

## 2. Gap 矩阵（kWatch 缺失项 × 3 竞品覆盖）

### P0 — 3 款竞品都具备 / 上架阻塞

| ID | Gap 描述 | iStat | iPulse | Stats | kWatch 现状 | 优先级 |
|---|---|---|---|---|---|---|
| G-F1 | **GPU 监控**（usage + VRAM + temperature） | ✅ | ✅ | ✅ | ❌ 仅 P2 候选 | **P0** |
| G-F2 | **Bluetooth 设备电量**（耳机/键盘/鼠标） | ❌ | ❌ | ✅ | ❌ P3 | P1→考虑提升 |
| G-F3 | **Time Machine 状态**（最后备份时间 + 大小） | ✅ | ❌ | ❌ | ❌ | P2 |
| G-U1 | **Spotlight 索引**（搜"kWatch"出现操作） | ✅ | ❌ | ❌ | ❌ | P2 |
| G-U2 | **全局快捷键**（Cmd+Shift+X 显示/隐藏） | ✅ | ✅ | ✅ | ❌ | **P0** |
| G-U3 | **右键/Command-click 菜单**（每 metric） | ✅ | ✅ | ✅ | ❌ | **P0** |
| G-U4 | **配置导出/导入**（迁移设置到新 Mac） | ✅ | ✅（Jacket）| ❌ | ❌ | P1 |
| G-V1 | **6+ 内置主题**（Light/Dark/Black/Solarized 等） | ✅ | ✅（Jackets）| ✅（颜色）| ⚠️ 仅 3-5 图标风格 | P1 |
| G-V2 | **图表缩放/拖拽检查**（popover 内交互） | ✅ | ❌ | ❌ | ❌ | P1 |
| G-V3 | **颜色阈值带**（绿/橙/红 自动着色） | ✅ | ❌ | ✅ | ❌ | P1 |
| G-I1 | **AppleScript 字典** | ✅ | ❌ | ❌ | ❌ | P1 |
| G-I2 | **URL Scheme** | ✅ | ❌ | ❌ | ❌ | P2 |
| G-E1 | **CSV/JSON 历史导出** | ✅ | ❌ | ✅（export）| ❌ | **P0** |
| G-E2 | **采样间隔可配置**（1s-10s） | ✅ | ✅ | ✅ | ⚠️ 固定 | P1 |

### P1 — 1-2 款独有 + 高频使用

| ID | Gap 描述 | iStat | iPulse | Stats | kWatch 现状 |
|---|---|---|---|---|---|
| G-F4 | **Weather 预报**（菜单栏内嵌） | ✅ | ❌ | ❌ | ❌ |
| G-F5 | **Disk SMART 健康**（温度/坏块/寿命） | ✅ | ❌ | ✅ | ❌ P3 |
| G-U5 | **Drift 浮动窗口**（可拖拽独立面板） | ✅ | ✅（桌面）| ❌ | ❌ |
| G-U6 | **菜单栏分隔符**（分组 + 拖放重排） | ✅ | ❌ | ✅ | ⚠️ 基础重排 |
| G-V4 | **自定义图标集**（PNG/SVG 导入） | ✅ | ✅（Jacket）| ❌ | ❌ |
| G-V5 | **数字字体精细控制**（tabular figures） | ✅ | ❌ | ❌ | ❌ |
| G-E3 | **规则引擎**（if CPU>90% run script） | ✅ | ❌ | ❌ | ❌ |
| G-E4 | **告警时间调度**（仅工作日/工作时间） | ✅ | ❌ | ❌ | ❌ |

### P2 — 独有 + 低频 / 锦上添花

| ID | Gap 描述 | iStat | iPulse | Stats | kWatch 现状 |
|---|---|---|---|---|---|
| G-F6 | **多显示器菜单栏** | ✅ | ❌ | ❌ | ❌ |
| G-U7 | **Touch Bar 支持** | ✅ | ❌ | ❌ | ❌（Apple 已弃用）|
| G-I3 | **Finder Quick Look 扩展** | ✅ | ❌ | ❌ | ❌ |
| G-E5 | **CLI 命令行工具** | ❌ | ❌ | ✅（stats-cli）| ❌ |
| G-E6 | **HTTP API 模式**（本地端口暴露指标）| ❌ | ❌ | ✅ | ❌ |

---

## 3. kWatch 独有优势（竞品没有）

| 优势 | 说明 | 竞品状态 |
|---|---|---|
| **Live Activity** | macOS 14+ 锁屏/灵动岛显示实时指标 | 3 款均无 |
| **Interactive Widget** | macOS 14+ Widget 内按钮操作 | Stats 有 open issue，iStat/iPulse 无 |
| **8 个 Shortcuts** | 最完整的 Shortcuts 集成 | iStat 仅 3 个，其余无 |
| **免费 Tier** | 全 7 类实时数据免费 | iStat/iPulse 付费，Stats 免费但无 Pro |
| **Pro 趋势数据** | 24h/7d/30d 历史图表 | Stats/iPulse 无，iStat 需导出 |
| **自绘菜单栏图标** | 3-5 种风格 × 8 metric 独立选 | 竞品风格少或不可定制 |
| **顶部快捷开关** | Wi-Fi/蓝牙/夜览/DND 一键切换 | 3 款均无此功能 |

---

## 4. Gap 优先级排序（推荐实施路径）

### 阶段 2（v1.1）必须补齐

| 顺序 | Gap ID | 实施内容 | 预估工时 |
|---|---|---|---|
| 1 | G-F1 | GPU 监控（IOReport/Metal API） | 1 周 |
| 2 | G-U2 | 全局快捷键（10+ configurable） | 2 天 |
| 3 | G-U3 | 右键菜单（每 metric：Copy/Open/Alert） | 2 天 |
| 4 | G-E1 | CSV/JSON 历史导出 | 3 天 |
| 5 | G-V3 | 颜色阈值带（绿/橙/红自动着色） | 2 天 |
| 6 | G-E2 | 采样间隔可配置（1s-10s per module） | 1 天 |

### 阶段 3（v2）候选

| 顺序 | Gap ID | 实施内容 | 预估工时 |
|---|---|---|---|
| 7 | G-I1 | AppleScript 字典 | 1 周 |
| 8 | G-E3 | 规则引擎（简化版） | 1 周 |
| 9 | G-V1 | 6+ 内置主题 | 3 天 |
| 10 | G-U4 | 配置导出/导入 | 2 天 |
| 11 | G-V2 | 图表缩放/拖拽 | 3 天 |
| 12 | G-F5 | Disk SMART 健康 | 3 天 |

### 灵感池（未来候选，不一定做）

| ID | 概念 | 来源 | 说明 |
|---|---|---|---|
| G-F4 | Weather 预报嵌入 | iStat Menus F9 | 用 yr.no API，免费无需 key |
| G-U5 | Drift 浮动窗口 | iStat Menus U2 | 可拖拽独立面板，macOS 多窗口管理 |
| G-E5 | CLI 命令行 | Stats E5 | `kwatch-cli cpu` → 23% |
| G-E6 | HTTP API 模式 | Stats E6 | `localhost:9090/metrics` 暴露 JSON |
| G-I3 | Finder Quick Look | iStat Menus I7 | 右键快速查看磁盘健康 |

---

## 5. 竞品弱点（kWatch 可利用）

### iStat Menus 弱点
1. **无 Interactive Widget / Live Activity** — v7 Widget 全是静态
2. **无 Shortcuts 集成** — 仅 3 个基础 Intent
3. **规则引擎 UI 复杂** — 多篇评测称"powerful but intimidating"
4. **订阅疲劳** — 从买断转向订阅引发用户不满
5. **首次运行权限引导重** — Accessibility + Notifications + Automation 多步弹窗

### iPulse 弱点
1. **无 Widget / Shortcuts / Live Activity** — 纯菜单栏 + 桌面
2. **无历史数据** — 仅实时显示，无法回溯
3. **无告警/通知** — macOS 版无告警功能
4. **更新节奏极慢** — 9 年一个大版本
5. **无进程级网络/磁盘详情** — CPU 有进程列表，其他无

### Stats 弱点
1. **无 Interactive Widget** — GitHub open issue
2. **无 Shortcuts/Intents** — 社区 PR 未合并
3. **无 Live Activity** — 无计划
4. **无历史趋势** — 仅实时
5. **无告警规则** — 仅基础阈值通知
6. **免费无 Pro 层** — 缺乏商业化路径

---

## 6. 总结

**kWatch 当前定位**: 在 Shortcuts/Widget/Live Activity 集成上领先，但在基础监控深度（GPU/SMART/Weather）和用户自定义（主题/快捷键/规则引擎/导出）上落后。

**核心差距**:
- 功能广度: kWatch 覆盖 7/10 指标（缺 GPU/Bluetooth/SMART），竞品平均 8-9/10
- 用户自定义: kWatch 缺全局快捷键、右键菜单、配置导出、规则引擎
- 数据导出: kWatch 无 CSV/JSON 导出，iStat 和 Stats 都有
- 历史数据: kWatch 有趋势图（Pro），但无原始数据导出

**差异化护城河**:
- Live Activity + Interactive Widget = macOS 生态最深度集成
- 8 个 Shortcuts = 最完整的自动化入口
- 免费 Tier + Pro 趋势 = 最合理的 Freemium 模型
- 顶部快捷开关 = 独创功能，竞品均无
