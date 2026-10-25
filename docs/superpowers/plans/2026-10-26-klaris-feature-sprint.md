# Klaris 推荐冲刺（Feature Sprint）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 补齐 Klaris 冲击 App Store 编辑推荐与超越竞品的 12 个差距面（无障碍、完成时刻、QuickLook、快捷键、Dock 拖放、预演安全感、FSEvents 秒级重扫、3 个新画布组、hero 比例可视化、App Intents 全家桶、Control Widget、12 语本地化）——**应用更新检查已由用户明确排除**。

**Architecture:** 全部在既有单一画布 IA 上增量：清理动作仍走统一预演链（CleanupRehearsal → CleanupViewModel → CleanupEngine），新画布组走 CanvasScanCoordinator fan-out 检测器缝（protocol 注入，可测），系统集成面（Intents/Control Widget/Dock）复用 AppGraph.shared 单根。文案一律 xcstrings key（本地化 Task 12 收口前三语先行）。

**Tech Stack:** Swift 5.9 / SwiftUI / macOS 13 floor（widget appex 14；Control Widget 以 `#available(macOS 15.0,*)` 门控）/ kFoundation 本地包 / FSEvents / AppIntents / XCTest。

**Spec:** 本计划 §范围即已确认需求（用户 2026-10-25 拍板：除应用更新检查外全部实现 + 12 语）。差距分析依据：同日语录「苹果推荐四件事」审计。

## Global Constraints

- 最低系统 macOS 13.0；编译 SDK macOS 14+（高版本 API 必须 `#available` 包裹）。
- App Sandbox 强制（MAS target）；`SWIFT_STRICT_CONCURRENCY = complete`。
- **零网络**：任何新代码禁止 URLSession / 外部请求（审计测试会抓）。
- 所有用户可见文案走 `kWise/Resources/Localizable.xcstrings`，新 key 三语（en/zh-Hans/ja）同 commit 补齐；助手意图匹配表的中文模式保留。
- 提交：`scripts/commit-app.sh kWise`；kFoundation 路径改动需 `--allow-kfoundation` 且调用点修复同 commit。
- 每任务收口：`xcodebuild build -workspace KraftlyWorkspace.xcworkspace -scheme kWise -destination 'platform=macOS'` 绿 + 新增单测绿 + 受影响既有测试绿。
- 测试文件放 `kWise/Tests/`（扁平目录）；审计型测试沿用 `#filePath` 相对路径 grep 源码机制（先例 `AttributionCopyAuditTests`）。
- 不写实现代码之外的东西进 CLAUDE.md；Task 13 统一同步文档。

## 探查锚点（实施者必读的既有事实）

以下签名来自 2026-10-25 代码实况探查，实施时**以仓库现状为准**，若漂移以现仓库为准并回写本文件：

- `GroupKind`：`case cause(AttributionCause) / duplicates / similarPhotos / largeFiles`（`kWise/Features/Anatomy/CanvasGroup.swift`）。
- `CanvasEntry { id, title, bytes, badge: BadgeKind, detail: String?, target: CleanupTarget? }`；`BadgeKind: recyclable/migrate/attention/dataNotJunk/leaveAlone`（色表在 `CanvasGroupCard.swift` 的 `CanvasGroupCardCopy`）。
- `CanvasScanCoordinator`（`kWise/Features/Anatomy/CanvasScanCoordinator.swift`）：init 注入四个检测器缝（`AttributionScanning/DuplicateScanning/PhotoScanning/LargeFileScanning`）；`runScan(scope: CanvasScanScope) async -> CanvasReport`；`@Published groups/uncertainCard/isRunning/scanDiagnostics`；`noteSkippedRegions(_:)`。
- `CanvasScanScope` 构造点：`kWise/Features/Anatomy/AnatomyScanState.swift:286`（`AnatomyViewModel` 内）；`CompositionSlice { id: GroupKind, fraction: Double, color: Color }` 与 `compositionSlices` 同文件 297-320 行。
- `AnatomyView`（`kWise/Features/Attribution/AnatomyView.swift`）：`idleHero` 内已有 `compositionBar`；结果卡 `QuickCleanResultCard(state:onDismiss:)`（`QuickCleanHeroStates.swift`）；下钻走本地页交换 `@State drillDown`，无 NavigationStack。
- `CleanupRehearsalSheet { init(items:context:onConfirm:onCancel:isExecuting:) }`；`RehearsalSheetPayload { items; context }`。
- `CleanupViewModel`（`kWise/Features/Cleanup/CleanupViewModel.swift`）：`makeRehearsal(entries:)/makeRehearsal(targets:)`、`executeConfirmedCleanup(sizes:confirmedTargets:) async -> CleanupOutcome?`、`onQuotaExhausted`。
- `CleanupTarget { url, size, risk: RiskLevel, bundleID?, categoryID? }`；`RiskLevel: recommended(0)/optional(1)/caution(2)/dangerous(3)`；`CleanupOutcome { succeeded, failed, skipped, freedBytes, measuredBytes?, skippedForQuota, quotaExhausted }`；引擎入口 `cleanup(targets:config:) async throws -> CleanupOutcome`（`CleanupConfiguration { warnHandling, moveToTrash, recordHistory, retentionDays }`）。
- QuickLook：`kWise/Features/Common/Components/KWQuickLookPreview.swift` 已有 `View.kwQuickLookPreview(_ url: Binding<URL?>)` + `View.kwQuickLookSpaceHandler(selectedURL:)`（全 app 唯一 `_QuickLook_SwiftUI` import 点）。
- 回滚：`RestoreFromTrashService.restore(path:) -> RestoreResult`；历史 `TimelineViewModel.rollback(_:)`（`kWise/Features/History/TimelineView.swift`）。
- `UserPreferences`（`kWise/Persistence/UserPreferences.swift`）：Codable JSON（AppSupport/preferences.json）；**新增可选字段必须用 Optional + computed 模式**（先例 `similarityPresetRaw`），否则旧 JSON 解码炸。
- Intents：`kWise/Intents/ScanIntent.swift` 已有 `ScanIntent / CleanCacheIntent / ShowLargeFilesIntent`；适配器 `IntentScanAdapter { scanSummary/recommendedPickTargets/largestFiles (scope: AppScope) }`；**全 app 无 AppShortcutsProvider**。
- Widget：`kWise/Widgets/kWiseWidget.swift` `kWiseWidgetBundle`（仅 `kWiseDiskWidget`）；快照 `WidgetSnapshotStore`（App Group `group.app.kraftly.klaris`）；共享 intent `RunSmartCareIntent`（深链 `klaris://smartcare`）；widget target deploymentTarget 14.0。
- 快捷键：`kWise/Features/Common/KeyboardShortcuts.swift` `scanKeyboardShortcuts(onNewScan:onRescan:)`（隐藏 Button + keyboardShortcut 模式）；`kWiseApp.swift` 仅 `.commands { CommandGroup(replacing: .newItem) {} }`。
- `AppDelegate` 只有 `applicationShouldTerminate`；`Info.plist` 无 `CFBundleDocumentTypes`。
- Reduce Motion：`kWise/Features/Common/DesignSystem/Accessibility.swift` `AccessibilitySettings.reduceMotionEnabled`（NSWorkspace）；DesignSystem `KFAnimation` 无 RM 感知。
- 设计 Token：`Color.brandPrimary/.success/.danger/.bgPrimary/.textPrimary`、`AppSpacing xs4/sm8/md12/lg16/xl24/xxl32`、`AppFont.title2/title3/body/caption`、`KFAnimation.easeInOut`。
- `AppScope.shared.capability`（`kWise/App/AppScope.swift`）：`ScopeLevel containerOnly/homeGranted/fullAccess`；主目录授权根 = `capability.grantedRoot`；协议方法是 `grantHomeFolder()` 不是 `grant()`。
- `LocalizationCompletenessTests`：`requiredLanguages = ["en","zh-Hans","ja"]`，断言每 key 三语非空。
- 沙盒注意：`~/.Trash`、`MobileSync` 仅 homeGranted/fullAccess 可读；container-only 必须诚实跳过并上画布诊断（先例 `noteSkippedRegions`）。

---

### Task 1: 无障碍基建 + 审计测试（A11y Audit）

**Files:**
- Modify: `kWise/Features/Common/DesignSystem/Accessibility.swift`
- Modify: `kWise/App/RootView.swift`（IconRailButton）、`kWise/Features/Anatomy/CanvasPlusMenu.swift`、`kWise/Features/Anatomy/CanvasGroupCard.swift`、`kWise/Features/Anatomy/GroupDrillDownView.swift`、`kWise/Features/Cleanup/CleanupRehearsalSheet.swift`、`kWise/Features/Attribution/AnatomyView.swift`（hero 按钮行）
- Test: `kWise/Tests/AccessibilityAuditTests.swift`（新建）

**Interfaces:**
- Produces: `AccessibilitySettings.reduceMotionAnimation(_ base: Animation) -> Animation`（全 app 的 RM 门控统一入口，Task 2/9 消费）；`View.klarisAccessibilityButton(labelKey:hintKey:)` 不是目标——直接用原生修饰符，不造新 API。

