# kWatch v1.0 — P0 硬伤修复 Implementation Plan（精品化 Wave 1）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 修复 kWatch 达到 App Store 精品水准前的 4 处硬伤（SMC 温度/风扇 stub、GPU 数据链路断裂、假快捷开关、商业模型文案矛盾），补齐三语本地化，清理死代码 —— 让"监控深度"这一维度不再落后于 iStat Menus / Stats。

**Architecture:** SMC 层通过 IOKit AppleSMC user client 直接实现（纯 Swift、无第三方依赖），解码逻辑抽为纯函数以便单测；GPU 修复是消费端类型匹配修正；QuickToggleBar 重构为沙箱内真实可用的控制（暂停监控 + Wi-Fi 只读状态）；商业模型统一为一次性买断（Non-Consumable，StoreKit 购买流已是 NonConsumable，只改文案与测试配置）。

**Tech Stack:** Swift 5.9 / IOKit（AppleSMC user client）/ SwiftUI / StoreKit 2 / XCTest

**Spec:** `kWatch/V1-TODO.md`（P0 硬伤定义）+ `docs/gap-analysis/2026-08-04-kwatch-vs-top3.md`（竞品差距）+ 2026-09-05 会话勘察报告（本计划的事实依据）+ 用户已锁定决策：范围=P0、商业模型=一次性买断 $7.99、假开关=换成真实功能。

## Global Constraints

- macOS deployment target: **13.0**（高版本 API 用 `@available(macOS 14.0, *)` 包裹）
- Swift strict concurrency enabled（`SWIFT_STRICT_CONCURRENCY: complete`）
- **无第三方依赖**（SMC 用 IOKit 手写，不引 KeyboardShortcuts/MASShortcut 等）
- DesignSystem 规则：视图代码禁止裸 `Color`/`Font`/`padding` 字面量，必须走 `AppColors.*`/`AppSpacing.*` 等 token
- **禁止伪造数据**：任何传感器读不到时必须诚实返回 `.unsupported(reason:)`（这是现有代码的良好纪律，SMC 实现同样遵守）
- 本地化：所有用户可见文案走 `String(localized:)` + `Localizable.xcstrings`，en / zh-Hans / ja 三语
- 提交规范：`feat(kWatch):` / `fix(kWatch):` / `test(kWatch):` / `chore(kWatch):` / `refactor(kWatch):`；kFoundation 改动用 `scripts/commit-app.sh kWatch --allow-kfoundation`
- Bundle ID `app.kraftly.kwatch`；IAP 产品 ID `app.kraftly.kwatch.pro`（**Non-Consumable 买断**）
- 测试命令（每个任务至少跑一次）：
  - App: `cd kWatch && xcodebuild -project kWatch.xcodeproj -scheme kWatch -only-testing:kWatchTests test 2>&1 | tail -5`（基线 282 全绿）
  - kFoundation: `cd kFoundation && swift test 2>&1 | tail -5`

---

### Task 0: 提交遗留未提交工作（U5 测试更新 + E4 CI）

上次会话留下的两个未提交文件，先入库让基线干净。

**Files:**
- Modify: `kWatch/Tests/SettingsViewModelTests.swift`（已改好：6-tab → 10-tab 断言）
- Create: `.github/workflows/kwatch-ci.yml`（已写好：SwiftLint + 单测 CI）

- [ ] **Step 1: 确认测试仍全绿**

```bash
cd kWatch && xcodebuild -project kWatch.xcodeproj -scheme kWatch -only-testing:kWatchTests test 2>&1 | tail -5
```
Expected: `Executed 282 tests, with 0 failures`

- [ ] **Step 2: Commit**

```bash
scripts/commit-app.sh kWatch
git commit -m "test(kWatch): U5 followup — Settings tab assertions for 10-tab layout"
git add .github/workflows/kwatch-ci.yml
git commit -m "ci(kWatch): E4 — GitHub Actions lint + unit test pipeline"
```

---

### Task 1: GPU 数据链路修复（菜单栏 + 历史图 + paywall 路由 bug）

`GPUMonitor` 在 Apple Silicon 上产出 `.percentage`（VRAM 占用比），但 `MenuBarViewModel.consume()` 只读 `.degreesCelsius`，`HistoryViewModel.extractDouble` 同样只认 `(.gpu, .degreesCelsius)` → GPU 在菜单栏和历史图永远空白。另外 `kWatchApp.swift:49` 多图标模式的 `onOpenPaywall` 被错误路由到 `.history`。

**Files:**
- Modify: `kWatch/MenuBar/MenuBarViewModel.swift:25,103,136`
- Modify: `kWatch/History/HistoryViewModel.swift:230-231`
- Modify: `kWatch/App/kWatchApp.swift:49`
- Test: `kWatch/Tests/MenuBarViewModelTests.swift`、`kWatch/Tests/HistoryViewModelTests.swift`

**Interfaces:**
- Produces: `MenuBarViewModel.gpuUsagePercent: Double?`（替换 `gpuTemperature: Double?`）；`displayData(for: .gpu)` 返回 unit `"%"`。Task 5（popover 卡片化）依赖此属性名。

- [ ] **Step 1: 写失败测试（MenuBarViewModelTests）**

在 `kWatch/Tests/MenuBarViewModelTests.swift` 追加（沿用文件内已有的 snapshot 构造 helper；若无 helper 则内联构造 `MetricSnapshot`）：

