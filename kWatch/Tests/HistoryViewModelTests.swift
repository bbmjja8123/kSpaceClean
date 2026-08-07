import XCTest
import Combine
import MetricsKit
@testable import kWatch

// MARK: - Spy repository

/// A test spy that records whether `samples(since:)` was called.
private final class SpyRepository: HistoryRepositoryProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var samplesCallCount = 0
    private let inner: HistoryRepositoryProtocol

    init(inner: HistoryRepositoryProtocol = InMemoryHistoryRepository()) {
        self.inner = inner
    }

    func append(_ snapshot: MetricSnapshot) throws {
        try inner.append(snapshot)
    }

    func samples(since start: Date) throws -> [MetricSnapshot] {
        lock.withLock { samplesCallCount += 1 }
        return try inner.samples(since: start)
    }

    func purge(olderThan cutoff: Date) throws {
        try inner.purge(olderThan: cutoff)
    }
}

// MARK: - Helpers

private func makeSamples(
    count: Int,
    from start: TimeInterval? = nil,
    interval: TimeInterval = 30
) -> [MetricSnapshot] {
    let firstTimestamp = start
        ?? Date().addingTimeInterval(-Double(max(count - 1, 0)) * interval).timeIntervalSince1970
    var result: [MetricSnapshot] = []
    result.reserveCapacity(count)
    for i in 0..<count {
        let ts = Date(timeIntervalSince1970: firstTimestamp + Double(i) * interval)
        let cpu: Double = Double(i).truncatingRemainder(dividingBy: 100)
        let mem: Double = Double(i * 2).truncatingRemainder(dividingBy: 100)
        let disk: Double = Double(i * 3).truncatingRemainder(dividingBy: 100)
        let net: UInt64 = UInt64(i * 1024)
        let temp: Double = Double(i).truncatingRemainder(dividingBy: 40) + 20
        let fan: Double = Double(i * 100).truncatingRemainder(dividingBy: 3000) + 1000
        let bat: Double = Double(i).truncatingRemainder(dividingBy: 50) + 30
        result.append(MetricSnapshot(
            timestamp: ts,
            values: [
                .cpu: .percentage(cpu),
                .memory: .percentage(mem),
                .disk: .percentage(disk),
                .network: .bytesPerSecond(net),
                .temperature: .degreesCelsius(temp),
                .fan: .revolutionsPerMinute(fan),
                .battery: .percentage(bat)
            ],
            availability: [:]
        ))
    }
    return result
}

// MARK: - Tests

@MainActor
final class HistoryViewModelTests: XCTestCase {

    // MARK: - Free gating

    func testFreeUserIsLockedAndRepositoryNotCalled() async {
        let spy = SpyRepository()
        let purchaseState = PurchaseState() // default isPro = false
        let model = HistoryViewModel(repository: spy, purchaseState: purchaseState)

        await model.load()

        XCTAssertTrue(model.isLocked)
        XCTAssertTrue(model.points.isEmpty)
        XCTAssertTrue(model.isEmpty)
        XCTAssertNil(model.minValue)
        XCTAssertNil(model.maxValue)
        XCTAssertNil(model.averageValue)
        XCTAssertEqual(spy.samplesCallCount, 0,
                       "Repository must not be queried for free users")
    }

    func testFreeUserStaysLockedAfterMultipleLoadAttempts() async {
        let spy = SpyRepository()
        let purchaseState = PurchaseState()
        let model = HistoryViewModel(repository: spy, purchaseState: purchaseState)

        await model.load()
        XCTAssertEqual(spy.samplesCallCount, 0)

        model.selectedRange = .days7
        await model.load()
        XCTAssertEqual(spy.samplesCallCount, 0,
                       "Changing range must not bypass the Pro gate")

        model.selectedMetric = .memory
        await model.load()
        XCTAssertEqual(spy.samplesCallCount, 0)
    }

    // MARK: - Pro entitlement