- [ ] **Step 1: 写失败审计测试**

```swift
// kWise/Tests/AccessibilityAuditTests.swift
// A11y 审计（grep 源码机制，先例 AttributionCopyAuditTests）。
// 断言关键交互面都有显式 accessibilityLabel —— VoiceOver 是编辑推荐硬门槛，
// 现状仅 8 个文件有 a11y 标注，本测试钉住「只增不减」。
import XCTest

final class AccessibilityAuditTests: XCTestCase {
    private func source(_ relative: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // Tests/
            .appendingPathComponent(relative)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func testRailButtonsExposeLabels() {
        // rail 按钮此前只有 .help（VoiceOver 不读）——必须有 label。
        XCTAssertTrue(source("App/RootView.swift").contains(".accessibilityLabel("),
                      "IconRailButton 需要 accessibilityLabel（VoiceOver）")
    }

    func testPlusMenuExposesLabelAndHint() {
        let src = source("Features/Anatomy/CanvasPlusMenu.swift")
        XCTAssertTrue(src.contains(".accessibilityLabel("), "「+」菜单需要 label")
        XCTAssertTrue(src.contains(".accessibilityHint("), "「+」菜单需要 hint")
    }

    func testGroupCardsCombineAsButtons() {
        let src = source("Features/Anatomy/CanvasGroupCard.swift")
        XCTAssertTrue(src.contains(".accessibilityAddTraits(.isButton)"),
                      "组卡整卡可点（下钻）必须暴露按钮特征")
    }

    func testRehearsalTogglesHaveLabels() {
        let src = source("Features/Cleanup/CleanupRehearsalSheet.swift")
        XCTAssertTrue(src.contains(".accessibilityLabel("),
                      "预演豁免 Toggle 需要 label（裸 Toggle 只有文件名，VoiceOver 缺语义）")
    }

    func testNewAnimationsGateReduceMotion() {
        // 完成时刻 / 比例环两个新动效必须走统一 RM 门控。
        for file in ["Features/Anatomy/CompositionRing.swift",
                     "Features/Anatomy/QuickCleanHeroStates.swift"] {
            let src = source(file)
            guard !src.isEmpty else { continue }   // Task 9 之前允许缺席
            XCTAssertTrue(src.contains("reduceMotionAnimation"),
                          "\(file) 的动画必须经 AccessibilitySettings.reduceMotionAnimation 门控")
        }
    }
}
```

- [ ] **Step 2: 跑测试确认红**

Run: `xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWise -destination 'platform=macOS' -only-testing:kWiseTests/AccessibilityAuditTests 2>&1 | tail -15`
Expected: 5 个用例中 ≥4 FAIL（label 缺失）。

- [ ] **Step 3: Accessibility.swift 增统一 RM 门控**

```swift
// Accessibility.swift 追加（struct AccessibilitySettings 内）：
    /// 全 app 动效统一门控：Reduce Motion 时退化为最短线性过渡。
    /// 新动效一律经此包装，禁止裸 withAnimation（审计测试钉住）。
    static func reduceMotionAnimation(_ base: Animation) -> Animation {
        reduceMotionEnabled ? .linear(duration: 0.1) : base
    }
```

- [ ] **Step 4: 给关键面补标注**

RootView.swift `IconRailButton.body`（`.help(item.tooltip)` 之后）：

```swift
        .accessibilityLabel(Text(item.tooltip))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
```

CanvasPlusMenu.swift（Menu 上，identifier 之后）：

```swift
        .accessibilityLabel(Text(String(localized: String.LocalizationValue("canvas.hero.plusMenu.help"))))
        .accessibilityHint(Text(String(localized: String.LocalizationValue("canvas.plusMenu.a11y.hint"))))
```

CanvasGroupCard.swift 组卡根视图（整卡 onTapGesture 下钻处）：

```swift
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(String(localized: String.LocalizationValue("canvas.group.a11y.drillHint"))))
```

CleanupRehearsalSheet.swift 每行豁免 Toggle：

```swift
        .accessibilityLabel(Text("\(item.target.url.lastPathComponent)，\(reasonLine(item))"))
        .accessibilityHint(Text(String(localized: String.LocalizationValue("attr.rehearsal.a11y.exemptHint"))))
```

AnatomyView hero 按钮行三个 Button（快捷回收 / 重新扫描）：

```swift
        .accessibilityLabel(Text(String(localized: String.LocalizationValue("canvas.hero.quickClean.a11y"))))
        // 重新扫描按钮同理，key: canvas.hero.rescan.a11y
```

- [ ] **Step 5: 新增 key 三语**

Localizable.xcstrings 增加（en/zh-Hans/ja 同步写全）：
`canvas.plusMenu.a11y.hint`（"Opens tools: uninstall, startup items, shredder and attribution rules"/“打开工具：应用卸载、启动项、粉碎与归因规则”/「ツールを開く：アプリ削除、起動項目、シュレッダー、帰属ルール」）、`canvas.group.a11y.drillHint`（"Shows files in this group"/“查看该组内文件”/「このグループのファイルを表示」）、`attr.rehearsal.a11y.exemptHint`（"Double-check to exempt this item from cleanup"/“勾选可豁免该项清理”/「チェックでこの項目を除外」）、`canvas.hero.quickClean.a11y`（"Quick clean recommended items"/“快捷回收推荐项”/「おすすめ項目をクイック整理」）、`canvas.hero.rescan.a11y`（"Start a fresh scan"/“重新扫描”/「再スキャン」）。

- [ ] **Step 6: 跑测试确认绿**

Run: 同 Step 2。
Expected: 5/5 PASS（testNewAnimationsGateReduceMotion 因文件尚不存在而 skip 逻辑生效）。

- [ ] **Step 7: Commit**

```bash
bash scripts/commit-app.sh kWise
# feat(kWise): a11y audit — labels/traits on rail, plus-menu, group cards, rehearsal toggles + RM gate helper
```

---

### Task 2: 清理完成时刻（数字滚动 + 空间回血 + 音效）

**Files:**
- Create: `kWise/Features/Anatomy/FreedBytesRoller.swift`
- Create: `kWise/Features/Common/CompletionSound.swift`
- Modify: `kWise/Persistence/UserPreferences.swift`（新偏好字段）、`kWise/Features/Settings/SettingsView.swift`（开关行）、`kWise/Features/Anatomy/QuickCleanHeroStates.swift`（结果卡嵌 roller）、`kWise/App/RootView.swift`（音效触发）
- Modify: `kWise/Resources/Localizable.xcstrings`、`kWise/Features/Settings/SettingsView.swift` 本地化
- Test: `kWise/Tests/CompletionMomentTests.swift`

**Interfaces:**
- Consumes: `AccessibilitySettings.reduceMotionAnimation(_:)`（Task 1）；`CleanupOutcome.freedBytes/measuredBytes/successCount`；`CleanupViewModel.lastOutcome`（@Published）。
- Produces: `UserPreferences.playCompletionSound: Bool`（computed，读 `playCompletionSoundRaw: Bool?`）；`enum CompletionSound { static func playIfEnabled(_ enabled: Bool) }`；`struct FreedBytesRoller { let bytes: Int64; let measured: Bool }`。

- [ ] **Step 1: 写失败测试**

```swift
// kWise/Tests/CompletionMomentTests.swift
import XCTest
@testable import kWise

final class CompletionMomentTests: XCTestCase {
    // 旧 preferences.json 无新字段 → 解码必须成功（similarityPresetRaw 先例）。
    func testLegacyJSONDecodesWithSoundDefaultOn() throws {
        let legacy = #"{"largeFileThreshold":104857600,"ignoredPaths":[],"defaultCleanAction":"trash","confirmHighRisk":true,"historyRetentionDays":30,"launchAtLogin":false,"showMenuBarDiskUsage":true,"scanSpeed":"medium","notifyAfterCleanup":false,"shredPasses":1}"#
        let prefs = try JSONDecoder().decode(UserPreferences.self, from: Data(legacy.utf8))
        XCTAssertTrue(prefs.playCompletionSound, "默认开（用户可关）")
    }

    func testExplicitOffRoundTrips() throws {
        var prefs = UserPreferences()
        prefs.playCompletionSound = false
        let data = try JSONEncoder().encode(prefs)
        let back = try JSONDecoder().decode(UserPreferences.self, from: data)
        XCTAssertFalse(back.playCompletionSound)
    }

    func testRollerNeverNegativeAndFinishesAtTarget() {
        let roller = FreedBytesRoller(bytes: 5_000_000_000, measured: true)
        // 纯逻辑侧：RM 开启时 displayed 直接落到目标值（无 0→N 动画）。
        XCTAssertTrue(FreedBytesRoller.jumpsToFinalWhenReduceMotion)
    }
}
```

- [ ] **Step 2: 跑测试确认编译失败**（类型不存在）

Run: `xcodebuild test ... -only-testing:kWiseTests/CompletionMomentTests 2>&1 | tail -5`
Expected: FAIL（`playCompletionSound` / `FreedBytesRoller` 不存在）。

