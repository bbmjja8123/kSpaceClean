import XCTest
@testable import MetricsKit

final class MockSMCProvider: SMCReadingProvider, @unchecked Sendable {
    let temperature: Double
    let supported: Bool

    init(temperature: Double, supported: Bool = true) {
        self.temperature = temperature
        self.supported = supported
    }

    var isSupported: Bool { supported }

    func read(key: SMCKey) throws -> Double {
        if key == .gpuTemperature { return temperature }
        throw MetricError.unsupported("key not implemented in mock: \(key.rawValue)")
    }
}

final class GPUMonitorTests: XCTestCase {
    func testGPUOnUnsupportedSystemIsNotFabricated() async throws {
        let sample = try await GPUMonitor(provider: UnsupportedSMCProvider()).sample()
        XCTAssertEqual(sample.kind, .gpu)
        XCTAssertEqual(sample.availability, .unsupported(reason: "SMC is unavailable on this Mac"))
        if case .unavailable = sample.value {} else { XCTFail("expected unavailable value") }
    }

    func testGPUSampleWithValidProviderReturnsDegreesCelsius() async throws {
        let provider = MockSMCProvider(temperature: 65.0)
        let sample = try await GPUMonitor(provider: provider).sample()
        XCTAssertEqual(sample.kind, .gpu)
        XCTAssertEqual(sample.availability, .available)
        if case .degreesCelsius(let value) = sample.value {
            XCTAssertEqual(value, 65.0, accuracy: 0.01)
        } else {
            XCTFail("Expected .degreesCelsius value")
        }
    }

    func testGPUSampleWhenProviderReadFailsReportsError() async throws {
        struct FailingSMC: SMCReadingProvider, @unchecked Sendable {
            var isSupported: Bool { true }
            func read(key: SMCKey) throws -> Double { throw MetricError.malformedData("bad SMC frame") }
        }
        let sample = try await GPUMonitor(provider: FailingSMC()).sample()
        XCTAssertEqual(sample.kind, .gpu)
        if case .available = sample.availability { XCTFail("expected non-available") }
        if case .unavailable(let error) = sample.value {
            if case .malformedData = error {} else { XCTFail("expected .malformedData error") }
        } else {
            XCTFail("expected .unavailable value")
        }
    }
}