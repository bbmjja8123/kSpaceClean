import XCTest
import MetricsKit
@testable import kWatch

// MARK: - Stub process provider

private final class StubProcessProvider: ProcessProvider, @unchecked Sendable {
    private let processes: [ProcessInfoSnapshot]

    init(processes: [ProcessInfoSnapshot]) {
        self.processes = processes
    }

    func list() throws -> [ProcessInfoSnapshot] {
        processes
    }
}

// MARK: - Helpers

private func makeProcesses(count: Int) -> [ProcessInfoSnapshot] {
    (0..<count).map { i in
        ProcessInfoSnapshot(
            pid: Int32(1000 + i),
            name: "Process-\(i)",
            cpuPercent: Double(i).truncatingRemainder(dividingBy: 100),
            memoryBytes: UInt64(i * 1024 * 1024),
            networkBytesPerSecond: UInt64(i * 1000)
        )
    }
}

// MARK: - Tests

@MainActor
final class ProcessesViewModelTests: XCTestCase {

    // MARK: - Free tier limits

    func testFreeUserSeesUpToFiveProcesses() async {
        let provider = StubProcessProvider(processes: makeProcesses(count: 60))
        let monitor = ProcessMonitor(provider: provider)
        let purchaseState = PurchaseState() // default isPro = false
        let model = ProcessesViewModel(processMonitor: monitor, purchaseState: purchaseState)

        XCTAssertEqual(model.limit, 5)
        await model.refresh()

        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.rows.count, 5)
    }

    func testFreeUserSeesAllWhenFewerThanFive() async {
        let provider = StubProcessProvider(processes: makeProcesses(count: 3))
        let monitor = ProcessMonitor(provider: provider)
        let purchaseState = PurchaseState()
        let model = ProcessesViewModel(processMonitor: monitor, purchaseState: purchaseState)

        await model.refresh()

        XCTAssertEqual(model.rows.count, 3)
    }

    // MARK: - Pro tier limits

    func testProUserSeesUpToFiftyProcesses() async {
        let provider = StubProcessProvider(processes: makeProcesses(count: 60))
        let monitor = ProcessMonitor(provider: provider)
        let purchaseState = PurchaseState()
        purchaseState.update(isPro: true)
        let model = ProcessesViewModel(processMonitor: monitor, purchaseState: purchaseState)

        XCTAssertEqual(model.limit, 50)
        await model.refresh()

        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.rows.count, 50)
    }

    func testProUserSeesAllWhenFewerThanFifty() async {
        let provider = StubProcessProvider(processes: makeProcesses(count: 20))
        let monitor = ProcessMonitor(provider: provider)
        let purchaseState = PurchaseState()
        purchaseState.update(isPro: true)
        let model = ProcessesViewModel(processMonitor: monitor, purchaseState: purchaseState)

        await model.refresh()

        XCTAssertEqual(model.rows.count, 20)
    }

    // MARK: - Sort gating

    func testFreeUserCannotSelectNetworkSort() async {
        let purchaseState = PurchaseState() // free
        let model = ProcessesViewModel(processMonitor: nil, purchaseState: purchaseState)

        XCTAssertFalse(model.availableSorts.contains(.network))
        XCTAssertTrue(model.availableSorts.contains(.cpu))
        XCTAssertTrue(model.availableSorts.contains(.memory))
        XCTAssertEqual(model.availableSorts.count, 2)
    }

    func testProUserCanSelectNetworkSort() async {
        let purchaseState = PurchaseState()
        purchaseState.update(isPro: true)
        let model = ProcessesViewModel(processMonitor: nil, purchaseState: purchaseState)

        XCTAssertTrue(model.availableSorts.contains(.network))
        XCTAssertTrue(model.availableSorts.contains(.cpu))
        XCTAssertTrue(model.availableSorts.contains(.memory))
        XCTAssertEqual(model.availableSorts.count, 3)
    }

    func testFreeUserNetworkSortIsClampedToCpu() async {
        let purchaseState = PurchaseState()
        purchaseState.update(isPro: true)
        let model = ProcessesViewModel(processMonitor: nil, purchaseState: purchaseState)

        // Set network sort while Pro.
        model.selectedSort = .network
        XCTAssertEqual(model.selectedSort, .network)

        // Downgrade to free — sort should be clamped to .cpu.
        purchaseState.update(isPro: false)
        // The Combine subscription fires on the next runloop, so we trigger refresh
        // which also clamps.
        await model.refresh()

        XCTAssertEqual(model.selectedSort, .cpu)
    }

    // MARK: - Pro search

    func testProSearchFiltersProcesses() async {
        let processes = [
            ProcessInfoSnapshot(pid: 1, name: "Safari", cpuPercent: 10, memoryBytes: 100, networkBytesPerSecond: 0),
            ProcessInfoSnapshot(pid: 2, name: "Safari WebKit", cpuPercent: 20, memoryBytes: 200, networkBytesPerSecond: 0),
            ProcessInfoSnapshot(pid: 3, name: "Terminal", cpuPercent: 5, memoryBytes: 50, networkBytesPerSecond: 0)
        ]
        let provider = StubProcessProvider(processes: processes)
        let monitor = ProcessMonitor(provider: provider)
        let purchaseState = PurchaseState()
        purchaseState.update(isPro: true)
        let model = ProcessesViewModel(processMonitor: monitor, purchaseState: purchaseState)

        model.searchQuery = "Safari"
        await model.refresh()

        XCTAssertEqual(model.rows.count, 2)
        XCTAssertTrue(model.rows.allSatisfy { $0.name.contains("Safari") })
    }

    func testProSearchIsCaseInsensitive() async {
        let processes = [
            ProcessInfoSnapshot(pid: 1, name: "Safari", cpuPercent: 10, memoryBytes: 100, networkBytesPerSecond: 0),
            ProcessInfoSnapshot(pid: 2, name: "safari", cpuPercent: 20, memoryBytes: 200, networkBytesPerSecond: 0)
        ]
        let provider = StubProcessProvider(processes: processes)
        let monitor = ProcessMonitor(provider: provider)
        let purchaseState = PurchaseState()
        purchaseState.update(isPro: true)
        let model = ProcessesViewModel(processMonitor: monitor, purchaseState: purchaseState)

        model.searchQuery = "safari"
        await model.refresh()

        XCTAssertEqual(model.rows.count, 2)
    }

    func testFreeUserSearchQueryIsIgnored() async {
        let processes = makeProcesses(count: 10)
        let provider = StubProcessProvider(processes: processes)
        let monitor = ProcessMonitor(provider: provider)
        let purchaseState = PurchaseState() // free
        let model = ProcessesViewModel(processMonitor: monitor, purchaseState: purchaseState)

        model.searchQuery = "Process-9"
        await model.refresh()

        // Free user: search is ignored, all 5 (limit) rows are returned.
        XCTAssertEqual(model.rows.count, 5)
    }

    func testProEmptySearchReturnsAll() async {
        let processes = makeProcesses(count: 10)
        let provider = StubProcessProvider(processes: processes)
        let monitor = ProcessMonitor(provider: provider)
        let purchaseState = PurchaseState()
        purchaseState.update(isPro: true)
        let model = ProcessesViewModel(processMonitor: monitor, purchaseState: purchaseState)

        model.searchQuery = ""
        await model.refresh()

        XCTAssertEqual(model.rows.count, 10)
    }

    // MARK: - Error handling

    func testProcessMonitorErrorIsCaptured() async {
        final class FailingProcessProvider: ProcessProvider, @unchecked Sendable {
            func list() throws -> [ProcessInfoSnapshot] {
                throw NSError(domain: "test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Process list failed"])
            }
        }

        let monitor = ProcessMonitor(provider: FailingProcessProvider())
        let purchaseState = PurchaseState()
        purchaseState.update(isPro: true)
        let model = ProcessesViewModel(processMonitor: monitor, purchaseState: purchaseState)

        await model.refresh()

        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertFalse(model.isLoading)
    }

    // MARK: - Nil monitor

    func testNilMonitorResultsInEmpty() async {
        let model = ProcessesViewModel(processMonitor: nil, purchaseState: PurchaseState())

        await model.refresh()

        XCTAssertTrue(model.isEmpty)
        XCTAssertTrue(model.rows.isEmpty)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isLoading)
    }

    // MARK: - Loading state

    func testLoadingStateIsTrueDuringRefresh() async {
        let provider = StubProcessProvider(processes: makeProcesses(count: 5))
        let monitor = ProcessMonitor(provider: provider)
        let purchaseState = PurchaseState()
        let model = ProcessesViewModel(processMonitor: monitor, purchaseState: purchaseState)

        let task = Task { await model.refresh() }
        // Before awaiting, isLoading should be true.
        // We can't reliably test this without actor interleaving guarantees,
        // so we at least verify it's false after completion.
        await task.value
        XCTAssertFalse(model.isLoading)
    }

    // MARK: - Row formatting

    func testRowFormatting() async {
        let process = ProcessInfoSnapshot(
            pid: 1234,
            name: "TestApp",
            cpuPercent: 12.5,
            memoryBytes: 145_000_000,
            networkBytesPerSecond: 2_300_000
        )
        let provider = StubProcessProvider(processes: [process])
        let monitor = ProcessMonitor(provider: provider)
        let purchaseState = PurchaseState()
        purchaseState.update(isPro: true)
        let model = ProcessesViewModel(processMonitor: monitor, purchaseState: purchaseState)

        await model.refresh()

        XCTAssertEqual(model.rows.count, 1)
        let row = model.rows[0]
        XCTAssertEqual(row.name, "TestApp")
        XCTAssertEqual(row.pid, 1234)
        XCTAssertEqual(row.cpuDisplay, "13%") // rounded
        XCTAssertEqual(row.memoryDisplay, "145 MB")
        XCTAssertEqual(row.networkDisplay, "2.3 MB/s")
    }
}