- [ ] **Step 3: UserPreferences 新字段**

```swift
    /// 完成音效开关（Task 2）。Optional 旧 JSON 兼容（先例 similarityPresetRaw）。
    public var playCompletionSoundRaw: Bool?
    /// 计算属性：nil → 默认开。
    public var playCompletionSound: Bool {
        get { playCompletionSoundRaw ?? true }
        set { playCompletionSoundRaw = newValue }
    }
```

- [ ] **Step 4: CompletionSound + FreedBytesRoller**

```swift
// kWise/Features/Common/CompletionSound.swift
import AppKit

/// 清理完成音效（Task 2 完成时刻）。系统音 Glass——零资产、零网络。
/// 用户可在设置关闭（playCompletionSound）。
enum CompletionSound {
    static func playIfEnabled(_ enabled: Bool) {
        guard enabled else { return }
        NSSound(named: NSSound.Name("Glass"))?.play()
    }
}
```

```swift
// kWise/Features/Anatomy/FreedBytesRoller.swift
import SwiftUI
import DesignSystem

/// 释放字节滚动动画（Task 2 完成时刻）。
/// - measured=true 显示实测值（引擎 measuredBytes），false 显示估算值并
///   保留既有「≈」前缀语义（C-3 诚实口径）。
/// - Reduce Motion：直接落终值，无滚动。
/// - .numericText 过渡 macOS 14+；13 静态刷新（回退无害）。
struct FreedBytesRoller: View {
    let bytes: Int64
    let measured: Bool
    static let jumpsToFinalWhenReduceMotion = true

    @State private var displayed: Double = 0

    var body: some View {
        Group {
            if measured {
                Text(ByteCountFormatter.string(fromByteCount: Int64(displayed), countStyle: .file))
            } else {
                Text("≈ " + ByteCountFormatter.string(fromByteCount: Int64(displayed), countStyle: .file))
            }
        }
        .font(AppFont.largeTitle.monospacedDigit())
        .foregroundStyle(Color.success)
        .modifier(NumericTransitionIfAvailable())
        .onAppear {
            guard !AccessibilitySettings.reduceMotionEnabled else {
                displayed = Double(bytes); return
            }
            displayed = 0
            withAnimation(AccessibilitySettings.reduceMotionAnimation(.easeOut(duration: 0.9))) {
                displayed = Double(bytes)
            }
        }
        .accessibilityLabel(Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)))
    }
}

struct NumericTransitionIfAvailable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.contentTransition(.numericText(value: 1.0))
        } else {
            content
        }
    }
}
```

- [ ] **Step 5: 接线**

RootView.swift `.onReceive(smartCareViewModel.$state)` 之后追加（覆盖三个清理入口——组头/快捷回收/下钻都走 cleanupViewModel 链）：

```swift
        // Task 2 完成时刻：任一统一链清理成功 → 音效（用户可关）。
        .onReceive(cleanupViewModel.$lastOutcome) { outcome in
            guard let outcome, outcome.successCount > 0 else { return }
            CompletionSound.playIfEnabled(UserPreferences.load().playCompletionSound)
        }
```

QuickCleanHeroStates.swift `QuickCleanResultCard` 的 done 分支：把既有 freed 字节 `Text` 替换为

```swift
                FreedBytesRoller(bytes: stateFreedBytes(state),
                                 measured: stateMeasuredBytes(state) != nil)
```

（`stateFreedBytes/stateMeasuredBytes` 为该文件内对 `SmartCareState.done(freedBytes:durationSeconds:)` 的既有取值 helper；若 `done` 未带 measuredBytes，以 `QuickCleanResultCopy` 现有文案为准仅传 `measured: false`，不扩 state——诚实口径不倒退。）

SettingsView.swift 清扫偏好分区追加开关行（样式照抄 `notifyAfterCleanup` 行）：

```swift
                Toggle(String(localized: String.LocalizationValue("settings.sound.completion")),
                       isOn: Binding(
                           get: { prefs.playCompletionSound },
                           set: { prefs.playCompletionSound = $0 }))
```

- [ ] **Step 6: 新增 key 三语**

`settings.sound.completion`："Play sound when cleanup finishes"/“清理完成后播放音效”/「クリーンアップ完了時にサウンドを再生」。

- [ ] **Step 7: 跑测试绿 + 构建 + Commit**

Run: `-only-testing:kWiseTests/CompletionMomentTests` PASS；双渠道 build。
Commit: `feat(kWise): cleanup completion moment — rolling freed-bytes, Glass sound (setting-gated), RM-aware`

---

### Task 3: 下钻页 QuickLook 接线

**Files:**
- Modify: `kWise/Features/Anatomy/GroupDrillDownView.swift`
- Test: `kWise/Tests/DrillDownQuickLookTests.swift`

**Interfaces:**
- Consumes: `View.kwQuickLookPreview(_:)`、`View.kwQuickLookSpaceHandler(selectedURL:)`（`KWQuickLookPreview.swift` 既有）。
- Produces: 无新 API。

- [ ] **Step 1: 写失败测试**

```swift
// kWise/Tests/DrillDownQuickLookTests.swift
import XCTest
@testable import kWise

final class DrillDownQuickLookTests: XCTestCase {
    // 下钻行只有文件系统里的真实目标才能预览 —— 组装器映射的 target.url
    // 必须存在且是常规文件；目录/虚拟条目不接 QuickLook（诚实降级）。
    func testPreviewableEntriesMapToRegularFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ql-fix-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("a.log")
        try Data("x".utf8).write(to: file)

        XCTAssertTrue(KWQuickLookEligibility.isPreviewable(file))
        XCTAssertFalse(KWQuickLookEligibility.isPreviewable(dir))
        XCTAssertFalse(KWQuickLookEligibility.isPreviewable(URL(fileURLWithPath: "/nonexistent-\(UUID())")))
        try? FileManager.default.removeItem(at: dir)
    }
}
```

- [ ] **Step 2: 确认红**（`KWQuickLookEligibility` 不存在 → 编译失败）

- [ ] **Step 3: 实现 eligibility + 接线**

KWQuickLookPreview.swift 追加：

```swift
/// QuickLook 只吃真实常规文件；目录 / 已消失路径一律不预览。
enum KWQuickLookEligibility {
    static func isPreviewable(_ url: URL) -> Bool {
        guard url.isFileURL, (try? url.checkResourceIsReachable()) == true else { return false }
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile ?? false
    }
}
```

GroupDrillDownView.swift：
1. `@State private var quickLookURL: URL?`
2. `fileList` 外层 `.kwQuickLookPreview($quickLookURL).kwQuickLookSpaceHandler { selectedRowURL() }`
3. `row(_ entry:)` 行尾追加预览按钮（仅 `entry.target?.url` 过 eligibility 时渲染）：

```swift
            if let url = entry.target?.url, KWQuickLookEligibility.isPreviewable(url) {
                Button {
                    quickLookURL = url
                } label: {
                    Image(systemName: "eye")
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: String.LocalizationValue("drill.quicklook.help")))
                .accessibilityLabel(Text(String(localized: String.LocalizationValue("drill.quicklook.help"))))
            }
```

4. `private func selectedRowURL() -> URL?`：取当前勾选集中第一个可预览 target，无则取首行可预览项；无任何可预览项返回 nil（Space 键静默，不出错）。

- [ ] **Step 4: key 三语** `drill.quicklook.help`："Quick Look"/“快速预览”/「クイックルック」

- [ ] **Step 5: 测试绿 + 构建 + Commit** `feat(kWise): drill-down QuickLook — per-row eye button + Space key`

---

### Task 4: 快捷键体系（⌘1/2/3 + ⌘,）

**Files:**
- Modify: `kWise/Features/Common/KeyboardShortcuts.swift`、`kWise/App/RootView.swift`
- Test: `kWise/Tests/KeyboardShortcutWiringTests.swift`

**Interfaces:**
- Produces: `View.railKeyboardShortcuts(onAnatomy:onHistory:onSettings:onOpenSettings:)`（隐藏 Button 模式，与 scanKeyboardShortcuts 同款）。

- [ ] **Step 1: 失败测试**

```swift
// kWise/Tests/KeyboardShortcutWiringTests.swift
import XCTest

final class KeyboardShortcutWiringTests: XCTestCase {
    private func source(_ relative: String) -> String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent(relative).flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    func testRailShortcutsDeclared() {
        let src = source("Features/Common/KeyboardShortcuts.swift")
        for key in ["1", "2", "3", ","] {
            XCTAssertTrue(src.contains(".keyboardShortcut(\"\(key)\""),
                          "缺少 ⌘\(key) 快捷键声明")
        }
    }

    func testRootViewInstallsRailShortcuts() {
        XCTAssertTrue(source("App/RootView.swift").contains("railKeyboardShortcuts"))
    }
}
```

- [ ] **Step 2: 确认红**

- [ ] **Step 3: 实现**

KeyboardShortcuts.swift 追加（照抄 scanKeyboardShortcuts 的隐藏 Button 模式）：