```swift
func testGPUPercentageIsConsumedForMenuBar() async throws {
    let vm = MenuBarViewModel(container: makeContainer(isPro: true))
    let snapshot = MetricSnapshot(
        timestamp: Date(),
        values: [.gpu: .percentage(42.5)],
        availability: [.gpu: .available]
    )
    vm.consumeForTesting(snapshot)   // 若测试文件已有暴露 consume 的通道则复用
    XCTAssertEqual(vm.gpuUsagePercent, 42.5)
    let data = vm.displayData(for: .gpu)
    XCTAssertEqual(data.unit, "%")
}

func testGPUPercentageNilForFreeUsers() async throws {
    let vm = MenuBarViewModel(container: makeContainer(isPro: false))
    let snapshot = MetricSnapshot(
        timestamp: Date(),
        values: [.gpu: .percentage(42.5)],
        availability: [.gpu: .available]
    )
    vm.consumeForTesting(snapshot)
    XCTAssertNil(vm.gpuUsagePercent)
}
```

> 注意：若 `consume(snapshot:)` 是 private 且测试没通道，加一个 `internal func consumeForTesting(_ snapshot: MetricSnapshot)`（`#if DEBUG` 包裹），文件内已有同类先例就照抄先例的风格。

- [ ] **Step 2: 写失败测试（HistoryViewModelTests）**

```swift
func testExtractDoubleAcceptsGPUPercentage() {
    let value = extractDouble(from: .percentage(66.0), for: .gpu)
    XCTAssertEqual(value, 66.0)
}
```

- [ ] **Step 3: 运行确认失败**

```bash
cd kWatch && xcodebuild -project kWatch.xcodeproj -only-testing:kWatchTests/MenuBarViewModelTests -only-testing:kWatchTests/HistoryViewModelTests test 2>&1 | grep -E "error|failed" | head
```
Expected: 编译错误（`gpuUsagePercent` 不存在）→ 修正测试后 compile error 消失、断言 FAIL。

- [ ] **Step 4: 实现**

`kWatch/MenuBar/MenuBarViewModel.swift`：
1. 属性改名：`@Published public private(set) var gpuTemperature: Double? = nil` →
   `@Published public private(set) var gpuUsagePercent: Double? = nil`
2. `consume()` 中：
```swift
gpuUsagePercent = pro ? snapshot.values[.gpu]?.percentage : nil
```
3. `displayData(for:)` 中 `.gpu` 分支：
```swift
case .gpu: return ([], gpuUsagePercent ?? 0, "%")
```
4. 全局搜索 `gpuTemperature` 的其余引用（含 `MultiIconStatusItemController`、`MenuBarView`、测试），一并改为 `gpuUsagePercent`。

`kWatch/History/HistoryViewModel.swift:230-231`：

```swift
case (.temperature, .degreesCelsius(let degrees)),
     (.gpu, .percentage(let percentage)):
    return kind == .gpu ? percentage : degrees
```
（直接写成两个 case 更清晰：）

```swift
case (.temperature, .degreesCelsius(let degrees)):
    return degrees
case (.gpu, .percentage(let percentage)):
    return percentage
```

`kWatch/App/kWatchApp.swift:49`：多图标模式 paywall 路由修复 —— 打开 dashboard 窗口后导航到首页（paywall 由 dashboard 的 Pro 卡/锁触发，或镜像单图标模式第 180 行的 sheet 模式）：

```swift
onOpenPaywall: { AppWindowRouter.openDashboardWindow(); container.appState.navigate(to: .dashboard) }
```
> 实施时先确认 `NavigationItem` 是否有 `.dashboard` case；命名以实际 enum 为准（grep `enum NavigationItem`）。若已有 paywall 呈现通道（如 `AppWindowRouter.openPaywall`）则优先用它。

- [ ] **Step 5: 运行测试通过**

同 Step 3 命令，Expected: 全部 PASS；然后跑全量 `-only-testing:kWatchTests` 确认 282+ 仍全绿。

- [ ] **Step 6: Commit**

```bash
scripts/commit-app.sh kWatch
git commit -m "fix(kWatch): GPU percentage data link — menu bar row + history chart + multi-icon paywall routing"
```

---

### Task 2: 死代码清理 + Live Widgets 命名修正

勘察确认的死代码与过期命名：`MiniTrendChart.swift`（全库无引用）、`HistoryView.swift` 私有 loading/error/empty 三视图（已被 DesignSystem state modifier 取代）、`AppCoordinator` 的 `isStopping`（赋值后从不读取）与 `AlertTrend`（算出后丢弃）、`startLiveActivityIfPossible` 名不副实（Live Activity 已删除）、`ProIntroPage` 仍写 "Live Activity"。

**Files:**
- Delete: `kWatch/MenuBar/MiniTrendChart.swift`
- Modify: `kWatch/History/HistoryView.swift`（删 3 个私有 view）
- Modify: `kWatch/App/AppCoordinator.swift:17,28,47,106-141`
- Modify: `kWatch/Onboarding/ProIntroPage.swift`

- [ ] **Step 1: 删除死代码**

```bash
git rm kWatch/MenuBar/MiniTrendChart.swift
```

`HistoryView.swift`：删除 `loadingView` / `errorView` / `emptyView` 三个私有计算属性（先 grep 确认无其他引用；若有 `.loadingOverlay` 等 modifier 调用点保持不变）。

`AppCoordinator.swift`：
- 删除 `private var isStopping` 及其 3 处赋值（28、47 行附近）。
- 删除 `private enum AlertTrend` 及 120 行附近的 trend 计算（`_ = trend` 丢弃处）。
- `startLiveActivityIfPossible(for:value:at:)` 改名 `notifyLiveWidgets(for:value:at:)`，方法头 DocC 注释改为描述"告警触发时 reload WidgetKit timelines 使 Live Widgets 立即刷新"。

`ProIntroPage.swift`：`"Live Activity"` 文案 → `"Live Widgets"`（同时检查对应 localization key 的三语值在 Task 6 一并同步）。

- [ ] **Step 2: 构建 + 全量测试**

