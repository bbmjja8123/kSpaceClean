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

    // MARK: - Confirm / Reset

    func testConfirmTransitionsThroughCleaningToDone() async {
        let scanVM = ScanResultsViewModel(engine: nil)
        let orch = SmartCareOrchestrator(scanResultsViewModel: scanVM)
        orch.start()
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        orch.confirm()
        try? await Task.sleep(nanoseconds: 100_000_000)
        if case .cleaning = orch.state {
            // OK mid-flight
        } else {
            XCTFail("expected .cleaning immediately after confirm, got \(orch.state)")
        }

        // confirm()'s stub sleeps 1.5s before transitioning to .done.
        try? await Task.sleep(nanoseconds: 1_700_000_000)
        if case .done(let freed, _) = orch.state {
            XCTAssertEqual(freed, 0)
        } else {
            XCTFail("expected .done, got \(orch.state)")
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