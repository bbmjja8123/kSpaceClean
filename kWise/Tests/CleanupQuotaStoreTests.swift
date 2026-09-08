// kWise/Tests/CleanupQuotaStoreTests.swift
//
// v2.0 Phase 1 — free-tier quota ledger, checker, and engine truncation.
import XCTest
@testable import kWise

/// Deterministic quota stub for engine tests.
struct StubQuota: CleanupQuotaChecking {
    var remaining: Int64?
    func remainingFreeBytes() async -> Int64? { remaining }
}

final class CleanupQuotaStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "test.quota.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Period key

    func testPeriodKeyUsesCalendarMonth() {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 7
        let date = Calendar(identifier: .gregorian).date(from: components)!
        XCTAssertEqual(FreeQuotaStore.periodKey(for: date), "2026-09")
    }

    func testRecordFreedAccumulatesWithinPeriod() {
        let store = FreeQuotaStore(defaults: defaults)
        store.recordFreed(300)
        store.recordFreed(200)
        XCTAssertEqual(store.consumedBytes(), 500)
        XCTAssertEqual(store.remainingBytes(), FreeQuotaStore.freeQuotaBytes - 500)
    }

    func testRecordFreedIgnoresNonPositive() {
        let store = FreeQuotaStore(defaults: defaults)
        store.recordFreed(0)
        store.recordFreed(-100)
        XCTAssertEqual(store.consumedBytes(), 0)
    }

    func testRemainingNeverGoesNegative() {
        let store = FreeQuotaStore(defaults: defaults)
        store.recordFreed(FreeQuotaStore.freeQuotaBytes * 2)
        XCTAssertEqual(store.remainingBytes(), 0)
    }

    func testNilDefaultsDegradeToZero() {
        let store = FreeQuotaStore(defaults: nil)
        store.recordFreed(1000)
        XCTAssertEqual(store.consumedBytes(), 0)
        XCTAssertEqual(store.remainingBytes(), FreeQuotaStore.freeQuotaBytes)
    }

    func testResetClearsCurrentPeriod() {
        let store = FreeQuotaStore(defaults: defaults)
        store.recordFreed(123)
        store.reset()
        XCTAssertEqual(store.consumedBytes(), 0)
    }

    // MARK: - Checker

    func testCheckerUnlimitedWhenSubscribed() async {
        let checker = CleanupQuotaChecker(
            store: FreeQuotaStore(defaults: defaults),
            isSubscribed: { true }
        )
        let remaining = await checker.remainingFreeBytes()
        XCTAssertNil(remaining, "Subscribed users must not be quota-limited")
    }

    func testCheckerReturnsRemainingForFreeUser() async {
        let store = FreeQuotaStore(defaults: defaults)
        store.recordFreed(1_000)
        let checker = CleanupQuotaChecker(store: store, isSubscribed: { false })
        let remaining = await checker.remainingFreeBytes()
        XCTAssertEqual(remaining, FreeQuotaStore.freeQuotaBytes - 1_000)
    }

    // MARK: - QuotaRecordSink

    func testQuotaRecordSinkFeedsLedger() async {
        let store = FreeQuotaStore(defaults: defaults)
        let sink = QuotaRecordSink(store: store)
        await sink.cleanupDidFinish(CleanupEvent(freedBytes: 4_096, measuredBytes: nil, itemCount: 2))
        XCTAssertEqual(store.consumedBytes(), 4_096)
    }
}

final class CleanupEngineQuotaTests: XCTestCase {

