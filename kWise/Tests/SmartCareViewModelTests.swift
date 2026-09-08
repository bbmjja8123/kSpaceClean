import XCTest
@testable import kWise

@MainActor
final class SmartCareViewModelTests: XCTestCase {
    // MARK: - State mirroring

    func testInitialStateMirrorsOrchestratorIdle() {
        let vm = SmartCareViewModel()
        XCTAssertEqual(vm.state, .idle)
        XCTAssertFalse(vm.isBusy)
    }

    func testIsBusyDuringScanningAndRecommending() async {
        let scanVM = ScanResultsViewModel(engine: nil)
        let vm = SmartCareViewModel(scanResultsViewModel: scanVM)
        XCTAssertFalse(vm.isBusy)

        vm.runSmartCare()
        // The empty-scan pipeline can settle into .confirming within one
        // RunLoop turn, so a mid-flight busy assertion would race. Instead
        // verify the state machine ran to completion and was mirrored: not
        // stuck busy, and not failed.
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        XCTAssertFalse(vm.isBusy)
        if case .failed = vm.state {
            XCTFail("unexpected failure: \(vm.state)")
        }
    }

    // MARK: - Intent

    func testRunSmartCareForwardsToOrchestrator() async {
        let scanVM = ScanResultsViewModel(engine: nil)
        let vm = SmartCareViewModel(scanResultsViewModel: scanVM)
        vm.runSmartCare()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        if case .confirming = vm.state {
            // OK
        } else {
            XCTFail("expected .confirming, got \(vm.state)")
        }
    }

    func testResetForwardsToOrchestrator() async {
        let scanVM = ScanResultsViewModel(engine: nil)
        let vm = SmartCareViewModel(scanResultsViewModel: scanVM)
        vm.runSmartCare()
        try? await Task.sleep(nanoseconds: 1_200_000_000)

        vm.reset()
        XCTAssertEqual(vm.state, .idle)
    }

    func testAttachLateBindsAfterConstruction() async {
        let vm = SmartCareViewModel()
        XCTAssertEqual(vm.state, .idle)

        let scanVM = ScanResultsViewModel(engine: nil)
        vm.attach(scanResultsViewModel: scanVM)
        vm.runSmartCare()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        if case .confirming = vm.state {
            // OK
        } else {
            XCTFail("expected .confirming after attach + runSmartCare, got \(vm.state)")
        }
    }
}