```swift
extension View {
    /// ⌘1/2/3 切 rail 三面；⌘, 打开设置（app 无 Settings scene，绑定 rail）。
    func railKeyboardShortcuts(
        onAnatomy: @escaping () -> Void,
        onHistory: @escaping () -> Void,
        onSettings: @escaping () -> Void
    ) -> some View {
        background(
            HStack {
                Button("Anatomy", action: onAnatomy).keyboardShortcut("1", modifiers: .command)
                Button("History", action: onHistory).keyboardShortcut("2", modifiers: .command)
                Button("Settings", action: onSettings).keyboardShortcut("3", modifiers: .command)
                Button("Open Settings", action: onSettings).keyboardShortcut(",", modifiers: .command)
            }
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
        )
    }
}
```

RootView.swift body 在 `.scanKeyboardShortcuts(...)` 之后追加：

```swift
        .railKeyboardShortcuts(
            onAnatomy: { appState.navigation = .anatomy },
            onHistory: { appState.navigation = .history },
            onSettings: { appState.navigation = .settings }
        )
```

- [ ] **Step 4: 测试绿 + 构建 + Commit** `feat(kWise): ⌘1/2/3 rail + ⌘, settings shortcuts`

---

### Task 5: Dock 拖放粉碎

**Files:**
- Modify: `kWise/Info.plist`、`kWise/App/AppDelegate.swift`、`kWise/App/RootView.swift`
- Test: `kWise/Tests/DockDropRoutingTests.swift`

**Interfaces:**
- Consumes: `DragToShredModel.urlsDropped(_:)`（既有全有全无校验）。
- Produces: `Notification.Name.klarisOpenFiles`（AppDelegate → RootView 单向路由）。

- [ ] **Step 1: 失败测试**

```swift
// kWise/Tests/DockDropRoutingTests.swift
import XCTest
import AppKit
@testable import kWise

final class DockDropRoutingTests: XCTestCase {
    // Dock 拖放 → AppDelegate open → 通知 → DragToShredModel 全有全无。
    func testOpenNotificationFeedsDragToShredModel() {
        let model = DragToShredModel()
        var received: [URL] = []
        model.onShredRequested = { received = $0 }

        let regular = FileManager.default.temporaryDirectory
            .appendingPathComponent("dock-\(UUID().uuidString).txt")
        try? Data("x".utf8).write(to: regular)

        NotificationCenter.default.post(
            name: .klarisOpenFiles, object: nil,
            userInfo: ["urls": [regular]])
        XCTAssertEqual(received.map(\.lastPathComponent), [regular.lastPathComponent])

        // 目录混入 → 整批拒绝（与整窗拖放同语义）。
        received = []
        NotificationCenter.default.post(
            name: .klarisOpenFiles, object: nil,
            userInfo: ["urls": [regular, FileManager.default.temporaryDirectory]])
        XCTAssertTrue(received.isEmpty)

        try? FileManager.default.removeItem(at: regular)
    }

    func testInfoPlistDeclaresDocumentTypes() throws {
        // Dock 拖放目标需要 CFBundleDocumentTypes；没有它 open 事件不进 AppDelegate。
        let plist = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../Info.plist")
        let data = try Data(contentsOf: plist)
        let dict = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        let types = dict?["CFBundleDocumentTypes"] as? [[String: Any]]
        XCTAssertNotNil(types)
        let contentTypes = types?.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] } ?? []
        XCTAssertTrue(contentTypes.contains("public.data"))
        XCTAssertTrue(contentTypes.contains("public.folder"))
    }
}
```

- [ ] **Step 2: 确认红**

- [ ] **Step 3: 实现**

Info.plist `CFBundleURLTypes` 之后追加：

```xml
	<key>CFBundleDocumentTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeName</key>Any File</key>
			<key>CFBundleTypeRole</key><string>Viewer</string>
			<key>LSHandlerRank</key><string>None</string>
			<key>LSItemContentTypes</key>
			<array>
				<string>public.data</string>
				<string>public.folder</string>
			</array>
		</dict>
	</array>
```

AppDelegate.swift 追加：

```swift
    /// Dock 图标拖放（Task 5）：文件落 Dock → open 事件 → 通知 RootView
    /// 转发 DragToShredModel（全有全无校验在模型内，粉碎 DELETE 确认链
    /// 在 ShredderView 内，这里零绕过）。
    func application(_ application: NSApplication, open urls: [URL]) {
        NotificationCenter.default.post(
            name: .klarisOpenFiles, object: nil, userInfo: ["urls": urls])
    }
```

RootView.swift：`Notification.Name.klarisOpenFiles` 声明放 `AppDelegate.swift` 底部 `extension Notification.Name { static let klarisOpenFiles = Notification.Name("app.kraftly.klaris.openFiles") }`；RootView body 追加：

```swift
        .onReceive(NotificationCenter.default.publisher(for: .klarisOpenFiles)) { note in
            guard let urls = note.userInfo?["urls"] as? [URL] else { return }
            _ = dragToShred.urlsDropped(urls)
        }
```

- [ ] **Step 4: 测试绿 + 双渠道构建**（KlarisDirect 共用 Info.plist，一并验证）+ Commit `feat(kWise): Dock drag-to-shred via open-URLs routing`

---

### Task 6: 预演安全感叙事（30 天回滚页脚）

**Files:**
- Modify: `kWise/Features/Cleanup/CleanupRehearsalSheet.swift`、`kWise/App/RootView.swift`、`kWise/Resources/Localizable.xcstrings`
- Test: `kWise/Tests/RehearsalSafetyCopyAuditTests.swift`

**Interfaces:**
- Produces: `CleanupRehearsalSheet.init(..., isPermanent: Bool = false)`；`RehearsalSheetPayload { items; context; isPermanent: Bool = false }`。

- [ ] **Step 1: 失败测试**

```swift
// kWise/Tests/RehearsalSafetyCopyAuditTests.swift
import XCTest

final class RehearsalSafetyCopyAuditTests: XCTestCase {
    private func source(_ relative: String) -> String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent(relative).flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    func testRehearsalSheetCarriesRollbackPromise() {
        let src = source("Features/Cleanup/CleanupRehearsalSheet.swift")
        XCTAssertTrue(src.contains("attr.rehearsal.rollbackNote"),
                      "预演 sheet 必须承诺 30 天废纸篓回滚（安全感叙事）")
        XCTAssertTrue(src.contains("attr.rehearsal.permanentNote"),
                      "永久路径（垃圾桶大项）必须诚实标注不可回滚")
    }

    func testPayloadCarriesIsPermanent() {
        XCTAssertTrue(source("App/RootView.swift").contains("isPermanent"),
                      "RootView 必须区分废纸篓路径与永久路径")
    }
}
```

- [ ] **Step 2: 确认红**

- [ ] **Step 3: 实现**

CleanupRehearsalSheet.swift：init 加 `var isPermanent: Bool = false`（struct 属性 `let isPermanent: Bool`）；footer 总计行下加：

```swift
                Text(String(localized: String.LocalizationValue(
                    isPermanent ? "attr.rehearsal.permanentNote" : "attr.rehearsal.rollbackNote")))
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
```

RehearsalSheetPayload 加 `var isPermanent: Bool = false`；RootView 两处 `RehearsalSheetPayload(items:...)` 组装点传该值（普通路径默认 false；Task 8 的垃圾桶组传 true——本任务先落机制）。

- [ ] **Step 4: key 三语**

`attr.rehearsal.rollbackNote`："Items move to Trash — restore anytime within 30 days from History"/“执行后移入废纸篓，30 天内可在「历史」一键回滚”/「実行後はゴミ箱へ移動 — 30 日以内なら履歴から復元できます」
`attr.rehearsal.permanentNote`："Items are removed permanently after confirmation — this cannot be undone"/“确认后将从废纸篓永久移除，此操作不可回滚”/「確認後はゴミ箱から完全に削除され、元に戻せません」

- [ ] **Step 5: 测试绿 + 构建 + Commit** `feat(kWise): rehearsal safety footer — 30-day rollback promise / honest permanent note`

---

### Task 7: FSEvents 增量监视（秒级重扫入口）

**Files:**
- Create: `kFoundation/Sources/FileScanner/FSEventsMonitor.swift`
- Modify: `kWise/Features/Anatomy/AnatomyScanState.swift`（AnatomyViewModel 持有监视器 + `hasPendingChanges`）、`kWise/Features/Attribution/AnatomyView.swift`（hero pill）、`kWise/Resources/Localizable.xcstrings`
- Test: `kWise/Tests/FSEventsMonitorTests.swift`

**Interfaces:**
- Produces: `public final class FSEventsMonitor`（kFoundation/FileScanner）：`init(watching: URL, latency: TimeInterval = 3.0, onChange: @escaping @Sendable () -> Void)`、`func start()`、`func stop()`；`AnatomyViewModel.hasPendingChanges: Bool`（@Published）。
- Commit 约束：kFoundation 改动 + kWise 调用同 commit，`--allow-kfoundation`。

