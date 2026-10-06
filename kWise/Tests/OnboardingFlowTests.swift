// kWise/Tests/OnboardingFlowTests.swift
//
// P2 T8 — Onboarding 5→3 页收敛 + 首启自动扫描恰一次：
// - 页数与流程：欢迎 → 扫描三类承诺+主目录授权（合并页）→ 完成即扫；
// - `FirstScanGate`：UserDefaults flag 守卫，完成回调只触发一次 startScan。
//
// 授权/承诺文案与旧页退役的源码级审计在 `NewCopyAuditTests`（与本仓
// Documents 路径的已知测试宿主 wedge 同源，T6/T7 记录在案，等效脚本
// 校验随任务报告归档）。
import XCTest
@testable import kWise

@MainActor
final class OnboardingFlowTests: XCTestCase {

    // MARK: - 页数与导航（OnboardingCoordinator 3 页枚举）

    func testCoordinatorHasThreePages() {
        let coordinator = OnboardingCoordinator()
        XCTAssertEqual(coordinator.totalPages, 3, "5→3 页收敛：欢迎 / 承诺+授权 / 完成即扫")
        XCTAssertEqual(coordinator.currentPage, 0)
    }

    func testFlowIsWelcomeThenPromiseThenReadyToScan() {
        let coordinator = OnboardingCoordinator()
        var completed = false
        coordinator.onComplete = { completed = true }

        coordinator.next()
        coordinator.next()
        XCTAssertEqual(coordinator.currentPage, 2, "两次 next 落到最后一页（完成即扫）")
        XCTAssertFalse(completed, "完成回调只在最后一页的 next() 触发")

        coordinator.next()
        XCTAssertTrue(completed)
    }

    func testBackFromReadyToScanReturnsToPromisePage() {
        let coordinator = OnboardingCoordinator()
        coordinator.next()
        coordinator.next()
        coordinator.back()
        XCTAssertEqual(coordinator.currentPage, 1, "完成即扫页可回退到承诺+授权合并页")
    }

    // MARK: - 授权跳过（原 skipFDA）语义

    /// 跳过授权直达「完成即扫」页；授权入口/出口的源码级审计在
    /// `NewCopyAuditTests`（与禁语审计同一次文件读取；测试宿主对本仓
    /// Documents 路径的 `open()` 有已知环境 wedge —— T6/T7 记录在案）。
    func testSkippingGrantLandsOnReadyToScanPage() {
        let coordinator = OnboardingCoordinator()
        coordinator.skipGrant()
        XCTAssertEqual(coordinator.currentPage, coordinator.totalPages - 1)
    }

    // MARK: - 首启自动扫描恰一次（FirstScanGate）

    func testAutoScanGateFiresExactlyOnce() {
        let suite = "test.onboardingflow.autoscan.once"
        let defaults = freshDefaults(named: suite)
        defer { UserDefaults(suiteName: suite)?
            .removePersistentDomain(forName: suite) }

        XCTAssertTrue(FirstScanGate.shouldAutoScan(defaults: defaults),
                      "首次完成：触发自动扫描")
        XCTAssertFalse(FirstScanGate.shouldAutoScan(defaults: defaults),
                       "第二次：守卫拦住，不再触发")
        XCTAssertFalse(FirstScanGate.shouldAutoScan(defaults: defaults),
                       "第三次：仍不触发")
    }

    func testAutoScanGateRespectsPersistedFlag() {
        let suite = "test.onboardingflow.autoscan.persisted"
        let defaults = freshDefaults(named: suite)
        defer { UserDefaults(suiteName: suite)?
            .removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: FirstScanGate.flagKey)

        XCTAssertFalse(FirstScanGate.shouldAutoScan(defaults: defaults),
                       "flag 已置位（模拟二次启动）→ 不触发")
    }

    // MARK: - Helpers

    private func freshDefaults(named suite: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: suite)
        defaults?.removePersistentDomain(forName: suite)
        return defaults!
    }
}
