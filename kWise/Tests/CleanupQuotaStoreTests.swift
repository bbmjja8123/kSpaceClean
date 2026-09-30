// kWise/Tests/CleanupQuotaStoreTests.swift
//
// P1 T7 — quota retired, buyout gate. The 1 GB monthly free-quota ledger
// (FreeQuotaStore) and its record sink are gone; `CleanupQuotaChecker` is now
// a pure buyout gate: purchased → nil (unlimited), unpurchased → 0.
//
// R5 (binding ruling): the free tier is a *refusal*, not a truncation —
// every selected target lands in `skippedForQuota` and the run reports
// `quotaExhausted`, which surfaces the paywall.
import XCTest
@testable import kWise

/// Deterministic quota stub for engine tests.
struct StubQuota: CleanupQuotaChecking {
    var remaining: Int64?
    func remainingFreeBytes() async -> Int64? { remaining }
}

final class CleanupQuotaStoreTests: XCTestCase {

    // MARK: - CleanupQuotaChecker (buyout gate)

    func testCheckerUnlimitedWhenPurchased() async {
        let checker = CleanupQuotaChecker(hasPurchased: { true })
        let remaining = await checker.remainingFreeBytes()
        XCTAssertNil(remaining, "Purchased users must not be quota-limited")
    }

    func testCheckerRefusesWhenNotPurchased() async {
        // R5: not "1 GB left" — zero. The engine then skips *everything*
        // (refusal) instead of greedily truncating the selection.
        let checker = CleanupQuotaChecker(hasPurchased: { false })
        let remaining = await checker.remainingFreeBytes()
        XCTAssertEqual(remaining, 0)
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

    /// R5 — unpurchased user: remaining 0 → ALL targets go to
    /// `skippedForQuota` (refusal, not truncation down to a 1 GB budget).
    func testUnpurchasedUserIsBlockedNotTruncated() async throws {
        let small = try makeFile(sizeBytes: 100)
        let medium = try makeFile(sizeBytes: 500)
        let large = try makeFile(sizeBytes: 1_000)

        let engine = makeEngine(quota: StubQuota(remaining: 0))
        let outcome = try await engine.cleanup(targets: [
            CleanupTarget(url: small, size: 100, risk: .recommended),
            CleanupTarget(url: medium, size: 500, risk: .recommended),
            CleanupTarget(url: large, size: 1_000, risk: .recommended),
        ])

        XCTAssertTrue(outcome.succeeded.isEmpty, "Refusal must not clean anything")
        XCTAssertEqual(
            Set(outcome.skippedForQuota),
            Set([small, medium, large]),
            "Every selected target must be refused, not partially truncated")
        XCTAssertTrue(outcome.quotaExhausted)
    }

    /// P1 final (M4) — size-0 target (stat-failure scenario) must NOT slip
    /// through the 0-budget gate: the old `used + size <= budget` greedy
    /// comparison kept it (`0 + 0 <= 0`), so an unpurchased user could trash
    /// real files with no paywall signal.
    func testZeroBudgetSkipsSizeZeroTarget() async throws {
        let file = try makeFile(sizeBytes: 4)

        let engine = makeEngine(quota: StubQuota(remaining: 0))
        let outcome = try await engine.cleanup(targets: [
            CleanupTarget(url: file, size: 0, risk: .recommended)
        ])

        XCTAssertTrue(outcome.succeeded.isEmpty, "Unpurchased: a size-0 target must not be cleaned")
        XCTAssertEqual(outcome.skippedForQuota, [file], "size-0 target must count as quota-skipped")
        XCTAssertTrue(outcome.quotaExhausted)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path),
                      "The file must be left untouched")
    }

    /// P1 final (M4) — the streaming surface carries a copy of the same
    /// greedy loop; the 0-budget hard gate must apply there too.
    func testStreamingZeroBudgetLeavesFilesBehind() async throws {
        let file = try makeFile(sizeBytes: 4)

        let engine = makeEngine(quota: StubQuota(remaining: 0))
        for await _ in engine.cleanup(urls: [file], warnHandling: .skip) {
            // Drain the stream; the assertion is on filesystem state.
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path),
                      "Streaming path: unpurchased (0 budget) must not clean the file")
    }

    /// Purchased user: nil remaining → no ceiling, everything cleans.
    func testPurchasedUserHasNoQuotaCeiling() async throws {
        let small = try makeFile(sizeBytes: 100)
        let medium = try makeFile(sizeBytes: 500)
        let large = try makeFile(sizeBytes: 1_000)

        let engine = makeEngine(quota: StubQuota(remaining: nil))
        let outcome = try await engine.cleanup(targets: [
            CleanupTarget(url: small, size: 100, risk: .recommended),
            CleanupTarget(url: medium, size: 500, risk: .recommended),
            CleanupTarget(url: large, size: 1_000, risk: .recommended),
        ])

        XCTAssertEqual(Set(outcome.succeeded), Set([small, medium, large]))
        XCTAssertTrue(outcome.skippedForQuota.isEmpty)
        XCTAssertFalse(outcome.quotaExhausted)
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