```bash
cd kWatch && xcodebuild -project kWatch.xcodeproj -scheme kWatch -only-testing:kWatchTests test 2>&1 | tail -5
```
Expected: BUILD SUCCEEDED，0 failures（AppCoordinator 的既有测试如有引用改名处需同步更新）。

- [ ] **Step 3: Commit**

```bash
scripts/commit-app.sh kWatch
git commit -m "refactor(kWatch): remove dead code (MiniTrendChart, legacy state views, isStopping/AlertTrend) + rename to notifyLiveWidgets"
```

---

### Task 3: QuickToggleBar 真实功能化

现状：Wi-Fi 用 `networksetup`（沙箱下 spawn 会失败，且写操作在 MAS 必拒），蓝牙/夜览/DND 是纯 NSLog 假开关 —— 审核风险 + 欺骗性 UI。**用户已拍板：换成真实功能。**

新设计（沙箱内 100% 真实可用）：
1. **暂停监控 toggle**（真）：控制 `MetricsAggregator` 采样循环。
2. **Wi-Fi 状态指示**（只读，非 toggle）：显示当前 Wi-Fi 硬件状态，点击跳系统设置 Wi-Fi 面板。
3. 删除蓝牙/夜览/DND 三个假开关及全部 stub 读写函数。

**Files:**
- Modify: `kFoundation/Sources/MetricsKit/MetricsAggregator.swift`（新增 pause）
- Modify: `kWatch/MenuBar/MenuBarViewModel.swift`（新增 pause 门面）
- Modify: `kWatch/MenuBar/QuickToggleBar.swift`（重写）
- Test: `kFoundation/Tests/MetricsKitTests/MetricsAggregatorTests.swift`（确认实际路径，`ls kFoundation/Tests`）、`kWatch/Tests/MenuBarViewModelTests.swift`、`kWatch/Tests/QuickToggleBarTests.swift`

**Interfaces:**
- Consumes: `MetricsAggregator`（actor，已有 `start()/stop()/stream()`）
- Produces:
  - `MetricsAggregator.setPaused(_ paused: Bool)` / `var isPaused: Bool`（暂停期间采样循环空转、不发 snapshot）
  - `MenuBarViewModel.isPaused: Bool`（@Published）、`func togglePause()`
  - `QuickToggleBar(viewModel: MenuBarViewModel, onOpenSystemSettings: (() -> Void)? = nil)`（闭包注入以便测试）

- [ ] **Step 1: 写失败测试（aggregator pause）**

在 MetricsKit 的 aggregator 测试文件追加：

```swift
func testPauseSkipsSampling() async throws {
    let monitor = CountingMonitor()   // 文件内已有 monitor stub；sample 计数
    let aggregator = MetricsAggregator(monitors: [monitor], clock: manualClock)
    await aggregator.setPaused(true)
    await aggregator.start()
    try await Task.sleep(for: .milliseconds(100))
    let countWhilePaused = await monitor.sampleCount
    XCTAssertEqual(countWhilePaused, 0)
    await aggregator.setPaused(false)
    try await Task.sleep(for: .milliseconds(200))
    let countAfterResume = await monitor.sampleCount
    XCTAssertGreaterThan(countAfterResume, 0)
    await aggregator.stop()
}
```
（`CountingMonitor`/`manualClock` 若测试文件已有等价 stub，用现有名字。）

- [ ] **Step 2: 写失败测试（MenuBarViewModel pause）**

```swift
func testTogglePauseFlipsStateAndAggregator() async throws {
    let vm = MenuBarViewModel(container: makeContainer(isPro: true))
    XCTAssertFalse(vm.isPaused)
    vm.togglePause()
    XCTAssertTrue(vm.isPaused)
    let paused = await makeContainer(isPro: true).aggregator.isPaused
    XCTAssertTrue(paused)
    vm.togglePause()
    XCTAssertFalse(vm.isPaused)
}
```

- [ ] **Step 3: 运行确认失败**

Expected: `setPaused`/`isPaused`/`togglePause` 编译错误。

- [ ] **Step 4: 实现 aggregator pause**

`MetricsAggregator.swift`：

```swift
/// When `true`, the sampling loop skips `sampleOnce()` (consumers keep
/// their last snapshot; no new samples are emitted).
public private(set) var isPaused = false

/// Pause or resume the sampling loop. Safe to call any state.
public func setPaused(_ paused: Bool) {
    isPaused = paused
}
```
采样循环改为：

```swift
task = Task { [weak self] in
    while !Task.isCancelled {
        if await self?.isPaused == false {
            await self?.sampleOnce()
        }
        try? await Task.sleep(for: interval)
    }
}
```

- [ ] **Step 5: 实现 MenuBarViewModel 门面**

```swift
@Published public private(set) var isPaused: Bool = false

/// Toggle monitoring on/off from the quick-toggle bar. Pausing stops the
/// aggregator from sampling (zero extra CPU/battery cost) without tearing
/// down consumer streams.
public func togglePause() {
    isPaused.toggle()
    let aggregator = container.aggregator
    let paused = isPaused
    Task { await aggregator.setPaused(paused) }
}
```

- [ ] **Step 6: 重写 QuickToggleBar**

