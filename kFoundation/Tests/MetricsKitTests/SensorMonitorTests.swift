import XCTest
@testable import MetricsKit

final class UnsupportedSMCProvider: SMCReadingProvider, @unchecked Sendable {
    func read(key: SMCKey) throws -> Double { throw MetricError.unsupported("SMC is unavailable on this Mac") }
    var isSupported: Bool { false }
}

final class StubBatteryProvider: BatteryReadingProvider, @unchecked Sendable {
    let state: BatteryReading
    init(_ state: BatteryReading) { self.state = state }
    func read() throws -> BatteryReading { state }
}

final class SensorMonitorTests: XCTestCase {
    func testUnsupportedSensorIsNotFabricated() async throws {
        let sample = try await TemperatureMonitor(provider: UnsupportedSMCProvider()).sample()
        XCTAssertEqual(sample.availability, .unsupported(reason: "SMC is unavailable on this Mac"))
        if case .unavailable = sample.value {} else { XCTFail("expected unavailable value") }
    }

    func testFanOnUnsupportedSystemIsNotFabricated() async throws {
        let sample = try await FanMonitor(provider: UnsupportedSMCProvider()).sample()
        XCTAssertEqual(sample.availability, .unsupported(reason: "SMC is unavailable on this Mac"))
    }

    func testBatteryProviderReportsCharge() async throws {
        let sample = try await BatteryMonitor(provider: StubBatteryProvider(.init(chargePercent: 80, isCharging: true, voltage: 12.5))).sample()
        XCTAssertEqual(sample.value, .percentage(80))
        XCTAssertEqual(sample.availability, .available)
    }

    func testZeroChargeBatteryReportsZero() async throws {
        let sample = try await BatteryMonitor(provider: StubBatteryProvider(.init(chargePercent: 0, isCharging: false, voltage: 0))).sample()
        XCTAssertEqual(sample.value, .percentage(0))
    }
}