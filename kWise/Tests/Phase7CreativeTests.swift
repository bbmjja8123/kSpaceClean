// kWise/Tests/Phase7CreativeTests.swift
//
// v2.0 Phase 7 — forecast engine, streak/achievements, report generation,
// Core Data runID/actionKind migration, timeline grouping.
import XCTest
import CoreData
@testable import kWise

final class DiskForecastEngineTests: XCTestCase {

    private func samples(dailyGrowthBytes: Int64, days: Int, capacity: Int64 = 500_000_000_000) -> [DiskSample] {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        return (0..<days).map { i in
            let day = calendar.date(byAdding: .day, value: i, to: start)!
            return DiskSample(
                day: DiskSampleStore.dayKey(for: day, calendar: calendar),
                usedBytes: 100_000_000_000 + dailyGrowthBytes * Int64(i),
                totalBytes: capacity
            )
        }
    }

    func testSyntheticRampPredictsDaysToFull() {
        // 1 GB/day growth, 400 GB remaining → ~400 days… capped at 365 → stable.
        let result = DiskForecastEngine.forecast(samples: samples(dailyGrowthBytes: 5_000_000_000, days: 30))
        if case .filling(let days, let r2) = result {
            XCTAssertGreaterThan(days, 0)
            XCTAssertLessThanOrEqual(days, 365)
            XCTAssertGreaterThanOrEqual(r2, 0.5)
        } else {
            XCTFail("A clean ramp must produce a filling forecast, got \(result)")
        }
    }

    func testNoisyDataReadsStable() {
        // Alternating +2 GB / -2 GB → no meaningful trend, r² low.
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 8, day: 1))!
        let noisy = (0..<30).map { i -> DiskSample in
            let day = calendar.date(byAdding: .day, value: i, to: start)!
            let delta = i % 2 == 0 ? 2_000_000_000 : -2_000_000_000
            return DiskSample(
                day: DiskSampleStore.dayKey(for: day, calendar: calendar),
                usedBytes: 100_000_000_000 + Int64(delta),
                totalBytes: 500_000_000_000
            )
        }
        XCTAssertEqual(DiskForecastEngine.forecast(samples: noisy), .stable)
    }

    func testFewerThanTwoSamplesIsInsufficient() {
        XCTAssertEqual(
            DiskForecastEngine.forecast(samples: [DiskSample(day: "2026-09-01", usedBytes: 1, totalBytes: 2)]),
            .insufficientData
        )
        XCTAssertEqual(DiskForecastEngine.forecast(samples: []), .insufficientData)
    }

    func testFlatUsageIsStable() {
        XCTAssertEqual(
            DiskForecastEngine.forecast(samples: samples(dailyGrowthBytes: 0, days: 30)),
            .stable
        )
    }

    func testSampleStoreUpsertAndRingCap() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("samples-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = DiskSampleStore(fileURL: url)

        store.upsert(usedBytes: 100, totalBytes: 500)
        store.upsert(usedBytes: 150, totalBytes: 500)  // Same day → replaces
        XCTAssertEqual(store.load().count, 1)
        XCTAssertEqual(store.load().first?.usedBytes, 150)

        // Ring cap: 500 synthetic past days.
        for i in 0..<450 {
            store.upsert(usedBytes: Int64(i), totalBytes: 500,
                         now: Calendar.current.date(byAdding: .day, value: -(i + 1), to: Date())!)
        }
        XCTAssertLessThanOrEqual(store.load().count, DiskSampleStore.maxSamples)
    }
}

final class StreakAchievementTests: XCTestCase {

    private func state() -> StreakState { StreakState() }

    func testConsecutiveDaysExtendStreak() {
        var s = state()
        StreakLogic.recordCleanup(&s, freedBytes: 100, on: "2026-09-06")
        StreakLogic.recordCleanup(&s, freedBytes: 100, on: "2026-09-07")
        XCTAssertEqual(s.currentStreak, 2)
        XCTAssertEqual(s.longestStreak, 2)
        XCTAssertEqual(s.totalCleanups, 2)
    }

    func testSameDayDoesNotInflate() {
        var s = state()
        StreakLogic.recordCleanup(&s, freedBytes: 100, on: "2026-09-07")
        StreakLogic.recordCleanup(&s, freedBytes: 200, on: "2026-09-07")
        XCTAssertEqual(s.currentStreak, 1)
        XCTAssertEqual(s.totalCleanups, 2)
        XCTAssertEqual(s.totalFreedBytes, 300)
    }

    func testGapResetsStreak() {
        var s = state()
        StreakLogic.recordCleanup(&s, freedBytes: 100, on: "2026-09-01")
        StreakLogic.recordCleanup(&s, freedBytes: 100, on: "2026-09-02")
        StreakLogic.recordCleanup(&s, freedBytes: 100, on: "2026-09-05")
        XCTAssertEqual(s.currentStreak, 1)
        XCTAssertEqual(s.longestStreak, 2)
    }

