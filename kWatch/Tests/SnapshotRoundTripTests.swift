import XCTest
@testable import kWatch

final class SnapshotRoundTripTests: XCTestCase {
    private func makeTempDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kWatch.roundtrip.\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func testSnapshotRoundTripPreservesTimestamp() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = SnapshotWriter(directory: directory)
        let originalTimestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = SharedSnapshot(
            timestamp: originalTimestamp,
            cpuPercent: 45, memoryPercent: 0, diskPercent: 0,
            networkBytesPerSecond: 0,
            temperatureCelsius: nil, fanRPM: nil, batteryPercent: nil,
            cpuAvailable: true, memoryAvailable: true, diskAvailable: true,
            networkAvailable: true, temperatureAvailable: false, fanAvailable: false,
            batteryAvailable: true,
            isPro: false, menuBarModeRaw: MenuBarMode.trend.rawValue
        )
        try writer.write(snapshot)
        let decoded = try XCTUnwrap(try writer.read())
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970,
                       originalTimestamp.timeIntervalSince1970,
                       accuracy: 0.001)
    }
}