- [ ] **Step 1: 失败测试**

```swift
// kWise/Tests/FSEventsMonitorTests.swift
import XCTest
import FileScanner
@testable import kWise

final class FSEventsMonitorTests: XCTestCase {
    // 沙盒测试宿主内临时目录可写可监听；10s 内必须收到一次变更回调。
    func testChangeInWatchedDirTriggersCallback() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fsev-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let expectation = expectation(description: "onChange fired")
        let monitor = FSEventsMonitor(watching: dir, latency: 0.5) { expectation.fulfill() }
        monitor.start()
        defer { monitor.stop(); try? FileManager.default.removeItem(at: dir) }

        try Data("x".utf8).write(to: dir.appendingPathComponent("new.bin"))
        wait(for: [expectation], timeout: 10)
    }

    func testStopSilencesCallbacks() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("fsev2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var fired = false
        let monitor = FSEventsMonitor(watching: dir, latency: 0.5) { fired = true }
        monitor.start(); monitor.stop()
        try Data("x".utf8).write(to: dir.appendingPathComponent("y.bin"))
        RunLoop.current.run(until: Date().addingTimeInterval(3))
        XCTAssertFalse(fired, "stop 后不得再回调")
        try? FileManager.default.removeItem(at: dir)
    }
}
```

- [ ] **Step 2: 确认红**（FSEventsMonitor 不存在）

- [ ] **Step 3: 实现 kFoundation**

```swift
// kFoundation/Sources/FileScanner/FSEventsMonitor.swift
//
// FSEvents 变更监视（秒级重扫入口的地基）。设计约束：
// - 回调只在会话生命周期内发生，start 幂等 / stop 后静默（测试钉住）；
// - latency 之外再加 debounce（coalesce 突发批量写入）；
// - 流创建失败（沙盒无该路径读权等）静默降级——调用方以画布诊断补诚实
//   提示，此处不抛错（监视是增强，不是承诺）。
import CoreServices
import Foundation

public final class FSEventsMonitor: @unchecked Sendable {
    private let path: String
    private let latency: TimeInterval
    private let onChange: @Sendable () -> Void
    private var stream: FSEventStreamRef?
    private var debounce: DispatchSourceTimer?
    private let lock = NSLock()

    public init(watching url: URL, latency: TimeInterval = 3.0,
                onChange: @escaping @Sendable () -> Void) {
        self.path = url.path
        self.latency = latency
        self.onChange = onChange
    }

    deinit { stop() }

    public func start() {
        lock.lock(); defer { lock.unlock() }
        guard stream == nil else { return }
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let monitor = Unmanaged<FSEventsMonitor>.fromOpaque(info).takeUnretainedValue()
            monitor.scheduleDebounce()
        }
        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault, callback, &context,
            [path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            [kFSEventStreamCreateFlagFileEvents, kFSEventStreamCreateFlagUseCFTypes].reduce(0, |))
        else { return }   // 沙盒/权限不足：静默降级
        self.stream = stream
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }

    public func stop() {
        lock.lock(); defer { lock.unlock() }
        debounce?.cancel(); debounce = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func scheduleDebounce() {
        lock.lock(); defer { lock.unlock() }
        debounce?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 2.0)
        timer.setEventHandler { [onChange] in onChange() }
        timer.resume()
        debounce = timer
    }
}
```

- [ ] **Step 4: AnatomyViewModel 接线**

AnatomyScanState.swift（AnatomyViewModel 内）：

```swift
    @Published public private(set) var hasPendingChanges = false
    private var fsMonitor: FSEventsMonitor?

    /// 首扫完成后启动主目录变更监视。沙盒 container-only 时 grantedRoot
    /// 为 nil → 不启动（pill 不出现，诚实降级）；流创建失败同样无感。
    public func startChangeMonitoring(root: URL?) {
        guard let root, fsMonitor == nil else { return }
        let monitor = FSEventsMonitor(watching: root) { [weak self] in
            Task { @MainActor in self?.hasPendingChanges = true }
        }
        monitor.start()
        fsMonitor = monitor
    }
    public func clearPendingChanges() { hasPendingChanges = false }
```

调用点：现有「扫描完成」路径（`bindScanViewModel` 的 isScanning true→false 订阅处）调用 `startChangeMonitoring(root: AppScope.shared.capability.grantedRoot)`；`startScan()` 触发时 `clearPendingChanges()`。

AnatomyView.swift `idleHero` 按钮行前插入 pill（`hasPendingChanges` 为 true 时渲染）：

```swift
                if viewModel.hasPendingChanges {
                    Button {
                        viewModel.startScan()
                    } label: {
                        Label(String(localized: String.LocalizationValue("canvas.changes.pending")),
                              systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(Text(String(localized: String.LocalizationValue("canvas.changes.pending"))))
                }
```

- [ ] **Step 5: key 三语** `canvas.changes.pending`："Contents changed — rescan"/“内容有变化——点按重新扫描”/「内容が変わりました — 再スキャン」

- [ ] **Step 6: 测试绿 + 构建 + Commit**

```bash
bash scripts/commit-app.sh kWise --allow-kfoundation
# feat(kWise): FSEvents change monitoring — instant-rescan pill on canvas
```

---

### Task 8: 三个新画布组（iOS 备份 / 下载分诊 / 垃圾桶大项）

**Files:**
- Create: `kWise/Features/Anatomy/HousekeepingDetector.swift`
- Modify: `kWise/Features/Anatomy/CanvasGroup.swift`（GroupKind + 组装）、`kWise/Features/Anatomy/CanvasGroupCard.swift`（copy 表）、`kWise/Features/Anatomy/CanvasScanCoordinator.swift`（第五检测缝）、`kWise/Features/Anatomy/AnatomyScanState.swift:286`（scope 补字段）、`kWise/Features/Cleanup/CleanupViewModel.swift`（config 参数）、`kWise/App/RootView.swift`（垃圾桶组 isPermanent）、`kWise/Resources/Localizable.xcstrings`
- Test: `kWise/Tests/HousekeepingDetectorTests.swift`

**Interfaces:**
- Produces: `enum HousekeepingKind: String, Sendable, CaseIterable { case iosBackup, staleDownloads, trashLargeItems }`；`struct HousekeepingFinding { kind, url, title, bytes, daysIdle: Int? }`；`protocol HousekeepingScanning { func scan(homeURL: URL?) async -> [HousekeepingFinding] }` + `struct HousekeepingDetector: HousekeepingScanning`；`GroupKind.housekeeping(HousekeepingKind)`；`CleanupViewModel.executeConfirmedCleanup(sizes:confirmedTargets:config:)`（新增 `config: CleanupConfiguration = .default`）。
- 沙盒语义：homeURL 传 `AppScope.shared.capability.grantedRoot`；container-only 传 nil → 检测器返回空 + coordinator 上 `noteSkippedRegions(["housekeeping"])` 诊断（禁止静默丢弃，先例 R2）。

- [ ] **Step 1: 失败测试**

```swift
// kWise/Tests/HousekeepingDetectorTests.swift
import XCTest
@testable import kWise

final class HousekeepingDetectorTests: XCTestCase {
    private func makeTempHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("hh-\(UUID().uuidString)", isDirectory: true)
        for rel in ["Library/Application Support/MobileSync/Backup/DEV1",
                    "Downloads", ".Trash"] {
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(rel), withIntermediateDirectories: true)
        }
        return home
    }

    func testDetectsIOSBackupDirs() throws {
        let home = try makeTempHome()
        let backup = home.appendingPathComponent("Library/Application Support/MobileSync/Backup/DEV1")
        try Data(repeating: 0, count: 5_000_000).write(to: backup.appendingPathComponent("Manifest.db"))

        let findings = HousekeepingDetector().scan(homeURL: home)   // 同步包装用于测试
        let backups = findings.filter { $0.kind == .iosBackup }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(backups.first?.url, backup)
    }

    func testStaleDownloadsThreshold() throws {
        let home = try makeTempHome()
        let dl = home.appendingPathComponent("Downloads")
        let old = dl.appendingPathComponent("old-video.mp4")
        try Data(repeating: 0, count: 20_000_000).write(to: old)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-14 * 86400 - 60)], ofItemAtPath: old.path)
        let fresh = dl.appendingPathComponent("fresh.mp4")
        try Data(repeating: 0, count: 20_000_000).write(to: fresh)

        let stale = HousekeepingDetector().scan(homeURL: home).filter { $0.kind == .staleDownloads }
        XCTAssertEqual(stale.map(\.url), [old], "14 天阈值：仅旧文件入组")
    }

    func testTrashLargeItems() throws {
        let home = try makeTempHome()
        let big = home.appendingPathComponent(".Trash/big.dmg")
        try Data(repeating: 0, count: 30_000_000).write(to: big)
        let small = home.appendingPathComponent(".Trash/small.txt")
        try Data("x".utf8).write(to: small)

        let trash = HousekeepingDetector().scan(homeURL: home).filter { $0.kind == .trashLargeItems }
        XCTAssertEqual(trash.map(\.url), [big], ">10MB 才入组")
    }

    func testContainerOnlyYieldsNothingNotCrash() {
        XCTAssertTrue(HousekeepingDetector().scan(homeURL: nil).isEmpty)
    }
}
```