```swift
import SwiftUI
import AppKit
import DesignSystem

/// A row of quick controls at the top of the menu-bar popover.
///
/// Everything here is genuinely functional inside the App Store sandbox:
/// - Pause monitoring: gates the `MetricsAggregator` sampling loop.
/// - Wi-Fi status: read-only indicator; tapping opens the system Wi-Fi
///   settings pane (writing network configuration is not sandbox-safe).
public struct QuickToggleBar: View {
    @ObservedObject public var viewModel: MenuBarViewModel
    var onOpenSystemSettings: (() -> Void)? = nil

    public init(viewModel: MenuBarViewModel, onOpenSystemSettings: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onOpenSystemSettings = onOpenSystemSettings
    }

    public var body: some View {
        HStack(spacing: 12) {
            Button {
                viewModel.togglePause()
            } label: {
                icon(
                    viewModel.isPaused ? "pause.circle.fill" : "play.circle.fill",
                    active: !viewModel.isPaused
                )
            }
            .buttonStyle(.plain)
            .help(String(localized: viewModel.isPaused ? "Resume monitoring" : "Pause monitoring"))

            Button {
                (onOpenSystemSettings ?? Self.openWiFiSettings)()
            } label: {
                icon("wifi", active: Self.readWiFiStatus())
            }
            .buttonStyle(.plain)
            .help(String(localized: "Wi-Fi status — click to open Network settings"))

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func icon(_ name: String, active: Bool) -> some View {
        Image(systemName: name)
            .foregroundStyle(active ? Color.brandPrimary : Color.textSecondary)
    }

    /// Read-only Wi-Fi hardware status via `networksetup -getairportpower`.
    /// Returns `false` silently when the command is unavailable (sandbox
    /// or VMs without en0) — this is a status *hint*, never a control.
    public static func readWiFiStatus() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = ["-getairportpower", "en0"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (String(data: data, encoding: .utf8) ?? "").contains("On")
        } catch {
            return false
        }
    }

    /// Deep-link into System Settings → Wi-Fi (public URL scheme).
    public static func openWiFiSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-duiextension") {
            NSWorkspace.shared.open(url)
        }
    }
}
```

调用点 `MenuBarView.swift:51` 改为 `QuickToggleBar(viewModel: viewModel)`；`MultiIconStatusItemController` 中若有 QuickToggleBar 实例化点同步（grep `QuickToggleBar(`）。

- [ ] **Step 7: 更新 QuickToggleBarTests**

删除针对 `readBluetooth/readNightShift/readDND/setBluetooth/setNightShift/setDND` 的用例；保留/改写 Wi-Fi 读取用例（不依赖真实网络环境的用例改为验证"命令失败时返回 false 而不抛出"，可直接调用 `readWiFiStatus()` 断言 Bool 类型即可）；新增 Button 行为用例（若现有测试是纯逻辑测试则验证 `viewModel.togglePause()` 与 bar 状态一致）。

- [ ] **Step 8: 全量测试通过 + Commit**

```bash
cd kWatch && xcodebuild -project kWatch.xcodeproj -scheme kWatch -only-testing:kWatchTests test 2>&1 | tail -5
cd ../kFoundation && swift test 2>&1 | tail -3
scripts/commit-app.sh kWatch --allow-kfoundation
git add kFoundation
git commit -m "feat(kWatch): real quick controls — pause monitoring toggle + read-only Wi-Fi status (sandbox-safe); drop fake Bluetooth/NightShift/DND toggles"
```

---

### Task 4: 商业模型统一为一次性买断 $7.99（Non-Consumable）

**事实核查结论（2026-09-05）**：StoreKit 购买流与 `StoreManager.productID = "app.kraftly.kwatch.pro"` 已指向 `.storekit` 配置里的 **NonConsumable** —— 购买实现本身正确。矛盾出在**文案**：`SubscriptionTerms` 的披露文案是自动续订模板（App Review §3.1.2(a) 对买断商品属错误陈述），而 Paywall/Onboarding 又写 one-time。本轮把文案统一为买断。

**Files:**
- Modify: `kWatch/Store/SubscriptionTerms.swift`
- Modify: `kWatch/Resources/Localizable.xcstrings`（`subscription.terms.*` 三语文案）
- Modify: `kWatch/Store/StoreKitTestConfiguration.storekit`（删除多余的 NonRenewingSubscription 条目）
- Test: `kWatch/Tests/SubscriptionTermsTests.swift`

- [ ] **Step 1: 写失败测试**

`SubscriptionTermsTests.swift` 中找到断言 body 包含 auto-renew 语义的用例（如 `testBodyDisclosesAutoRenewal` 或类似），改为：

```swift
func testBodyStatesOneTimePurchase() {
    let disclosure = SubscriptionTerms.disclosure(for: Locale(identifier: "en"))
    XCTAssertTrue(disclosure.body.contains("one-time"), "买断披露必须明示一次性付费")
    XCTAssertFalse(disclosure.body.lowercased().contains("auto-renew"), "买断商品不得出现自动续订陈述")
    XCTAssertFalse(disclosure.body.lowercased().contains("automatically renew"), "买断商品不得出现自动续订陈述")
}

func testURLsAreStable() { /* 保留现有用例不动 */ }
```

- [ ] **Step 2: 运行确认失败**（现有 copy 含 auto-renew → FAIL）

- [ ] **Step 3: 改文案**

`Localizable.xcstrings` 中 `subscription.terms.title` / `subscription.terms.body` / `subscription.terms.supportLink` 三个 key 的 en/zh-Hans/ja 值替换为（key 名暂不改——改 key 牵动面大，注释里说明语义即可）：

- en title: `kWatch Pro — One-Time Purchase`
- en body: `kWatch Pro is a one-time purchase of $7.99 (local pricing applies at checkout). Payment is charged once to your Apple ID. There is no subscription and no automatic renewal. Restore anytime on this Mac with "Restore Purchases". Terms: {supportLink}`
- zh-Hans title: `kWatch Pro — 一次买断`
- zh-Hans body: `kWatch Pro 为一次性买断（结算时按当地定价显示，约 ¥68）。费用通过您的 Apple ID 一次性支付，无订阅、无自动续费。可随时在本机通过"恢复购买"找回。条款：{supportLink}`
- ja title: `kWatch Pro — 買い切り`
- ja body: `kWatch Pro は買い切り（¥1,200・購入時に現地価格で表示）。Apple ID に一度だけ請求されます。サブスクリプションではなく自動更新もありません。「購入を復元」からいつでも復元できます。規約：{supportLink}`

