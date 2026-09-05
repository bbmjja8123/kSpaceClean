import XCTest
@testable import MetricsKit

/// SMC stub used by the GPU monitor tests. Placed here rather than in
/// production code because the production adapter
/// (`IOKitSMCReadingProvider`) explicitly does not support real SMC
/// reads — see its TODO comment.
private final class StubSMC: SMCReadingProvider, @unchecked Sendable {
    let supported: Bool
    let temperature: Double?

    init(supported: Bool, temperature: Double? = nil) {
        self.supported = supported
        self.temperature = temperature
    }

    var isSupported: Bool { supported }

    func read(key: SMCKey) throws -> Double {
        switch key {
        case .gpuTemperature:
            if let temperature { return temperature }
            throw MetricError.unsupported("gpu temp")
        default:
            throw MetricError.unsupported("not implemented in stub")
        }
    }
}

final class GPUMonitorTests: XCTestCase {

    /// On Apple Silicon the usage provider returns a `[0, 1]` fraction
    /// and the monitor surfaces it as a `.percentage` value (the
    /// dashboard's "GPU Usage" card plots this number).
    func testSampleReturnsPercentageWhenUsageProviderSupported() async throws {
        let smc = StubSMC(supported: false)
        let usage = StubGPUUsageProvider(fraction: 0.42)
        let monitor = GPUMonitor(smcProvider: smc, usageProvider: usage)

        let sample = try await monitor.sample()

        XCTAssertEqual(sample.kind, .gpu)
        XCTAssertEqual(sample.availability, .available)
        XCTAssertEqual(sample.value.percentage ?? -1, 0.42, accuracy: 0.0001)
        XCTAssertNil(sample.value.degreesCelsius)
    }

    /// When the usage provider is unsupported (e.g. Intel iGPU) but SMC
    /// still exposes `TG0P`, the monitor falls back to a
    /// `.degreesCelsius` sample so Intel users still see something
    /// useful on the dashboard.
    func testSampleFallsBackToTemperatureWhenUsageUnsupported() async throws {
        let smc = StubSMC(supported: true, temperature: 72.0)
        let usage = StubGPUUsageProvider(fraction: nil, supported: false)
        let monitor = GPUMonitor(smcProvider: smc, usageProvider: usage)

        let sample = try await monitor.sample()

        XCTAssertEqual(sample.availability, .available)
        XCTAssertEqual(sample.value.degreesCelsius ?? -1, 72.0, accuracy: 0.0001)
        XCTAssertNil(sample.value.percentage)
    }

    /// When neither source has data, the monitor returns a `.unsupported`
    /// sample so the dashboard can render an explicit "unavailable"
    /// badge rather than fabricating numbers.
    func testSampleReturnsUnsupportedWhenBothProvidersFail() async throws {
        let smc = StubSMC(supported: false)
        let usage = StubGPUUsageProvider(fraction: nil, supported: false)
        let monitor = GPUMonitor(smcProvider: smc, usageProvider: usage)

        let sample = try await monitor.sample()

        if case .unsupported = sample.availability {
            // ok
        } else {
            XCTFail("Expected unsupported availability, got \(sample.availability)")
        }
        XCTAssertNil(sample.value.percentage)
        XCTAssertNil(sample.value.degreesCelsius)
    }
}