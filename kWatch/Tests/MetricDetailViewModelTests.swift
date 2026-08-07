import XCTest
import MetricsKit
@testable import kWatch

@MainActor
final class MetricDetailViewModelTests: XCTestCase {
    private var historyRepo: InMemoryHistoryRepository!
    private var purchaseState: PurchaseState!

    override func setUp() {
        super.setUp()
        historyRepo = InMemoryHistoryRepository()
        purchaseState = PurchaseState()
    }

    // MARK: - Initial state

    func testInitialPointsAreEmpty() {
        let vm = MetricDetailViewModel(
            kind: .cpu,
            historyRepo: historyRepo,
            purchaseState: purchaseState
        )
        XCTAssertTrue(vm.points.isEmpty)
    }

    func testInitialStatsAreDash() {
        let vm = MetricDetailViewModel(
            kind: .cpu,
            historyRepo: historyRepo,
            purchaseState: purchaseState
        )
        XCTAssertEqual(vm.minDisplay, "--")
        XCTAssertEqual(vm.avgDisplay, "--")
        XCTAssertEqual(vm.maxDisplay, "--")
    }

    func testInitialProcessRowsAreEmpty() {
        let vm = MetricDetailViewModel(
            kind: .cpu,
            historyRepo: historyRepo,
            purchaseState: purchaseState
        )
        XCTAssertTrue(vm.processRows.isEmpty)
    }

    func testDefaultSelectedRangeIsH24() {
        let vm = MetricDetailViewModel(
            kind: .cpu,
            historyRepo: historyRepo,
            purchaseState: purchaseState
        )
        XCTAssertEqual(vm.selectedRange, .h24)
    }

    // MARK: - supportsProcesses

    func testSupportsProcessesForCPU() {
        let vm = MetricDetailViewModel(
            kind: .cpu,
            historyRepo: historyRepo,
            purchaseState: purchaseState
        )
        XCTAssertTrue(vm.supportsProcesses)
    }

    func testSupportsProcessesForMemory() {
        let vm = MetricDetailViewModel(
            kind: .memory,
            historyRepo: historyRepo,
            purchaseState: purchaseState
        )
        XCTAssertTrue(vm.supportsProcesses)
    }

    func testSupportsProcessesForNetwork() {
        let vm = MetricDetailViewModel(
            kind: .network,
            historyRepo: historyRepo,
            purchaseState: purchaseState
        )
        XCTAssertTrue(vm.supportsProcesses)
    }

    func testDoesNotSupportProcessesForTemperature() {
        let vm = MetricDetailViewModel(
            kind: .temperature,
            historyRepo: historyRepo,
            purchaseState: purchaseState
        )
        XCTAssertFalse(vm.supportsProcesses)
    }

    func testDoesNotSupportProcessesForDisk() {
        let vm = MetricDetailViewModel(
            kind: .disk,
            historyRepo: historyRepo,
            purchaseState: purchaseState
        )
        XCTAssertFalse(vm.supportsProcesses)
    }

    // MARK: - chartColor

    func testChartColorReturnsCorrectColor() {
        let vm = MetricDetailViewModel(
            kind: .cpu,
            historyRepo: historyRepo,
            purchaseState: purchaseState
        )
        XCTAssertEqual(vm.chartColor, .blue)
    }

    func testChartColorForMemory() {
        let vm = MetricDetailViewModel(
            kind: .memory,
            historyRepo: historyRepo,
            purchaseState: purchaseState
        )
        XCTAssertEqual(vm.chartColor, .green)
    }

    func testChartColorForTemperature() {
        let vm = MetricDetailViewModel(
            kind: .temperature,
            historyRepo: historyRepo,
            purchaseState: purchaseState
        )
        XCTAssertEqual(vm.chartColor, .red)
    }

    // MARK: - kindTitle

    func testKindTitleForCPU() {
        let vm = MetricDetailViewModel(
            kind: .cpu,
            historyRepo: historyRepo,
            purchaseState: purchaseState
        )
        XCTAssertEqual(vm.kindTitle, "CPU")
    }

    func testKindTitleForGPU() {
        let vm = MetricDetailViewModel(
            kind: .gpu,
            historyRepo: historyRepo,
            purchaseState: purchaseState
        )
        XCTAssertEqual(vm.kindTitle, "GPU")
    }

    // MARK: - Load gated by purchase state

    func testFreeUserDoesNotLoadData() async {
        let vm = MetricDetailViewModel(
            kind: .cpu,
            historyRepo: historyRepo,
            purchaseState: purchaseState
        )

        // Insert a snapshot into the history repo
        try! historyRepo.append(MetricSnapshot(
            timestamp: Date(),
            values: [.cpu: .percentage(75)],
            availability: [:]
        ))

        await vm.load()

        XCTAssertTrue(vm.points.isEmpty)
        XCTAssertEqual(vm.minDisplay, "--")
        XCTAssertTrue(vm.processRows.isEmpty)
    }

    func testProUserLoadsData() async {
        purchaseState.update(isPro: true)

        let now = Date()
        let snapshots = (0..<10).map { i in
            MetricSnapshot(
                timestamp: now.addingTimeInterval(Double(-i * 60)),
                values: [.cpu: .percentage(Double(20 + i * 5))],
                availability: [:]
            )
        }
        for snapshot in snapshots {
            try! historyRepo.append(snapshot)
        }

        let vm = MetricDetailViewModel(
            kind: .cpu,
            historyRepo: historyRepo,
            purchaseState: purchaseState
        )

        await vm.load()

        XCTAssertFalse(vm.points.isEmpty)
        XCTAssertNotEqual(vm.minDisplay, "--")
        XCTAssertNotEqual(vm.maxDisplay, "--")
        XCTAssertNotEqual(vm.avgDisplay, "--")
    }

    // MARK: - Range duration

    func testRangeDurations() {
        XCTAssertEqual(MetricDetailViewModel.Range.h24.duration, 24 * 60 * 60)
        XCTAssertEqual(MetricDetailViewModel.Range.d7.duration, 7 * 24 * 60 * 60)
        XCTAssertEqual(MetricDetailViewModel.Range.d30.duration, 30 * 24 * 60 * 60)
    }

    func testRangeDisplayNames() {
        XCTAssertEqual(MetricDetailViewModel.Range.h24.displayName, "24H")
        XCTAssertEqual(MetricDetailViewModel.Range.d7.displayName, "7D")
        XCTAssertEqual(MetricDetailViewModel.Range.d30.displayName, "30D")
    }

    func testRangeAllCases() {
        XCTAssertEqual(MetricDetailViewModel.Range.allCases.count, 3)
    }

    // MARK: - MetricKind Identifiable

    func testMetricKindIdentifiable() {
        XCTAssertEqual(MetricKind.cpu.id, "cpu")
        XCTAssertEqual(MetricKind.memory.id, "memory")
        XCTAssertEqual(MetricKind.disk.id, "disk")
        XCTAssertEqual(MetricKind.network.id, "network")
        XCTAssertEqual(MetricKind.temperature.id, "temperature")
        XCTAssertEqual(MetricKind.fan.id, "fan")
        XCTAssertEqual(MetricKind.battery.id, "battery")
        XCTAssertEqual(MetricKind.gpu.id, "gpu")
    }
}