    private func makeFile(sizeBytes: Int) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-\(UUID().uuidString).bin")
        let data = Data(count: sizeBytes)
        try data.write(to: url)
        return url
    }

    private nonisolated func makeEngine(quota: CleanupQuotaChecking?) -> CleanupEngine {
        CleanupEngine(persistence: PersistenceController(inMemory: true), quota: quota)
    }

    func testQuotaTruncatesLargestFirstAndReportsExhausted() async throws {
        let small = try makeFile(sizeBytes: 100)
        let medium = try makeFile(sizeBytes: 500)
        let large = try makeFile(sizeBytes: 1_000)

        // Budget fits only the largest target (greedy largest-first).
        let engine = makeEngine(quota: StubQuota(remaining: 1_000))
        let outcome = try await engine.cleanup(targets: [
            CleanupTarget(url: small, size: 100, risk: .recommended),
            CleanupTarget(url: medium, size: 500, risk: .recommended),
            CleanupTarget(url: large, size: 1_000, risk: .recommended),
        ])

        XCTAssertEqual(outcome.succeeded, [large])
        XCTAssertEqual(Set(outcome.skippedForQuota), Set([small, medium]))
        XCTAssertTrue(outcome.quotaExhausted)
        XCTAssertEqual(outcome.freedBytes, 1_000)
    }

    func testUnlimitedQuotaCleansEverything() async throws {
        let a = try makeFile(sizeBytes: 100)
        let b = try makeFile(sizeBytes: 200)
        // Subscribed → nil remaining.
        let engine = makeEngine(quota: StubQuota(remaining: nil))
        let outcome = try await engine.cleanup(targets: [
            CleanupTarget(url: a, size: 100, risk: .recommended),
            CleanupTarget(url: b, size: 200, risk: .recommended),
        ])
        XCTAssertEqual(outcome.succeeded.count, 2)
        XCTAssertFalse(outcome.quotaExhausted)
    }

    func testZeroQuotaSkipsEverything() async throws {
        let a = try makeFile(sizeBytes: 10)
        let engine = makeEngine(quota: StubQuota(remaining: 0))
        let outcome = try await engine.cleanup(targets: [
            CleanupTarget(url: a, size: 10, risk: .recommended)
        ])
        XCTAssertTrue(outcome.succeeded.isEmpty)
        XCTAssertEqual(outcome.skippedForQuota, [a])
        XCTAssertTrue(outcome.quotaExhausted)
    }

    func testNilQuotaCleansEverything() async throws {
        let a = try makeFile(sizeBytes: 10)
        let engine = makeEngine(quota: nil)
        let outcome = try await engine.cleanup(targets: [
            CleanupTarget(url: a, size: 10, risk: .recommended)
        ])
        XCTAssertEqual(outcome.succeeded.count, 1)
    }

    func testEventSinkFiredAfterStructuredCleanup() async throws {
        let a = try makeFile(sizeBytes: 100)
        let recorder = EventRecorderSink()
        let engine = CleanupEngine(
            persistence: PersistenceController(inMemory: true),
            sinks: [recorder]
        )
        _ = try await engine.cleanup(targets: [
            CleanupTarget(url: a, size: 100, risk: .recommended)
        ])
        // Sinks fire in a detached Task; poll briefly.
        for _ in 0..<50 where recorder.events.isEmpty {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(recorder.events.count, 1)
        XCTAssertEqual(recorder.events.first?.freedBytes, 100)
        XCTAssertEqual(recorder.events.first?.itemCount, 1)
    }

    func testNoSinkEventForFullyFailedRun() async throws {
        let missing = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString)")
        let recorder = EventRecorderSink()
        let engine = CleanupEngine(
            persistence: PersistenceController(inMemory: true),
            sinks: [recorder]
        )
        _ = try await engine.cleanup(targets: [
            CleanupTarget(url: missing, size: 0, risk: .recommended)
        ])
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(recorder.events.isEmpty, "A run with zero successes must not meter freed bytes")
    }
}

/// Test sink that records every event.
final class EventRecorderSink: CleanupEventSink, @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [CleanupEvent] = []
    var events: [CleanupEvent] {
        lock.lock(); defer { lock.unlock() }
        return _events
    }

    func cleanupDidFinish(_ event: CleanupEvent) async {
        lock.lock(); defer { lock.unlock() }
        _events.append(event)
    }
}