（占位符 `{supportLink}` 若现有实现是拼接而非插值，按 PaywallView 实际拼法对齐；目标是正文含可点击支持链接。）

同时把 `SubscriptionTerms.swift` 头部 DocC 从 "auto-renewal disclosure" 改为 "one-time purchase disclosure"。

- [ ] **Step 4: 清理 .storekit 冗余**

`StoreKitTestConfiguration.storekit`：删除 `nonRenewingSubscriptions` 数组整体（含 `app.kraftly.kwatch.pro.subscription` 条目），`subscriptionGroups` 保持 `[]`。grep 全库确认无代码引用 `pro.subscription` 这个 ID。

- [ ] **Step 5: 测试通过 + Commit**

```bash
cd kWatch && xcodebuild -project kWatch.xcodeproj -only-testing:kWatchTests/SubscriptionTermsTests -only-testing:kWatchTests/PaywallViewModelTermsTests test 2>&1 | tail -3
scripts/commit-app.sh kWatch
git commit -m "fix(kWatch): unify business model copy — one-time $7.99 purchase disclosure (drop auto-renew claims) + prune .storekit"
```

---

### Task 5: SMC 温度/风扇真实现（含沙箱 spike 验证）

现状：`IOKitSMCReadingProvider` 硬编码 `isSupported=false` —— 温度/风扇在所有 Mac 上 Unavailable，是竞品差距第一名。本任务实现真实 AppleSMC user client 读取。

**风险与验收门（重要）**：App Sandbox 下 `IOServiceOpen("AppleSMC")` 能否成功**无法离线确认**。本任务以 spike 收尾：在沙箱开启的 Debug 构建真机运行验证。
- 若成功 → 完成 Task 5 全部内容。
- 若失败（`kIOReturnNotPermitted`）→ 保留诚实 unsupported 路径，在 `V1-TODO.md` 记录 spike 结论（含错误码），温度/风扇维持 Unavailable 文案，**禁止伪造**。此时本任务仍提交（真实实现 + 解码器测试 + 优雅降级），把"SMC 可用性"标注为待真机/App Review 验证的已知项。

**Files:**
- Create: `kFoundation/Sources/MetricsKit/Monitors/AppleSMCConnector.swift`
- Modify: `kFoundation/Sources/MetricsKit/Monitors/IOKitSMCReadingProvider.swift`（重写）
- Modify: `kFoundation/Sources/MetricsKit/Monitors/SMCAdapter.swift`（SMCKey 扩展 + 注释更新）
- Test: `kFoundation/Tests/MetricsKitTests/SMCValueDecoderTests.swift`（新建；目录以实际为准）

**Interfaces:**
- Consumes: `SMCReadingProvider` protocol（已有）、`SMCKey`（已有：TC0P/TG0P/F0Ac/VBAT）
- Produces:
  - `enum SMCValueDecoder { static func decode(type: String, data: [UInt8]) -> Double? }` — 纯函数，支持 `fpe2` / `sp78` / `flt ` / `ui8` / `ui16`
  - `protocol SMCConnecting { func open() -> Bool; func close(); func call(selector: UInt32, input: SMCParamStruct) -> SMCParamStruct? }`（`SMCParamStruct` 提为 internal 以便注入测试）
  - `IOKitSMCReadingProvider(connector: any SMCConnecting = AppleSMCConnector())` — 默认参数保持现有构造点兼容

- [ ] **Step 1: 写解码器测试（纯逻辑，先写）**

```swift
import XCTest
@testable import MetricsKit

final class SMCValueDecoderTests: XCTestCase {
    // sp78: signed 7.8 fixed-point, big-endian 2 bytes. 0x30 0x00 = 48.0°C
    func testDecodeSP78() {
        XCTAssertEqual(SMCValueDecoder.decode(type: "sp78", data: [0x30, 0x00]), 48.0)
        XCTAssertEqual(SMCValueDecoder.decode(type: "sp78", data: [0xFB, 0x00]), -20.0)
    }
    // fpe2: signed fixed-point with 2 fractional bits, big-endian 2 bytes. 0x0E 0x10 = 3600/4 = 900 RPM? 
    // 0x0E 0x10 = 3600 → 3600/4 = 900
    func testDecodeFPE2() {
        XCTAssertEqual(SMCValueDecoder.decode(type: "fpe2", data: [0x0E, 0x10]), 900.0)
        XCTAssertEqual(SMCValueDecoder.decode(type: "fpe2", data: [0xFF, 0xFC]), -1.0)
    }
    // flt : 32-bit IEEE754 little-endian
    func testDecodeFloat() {
        let f: Float = 55.5
        let bytes = withUnsafeBytes(of: f.bitPattern.littleEndian) { Array($0) }
        XCTAssertEqual(SMCValueDecoder.decode(type: "flt ", data: bytes), 55.5, accuracy: 0.001)
    }
    // ui8 / ui16
    func testDecodeUnsigned() {
        XCTAssertEqual(SMCValueDecoder.decode(type: "ui8", data: [0x64]), 100.0)
        XCTAssertEqual(SMCValueDecoder.decode(type: "ui16", data: [0x01, 0x90]), 400.0)
    }
    func testUnknownTypeReturnsNil() {
        XCTAssertNil(SMCValueDecoder.decode(type: "!!!!", data: [0, 0]))
        XCTAssertNil(SMCValueDecoder.decode(type: "sp78", data: []))
    }
}
```