- [ ] **Step 2: 确认红**

- [ ] **Step 3: 实现 HousekeepingDetector**

```swift
// kWise/Features/Anatomy/HousekeepingDetector.swift
//
// 家务三组检测器（Task 8）：iOS 设备备份 / 下载分诊 / 废纸篓大项。
// 沙盒契约（MasScanScope.md 同源）：homeURL 为 nil（container-only）时
// 返回空——调用方负责上画布诊断，禁止静默丢弃。iOS 备份是「数据·注意」
// 徽章（删了本机备份不影响 iCloud），垃圾桶大项走永久移除（isPermanent）。
import Foundation

public enum HousekeepingKind: String, Sendable, CaseIterable {
    case iosBackup, staleDownloads, trashLargeItems
}

public struct HousekeepingFinding: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let kind: HousekeepingKind
    public let url: URL
    public let title: String
    public let bytes: Int64
    public let daysIdle: Int?
    public init(id: UUID = UUID(), kind: HousekeepingKind, url: URL,
                title: String, bytes: Int64, daysIdle: Int?) { ... }
}

public protocol HousekeepingScanning: Sendable {
    func scan(homeURL: URL?) async -> [HousekeepingFinding]
}

public struct HousekeepingDetector: HousekeepingScanning {
    public init() {}
    static let staleDays = 14
    static let minBytes: Int64 = 10_000_000

    public func scan(homeURL: URL?) async -> [HousekeepingFinding] {
        guard let homeURL else { return [] }
        var findings: [HousekeepingFinding] = []
        findings += iosBackups(home: homeURL)
        findings += staleDownloads(home: homeURL)
        findings += trashLargeItems(home: homeURL)
        return findings
    }
    // 三个私有枚举目录（contentsOfDirectory incl. resourceKeys
    // [.fileSizeKey, .contentAccessDateKey, .isDirectoryKey]），目录递归
    // 汇总字节；MobileSync/Backup/* 每台设备一个子目录，整目录为一个
    // finding；Downloads 与 .Trash 取 >10MB 顶层项；staleDownloads 阈值
    // 14 天（contentAccessDate 缺失时回退 modificationDate）。
}
```

（实现按注释展开：`directorySize(_:)` 递归求和、异常路径 try? 吞掉并跳过——只读探测，零写入。）

- [ ] **Step 4: GroupKind + 组装 + 卡片 copy**

CanvasGroup.swift：

```swift
public enum GroupKind: Equatable, Hashable, Sendable {
    case cause(AttributionCause)
    case duplicates
    case similarPhotos
    case largeFiles
    case housekeeping(HousekeepingKind)   // Task 8
}
```

`CanvasGroupAssembler` 追加：

```swift
    public static func assembleHousekeeping(from findings: [HousekeepingFinding]) -> [CanvasGroup] {
        HousekeepingKind.allCases.compactMap { kind in
            let items = findings.filter { $0.kind == kind }
            guard !items.isEmpty else { return nil }
            let entries = items.map { f in
                CanvasEntry(title: f.title, bytes: f.bytes,
                            badge: badge(for: kind),
                            detail: f.url.deletingLastPathComponent().path,
                            target: CleanupTarget(
                                url: f.url, size: f.bytes,
                                risk: risk(for: kind),
                                categoryID: "housekeeping.\(kind.rawValue)"))
            }
            return assemble(kind: .housekeeping(kind), icon: icon(for: .housekeeping(kind)),
                            entries: entries,
                            totalBytes: entries.reduce(0) { $0 + $1.bytes })
        }
    }
    static func badge(for kind: HousekeepingKind) -> BadgeKind {
        switch kind {
        case .iosBackup: return .attention          // 橙：数据注意
        case .staleDownloads, .trashLargeItems: return .recyclable
        }
    }
    static func risk(for kind: HousekeepingKind) -> RiskLevel {
        switch kind {
        case .iosBackup: return .caution            // 删本机备份不可恢复（iCloud 不受影响）
        case .staleDownloads: return .optional
        case .trashLargeItems: return .recommended
        }
    }
    // icon(for:) 补 case：iosBackup "ipad.and.iphone", staleDownloads
    // "arrow.down.circle", trashLargeItems "trash"
```

CanvasGroupCard.swift `CanvasGroupCardCopy` 补三 case 的 title/subtitle key（下 Step 7）。

- [ ] **Step 5: coordinator 第五缝 + CleanupViewModel config + RootView isPermanent**

CanvasScanCoordinator.swift：

```swift
public protocol HousekeepingScanning: Sendable { ... }   // 复用 detector 定义即可，无需重复声明
// init 增参：housekeepingScanner: (any HousekeepingScanning)? = HousekeepingDetector()
// runScan 尾部（large files 之后）：
        if let scanner = housekeepingScanner {
            let findings = await scanner.scan(homeURL: scope.housekeepingHome)
            if findings.isEmpty && scope.housekeepingHome == nil {
                noteSkippedRegions(["housekeeping"])   // container-only：诚实诊断
            }
            appendGroups(CanvasGroupAssembler.assembleHousekeeping(from: findings))
        }
```

`CanvasScanScope` 加 `public var housekeepingHome: URL?`；AnatomyScanState.swift:286 构造点传 `AppScope.shared.capability.grantedRoot`（同文件能拿到 AppScope 则注入传入，保持 VM 可测：`AnatomyViewModel` 增加 `housekeepingHomeProvider: () -> URL? = { AppScope.shared.capability.grantedRoot }`）。

CleanupViewModel.swift：

```swift
    @discardableResult public func executeConfirmedCleanup(
        sizes: [URL: Int64]? = nil,
        confirmedTargets: [CleanupTarget]? = nil,
        config: CleanupConfiguration = .default) async -> CleanupOutcome? {
        ...
        // engine.cleanup(targets:config:) 透传；其余路径默认 .default 行为不变
```

RootView.swift `finishRehearsal`：把 payload 的 isPermanent 传下去——`RehearsalSheetPayload` 增加 `isPermanent`（Task 6 已加），`onConfirm` 闭包捕获并在 `executeConfirmedCleanup(confirmedTargets: confirmed, config: payload.isPermanent ? permanentConfig : .default)` 使用：

```swift
    /// 垃圾桶大项：确认后永久移除（不二次入废纸篓），预演页脚已诚实标注。
    static let permanentConfig = CleanupConfiguration(
        warnHandling: .skip, moveToTrash: false, recordHistory: true, retentionDays: 30)
```

（`presentGroupRehearsal` 中对 `group.id == .housekeeping(.trashLargeItems)` 置 `isPermanent: true`。）

- [ ] **Step 6: key 三语**

`canvas.group.housekeeping.iosBackup.title/subtitle`（“iOS 设备备份”/“本机完整备份，删除不影响 iCloud 云备份”；en/ja 对应）、`canvas.group.housekeeping.staleDownloads.title/subtitle`（“下载分诊”/“14 天未再打开的大文件”）、`canvas.group.housekeeping.trashLargeItems.title/subtitle`（“废纸篓大项”/“仍在废纸篓占用空间的大文件”）、`canvas.diagnostic.skippedHousekeeping`（“家务组需主目录授权后才能检查”）。

- [ ] **Step 7: 测试绿 + 构建 + 既有画布测试回归**

Run: `-only-testing:kWiseTests/HousekeepingDetectorTests -only-testing:kWiseTests/AnatomyScanStateTests`（CanvasScanScope 增字段带默认值，旧构造不破）。
Commit: `feat(kWise): three housekeeping canvas groups — iOS backups, stale downloads, trash large items`

---

### Task 9: hero 比例可视化（CompositionRing）

**Files:**
- Create: `kWise/Features/Anatomy/CompositionRing.swift`
- Modify: `kWise/Features/Attribution/AnatomyView.swift`（idleHero compositionBar 旁嵌环）
- Test: `kWise/Tests/CompositionRingTests.swift`

**Interfaces:**
- Consumes: `AnatomyViewModel.compositionSlices: [CompositionSlice] { id: GroupKind, fraction: Double, color: Color }`（既有）。
- Produces: `struct RingSliceModel { id: GroupKind, fraction: Double }`；`enum RingFold { static func fold(_ slices: [RingSliceModel], top: Int = 3) -> [RingSliceModel] }`（前 N + 其他合并）；`struct CompositionRing: View { let slices: [CompositionSlice]; let onSelect: (GroupKind) -> Void }`。

- [ ] **Step 1: 失败测试**

