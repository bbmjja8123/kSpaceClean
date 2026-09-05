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
            .init(pid: 1, name: "A", cpuPercent: 2, memoryBytes: 5, networkBytesDownload: 0, networkBytesUpload: 0),
            .init(pid: 2, name: "B", cpuPercent: 8, memoryBytes: 1, networkBytesDownload: 0, networkBytesUpload: 0)
        ])).top(limit: 2, sort: .cpu)
        XCTAssertEqual(result.map(\.pid), [2, 1])
    }

    func testProcessesLimitRespected() async throws {
        let processes = (0..<10).map { pid in
            ProcessInfoSnapshot(pid: pid, name: "P\(pid)", cpuPercent: Double(pid), memoryBytes: 0, networkBytesDownload: 0, networkBytesUpload: 0)
        }
        let result = try ProcessMonitor(provider: StubProcessProvider(processes)).top(limit: 3, sort: .cpu)
        XCTAssertEqual(result.count, 3)
    }

    /// F5: sort by network upload surfaces the highest-uploaders first.
    func testProcessesSortByNetworkUpload() async throws {
        let result = try ProcessMonitor(provider: StubProcessProvider([
            .init(pid: 1, name: "A", cpuPercent: 0, memoryBytes: 0, networkBytesDownload: 0, networkBytesUpload: 100),
            .init(pid: 2, name: "B", cpuPercent: 0, memoryBytes: 0, networkBytesDownload: 50, networkBytesUpload: 5000)
        ])).top(limit: 2, sort: .networkUpload)
        XCTAssertEqual(result.map(\.pid), [2, 1])
    }

    /// F5: sort by network download surfaces the highest-downloaders first.
    func testProcessesSortByNetworkDownload() async throws {
        let result = try ProcessMonitor(provider: StubProcessProvider([
            .init(pid: 1, name: "A", cpuPercent: 0, memoryBytes: 0, networkBytesDownload: 10_000, networkBytesUpload: 0),
            .init(pid: 2, name: "B", cpuPercent: 0, memoryBytes: 0, networkBytesDownload: 100, networkBytesUpload: 0)
        ])).top(limit: 2, sort: .networkDownload)
        XCTAssertEqual(result.map(\.pid), [1, 2])
    }

    /// F5: `networkBytesPerSecond` accessor sums upload + download so the
    /// existing `sort: .network` callers stay correct.
    func testNetworkBytesPerSecondSumsUploadAndDownload() {
        let snap = ProcessInfoSnapshot(
            pid: 1, name: "x", cpuPercent: 0, memoryBytes: 0,
            networkBytesDownload: 300, networkBytesUpload: 700
        )
        XCTAssertEqual(snap.networkBytesPerSecond, 1000)
    }
}