- [ ] **Step 2: 运行确认失败**（`SMCValueDecoder` 不存在 → 编译错误）

```bash
cd kFoundation && swift test --filter SMCValueDecoderTests 2>&1 | tail -5
```

- [ ] **Step 3: 实现解码器（纯 Swift，放 IOKitSMCReadingProvider.swift 或独立文件）**

```swift
/// Decodes SMC sensor payloads into Doubles.
///
/// SMC keys carry a 4-char type tag. Supported tags cover every type
/// observed on Intel and Apple Silicon Macs for temperature, fan, and
/// voltage keys (per the public osx-cpu-temp / Stats implementations).
public enum SMCValueDecoder {
    public static func decode(type: String, data: [UInt8]) -> Double? {
        switch type {
        case "sp78", "sp87", "fp78", "fp87":
            // Signed fixed-point big-endian: 1 sign + 7 int bits, 8 (or 7) frac bits.
            guard data.count >= 2 else { return nil }
            let raw = Int16(UInt16(data[0]) << 8 | UInt16(data[1]))
            let fracBits: Double = type.hasSuffix("78") ? 256 : 128
            return Double(raw) / fracBits
        case "fpe2", "fp1f", "fp4c", "fp5a":
            guard data.count >= 2 else { return nil }
            let raw = Int16(UInt16(data[0]) << 8 | UInt16(data[1]))
            let divisor: Double = switch type {
            case "fpe2": 4
            case "fp1f": 2
            case "fp4c": 16
            default: 32   // fp5a
            }
            return Double(raw) / divisor
        case "flt ":
            guard data.count >= 4 else { return nil }
            let bits = UInt32(data[0]) | UInt32(data[1]) << 8 | UInt32(data[2]) << 16 | UInt32(data[3]) << 24
            return Double(Float(bitPattern: bits))
        case "ui8":
            guard data.count >= 1 else { return nil }
            return Double(data[0])
        case "ui16":
            guard data.count >= 2 else { return nil }
            return Double(UInt16(data[0]) << 8 | UInt16(data[1]))
        case "si8":
            guard data.count >= 1 else { return nil }
            return Double(Int8(bitPattern: data[0]))
        default:
            return nil
        }
    }
}
```

- [ ] **Step 4: 解码器测试通过**

```bash
cd kFoundation && swift test --filter SMCValueDecoderTests 2>&1 | tail -3
```
Expected: 5 tests passed.

- [ ] **Step 5: 写 provider 失败测试（注入 mock connector）**

```swift
final class IOKitSMCReadingProviderTests: XCTestCase {
    func testIsSupportedFalseWhenOpenFails() {
        let provider = IOKitSMCReadingProvider(connector: FailingConnector())
        XCTAssertFalse(provider.isSupported)
        XCTAssertThrowsError(try provider.read(key: .cpuTemperature))
    }
    func testReadsCPUTemperatureThroughConnector() throws {
        // sp78 payload 0x30 0x00 → 48.0; keyInfo dataType 'sp78', dataSize 2
        let connector = MockSMCConnector(
            keyInfo: KeyInfo(type: 0x73703738 /* 'sp78' */, size: 2),
            payload: [0x30, 0x00]
        )
        let provider = IOKitSMCReadingProvider(connector: connector)
        XCTAssertTrue(provider.isSupported)
        XCTAssertEqual(try provider.read(key: .cpuTemperature), 48.0, accuracy: 0.01)
    }
    func testKeyNotFoundSurfacesUnsupported() {
        let connector = MockSMCConnector(result: 0x84) // kSMCKeyNotFound
        let provider = IOKitSMCReadingProvider(connector: connector)
        XCTAssertThrowsError(try provider.read(key: .gpuTemperature))
    }
}
```

- [ ] **Step 6: 实现 connector + provider 重写**

`AppleSMCConnector.swift`（selector/结构体布局依据公开的 osx-cpu-temp 与 Stats 实现）：

```swift
#if canImport(Darwin)
import IOKit
import Darwin

/// Wire-level constants of the AppleSMC user client (public knowledge,
/// reproduced from osx-cpu-temp / exelban-stats — no Apple private SDK).
enum SMCUserClient {
    static let open: UInt32 = 0
    static let close: UInt32 = 1
    static let readKey: UInt32 = 5
    static let getKeyInfo: UInt32 = 9
    static let success: UInt8 = 0
    static let keyNotFound: UInt8 = 0x84
}

/// Mirrors the kernel's SMCParamStruct (63-byte wire layout via
/// MemoryLayout stride — same approach as the public Stats implementation).
public struct SMCParamStruct {
    public var key: UInt32 = 0
    public var vers: (UInt16, UInt16, UInt16, UInt16) = (0, 0, 0, 0)
    public var pLimitData: (UInt16, UInt16, UInt16, UInt16) = (0, 0, 0, 0)
    public var keyInfoDataSize: UInt8 = 0
    public var keyInfoDataAttributes: UInt8 = 0
    public var keyInfoType: UInt32 = 0
    public var pad0: (UInt8, UInt8, UInt8) = (0, 0, 0)
    public var result: UInt8 = 0
    public var status: UInt8 = 0
    public var dataSize: UInt8 = 0
    public var data = (
        UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
        UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
        UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
        UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0)
    )
    public init() {}
}

public protocol SMCConnecting: Sendable {
    func open() -> Bool
    func close()
    func call(selector: UInt32, input: SMCParamStruct) -> SMCParamStruct?
}

/// Real IOKit AppleSMC user-client connector.
public final class AppleSMCConnector: SMCConnecting, @unchecked Sendable {
    private var connect: io_connect_t = 0

    public init() {}

    public func open() -> Bool {
        var service = IOServiceGetMatchingService(kIOMasterPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        let kr = IOServiceOpen(service, mach_task_self_, 0, &connect)
        guard kr == KERN_SUCCESS else { return false }
        var scaler: UInt32 = 0
        return IOConnectCallScalarMethod(connect, SMCUserClient.open, nil, 0, &scaler, nil) == KERN_SUCCESS
    }

    public func close() {
        _ = IOConnectCallScalarMethod(connect, SMCUserClient.close, nil, 0, nil, nil)
        IOServiceClose(connect)
    }

    public func call(selector: UInt32, input: SMCParamStruct) -> SMCParamStruct? {
        var inputCopy = input
        var output = SMCParamStruct()
        let inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = inputSize
        let kr = withUnsafeMutableBytes(of: &inputCopy) { inBuf in
            IOConnectCallStructMethod(connect, selector, inBuf.baseAddress, inputSize, &output, &outputSize)
        }
        guard kr == KERN_SUCCESS, output.result == SMCUserClient.success else { return nil }
        return output
    }
}
#endif
```