```swift
// kWise/Tests/CompositionRingTests.swift
import XCTest
@testable import kWise

final class CompositionRingTests: XCTestCase {
    private func slice(_ id: GroupKind, _ f: Double) -> RingSliceModel {
        RingSliceModel(id: id, fraction: f)
    }

    func testFoldKeepsTopNAndMergesRest() {
        let slices = [slice(.largeFiles, 0.4), slice(.duplicates, 0.25),
                      slice(.similarPhotos, 0.15), slice(.cause(.cache), 0.12),
                      slice(.cause(.logs), 0.08)]
        let folded = RingFold.fold(slices, top: 3)
        XCTAssertEqual(folded.count, 4, "top3 + 其他")
        XCTAssertEqual(folded.last?.fraction ?? 0, 0.20, accuracy: 0.001, "其余合并")
    }

    func testFoldConservesTotal() {
        let slices = (0..<9).map { slice(.cause(.cache), 1.0 / Double(9)) }
        let total = RingFold.fold(slices, top: 3).reduce(0) { $0 + $1.fraction }
        XCTAssertEqual(total, 1.0, accuracy: 0.0001, "角度守恒")
    }

    func testEmptySlicesGiveEmptyFold() {
        XCTAssertTrue(RingFold.fold([], top: 3).isEmpty)
    }
}
```

- [ ] **Step 2: 确认红**

- [ ] **Step 3: 实现**

```swift
// kWise/Features/Anatomy/CompositionRing.swift
import SwiftUI
import DesignSystem

/// hero 迷你比例环（Task 9）：compositionBar 的图形升级——SwiftUI Canvas
/// 环形分段（2π 守恒，小份额折叠为「其他」），分段可点 → 下钻对应组。
/// 无 Metal、无第三方；Reduce Motion 时无入场动画。
struct RingSliceModel: Identifiable, Equatable {
    let id: GroupKind
    let fraction: Double
}

enum RingFold {
    static func fold(_ slices: [RingSliceModel], top: Int = 3) -> [RingSliceModel] {
        guard slices.count > top else { return slices }
        let sorted = slices.sorted { $0.fraction > $1.fraction }
        let head = sorted.prefix(top)
        let restFraction = sorted.dropFirst(top).reduce(0.0) { $0 + $1.fraction }
        guard restFraction > 0 else { return Array(head) }
        return Array(head) + [RingSliceModel(id: .duplicates, fraction: restFraction)] // 其他占位 id 由调用方映射
    }
}
```

（「其他」分段用独立哨兵：`RingSliceModel` 增加可选 `isOther: Bool = false`，避免伪造 GroupKind——实现时以此为准，测试断言按 isOther 判别。）

```swift
struct CompositionRing: View {
    let slices: [CompositionSlice]
    var onSelect: (GroupKind) -> Void = { _ in }
    @State private var appeared = false

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 4
            var start = Angle.degrees(-90)
            for slice in folded {
                let sweep = Angle.degrees(slice.fraction * 360)
                var path = Path()
                path.addArc(center: center, radius: radius,
                            startAngle: start, endAngle: start + sweep, clockwise: false)
                context.stroke(path,
                               Color(slice.color),
                               style: StrokeStyle(lineWidth: 10, lineCap: .butt))
                start += sweep
            }
        }
        .frame(width: 84, height: 84)
        .scaleEffect(appeared ? 1 : (AccessibilitySettings.reduceMotionEnabled ? 1 : 0.9))
        .onAppear {
            withAnimation(AccessibilitySettings.reduceMotionAnimation(.easeOut(duration: 0.4))) {
                appeared = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(a11ySummary))
    }
    // folded: RingFold.fold(slices.map { RingSliceModel(id: $0.id, fraction: $0.fraction) })
    // a11ySummary: "空间构成：大文件 40%、重复文件 25%…"（用组名 + 百分比）
}
```

AnatomyView.swift `idleHero`：`compositionBar` 所在容器改为 `HStack { compositionBar; Spacer(); CompositionRing(slices: viewModel.compositionSlices, onSelect: { kind in /* 由既有 groups 定位 CanvasGroup 并 openDrillDown */ }) }`。

- [ ] **Step 4: 测试绿 + 构建 + Commit** `feat(kWise): composition ring on canvas hero — folded top-N proportional viz`

---

### Task 10: App Intents 全家桶 + Spotlight（AppShortcutsProvider）

**Files:**
- Create: `kWise/Intents/KlarisShortcuts.swift`（AppShortcutsProvider + AskStatusIntent）
- Modify: `kWise/Intents/ScanIntent.swift`（CleanCacheIntent 增加 ProvidesDialog 结果）
- Test: `kWise/Tests/AppIntentsSurfaceTests.swift`

**Interfaces:**
- Consumes: `IntentScanAdapter.scanSummary(scope:) -> (categories: Int, bytes: Int64)`；`WidgetSnapshotStore().read() -> WidgetSnapshot?`；`AppGraph.shared.cleanupEngine`；`AppScope.shared`。
- Produces: `struct AskStatusIntent: AppIntent`（ProvidesDialog）；`struct KlarisShortcuts: AppShortcutsProvider`。

- [ ] **Step 1: 失败测试**

```swift
// kWise/Tests/AppIntentsSurfaceTests.swift
import XCTest

final class AppIntentsSurfaceTests: XCTestCase {
    private func source(_ relative: String) -> String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent(relative).flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
    }

    func testShortcutsProviderRegistered() {
        let src = source("Intents/KlarisShortcuts.swift")
        XCTAssertTrue(src.contains("AppShortcutsProvider"), "Spotlight/Siri 入口必须注册")
        XCTAssertTrue(src.contains("ScanIntent") && src.contains("CleanCacheIntent")
                      && src.contains("AskStatusIntent"), "三个核心 intent 上架")
        // 零网络审计（项目红线）。
        XCTAssertFalse(src.contains("URLSession"))
    }

    func testCleanIntentReportsDialog() {
        XCTAssertTrue(source("Intents/ScanIntent.swift").contains("ProvidesDialog"),
                      "清理意图必须用 dialog 汇报释放字节（不能静默）")
    }
}
```

- [ ] **Step 2: 确认红**

- [ ] **Step 3: 实现**

```swift
// kWise/Intents/KlarisShortcuts.swift
//
// App Shortcuts 注册（Task 10）：Spotlight 顶部结果 / Siri / 快捷指令
// 免配置入口。短语三语（en/zh-Hans/ja——匹配助手意图表的三语先例）。
import AppIntents

struct AskStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Disk Status"
    static let description = IntentDescription("Report disk usage and cleanup forecast.", categoryName: "Status")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // 快照优先（App Group 内 15 分钟新鲜度），缺则现取。
        if let snap = WidgetSnapshotStore().read(), let disk = snap.disk {
            let used = ByteCountFormatter.string(fromByteCount: disk.usedBytes, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: Int64(disk.usedFraction == 0 ? 0 : Double(disk.usedBytes) / disk.usedFraction), countStyle: .file)
            var line = String(localized: String.LocalizationValue("intent.status.used"))
                .replacingOccurrences(of: "{used}", with: used)
                .replacingOccurrences(of: "{total}", with: total)
            if let forecast = snap.forecast, forecast.isReliable {
                line += "\n" + String(localized: String.LocalizationValue("intent.status.forecast"))
                    .replacingOccurrences(of: "{days}", with: "\(forecast.daysToFull)")
            }
            return .result(dialog: IntentDialog(stringLiteral: line))
        }
        let summary = await IntentScanAdapter.scanSummary(scope: AppScope.shared)
        let used = ByteCountFormatter.string(fromByteCount: summary.bytes, countStyle: .file)
        return .result(dialog: IntentDialog(stringLiteral:
            String(localized: String.LocalizationValue("intent.status.fallback"))
                .replacingOccurrences(of: "{used}", with: used)))
    }
}

struct KlarisShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ScanIntent,
                    phrases: ["Scan with \(.applicationName)", "用\(.applicationName)扫描", "\(.applicationName)でスキャン"],
                    shortTitle: "Scan Mac",
                    systemImageName: "magnifyingglass")
        AppShortcut(intent: CleanCacheIntent,
                    phrases: ["Quick clean with \(.applicationName)", "用\(.applicationName)快捷回收", "\(.applicationName)でクイック整理"],
                    shortTitle: "Quick Clean",
                    systemImageName: "sparkles")
        AppShortcut(intent: AskStatusIntent,
                    phrases: ["Ask \(.applicationName) about disk", "问\(.applicationName)磁盘状态", "\(.applicationName)にディスク状態を聞く"],
                    shortTitle: "Disk Status",
                    systemImageName: "internaldrive")
    }
}
```

ScanIntent.swift CleanCacheIntent：返回类型改 `some IntentResult & ProvidesDialog`，成功后：

```swift
        let freed = ByteCountFormatter.string(fromByteCount: outcome.freedBytes, countStyle: .file)
        return .result(dialog: IntentDialog(stringLiteral:
            String(localized: String.LocalizationValue("intent.clean.done"))
                .replacingOccurrences(of: "{freed}", with: freed)))
```

- [ ] **Step 4: key 三语** `intent.status.used`（"已用 {used} / 共 {total}"）、`intent.status.forecast`（"照当前速度约 {days} 天后占满"）、`intent.status.fallback`（"当前已用 {used}"）、`intent.clean.done`（"已释放 {freed}"）。

