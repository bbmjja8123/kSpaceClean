import XCTest
@testable import kWise

final class VolumeLayerReaderTests: XCTestCase {
    /// fixture 从源码树读取（与语料审计同一 #filePath 模式）。
    private func fixtureData() throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/
            .appendingPathComponent("Fixtures/apfs_snapshots.plist")
        return try Data(contentsOf: url)
    }

    private struct StubRunner: VolumeCommandRunning {
        let status: Int32
        let output: Data
        func run(arguments: [String]) async -> (status: Int32, stdout: String) {
            (status, status == 0 ? String(data: output, encoding: .utf8) ?? "" : "")
        }
    }

    func testParseFixture() throws {
        let snapshots = try VolumeLayerReader.parseSnapshotPlist(try fixtureData())
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots[0].name, "com.apple.TimeMachine.2026-09-20-031544.local")
        // fixture <date>2026-09-19T19:15:44Z</date> 的纪元秒（brief 占位值 1_789_855_344 - 86_400
        // 与 fixture 对不上，按 brief 注释口径改为以 fixture 为准的精确断言）。
        XCTAssertEqual(snapshots[0].createdDate,
                       Date(timeIntervalSince1970: 1_789_845_344), // 2026-09-19T19:15:44Z
                       "plist <date> 必须还原为 Date")
        XCTAssertNil(snapshots[1].createdDate, "无日期字段的快照必须诚实为 nil")
    }

    func testEmptyArrayIsValidNoSnapshots() throws {
        let data = Data("<plist version=\"1.0\"><array/></plist>".utf8)
        XCTAssertEqual(try VolumeLayerReader.parseSnapshotPlist(data), [])
    }

    func testNonArrayIsUnreadable() {
        let data = Data("<plist version=\"1.0\"><dict/></plist>".utf8)
        XCTAssertThrowsError(try VolumeLayerReader.parseSnapshotPlist(data)) { error in
            XCTAssertEqual(error as? VolumeLayerError, .unreadable)
        }
    }

    func testNonZeroExitIsUnreadable() async {
        let reader = VolumeLayerReader(runner: StubRunner(status: 1, output: Data()),
                                       volumePath: "/")
        do {
            _ = try await reader.listSnapshots()
            XCTFail("non-zero exit must throw")
        } catch {
            XCTAssertEqual(error as? VolumeLayerError, .unreadable)
        }
    }

    func testSuccessfulReadReturnsSnapshots() async throws {
        let reader = VolumeLayerReader(runner: StubRunner(status: 0, output: try fixtureData()),
                                       volumePath: "/")
        let snapshots = try await reader.listSnapshots()
        XCTAssertEqual(snapshots.count, 2)
    }
}
