import XCTest
@testable import kWatch

final class SnapshotWriterTests: XCTestCase {
    private func makeTempDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kWatch.snapshot.tests.\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func testSnapshotRoundTripsThroughDirectory() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = SnapshotWriter(directory: directory)
        let snapshot = SharedSnapshot(
            timestamp: Date(timeIntervalSince1970: 1),
            cpuPercent: 44, memoryPercent: 55, diskPercent: 66,
            networkBytesPerSecond: 77,
            temperatureCelsius: 42, fanRPM: 1200, batteryPercent: 88,
            cpuAvailable: true, memoryAvailable: true, diskAvailable: true,
            networkAvailable: true, temperatureAvailable: true, fanAvailable: true,
            batteryAvailable: true,
            isPro: false, menuBarModeRaw: MenuBarMode.trend.rawValue
        )
        try writer.write(snapshot)
        let reread = try XCTUnwrap(try writer.read())
        XCTAssertEqual(reread.cpuPercent, 44)
        XCTAssertEqual(reread.temperatureCelsius, 42)
        XCTAssertEqual(reread.menuBarModeRaw, MenuBarMode.trend.rawValue)
    }

    func testReaderReturnsNilForMissingFile() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = SnapshotWriter(directory: directory)
        XCTAssertNil(try writer.read())
    }

    func testAtomicWriteDoesNotLeaveTempFileOnSuccess() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = SnapshotWriter(directory: directory)
        let snapshot = SharedSnapshot(
            timestamp: Date(timeIntervalSince1970: 2),
            cpuPercent: 1, memoryPercent: 2, diskPercent: 3,
            networkBytesPerSecond: 4,
            temperatureCelsius: nil, fanRPM: nil, batteryPercent: nil,
            cpuAvailable: true, memoryAvailable: true, diskAvailable: true,
            networkAvailable: true, temperatureAvailable: false, fanAvailable: false,
            batteryAvailable: true,
            isPro: true, menuBarModeRaw: MenuBarMode.numeric.rawValue
        )
        try writer.write(snapshot)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertTrue(files.contains { $0.lastPathComponent == "snapshot.json" })
        XCTAssertFalse(files.contains { $0.lastPathComponent == "snapshot.json.tmp" })
    }

    func testStalenessFlagActivatesAfterThreshold() throws {
        let oldSnapshot = SharedSnapshot(
            timestamp: Date(timeIntervalSince1970: 0),
            cpuPercent: 0, memoryPercent: 0, diskPercent: 0,
            networkBytesPerSecond: 0,
            temperatureCelsius: nil, fanRPM: nil, batteryPercent: nil,
            cpuAvailable: true, memoryAvailable: true, diskAvailable: true,
            networkAvailable: true, temperatureAvailable: false, fanAvailable: false,
            batteryAvailable: true,
            isPro: false, menuBarModeRaw: MenuBarMode.minimal.rawValue
        )
        XCTAssertTrue(oldSnapshot.isStale)
        let fresh = SharedSnapshot(
            timestamp: Date(),
            cpuPercent: 0, memoryPercent: 0, diskPercent: 0,
            networkBytesPerSecond: 0,
            temperatureCelsius: nil, fanRPM: nil, batteryPercent: nil,
            cpuAvailable: true, memoryAvailable: true, diskAvailable: true,
            networkAvailable: true, temperatureAvailable: false, fanAvailable: false,
            batteryAvailable: true,
            isPro: false, menuBarModeRaw: MenuBarMode.minimal.rawValue
        )
        XCTAssertFalse(fresh.isStale)
    }
}
