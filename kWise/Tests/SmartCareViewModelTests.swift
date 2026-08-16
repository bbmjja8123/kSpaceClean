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
        // Catch the busy window between .scanning and the pipeline
        // settling into .confirming.
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(vm.isBusy)

        // Wait past the 1.2s pipeline cap.
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        XCTAssertFalse(vm.isBusy)
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