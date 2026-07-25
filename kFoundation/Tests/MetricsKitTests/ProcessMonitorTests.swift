import XCTest
@testable import MetricsKit

final class StubProcessProvider: ProcessProvider, @unchecked Sendable {
    private let processes: [ProcessInfoSnapshot]
    init(_ processes: [ProcessInfoSnapshot]) { self.processes = processes }
    func list() throws -> [ProcessInfoSnapshot] { processes }
}

final class ProcessMonitorTests: XCTestCase {
    func testProcessesSortByCPUDescending() async throws {
        let result = try ProcessMonitor(provider: StubProcessProvider([
            .init(pid: 1, name: "A", cpuPercent: 2, memoryBytes: 5, networkBytesPerSecond: 0),
            .init(pid: 2, name: "B", cpuPercent: 8, memoryBytes: 1, networkBytesPerSecond: 0)
        ])).top(limit: 2, sort: .cpu)
        XCTAssertEqual(result.map(\.pid), [2, 1])
    }

    func testProcessesLimitRespected() async throws {
        let processes = (0..<10).map { pid in
            ProcessInfoSnapshot(pid: pid, name: "P\(pid)", cpuPercent: Double(pid), memoryBytes: 0, networkBytesPerSecond: 0)
        }
        let result = try ProcessMonitor(provider: StubProcessProvider(processes)).top(limit: 3, sort: .cpu)
        XCTAssertEqual(result.count, 3)
    }
}