> ⚠️ 字节偏移注意：`SMCParamStruct` 的内存布局必须与内核期望一致（key 4B + vers 8B + pLimitData 8B + keyInfo: data_size 1B + data_attributes 1B + data_type 4B + pad 3B + result 1B + status 1B + data_size 1B + data 32B）。实现后先用 spike 步骤（Step 8）在真机上读 `TC0P` 对比 Activity Monitor/Stats 的读数验证布局正确；若读数异常，改用 `[UInt8]` 手工偏移布局（0:key, 4:vers, 12:pLimit, 20:keyInfo.dataSize, 21:attributes, 22:type[4], 26:pad, 29:result, 30:status, 31:dataSize, 32..64:data — 以真机校准为准）。

`IOKitSMCReadingProvider.swift` 重写：

```swift
#if canImport(Darwin)
import Darwin
import Foundation

/// Darwin SMC reading provider backed by the real AppleSMC user client.
///
/// Availability is probed once at init via `SMCConnecting.open()`. When
/// the open fails (sandbox policy, VM, unsupported host) the provider
/// degrades to explicit `.unsupported` — values are never fabricated.
public final class IOKitSMCReadingProvider: SMCReadingProvider, @unchecked Sendable {
    private let connector: any SMCConnecting
    private let opened: Bool

    public init(connector: any SMCConnecting = AppleSMCConnector()) {
        self.connector = connector
        self.opened = connector.open()
    }

    public var isSupported: Bool { opened }

    public func read(key: SMCKey) throws -> Double {
        guard opened else {
            throw MetricError.unsupported("SMC is unavailable on this Mac")
        }
        let fourCC = key.rawValue.utf8   // exactly 4 bytes, e.g. "TC0P"
        precondition(fourCC.count == 4, "SMC keys must be 4 bytes")
        let keyInt = fourCC.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }

        // 1) Key info → type + size
        var info = SMCParamStruct()
        info.key = keyInt
        guard let infoReply = connector.call(selector: SMCUserClient.getKeyInfo, input: info) else {
            throw MetricError.systemCall("SMC getKeyInfo", -1)
        }
        let typeBytes: [UInt8] = withUnsafeBytes(of: infoReply.keyInfoType.bigEndian) { Array($0) }
        let typeName = String(bytes: typeBytes, encoding: .ascii) ?? "????"
        let size = Int(infoReply.keyInfoDataSize)

        // 2) Read payload
        var query = SMCParamStruct()
        query.key = keyInt
        guard let reply = connector.call(selector: SMCUserClient.readKey, input: query), reply.dataSize > 0 else {
            throw MetricError.systemCall("SMC readKey", -1)
        }
        let payload = withUnsafeBytes(of: reply.data) { Array($0.prefix(size)) }
        guard let value = SMCValueDecoder.decode(type: typeName, data: payload) else {
            throw MetricError.malformedData("SMC type \(typeName) undecodable for key \(key.rawValue)")
        }
        return value
    }
}
#endif
```

- [ ] **Step 7: provider 测试通过**

```bash
cd kFoundation && swift test --filter "SMC" 2>&1 | tail -3
```

- [ ] **Step 8: 真机 spike（沙箱开启的 Debug 构建）**

```bash
cd kWatch && xcodebuild -project kWatch.xcodeproj -scheme kWatch -configuration Debug build 2>&1 | tail -2
open /Users/torsys/Library/Developer/Xcode/DerivedData/kWatch-*/Build/Products/Debug/kWatch.app
```
在本机（Apple Silicon）菜单栏 popover 观察 Temperature / Fan 行：
- 显示数值 → 与系统观察（如终端 `powermetrics --samplers smc -n 1` 需 sudo，或对照 Stats 若安装）量级一致 → 记录 ✅
- 显示 Unavailable → 在 Xcode console 查 `MetricError` reason，区分 sandbox 拒绝 vs key 缺失，结论写入 `V1-TODO.md`

- [ ] **Step 9: 全量回归 + Commit**

```bash
cd kFoundation && swift test 2>&1 | tail -3
cd ../kWatch && xcodebuild -project kWatch.xcodeproj -scheme kWatch -only-testing:kWatchTests test 2>&1 | tail -5
scripts/commit-app.sh kWatch --allow-kfoundation
git add kFoundation
git commit -m "feat(metrics): real AppleSMC user client — temperature/fan readings with fpe2/sp78/flt/ui decoders + graceful sandbox fallback"
```

---

### Task 6: 三语本地化补齐（zh-Hans + ja：214 keys）

现状：`Localizable.xcstrings` en 214 / zh-Hans 7 / ja 7 —— 实际是纯英文应用（V1-TODO C13 未启动）。所有 key 已经用 `String(localized:)` 抽出，只差翻译。

**Files:**
- Modify: `kWatch/Resources/Localizable.xcstrings`

