import XCTest
@testable import kWise

@MainActor
final class SmartCareOrchestratorTests: XCTestCase {
    // MARK: - State

    func testInitialStateIsIdle() {
        let orch = SmartCareOrchestrator()
        XCTAssertEqual(orch.state, .idle)
        XCTAssertTrue(orch.recommendedItems.isEmpty)
    }

    func testStartWithoutScanVMTransitionsToFailed() {
        let orch = SmartCareOrchestrator()
        orch.start()
        if case .failed(let message) = orch.state {
            XCTAssertFalse(message.isEmpty)
        } else {
            XCTFail("expected .failed, got \(orch.state)")
        }
    }

    // MARK: - Pipeline

    func testStartWithEmptyScanVMSettlesAtConfirmingWithZeroPicks() async {
        let scanVM = ScanResultsViewModel(engine: nil)
        let orch = SmartCareOrchestrator(scanResultsViewModel: scanVM)
        orch.start()
        // Poll cadence is 100ms × 5 cycles + 0.5s FDA check ≈ <1s settle.
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        if case .confirming(let count, let total) = orch.state {
            XCTAssertEqual(count, 0)
            XCTAssertEqual(total, 0)
        } else {
            XCTFail("expected .confirming, got \(orch.state)")
        }
    }

    // MARK: - Execution (host-driven, P2 T5 R-统一)

    /// P2 T5：旧 `confirm()` 直执行路径已废除 —— `.confirming` 停在原地等
    /// 预演 sheet；状态推进由宿主经统一链跑完后回填。
    func testExecutionTransitionsAreHostDriven() async {
        let scanVM = ScanResultsViewModel(engine: nil)
        let orch = SmartCareOrchestrator(scanResultsViewModel: scanVM)
        orch.start()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard case .confirming = orch.state else {
            return XCTFail("expected .confirming, got \(orch.state)")
        }

        // orchestrator 自己不动手：确认态停留（无 .cleaning/.done 自迁移）。
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard case .confirming = orch.state else {
            return XCTFail("confirming must hold until host drives, got \(orch.state)")
        }

        orch.beginExecution()
        XCTAssertEqual(orch.state, .cleaning(progress: 0))
        orch.completeExecution(freedBytes: 128, durationSeconds: 0.4)
        if case .done(let freed, let duration) = orch.state {
            XCTAssertEqual(freed, 128)
            XCTAssertGreaterThanOrEqual(duration, 0)
        } else {
            XCTFail("expected .done, got \(orch.state)")
        }
    }

    func testFailExecutionSurfacesFailed() {
        let orch = SmartCareOrchestrator()
        orch.failExecution(message: "清理未能完成")
        if case .failed(let message) = orch.state {
            XCTAssertFalse(message.isEmpty)
        } else {
            XCTFail("expected .failed, got \(orch.state)")
        }
    }

    func testResetReturnsToIdle() async {
        let scanVM = ScanResultsViewModel(engine: nil)
        let orch = SmartCareOrchestrator(scanResultsViewModel: scanVM)
        orch.start()
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        orch.reset()
        XCTAssertEqual(orch.state, .idle)
        XCTAssertTrue(orch.recommendedItems.isEmpty)
    }

    func testAttachResetsStateAndRebinds() async {
        let orch = SmartCareOrchestrator()
        orch.start()
        // Orchestrator is now in .failed.
        let scanVM = ScanResultsViewModel(engine: nil)
        orch.attach(scanResultsViewModel: scanVM)
        XCTAssertEqual(orch.state, .idle)

        orch.start()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        if case .confirming = orch.state {
            // OK — Attach + Start round trip works
        } else {
            XCTFail("expected .confirming after attach + start, got \(orch.state)")
        }
    }
}