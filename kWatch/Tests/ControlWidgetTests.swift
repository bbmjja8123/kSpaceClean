import XCTest
@testable import kWatch

/// Tests for the Control Widget's shared data types.
///
/// The WidgetKit-dependent source files (ControlWidget.swift,
/// ControlWidgetProvider.swift, ControlWidgetView.swift, ControlWidgetEntry.swift)
/// are compiled only in the kWatchControlWidget target because the test target
/// cannot resolve the WidgetKit module. These tests exercise the shared
/// `SharedSnapshot` type that the widget reads from the App Group.
final class ControlWidgetTests: XCTestCase {

    // MARK: - SharedSnapshot Decoding

    func testSharedSnapshotDecodesFromJSON() throws {
        let json = """
        {
            "timestamp": "2026-08-06T12:00:00Z",
            "cpuPercent": 42.5,
            "memoryPercent": 67.8,
            "diskPercent": 55.0,
            "networkBytesPerSecond": 1024000,
            "temperatureCelsius": null,
            "fanRPM": null,
            "batteryPercent": null,
            "gpuTemperature": null,
            "cpuAvailable": true,
            "memoryAvailable": true,
            "diskAvailable": true,
            "networkAvailable": true,
            "temperatureAvailable": false,
            "fanAvailable": false,
            "batteryAvailable": false,
            "gpuAvailable": false,
            "isPro": false,
            "menuBarModeRaw": "trend"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(SharedSnapshot.self, from: json)

        XCTAssertEqual(snapshot.cpuPercent, 42.5, accuracy: 0.01)
        XCTAssertEqual(snapshot.memoryPercent, 67.8, accuracy: 0.01)
        XCTAssertTrue(snapshot.cpuAvailable)
        XCTAssertTrue(snapshot.memoryAvailable)
        XCTAssertFalse(snapshot.temperatureAvailable)
        XCTAssertFalse(snapshot.isPro)
    }

    func testSharedSnapshotEncodesAndDecodesRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let original = SharedSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            cpuPercent: 73.2,
            memoryPercent: 45.9,
            diskPercent: 80.1,
            networkBytesPerSecond: 5_000_000,
            temperatureCelsius: 62.0,
            fanRPM: 3200,
            batteryPercent: 85,
            cpuAvailable: true,
            memoryAvailable: true,
            diskAvailable: true,
            networkAvailable: true,
            temperatureAvailable: true,
            fanAvailable: true,
            batteryAvailable: true,
            isPro: true,
            menuBarModeRaw: "icon"
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(SharedSnapshot.self, from: data)

        XCTAssertEqual(original.cpuPercent, decoded.cpuPercent)
        XCTAssertEqual(original.memoryPercent, decoded.memoryPercent)
        XCTAssertEqual(original.diskPercent, decoded.diskPercent)
        XCTAssertEqual(original.networkBytesPerSecond, decoded.networkBytesPerSecond)
        XCTAssertEqual(original.temperatureCelsius, decoded.temperatureCelsius)
        XCTAssertEqual(original.fanRPM, decoded.fanRPM)
        XCTAssertEqual(original.batteryPercent, decoded.batteryPercent)
        XCTAssertEqual(original.isPro, decoded.isPro)
        XCTAssertEqual(original.menuBarModeRaw, decoded.menuBarModeRaw)
    }

    // MARK: - SharedSnapshot Staleness

    func testSharedSnapshotIsStaleAfterThreshold() {
        let recent = SharedSnapshot(
            timestamp: Date().addingTimeInterval(-5),
            cpuPercent: 0, memoryPercent: 0, diskPercent: 0,
            networkBytesPerSecond: 0,
            temperatureCelsius: nil, fanRPM: nil, batteryPercent: nil,
            cpuAvailable: true, memoryAvailable: true, diskAvailable: true,
            networkAvailable: true, temperatureAvailable: false, fanAvailable: false,
            batteryAvailable: false,
            isPro: false, menuBarModeRaw: MenuBarMode.trend.rawValue
        )
        XCTAssertFalse(recent.isStale)

        let old = SharedSnapshot(
            timestamp: Date().addingTimeInterval(-SharedSnapshot.stalenessThreshold - 1),
            cpuPercent: 0, memoryPercent: 0, diskPercent: 0,
            networkBytesPerSecond: 0,
            temperatureCelsius: nil, fanRPM: nil, batteryPercent: nil,
            cpuAvailable: true, memoryAvailable: true, diskAvailable: true,
            networkAvailable: true, temperatureAvailable: false, fanAvailable: false,
            batteryAvailable: false,
            isPro: false, menuBarModeRaw: MenuBarMode.trend.rawValue
        )
        XCTAssertTrue(old.isStale)
    }

    // MARK: - SharedSnapshot Default Values

    func testSharedSnapshotDefaultAvailabilityFlags() {
        let snapshot = SharedSnapshot(
            timestamp: Date(),
            cpuPercent: 0, memoryPercent: 0, diskPercent: 0,
            networkBytesPerSecond: 0,
            temperatureCelsius: nil, fanRPM: nil, batteryPercent: nil,
            cpuAvailable: false, memoryAvailable: false, diskAvailable: false,
            networkAvailable: false, temperatureAvailable: false, fanAvailable: false,
            batteryAvailable: false,
            isPro: false, menuBarModeRaw: "trend"
        )
        XCTAssertFalse(snapshot.cpuAvailable)
        XCTAssertFalse(snapshot.memoryAvailable)
        XCTAssertFalse(snapshot.diskAvailable)
        XCTAssertFalse(snapshot.networkAvailable)
        XCTAssertNil(snapshot.temperatureCelsius)
        XCTAssertNil(snapshot.fanRPM)
        XCTAssertNil(snapshot.batteryPercent)
    }

    func testSharedSnapshotWithAllMetricsAvailable() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let original = SharedSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            cpuPercent: 10.0,
            memoryPercent: 20.0,
            diskPercent: 30.0,
            networkBytesPerSecond: 1_000_000,
            temperatureCelsius: 45.5,
            fanRPM: 2000,
            batteryPercent: 92,
            cpuAvailable: true,
            memoryAvailable: true,
            diskAvailable: true,
            networkAvailable: true,
            temperatureAvailable: true,
            fanAvailable: true,
            batteryAvailable: true,
            isPro: true,
            menuBarModeRaw: "icon"
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(SharedSnapshot.self, from: data)

        XCTAssertEqual(decoded.temperatureCelsius ?? 0, 45.5, accuracy: 0.01)
        XCTAssertEqual(decoded.fanRPM ?? 0, 2000)
        XCTAssertEqual(decoded.batteryPercent ?? 0, 92)
        XCTAssertTrue(decoded.temperatureAvailable)
        XCTAssertTrue(decoded.fanAvailable)
        XCTAssertTrue(decoded.batteryAvailable)
    }

    // MARK: - SharedSnapshot GPU Metrics

    func testSharedSnapshotGPUMetricRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let original = SharedSnapshot(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            cpuPercent: 55.0,
            memoryPercent: 60.0,
            diskPercent: 40.0,
            networkBytesPerSecond: 2_000_000,
            temperatureCelsius: 70.0,
            fanRPM: 3000,
            batteryPercent: 88,
            gpuTemperature: 82.5,
            cpuAvailable: true,
            memoryAvailable: true,
            diskAvailable: true,
            networkAvailable: true,
            temperatureAvailable: true,
            fanAvailable: true,
            batteryAvailable: true,
            gpuAvailable: true,
            isPro: true,
            menuBarModeRaw: "trend"
        )

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(SharedSnapshot.self, from: data)

        XCTAssertEqual(decoded.gpuTemperature ?? 0, 82.5, accuracy: 0.01)
        XCTAssertTrue(decoded.gpuAvailable)
    }

    func testSharedSnapshotGPUAvailableFlagDecodesFromJSON() throws {
        let json = """
        {
            "timestamp": "2026-08-06T12:00:00Z",
            "cpuPercent": 30.0,
            "memoryPercent": 50.0,
            "diskPercent": 60.0,
            "networkBytesPerSecond": 500000,
            "temperatureCelsius": 65.0,
            "fanRPM": 2500,
            "batteryPercent": 78,
            "gpuTemperature": 90.0,
            "cpuAvailable": true,
            "memoryAvailable": true,
            "diskAvailable": true,
            "networkAvailable": true,
            "temperatureAvailable": true,
            "fanAvailable": true,
            "batteryAvailable": true,
            "gpuAvailable": true,
            "isPro": true,
            "menuBarModeRaw": "numeric"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(SharedSnapshot.self, from: json)

        XCTAssertTrue(snapshot.gpuAvailable)
        XCTAssertEqual(snapshot.gpuTemperature ?? 0, 90.0, accuracy: 0.01)
    }

    func testSharedSnapshotGPUNotAvailableDefaults() {
        let snapshot = SharedSnapshot(
            timestamp: Date(),
            cpuPercent: 0, memoryPercent: 0, diskPercent: 0,
            networkBytesPerSecond: 0,
            temperatureCelsius: nil, fanRPM: nil, batteryPercent: nil,
            cpuAvailable: true, memoryAvailable: true, diskAvailable: true,
            networkAvailable: true, temperatureAvailable: false, fanAvailable: false,
            batteryAvailable: false,
            isPro: false, menuBarModeRaw: "trend"
        )
        // gpuAvailable defaults to false in the init
        XCTAssertFalse(snapshot.gpuAvailable)
        XCTAssertNil(snapshot.gpuTemperature)
    }

    // MARK: - SharedSnapshot Staleness Edge Cases

    func testSharedSnapshotNotStaleJustBelowThreshold() {
        // Well within the staleness window — should not be stale.
        let snapshot = SharedSnapshot(
            timestamp: Date().addingTimeInterval(-SharedSnapshot.stalenessThreshold + 5),
            cpuPercent: 0, memoryPercent: 0, diskPercent: 0,
            networkBytesPerSecond: 0,
            temperatureCelsius: nil, fanRPM: nil, batteryPercent: nil,
            cpuAvailable: true, memoryAvailable: true, diskAvailable: true,
            networkAvailable: true, temperatureAvailable: false, fanAvailable: false,
            batteryAvailable: false,
            isPro: false, menuBarModeRaw: MenuBarMode.trend.rawValue
        )
        XCTAssertFalse(snapshot.isStale)
    }

    func testSharedSnapshotNotStaleWithFutureTimestamp() {
        let snapshot = SharedSnapshot(
            timestamp: Date().addingTimeInterval(60),
            cpuPercent: 50, memoryPercent: 50, diskPercent: 50,
            networkBytesPerSecond: 0,
            temperatureCelsius: nil, fanRPM: nil, batteryPercent: nil,
            cpuAvailable: true, memoryAvailable: true, diskAvailable: true,
            networkAvailable: true, temperatureAvailable: false, fanAvailable: false,
            batteryAvailable: false,
            isPro: false, menuBarModeRaw: MenuBarMode.trend.rawValue
        )
        XCTAssertFalse(snapshot.isStale)
    }

    // MARK: - SharedSnapshot Equatable

    func testSharedSnapshotEquality() {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let a = SharedSnapshot(
            timestamp: timestamp,
            cpuPercent: 42.5, memoryPercent: 67.8, diskPercent: 55.0,
            networkBytesPerSecond: 1024000,
            temperatureCelsius: 60.0, fanRPM: 2200, batteryPercent: 85,
            cpuAvailable: true, memoryAvailable: true, diskAvailable: true,
            networkAvailable: true, temperatureAvailable: true, fanAvailable: true,
            batteryAvailable: true,
            isPro: true, menuBarModeRaw: "trend"
        )
        let b = SharedSnapshot(
            timestamp: timestamp,
            cpuPercent: 42.5, memoryPercent: 67.8, diskPercent: 55.0,
            networkBytesPerSecond: 1024000,
            temperatureCelsius: 60.0, fanRPM: 2200, batteryPercent: 85,
            cpuAvailable: true, memoryAvailable: true, diskAvailable: true,
            networkAvailable: true, temperatureAvailable: true, fanAvailable: true,
            batteryAvailable: true,
            isPro: true, menuBarModeRaw: "trend"
        )
        XCTAssertEqual(a, b)

        let c = SharedSnapshot(
            timestamp: timestamp,
            cpuPercent: 99.0, memoryPercent: 67.8, diskPercent: 55.0,
            networkBytesPerSecond: 1024000,
            temperatureCelsius: 60.0, fanRPM: 2200, batteryPercent: 85,
            cpuAvailable: true, memoryAvailable: true, diskAvailable: true,
            networkAvailable: true, temperatureAvailable: true, fanAvailable: true,
            batteryAvailable: true,
            isPro: true, menuBarModeRaw: "trend"
        )
        XCTAssertNotEqual(a, c)
    }
}