    func testProUserCanLoadHistory() async {
        let samples = makeSamples(count: 20)
        let repository = InMemoryHistoryRepository(snapshots: samples)
        let purchaseState = PurchaseState()
        purchaseState.update(isPro: true)
        let model = HistoryViewModel(repository: repository, purchaseState: purchaseState)

        await model.load()

        XCTAssertFalse(model.isLocked)
        XCTAssertFalse(model.isLoading)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isEmpty)
        XCTAssertGreaterThan(model.points.count, 0)
    }

    func testUpgradeTriggersLoadAndUnlocks() async {
        let samples = makeSamples(count: 5)
        let repository = InMemoryHistoryRepository(snapshots: samples)
        let purchaseState = PurchaseState() // free
        let model = HistoryViewModel(repository: repository, purchaseState: purchaseState)

        await model.load()
        XCTAssertTrue(model.isLocked)

        // Upgrade.
        purchaseState.update(isPro: true)
        await model.load()

        XCTAssertFalse(model.isLocked)
        XCTAssertFalse(model.isEmpty)
    }

    func testDowngradeLocksAndClearsData() async {
        let samples = makeSamples(count: 5)
        let repository = InMemoryHistoryRepository(snapshots: samples)
        let purchaseState = PurchaseState()
        purchaseState.update(isPro: true)
        let model = HistoryViewModel(repository: repository, purchaseState: purchaseState)

        await model.load()
        XCTAssertFalse(model.isLocked)
        XCTAssertGreaterThan(model.points.count, 0)

        // Downgrade.
        purchaseState.update(isPro: false)
        await model.load()

        XCTAssertTrue(model.isLocked)
        XCTAssertTrue(model.points.isEmpty)
    }

    // MARK: - Range cutoff

    func testHistoryRangesUseExactDurations() {
        let end = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(HistoryRange.hours24.dateInterval(endingAt: end).duration, 24 * 60 * 60)
        XCTAssertEqual(HistoryRange.days7.dateInterval(endingAt: end).duration, 7 * 24 * 60 * 60)
        XCTAssertEqual(HistoryRange.days30.dateInterval(endingAt: end).duration, 30 * 24 * 60 * 60)
    }

    func testRangeCutoffHours24() async {
        let now = Date()
        let recent = MetricSnapshot(
            timestamp: now.addingTimeInterval(-3600), // 1 hour ago
            values: [.cpu: .percentage(50)],
            availability: [:]
        )
        let old = MetricSnapshot(
            timestamp: now.addingTimeInterval(-48 * 3600), // 48 hours ago
            values: [.cpu: .percentage(30)],
            availability: [:]
        )
        let repository = InMemoryHistoryRepository(snapshots: [recent, old])
        let purchaseState = PurchaseState()
        purchaseState.update(isPro: true)
        let model = HistoryViewModel(repository: repository, purchaseState: purchaseState)

        // Override the range's dateInterval to use `now` as reference.
        // Since `HistoryRange.dateInterval` uses `Date()`, which is `now` in tests,
        // 24h should include `recent` and exclude `old`.
        model.selectedRange = .hours24
        await model.load()

        // Both snapshots have timestamps; .hours24 filters to last 24h.
        // `recent` is 1h ago → included. `old` is 48h ago → excluded.
        XCTAssertEqual(model.points.count, 1)
        XCTAssertEqual(model.minValue, 50)
    }

    func testRangeCutoffDays7() async {
        let now = Date()
        let recent = MetricSnapshot(
            timestamp: now.addingTimeInterval(-3600 * 24 * 2), // 2 days ago
            values: [.cpu: .percentage(60)],
            availability: [:]
        )
        let old = MetricSnapshot(
            timestamp: now.addingTimeInterval(-3600 * 24 * 14), // 14 days ago
            values: [.cpu: .percentage(20)],
            availability: [:]
        )
        let repository = InMemoryHistoryRepository(snapshots: [recent, old])
        let purchaseState = PurchaseState()
        purchaseState.update(isPro: true)
        let model = HistoryViewModel(repository: repository, purchaseState: purchaseState)

        model.selectedRange = .days7
        await model.load()

        XCTAssertEqual(model.points.count, 1)
        XCTAssertEqual(model.minValue, 60)
    }

    func testRangeCutoffDays30() async {
        let now = Date()
        let recent = MetricSnapshot(
            timestamp: now.addingTimeInterval(-3600 * 24 * 20), // 20 days ago
            values: [.cpu: .percentage(70)],
            availability: [:]
        )
        let old = MetricSnapshot(
            timestamp: now.addingTimeInterval(-3600 * 24 * 45), // 45 days ago
            values: [.cpu: .percentage(10)],
            availability: [:]
        )
        let repository = InMemoryHistoryRepository(snapshots: [recent, old])
        let purchaseState = PurchaseState()
        purchaseState.update(isPro: true)
        let model = HistoryViewModel(repository: repository, purchaseState: purchaseState)

        model.selectedRange = .days30
        await model.load()

        XCTAssertEqual(model.points.count, 1)
        XCTAssertEqual(model.minValue, 70)
    }

    // MARK: - Metric conversion

    func testExtractDoubleForAllMetricKinds() {
        XCTAssertEqual(extractDouble(from: .percentage(42.5), for: .cpu), 42.5)
        XCTAssertEqual(extractDouble(from: .percentage(85), for: .memory), 85)
        XCTAssertEqual(extractDouble(from: .percentage(60), for: .disk), 60)
        XCTAssertEqual(extractDouble(from: .bytesPerSecond(2048), for: .network), 2048)
        XCTAssertEqual(extractDouble(from: .degreesCelsius(36.6), for: .temperature), 36.6)
        XCTAssertEqual(extractDouble(from: .revolutionsPerMinute(2200), for: .fan), 2200)
        XCTAssertEqual(extractDouble(from: .percentage(91), for: .battery), 91)
    }

    func testExtractDoubleRejectsMismatchedValueType() {
        XCTAssertNil(extractDouble(from: .percentage(50), for: .temperature))
        XCTAssertNil(extractDouble(from: .bytes(1024), for: .memory))
        XCTAssertNil(extractDouble(from: .volts(12.3), for: .battery))
        XCTAssertNil(extractDouble(from: .text("hello"), for: .cpu))
    }

    func testExtractDoubleReturnsNilForUnavailable() {
        XCTAssertNil(extractDouble(from: .unavailable(.unsupported("test")), for: .cpu))
        XCTAssertNil(extractDouble(from: .unavailable(.systemCall("err", 1)), for: .network))
        XCTAssertNil(extractDouble(from: .unavailable(.malformedData("bad")), for: .fan))
    }

    func testExtractDoubleReturnsNilForNil() {
        XCTAssertNil(extractDouble(from: nil, for: .cpu))
    }

    func testUnavailableValuesAreOmittedFromChartPoints() async {
        let snapshot = MetricSnapshot(
            timestamp: Date(),
            values: [.cpu: .unavailable(.unsupported("no sensor"))],
            availability: [:]
        )
        let repository = InMemoryHistoryRepository(snapshots: [snapshot])
        let purchaseState = PurchaseState()
        purchaseState.update(isPro: true)
        let model = HistoryViewModel(repository: repository, purchaseState: purchaseState)

        model.selectedMetric = .cpu
        await model.load()

        XCTAssertTrue(model.points.isEmpty,
                      "Unavailable values must be omitted, not converted to zero")
    }

    func testMismatchedMetricValueIsOmitted() async {
        let snapshot = MetricSnapshot(
            timestamp: Date(),
            values: [.temperature: .percentage(50)],
            availability: [:]
        )
        let repository = InMemoryHistoryRepository(snapshots: [snapshot])
        let purchaseState = PurchaseState()
        purchaseState.update(isPro: true)
        let model = HistoryViewModel(repository: repository, purchaseState: purchaseState)

        model.selectedMetric = .temperature
        await model.load()

        XCTAssertTrue(model.points.isEmpty,
                      "Mismatched values must be omitted")
    }

    // MARK: - Metric selection

    func testCanSelectDifferentMetrics() async {
        let samples = makeSamples(count: 10)
        let repository = InMemoryHistoryRepository(snapshots: samples)
        let purchaseState = PurchaseState()
        purchaseState.update(isPro: true)
        let model = HistoryViewModel(repository: repository, purchaseState: purchaseState)

        model.selectedMetric = .memory
        await model.load()
        XCTAssertGreaterThan(model.points.count, 0)
        XCTAssertNotNil(model.minValue)

        model.selectedMetric = .network
        await model.load()
        XCTAssertGreaterThan(model.points.count, 0)
    }

    // MARK: - Summaries

    func testSummariesAreComputedFromLoadedPoints() async {
        let now = Date()
        let samples = (1...5).map { i in
            MetricSnapshot(
                timestamp: now.addingTimeInterval(Double(i - 5) * 60),
                values: [.cpu: .percentage(Double(i * 10))], // 10, 20, 30, 40, 50
                availability: [:]
            )
        }
        let repository = InMemoryHistoryRepository(snapshots: samples)
        let purchaseState = PurchaseState()
        purchaseState.update(isPro: true)
        let model = HistoryViewModel(repository: repository, purchaseState: purchaseState)

        await model.load()

        XCTAssertEqual(model.minValue, 10)
        XCTAssertEqual(model.maxValue, 50)
        XCTAssertEqual(model.averageValue, 30)
        XCTAssertEqual(model.minDisplay, "10%")
        XCTAssertEqual(model.maxDisplay, "50%")
        XCTAssertEqual(model.averageDisplay, "30%")
    }

    func testSummariesUseFullSeriesBeforeDownsampling() async {
        let now = Date()
        let samples = (0..<1_000).map { index in
            MetricSnapshot(
                timestamp: now.addingTimeInterval(Double(index - 999) * 30),
                values: [.cpu: .percentage(index == 500 ? 100 : 0)]
            )
        }
        let repository = InMemoryHistoryRepository(snapshots: samples)
        let purchaseState = PurchaseState()
        purchaseState.update(isPro: true)
        let model = HistoryViewModel(repository: repository, purchaseState: purchaseState)

        await model.load()

        XCTAssertLessThanOrEqual(model.points.count, 500)
        XCTAssertEqual(model.minValue, 0)
        XCTAssertEqual(model.maxValue, 100)
        XCTAssertEqual(model.averageValue ?? -1, 0.1, accuracy: 0.0001)
    }

    func testSummariesAreNilWhenNoData() async {
        let repository = InMemoryHistoryRepository() // empty
        let purchaseState = PurchaseState()
        purchaseState.update(isPro: true)
        let model = HistoryViewModel(repository: repository, purchaseState: purchaseState)

        await model.load()

        XCTAssertNil(model.minValue)
        XCTAssertNil(model.maxValue)
        XCTAssertNil(model.averageValue)
        XCTAssertNil(model.minDisplay)
        XCTAssertNil(model.maxDisplay)
        XCTAssertNil(model.averageDisplay)
    }

    func testSummariesAreClearedOnFreeGate() async {
        let samples = makeSamples(count: 5)
        let repository = InMemoryHistoryRepository(snapshots: samples)
        let purchaseState = PurchaseState()
        purchaseState.update(isPro: true)
        let model = HistoryViewModel(repository: repository, purchaseState: purchaseState)

        await model.load()
        XCTAssertNotNil(model.minValue)

        purchaseState.update(isPro: false)
        await model.load()
        XCTAssertNil(model.minValue)
        XCTAssertNil(model.maxValue)
        XCTAssertNil(model.averageValue)
    }

    // MARK: - Downsampling

    func testDownsampleReturnsEmptyForEmptyInput() {
        let result = downsample(points: [], maxCount: 500)
        XCTAssertTrue(result.isEmpty)
    }

    func testDownsampleReturnsSingletonUnchanged() {
        let point = ChartPoint(date: Date(), value: 42)
        let result = downsample(points: [point], maxCount: 500)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].value, 42)
    }

    func testDownsampleReturnsSmallArrayUnchanged() {
        let points = (0..<10).map { i in
            ChartPoint(date: Date(timeIntervalSince1970: Double(i)), value: Double(i))
        }
        let result = downsample(points: points, maxCount: 500)
        XCTAssertEqual(result.count, 10)
    }

    func testDownsampleReducesLargeSeriesToAtMost500() {
        let points = (0..<10_000).map { i in
            ChartPoint(
                date: Date(timeIntervalSince1970: Double(i) * 30),
                value: Double(i).truncatingRemainder(dividingBy: 100)
            )
        }
        let result = downsample(points: points, maxCount: 500)
        XCTAssertLessThanOrEqual(result.count, 500,
                                 "Downsampled series must not exceed 500 points")
        XCTAssertGreaterThan(result.count, 0,
                             "Downsampled series must not be empty")
    }

    func testDownsamplePreservesChronologicalOrder() {
        let points = (0..<10_000).map { i in
            ChartPoint(
                date: Date(timeIntervalSince1970: Double(i) * 30),
                value: Double(i).truncatingRemainder(dividingBy: 100)
            )
        }
        let result = downsample(points: points, maxCount: 500)
        let dates = result.map(\.date)
        XCTAssertEqual(dates, dates.sorted(),
                       "Downsampled points must remain in chronological order")
    }

    func testDownsamplePreservesSpikes() {
        // Create a series with one extreme spike.
        var pts: [ChartPoint] = []
        for i in 0..<200 {
            let value: Double = (i == 100) ? 999 : Double(i).truncatingRemainder(dividingBy: 50)
            pts.append(ChartPoint(
                date: Date(timeIntervalSince1970: Double(i) * 30),
                value: value
            ))
        }

        let result = downsample(points: pts, maxCount: 50)

        // The spike (999) should still be present in the downsampled result.
        XCTAssertTrue(result.contains(where: { $0.value == 999 }),
                      "Spike value 999 must be preserved after downsampling")
    }

    func testDownsamplePreservesMinima() {
        // Create a series with one extreme minimum.
        var pts: [ChartPoint] = []
        for i in 0..<200 {
            let value: Double = (i == 50) ? -10 : Double(i).truncatingRemainder(dividingBy: 50)
            pts.append(ChartPoint(
                date: Date(timeIntervalSince1970: Double(i) * 30),
                value: value
            ))
        }

        let result = downsample(points: pts, maxCount: 50)

        XCTAssertTrue(result.contains(where: { $0.value == -10 }),
                      "Minimum spike -10 must be preserved after downsampling")
    }

    func testDownsampleHandlesExactMaxCount() {
        let points = (0..<500).map { i in
            ChartPoint(date: Date(timeIntervalSince1970: Double(i)), value: Double(i))
        }
        let result = downsample(points: points, maxCount: 500)
        // At or below maxCount → pass through unchanged.
        XCTAssertEqual(result.count, 500)
    }

    func testDownsampleHandlesJustAboveMaxCount() {
        let points = (0..<501).map { i in
            ChartPoint(date: Date(timeIntervalSince1970: Double(i)), value: Double(i))
        }
        let result = downsample(points: points, maxCount: 500)
        XCTAssertLessThanOrEqual(result.count, 500)
    }

    // MARK: - Integration: view model uses downsampling

    func testViewModelDownsamplesLargeHistory() async {
        let samples = makeSamples(count: 10_000, interval: 30)
        let repository = InMemoryHistoryRepository(snapshots: samples)
        let purchaseState = PurchaseState()
        purchaseState.update(isPro: true)
        let model = HistoryViewModel(repository: repository, purchaseState: purchaseState)

        model.selectedRange = .days7
        await model.load()

        XCTAssertLessThanOrEqual(model.points.count, 500,
                                 "View model must downsample to at most 500 points")
    }

    // MARK: - Error handling

    func testRepositoryErrorIsCaptured() async {
        struct TestError: Error, LocalizedError {
            var errorDescription: String? { "Test repository failure" }
        }
        let failing = FailingHistoryRepository(error: TestError())
        let purchaseState = PurchaseState()
        purchaseState.update(isPro: true)
        let model = HistoryViewModel(repository: failing, purchaseState: purchaseState)

        await model.load()

        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.points.isEmpty)
        XCTAssertFalse(model.isLoading)
    }

    // MARK: - Formatting

    func testFormatMetricValue() {
        // CPU/Memory/Disk/Battery → percentage
        XCTAssertEqual(formatMetricValue(42, for: .cpu), "42%")
        XCTAssertEqual(formatMetricValue(85.3, for: .memory), "85%")
        XCTAssertEqual(formatMetricValue(99.9, for: .disk), "100%")
        XCTAssertEqual(formatMetricValue(50, for: .battery), "50%")

        // Network → bytes/s
        XCTAssertEqual(formatMetricValue(1024, for: .network), "1.0 KB/s")
        XCTAssertEqual(formatMetricValue(1_048_576, for: .network), "1.0 MB/s")

        // Temperature → Celsius
        XCTAssertEqual(formatMetricValue(36.6, for: .temperature), "37°C")

        // Fan → RPM
        XCTAssertEqual(formatMetricValue(2200, for: .fan), "2200 RPM")
    }
}

// MARK: - Failing repository stub

private struct FailingHistoryRepository: HistoryRepositoryProtocol, @unchecked Sendable {
    let error: Error

    init(error: Error) {
        self.error = error
    }

    func append(_ snapshot: MetricSnapshot) throws {
        throw error
    }

    func samples(since start: Date) throws -> [MetricSnapshot] {
        throw error
    }

    func purge(olderThan cutoff: Date) throws {
        throw error
    }
}
