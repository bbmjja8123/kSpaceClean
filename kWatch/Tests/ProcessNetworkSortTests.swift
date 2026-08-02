import XCTest
import MetricsKit
@testable import kWatch

private final class StubProcessProvider: ProcessProvider, @unchecked Sendable {
    private let processes: [ProcessInfoSnapshot]

    init(processes: [ProcessInfoSnapshot]) {
        self.processes = processes
    }

    func list() throws -> [ProcessInfoSnapshot] {
        processes
    }
}

final class ProcessNetworkSortTests: XCTestCase {

    /// When sorting by network, the highest-throughput processes appear first.
    func testTopByNetworkReturnsHighestFirst() throws {
        let provider = StubProcessProvider(processes: [
            ProcessInfoSnapshot(pid: 1, name: "Background", cpuPercent: 1, memoryBytes: 100, networkBytesPerSecond: 500),
            ProcessInfoSnapshot(pid: 2, name: "Browser",    cpuPercent: 5, memoryBytes: 200, networkBytesPerSecond: 50_000),
            ProcessInfoSnapshot(pid: 3, name: "Mail",       cpuPercent: 3, memoryBytes: 150, networkBytesPerSecond: 10_000),
        ])
        let monitor = ProcessMonitor(provider: provider)

        let top = try monitor.top(limit: 3, sort: .network)

        XCTAssertEqual(top.map(\.name), ["Browser", "Mail", "Background"])
        XCTAssertEqual(top.first?.networkBytesPerSecond, 50_000)
        XCTAssertEqual(top.last?.networkBytesPerSecond, 500)
    }

    /// The `limit` parameter caps the result set while preserving rank order.
    func testTopByNetworkRespectsLimit() throws {
        let provider = StubProcessProvider(processes: (1...10).map { i in
            ProcessInfoSnapshot(
                pid: Int32(i),
                name: "p\(i)",
                cpuPercent: 0,
                memoryBytes: 0,
                networkBytesPerSecond: UInt64(i * 1000)
            )
        })
        let monitor = ProcessMonitor(provider: provider)

        let top = try monitor.top(limit: 3, sort: .network)

        XCTAssertEqual(top.count, 3)
        XCTAssertEqual(top.map(\.networkBytesPerSecond), [10_000, 9_000, 8_000])
    }

    /// Network sort ties are broken by stable insertion order (matches the
    /// `sorted` algorithm's behavior — documents the current contract).
    func testTopByNetworkStableOnTies() throws {
        let provider = StubProcessProvider(processes: [
            ProcessInfoSnapshot(pid: 1, name: "First",  cpuPercent: 0, memoryBytes: 0, networkBytesPerSecond: 1_000),
            ProcessInfoSnapshot(pid: 2, name: "Second", cpuPercent: 0, memoryBytes: 0, networkBytesPerSecond: 1_000),
            ProcessInfoSnapshot(pid: 3, name: "Third",  cpuPercent: 0, memoryBytes: 0, networkBytesPerSecond: 500),
        ])
        let monitor = ProcessMonitor(provider: provider)

        let top = try monitor.top(limit: 3, sort: .network)

        XCTAssertEqual(top.map(\.name), ["First", "Second", "Third"])
    }
}