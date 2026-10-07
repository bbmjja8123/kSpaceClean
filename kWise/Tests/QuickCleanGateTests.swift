// kWise/Tests/QuickCleanGateTests.swift
//
// P2 T9 fix r1 — 快捷回收门控 + 结果态渲染的锁定测试（controller 裁定恢复）：
// - Critical 1：container-only 用户点快捷回收 → 授权卡呈现、管线不启动
//   （门控同时约束按钮渲染与 RootView / 菜单栏两处管线启动点）
// - Important 2：已授权 done 态渲染 freedBytes 行（C-3 真实字节）+
//   「移入废纸篓 · 30 天可还原」披露；failed 态渲染失败信息
// - 被 P2 T9 退役的 `scopeGrantCard` 强制测试以新形态恢复
//   （原 SmartCareDemotionCopyAuditTests.testScopeGrantCardSurvivesDemotion）
import XCTest
import SwiftUI
import AppKit
import PowerScope
@testable import kWise

@MainActor
final class QuickCleanGateTests: SnapshotTestCase {

    // MARK: - Critical 1：门控（纯逻辑）

    /// container-only：授权卡呈现，管线不允许启动 —— 扫描只能看到容器，
    /// 跑一次一无所获的管线属于对用户的浪费。
    func testContainerOnlyBlocksPipelineAndShowsGrantCard() {
        XCTAssertTrue(QuickCleanGate.showsGrantCard(.containerOnly),
                      "container-only 必须呈现授权卡（R1 裁定恢复）")
        XCTAssertFalse(QuickCleanGate.allowsPipeline(.containerOnly),
                       "container-only 不允许启动快捷回收管线")
    }

    /// 已授权（homeGranted）：快捷回收按钮正常渲染，管线放行。
    func testHomeGrantedAllowsPipelineAndHidesGrantCard() {
        XCTAssertTrue(QuickCleanGate.allowsPipeline(.homeGranted))
        XCTAssertFalse(QuickCleanGate.showsGrantCard(.homeGranted),
                       "已授权后授权卡必须让位给快捷回收按钮")
    }

    // MARK: - 接线审计（源码级，防门控被静默移除）

    private func source(_ relative: String) throws -> String {
        try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // kWise/
            .appendingPathComponent(relative), encoding: .utf8)
    }

    /// 两个管线启动点（hero 按钮 + 菜单栏 quickClean）都必须经过门控。
    func testBothPipelineEntryPointsAreGatedInRootView() throws {
        let root = try source("App/RootView.swift")
        let gateCalls = root.components(separatedBy:
            "QuickCleanGate.allowsPipeline").count - 1
        XCTAssertGreaterThanOrEqual(gateCalls, 2,
            "RootView 的 hero onQuickClean 与菜单栏 quickClean 都必须过门控")
    }

    /// 原强制测试的新形态（controller ruling R1）：hero 的授权卡必须存活
    /// ——container-only 的快捷回收要诚实降级，不得空跑也不得静默消失。
    func testGrantCardSurvivesInAnatomyHero() throws {
        let anatomy = try source("Features/Attribution/AnatomyView.swift")
        XCTAssertTrue(anatomy.contains("QuickCleanGate.showsGrantCard"),
                      "hero 必须按授权态决定快捷回收位的形态")
        XCTAssertTrue(anatomy.contains("QuickCleanGrantCard"),
                      "R1: 授权卡（grant 按钮 + 已授权反馈 + 暂不授权）必须保留")
        XCTAssertTrue(anatomy.contains("QuickCleanResultCard"),
                      "hero 必须渲染快捷回收结果态（fix r1 Important 2）")
        XCTAssertTrue(anatomy.contains(".task(id: smartCareViewModel.state)"),
                      "结果态必须有自动复位（数秒后回 idle）")
    }

    // MARK: - Important 2：结果态文案（纯函数）

    /// done 态标题行渲染真实释放字节（C-3）—— 与 SharedByteFormat 同口径。
    func testDoneTitleRendersFreedBytesRow() {
        let bytes: Int64 = 1_500_000_000
        let title = QuickCleanResultCopy.doneTitle(freedBytes: bytes)
        XCTAssertTrue(title.contains(SharedByteFormat.formatBytes(bytes)),
                      "标题必须内嵌真实字节格式化结果: \(title)")
        XCTAssertTrue(title.contains("已释放") || title.contains("Freed") || title.contains("解放"),
                      "标题必须是释放语义: \(title)")
        // 负数字节钳到 0 —— 绝不渲染负的已释放量（诚实零契约）。
        let negative = QuickCleanResultCopy.doneTitle(freedBytes: -5)
        XCTAssertFalse(negative.contains("-"),
                       "负的已释放量必须被钳到 0: \(negative)")
    }

    /// done 态披露行：移入废纸篓 + 30 天可还原（P1 诚实文案契约延续）。
    func testDoneDetailShipsHonestCopy() {
        let detail = QuickCleanResultCopy.doneDetail
        XCTAssertTrue(detail.contains("废纸篓") || detail.contains("Trash") || detail.contains("ゴミ箱"),
                      "披露行必须如实告知移入废纸篓: \(detail)")
        XCTAssertTrue(detail.contains("30 天") || detail.contains("30 days") || detail.contains("30 日"),
                      "披露行必须保留 30 天还原承诺: \(detail)")
    }

    // MARK: - 结构快照（视图可构造、可渲染）

    func testGrantCardRendersStructurally() {
        assertStructuralSnapshot(
            QuickCleanGrantCard(onGrant: {}, onSkip: {}),
            named: "quick-clean-grant-card",
            size: CGSize(width: 700, height: 120))
    }

    func testGrantDeclinedRowRendersStructurally() {
        assertStructuralSnapshot(
            QuickCleanGrantDeclinedRow(onGrant: {}),
            named: "quick-clean-grant-declined",
            size: CGSize(width: 700, height: 60))
    }

    func testDoneResultCardRendersStructurally() {
        assertStructuralSnapshot(
            QuickCleanResultCard(state: .done(freedBytes: 1_500_000_000,
                                              durationSeconds: 12),
                                 onDismiss: {}),
            named: "quick-clean-done",
            size: CGSize(width: 700, height: 120))
    }

    func testFailedResultCardRendersStructurally() {
        assertStructuralSnapshot(
            QuickCleanResultCard(state: .failed(message: "清理未能完成，请重试"),
                                 onDismiss: {}),
            named: "quick-clean-failed",
            size: CGSize(width: 700, height: 120))
    }

    /// 非结果态传入结果卡属调用方契约错误 —— isResultState 必须如实拒绝。
    func testIsResultStateRejectsNonResultStates() {
        XCTAssertFalse(QuickCleanResultCard.isResultState(.idle))
        XCTAssertFalse(QuickCleanResultCard.isResultState(.scanning(progress: 0.5)))
        XCTAssertFalse(QuickCleanResultCard.isResultState(.confirming(itemCount: 3, totalSize: 100)))
        XCTAssertTrue(QuickCleanResultCard.isResultState(.done(freedBytes: 1, durationSeconds: 1)))
        XCTAssertTrue(QuickCleanResultCard.isResultState(.failed(message: "x")))
    }
}
