import XCTest
@testable import MetricsKit

final class StubMonitor: MetricMonitor {
    let kind: MetricKind
    private let samples: [MetricValue]
    private var iterator: Int = 0
    init(kind: MetricKind, samples: [MetricValue]) { self.kind = kind; self.samples = samples }
    func sample() async throws -> MetricSample {
        defer { iterator += 1 }
        let value = samples[min(iterator, samples.count - 1)]
        return MetricSample(kind: kind, value: value, availability: .available, timestamp: Date())
    }
}

final class MetricsAggregatorTests: XCTestCase {
    func testAggregatorPublishesSnapshotsToMultipleConsumers() async throws {
        let monitor = StubMonitor(kind: .cpu, samples: [.percentage(10), .percentage(20)])
        let aggregator = MetricsAggregator(monitors: [monitor], strategy: SamplingStrategy(interval: .milliseconds(1)))
        let first = await aggregator.stream()
        let second = await aggregator.stream()
        await aggregator.start()
        let firstValue = try await first.first(where: { $0.values[.cpu] != nil })
        let firstSnapshot = try XCTUnwrap(firstValue)
        let secondValue = try await second.first(where: { $0.values[.cpu] != nil })
        let secondSnapshot = try XCTUnwrap(secondValue)
        XCTAssertEqual(firstSnapshot.values[.cpu], secondSnapshot.values[.cpu])
        await aggregator.stop()
    }

    func testAggregatorConvertsMonitorErrorsIntoUnavailableSamples() async throws {
        struct FailingMonitor: MetricMonitor {
            let kind: MetricKind = .memory
            func sample() async throws -> MetricSample { throw MetricError.malformedData("nope") }
        }
        let aggregator = MetricsAggregator(monitors: [FailingMonitor()], strategy: .init(interval: .milliseconds(1)))
        let stream = await aggregator.stream()
        await aggregator.start()
        let emitted = try await stream.first(where: { $0.availability[.memory] != nil })
        let snapshot = try XCTUnwrap(emitted)
        if case .unavailable = snapshot.values[.memory] {} else { XCTFail("expected unavailable value, got \(String(describing: snapshot.values[.memory]))") }
        if case .unavailable = snapshot.availability[.memory] {} else { XCTFail("expected unavailable availability") }
        await aggregator.stop()
    }
}