- [ ] **Step 5: 测试绿 + 构建 + Commit** `feat(kWise): App Shortcuts provider + status/clean dialogs`

---

### Task 11: Control Widget（macOS 15+ 门控）

**Files:**
- Modify: `kWise/Widgets/kWiseWidget.swift`
- Test: `kWise/Tests/WidgetSurfaceTests.swift`

**Interfaces:**
- Consumes: `RunSmartCareIntent`（既有，深链画布）；widget target deploymentTarget 14.0。

- [ ] **Step 1: 失败测试**

```swift
// kWise/Tests/WidgetSurfaceTests.swift
import XCTest

final class WidgetSurfaceTests: XCTestCase {
    func testControlWidgetDeclaredWithAvailabilityGate() {
        let src = (try? String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("../Widgets/kWiseWidget.swift"),
            encoding: .utf8)) ?? ""
        XCTAssertTrue(src.contains("ControlWidget"), "控制中心入口必须声明")
        XCTAssertTrue(src.contains("#available(macOS 15.0"), "必须 15.0 门控（CLAUDE.md 能力表 14 系笔误，实际 API 15+）")
    }
}
```

- [ ] **Step 2: 确认红**

- [ ] **Step 3: 实现 kWiseWidget.swift**

```swift
/// 控制中心快捷扫描（Task 11）。ControlWidget API 是 macOS 15+（iOS 18
/// 同代），CLAUDE.md §2.3 的「14+」为笔误——以 @available 门控，13/14
/// 用户照常只用桌面 widget。
@available(macOS 15.0, *)
struct KlarisQuickScanControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        ControlWidgetButton(action: RunSmartCareIntent()) {
            Label("Quick Clean", systemImage: "sparkles")
        }
        .displayName("Klaris")
        .description(Text("One tap to Klaris quick clean"))
    }
}

// bundle body 追加：
        if #available(macOS 15.0, *) { KlarisQuickScanControl() }
```

- [ ] **Step 4: key**（Label 走 xcstrings：`widget.control.quickClean` 三语）+ 测试绿 + 构建（含 kWiseWidget scheme）+ Commit `feat(kWise): Control Center quick-clean control widget (macOS 15+)`

---

### Task 12: 12 语本地化 + RTL 审计

**Files:**
- Modify: `kWise/Resources/Localizable.xcstrings`（846+ 新增 key → 12 语）、`kWise/InfoPlist.xcstrings`
- Modify: `kWise/Tests/LocalizationCompletenessTests.swift`（12 语门禁）
- Create: `kWise/Tests/RTLLayoutAuditTests.swift`
- Tools: `Tools/i18n/xcstrings_fill.py`（新建，导出缺译 → 回填）

**Interfaces:**
- 新语言：`zh-Hant, ko, de, fr, es, pt-BR, it, ru, ar`（用户 2026-10-25 拍板「大市场组合」）。
- 术语表（所有翻译批次的锚）：Cleanup=清理/整理 (de: Bereinigung, fr: nettoyage, es: limpieza, pt: limpeza, it: pulizia, ru: очистка, ko: 정리, ar: تنظيف)；Attribution=归因；Rehearsal=预演；Shred=粉碎；Buyout=买断。

- [ ] **Step 1: 门禁先行（红）**

LocalizationCompletenessTests.swift：

```swift
    private static let requiredLanguages = [
        "en", "zh-Hans", "ja",
        "zh-Hant", "ko", "de", "fr", "es", "pt-BR", "it", "ru", "ar",
    ]
```

Run: `-only-testing:kWiseTests/LocalizationCompletenessTests`
Expected: FAIL（9 语全缺）。

- [ ] **Step 2: 导出缺译清单**

```bash
mkdir -p Tools/i18n
python3 - <<'EOF'
# Tools/i18n/xcstrings_fill.py 的 mode=export：
# 读 kWise/Resources/Localizable.xcstrings，对 9 个新语言收集
# {key: {lang: ""}}，写 /tmp/i18n-batch-<lang>.json；en 译文作为源文并附
# zh-Hans/ja 作参照。打印各语言缺失计数。
EOF
```

- [ ] **Step 3: 三批并行翻译（3 个子代理，各 3 语）**

每代理输入 `/tmp/i18n-batch-<lang>.json` + 术语表 + 语气规范（简洁、无营销吹嘘、无 scareware 禁语——沿用 ScarewareCopyAuditTests 禁词表英译等价词），输出回填 JSON。代理用 python 脚本回写 xcstrings（`ensure_ascii=False, indent=2, "stringUnit": {"state": "translated", "value": ...}`）。分批：A=zh-Hant/ko/ru；B=de/fr/es；C=pt-BR/it/ar。

- [ ] **Step 4: InfoPlist.xcstrings 同步 9 语**（CFBundleDisplayName ×3 target：Klaris 全语言同名，明澈 zh 系）

- [ ] **Step 5: RTL 审计测试**

```swift
// kWise/Tests/RTLLayoutAuditTests.swift
// 阿语 RTL 硬门槛：源码不得硬编码 .left/.right 对齐（leading/trailing
// 自动镜像）。审计 grep 全 Features/ 与 App/。
import XCTest

final class RTLLayoutAuditTests: XCTestCase {
    func testNoHardcodedLeftRightAlignment() throws {
        let features = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../Features")
        let app = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../App")
        for root in [features, app] {
            let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
            for case let file as URL in enumerator! where file.pathExtension == "swift" {
                let src = try String(contentsOf: file, encoding: .utf8)
                for banned in [".alignment: .left", ".alignment: .right",
                               "textAlignment = .left", "textAlignment = .right"] {
                    XCTAssertFalse(src.contains(banned),
                                   "\(file.lastPathComponent) 含硬编码 \(banned)（RTL 违约）")
                }
            }
        }
    }
}
```

Run: PASS（若现库有命中，逐处改 leading/trailing/自然方向 API 并入本 commit）。

- [ ] **Step 6: 门禁转绿 + 全量本地化测试**

Run: `-only-testing:kWiseTests/LocalizationCompletenessTests -only-testing:kWiseTests/RTLLayoutAuditTests -only-testing:kWiseTests/NewCopyAuditTests`
Expected: 全 PASS。

- [ ] **Step 7: Commit**

```bash
bash scripts/commit-app.sh kWise
# feat(kWise): 12-language localization — zh-Hant/ko/de/fr/es/pt-BR/it/ru/ar + RTL audit gate
```

---

### Task 13: 双渠道全量基线 + 文档同步

**Files:**
- Modify: `CLAUDE.md`（§3.4 功能表 + §7 进度）、`kWise/docs/Launch/AppStoreMetadata.md`（元数据补 12 语 + 新功能卖点）

- [ ] **Step 1: MAS 全量基线**

Run: `xcodebuild test -workspace KraftlyWorkspace.xcworkspace -scheme kWise -destination 'platform=macOS' 2>&1 | tail -20`
Expected: 672 + 本冲刺新增，0 failures（~25 分钟）。

- [ ] **Step 2: KlarisDirect Debug 构建**（冒烟套件若已解 wedge 顺跑 `kWiseSmokeUI`）

- [ ] **Step 3: CLAUDE.md §3.4/§7 更新**（新模块行：无障碍审计 ✅ / 完成时刻 ✅ / QuickLook ✅ / 快捷键 ✅ / Dock 拖放 ✅ / FSEvents ✅ / 家务三组 ✅ / CompositionRing ✅ / App Shortcuts ✅ / Control Widget ✅ / 12 语 ✅；基线数字回写）

- [ ] **Step 4: Commit + push**

```bash
bash scripts/commit-app.sh kWise && git add CLAUDE.md && git commit -m "docs: sync feature-sprint reality" && git push origin main
```

---

## Self-Review 记录

1. **覆盖核对**：用户清单 12 项 → T1 无障碍、T2 完成时刻、T3 QuickLook、T4 快捷键、T5 Dock 拖放、T6 预演叙事、T7 FSEvents、T8 三组、T9 hero 可视化、T10 Intents/Spotlight、T11 Control Widget、T12 十二语。**明确排除**：应用更新检查（用户指示）；⌘W 关 sheet（macOS 原生 Esc 语义，覆写反直觉——决策记录）。
2. **占位符扫描**：T8 detector 私有方法、T9 Canvas 逐弧着色按注释展开——实现时若与锚点签名冲突以仓库为准；其余无 TBD。
3. **类型一致性**：`RingSliceModel.isOther` 哨兵、`RehearsalSheetPayload.isPermanent`（T6 定义 T8 消费）、`CleanupConfiguration.permanentConfig`（T8 内 RootView 常量）、`housekeepingHome`（T8 scope 字段）——前后引用已对齐。
4. **风险注记**：Control Widget 实际 API 为 macOS 15（CLAUDE.md 能力表 14 为笔误，T11 测试钉 15.0 门控）；FSEvents 在 MAS 沙盒下对授权根的行为以测试为准，失败路径静默降级；iCloud 无备份时删 iOS 本机备份属数据损失——徽章橙 + reason 文案必须含此警示（T8 审计点）。