    func testAchievementsUnlockOnce() {
        var s = state()
        StreakLogic.recordCleanup(&s, freedBytes: 2_000_000_000, on: "2026-09-07")
        let first = AchievementEngine.evaluate(s)
        XCTAssertTrue(first.contains { $0.id == "first.cleanup" })
        XCTAssertTrue(first.contains { $0.id == "freed.1g" })

        s.unlockedBadgeIDs += first.map(\.id)
        StreakLogic.recordCleanup(&s, freedBytes: 1_000, on: "2026-09-07")
        let second = AchievementEngine.evaluate(s)
        XCTAssertTrue(second.isEmpty, "Already-unlocked badges must never re-emit")
    }

    func testStreakBadgesAtBoundaries() {
        var s = state()
        var day = 1
        func nextDay() -> String { day += 1; return String(format: "2026-09-%02d", day) }
        for _ in 0..<3 { StreakLogic.recordCleanup(&s, freedBytes: 1, on: nextDay()) }
        XCTAssertTrue(AchievementEngine.evaluate(s).contains { $0.id == "streak.3" })
    }

    func testStreakSinkPersistsAndMirrorsWidget() async {
        let suite = "test.streak.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)
        defaults?.removePersistentDomain(forName: suite)
        defer { defaults?.removePersistentDomain(forName: suite) }

        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sink-snap-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: snapshotURL) }

        let sink = StreakSink(
            store: StreakStore(defaults: defaults),
            snapshotStore: WidgetSnapshotStore(fileURL: snapshotURL)
        )
        await sink.cleanupDidFinish(CleanupEvent(freedBytes: 500, measuredBytes: nil, itemCount: 1))
        let state = StreakStore(defaults: defaults).load()
        XCTAssertEqual(state.totalCleanups, 1)
        XCTAssertEqual(state.currentStreak, 1)
        XCTAssertEqual(WidgetSnapshotStore(fileURL: snapshotURL).read()?.streak?.currentStreak, 1)
    }
}

final class TimelineMigrationTests: XCTestCase {

    @MainActor
    func testInsertHistoryPopulatesRunIDAndKind() async {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.newBackgroundContext()
        let runID = UUID()
        let target = CleanupTarget(url: URL(fileURLWithPath: "/tmp/x"), size: 10, risk: .recommended)
        await context.perform { [persistence] in
            persistence.insertHistory(targets: [target], runID: runID,
                                      actionKind: CleanupHistoryItem.ActionKind.cleanup,
                                      in: context)
            persistence.save(context: context)
        }

        let rows = persistence.fetchHistory(limit: 0)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.runID, runID)
        XCTAssertEqual(rows.first?.actionKind, "cleanup")
        XCTAssertNil(rows.first?.restoredAt)
        XCTAssertFalse(rows.first?.isRestored ?? true)
    }

    @MainActor
    func testEngineGroupsStructuredRunByRunID() async throws {
        let file1 = FileManager.default.temporaryDirectory.appendingPathComponent("t1-\(UUID()).txt")
        let file2 = FileManager.default.temporaryDirectory.appendingPathComponent("t2-\(UUID()).txt")
        try "a".write(to: file1, atomically: true, encoding: .utf8)
        try "b".write(to: file2, atomically: true, encoding: .utf8)

        let persistence = PersistenceController(inMemory: true)
        let engine = CleanupEngine(persistence: persistence)
        _ = try await engine.cleanup(targets: [
            CleanupTarget(url: file1, size: 1, risk: .recommended),
            CleanupTarget(url: file2, size: 1, risk: .recommended),
        ])

        let rows = persistence.fetchHistory(limit: 0)
        XCTAssertEqual(rows.count, 2)
        let runIDs = Set(rows.compactMap(\.runID))
        XCTAssertEqual(runIDs.count, 1, "One cleanup call → one runID → one timeline event")

        let events = TimelineViewModel.group(rows)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.itemCount, 2)
    }
}

@MainActor
final class ReportGeneratorTests: XCTestCase {

    func testEmptyHistoryProducesHonestZeros() {
        let report = ReportGenerator.generate(
            history: [], streak: StreakState(), samples: []
        )
        XCTAssertEqual(report.totalFreedBytes, 0)
        XCTAssertEqual(report.totalCleanups, 0)
        XCTAssertTrue(report.topCategories.isEmpty)
        XCTAssertEqual(report.forecast, .insufficientData)
    }

    func testWeeklyBucketsAggregate() {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.viewContext
        // Two rows today.
        for i in 0..<2 {
            let item = CleanupHistoryItem(context: context)
            item.id = UUID()
            item.path = "/tmp/\(i)"
            item.size = 1_000
            item.cleanedAt = Date()
            item.riskLevel = "recommended"
            item.categoryID = "system.cache"
        }
        persistence.save(context: context)

        let report = ReportGenerator.generate(
            history: persistence.fetchHistory(limit: 0),
            streak: StreakState(),
            samples: []
        )
        XCTAssertEqual(report.totalCleanups, 2)
        XCTAssertEqual(report.totalFreedBytes, 2_000)
        XCTAssertEqual(report.topCategories.first?.title, "系统缓存")
        XCTAssertEqual(report.weekly.count, 4)
    }
}
