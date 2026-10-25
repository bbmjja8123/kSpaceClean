// kWise/Tests/AccessibilityAuditTests.swift
//
// A11y 审计（grep 源码机制，先例 AttributionCopyAuditTests）。
// 断言关键交互面都有显式 accessibilityLabel —— VoiceOver 是编辑推荐硬门槛，
// 现状仅 8 个文件有 a11y 标注，本测试钉住「只增不减」。
import XCTest

final class AccessibilityAuditTests: XCTestCase {
    /// 源码根 = kWise/（#filePath 在 Tests/ 内，先例同款两级回退）。
    private func source(_ relative: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()          // Tests/
            .deletingLastPathComponent()          // kWise/
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