- [ ] **Step 1: 枚举未翻译 key 清单**

```bash
python3 - <<'EOF'
import json
d = json.load(open('kWatch/Resources/Localizable.xcstrings'))
missing = [k for k, v in d['strings'].items()
           if not (v.get('localizations') or {}).get('zh-Hans')]
print(len(missing))
for k in missing: print(k)
EOF
```
把清单存到临时文件供翻译时逐条处理。

- [ ] **Step 2: 批量翻译并写回**

术语表（保证一致性）：

| en | zh-Hans | ja |
|---|---|---|
| Menu Bar | 菜单栏 | メニューバー |
| Dashboard | 仪表盘 | ダッシュボード |
| History | 历史趋势 | 履歴 |
| Processes | 进程 | プロセス |
| Alerts | 告警 | アラート |
| Sampling interval | 采样间隔 | サンプリング間隔 |
| Temperature | 温度 | 温度 |
| Fan | 风扇 | ファン |
| Pro / kWatch Pro | Pro（保留） | Pro（保留） |
| Restore Purchases | 恢复购买 | 購入を復元 |
| Pause monitoring | 暂停监控 | モニタリングを一時停止 |

翻译规则：
- 单位与数字格式保留英文惯例（`GB`、`MB/s`、`°C`、`RPM` 不译）
- `%@`/`%lld`/String Interpolation 占位符**必须原样保留**（写回前用脚本校验每个译文的格式占位符集合与 en 相同）
- 日文用ですます体，中文用简体、界面级简洁风格
- Task 3/4/5 新增的 key（Pause monitoring / Wi-Fi status… / purchase.terms 等）包含在内

写回用脚本逐 key 注入 `localizations["zh-Hans"] = {"stringUnit": {"state": "translated", "value": …}}`（ja 同理），保持 JSON 格式与 Xcode 生成格式一致（2 空格缩进、key 排序与现状一致）。

- [ ] **Step 3: 校验占位符完整性**

```bash
python3 - <<'EOF'
import json, re
d = json.load(open('kWatch/Resources/Localizable.xcstrings'))
pat = re.compile(r'%(?:\d+\$)?[@dDuUfFeEgGxXoOaAcCsSp]|\\n|\{[^}]+\}')
bad = []
for k, v in d['strings'].items():
    locs = v.get('localizations') or {}
    en = pat.findall((locs.get('en') or {}).get('stringUnit', {}).get('value', ''))
    for loc in ('zh-Hans', 'ja'):
        t = pat.findall((locs.get(loc) or {}).get('stringUnit', {}).get('value', ''))
        if sorted(map(str, t)) != sorted(map(str, en)):
            bad.append((k, loc))
print('MISMATCH:', bad if bad else 'none')
EOF
```
Expected: `MISMATCH: none`

- [ ] **Step 4: 构建 + 全量测试**

（`MetricCardViewModelTests` 等已有 locale-robust 处理先例 0aeec21；若个别测试因翻译改变断言，按先例模式固定 locale。）

- [ ] **Step 5: Commit**

```bash
scripts/commit-app.sh kWatch
git commit -m "feat(kWatch): C13 — complete zh-Hans + ja localization (214 keys) with format-placeholder guard"
```

---

### Task 7: 收尾 — 文档同步 + 全量回归

**Files:**
- Modify: `kWatch/V1-TODO.md`
- Modify: `CLAUDE.md`（进度表）
- Modify: `kWatch/kWatchApp.swift` 中的 `onOpenPaywall`（若 Task 1 未覆盖全部 3 处路由 bug）

- [ ] **Step 1: V1-TODO.md 同步**

- 阶段 0：C1-C3/C5 标 ✅（已实现）；C4/C6/C7/C8 标注"App Store Connect/设计侧待办"
- K1-K5 已知问题段：标 ✅ 已修复（commit 4b625a5，282/282）
- 阶段 2：F5/F8/U5/V8/I8/E2 标 ✅；新增"P0 硬伤修复 wave"小节记录 Task 1-6 完成情况 + SMC spike 结论
- E4 CI 标 ✅

- [ ] **Step 2: CLAUDE.md 进度表**

在 §7 增加 kWatch v1.0 P0 hardening 条目（一行，注明日期与本计划文档路径）。

- [ ] **Step 3: 全量回归**

```bash
cd kFoundation && swift test 2>&1 | tail -3
cd ../kWatch && xcodebuild -project kWatch.xcodeproj -scheme kWatch test 2>&1 | tail -5
```
Expected: 全绿。

- [ ] **Step 4: Commit + push**

```bash
scripts/commit-app.sh kWatch
git commit -m "docs(kWatch): sync V1-TODO + CLAUDE.md after P0 hardening wave"
git push origin worktree-kwatch-v1
```

---

## 明确不在本 Wave 范围（P1 竞品差距，P0 落地后另出细案）

popover 卡片化+sparkline（F1 真落地）、右键菜单 G-U3、CSV/JSON 导出 G-E1、阈值色带 G-V3、每 metric 独立采样率 G-E2、全局快捷键 G-U2、App 图标 C7（设计侧）、App Store 截图 C8（设计侧）。

## Self-Review 结论

- Spec 覆盖：勘察报告 P0 四硬伤 → Task 1/3/4/5；本地化 → Task 6；死代码 → Task 2；基线入库 → Task 0 ✓
- 占位符：无 TBD；两处"以实际 enum/test helper 命名为准"是防写错既有符号的显式指令，非占位符 ✓
- 类型一致性：`gpuUsagePercent`（Task 1 定义，P1 消费）、`setPaused/isPaused/togglePause`（Task 3 内部一致）、`SMCValueDecoder.decode(type:data:)` 与 provider 调用一致 ✓
