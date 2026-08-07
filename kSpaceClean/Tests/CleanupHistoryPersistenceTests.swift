import CoreData
import XCTest
@testable import kSpaceClean

/// Task C1 — Core Data cleanup history stack + 30-day lazy expiry.
final class CleanupHistoryPersistenceTests: XCTestCase {

    private var persistence: PersistenceController!

    override func setUp() {
        super.setUp()
        persistence = PersistenceController(inMemory: true)
    }

    override func tearDown() {
        persistence = nil
        super.tearDown()
    }

    // MARK: - Model

    func testEntityExistsInModel() {
        let entities = persistence.container.managedObjectModel.entitiesByName
        let entity = entities["CleanupHistoryItem"]
        XCTAssertNotNil(entity, "CleanupHistoryItem entity missing from kSpaceClean model")
        XCTAssertEqual(entity?.managedObjectClassName, "CleanupHistoryItem")

        let attributes = Set(entity?.attributesByName.keys.map { $0 } ?? [])
        XCTAssertTrue(attributes.isSuperset(of: ["id", "path", "size", "cleanedAt",
                                                 "bundleID", "categoryID", "riskLevel"]),
                      "Missing attributes, found: \(attributes.sorted())")
    }

    // MARK: - Insert + fetch

    func testInsertHistoryPersistsTargetMetadata() throws {
        let context = persistence.viewContext
        let target = CleanupTarget(url: URL(fileURLWithPath: "/tmp/kspaceclean-a.log"),
                                   size: 4096,
                                   risk: .caution,
                                   bundleID: "com.apple.dt.Xcode",
                                   categoryID: "systemCache")

        persistence.insertHistory(targets: [target], in: context)
        persistence.save(context: context)

        let fetched = persistence.fetchHistory()
        XCTAssertEqual(fetched.count, 1)
        let item = try XCTUnwrap(fetched.first)
        XCTAssertEqual(item.path, "/tmp/kspaceclean-a.log")
        XCTAssertEqual(item.size, 4096)
        XCTAssertEqual(item.bundleID, "com.apple.dt.Xcode")
        XCTAssertEqual(item.categoryID, "systemCache")
        XCTAssertEqual(item.riskLevel, "caution")
        XCTAssertEqual(item.risk, .caution)
    }

    func testFetchHistoryIsNewestFirstAndRespectsLimit() {
        let context = persistence.viewContext
        let base = Date()
        for offset in 0..<5 {
            let target = CleanupTarget(url: URL(fileURLWithPath: "/tmp/file-\(offset)"))
            persistence.insertHistory(targets: [target],
                                      cleanedAt: base.addingTimeInterval(Double(offset) * 60),
                                      in: context)
        }
        persistence.save(context: context)

        let all = persistence.fetchHistory()
        XCTAssertEqual(all.count, 5)
        XCTAssertEqual(all.first?.path, "/tmp/file-4", "Expected newest-first ordering")

        XCTAssertEqual(persistence.fetchHistory(limit: 2).count, 2)
    }

    // MARK: - 30-day lazy expiry

    func testPurgeRemovesOnlyRowsOlderThanRetentionWindow() {
        let context = persistence.viewContext
        let now = Date()

        persistence.insertHistory(targets: [CleanupTarget(url: URL(fileURLWithPath: "/tmp/old"))],
                                  cleanedAt: now.addingTimeInterval(-40 * 86_400),
                                  in: context)
        persistence.insertHistory(targets: [CleanupTarget(url: URL(fileURLWithPath: "/tmp/fresh"))],
                                  cleanedAt: now.addingTimeInterval(-3 * 86_400),
                                  in: context)
        persistence.save(context: context)
        XCTAssertEqual(persistence.fetchHistory().count, 2)

        let deleted = persistence.purgeExpiredHistory(now: now)

        XCTAssertEqual(deleted, 1)
        let remaining = persistence.fetchHistory()
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.path, "/tmp/fresh")
    }

    func testPurgeKeepsRowExactlyAtBoundary() {
        let context = persistence.viewContext
        let now = Date()
        // Exactly 30 days old — the predicate is strictly `<` cutoff, so it survives.
        persistence.insertHistory(targets: [CleanupTarget(url: URL(fileURLWithPath: "/tmp/edge"))],
                                  cleanedAt: CleanupHistoryRetention.cutoff(from: now),
                                  in: context)
        persistence.save(context: context)

        XCTAssertEqual(persistence.purgeExpiredHistory(now: now), 0)
        XCTAssertEqual(persistence.fetchHistory().count, 1)
    }

    func testPurgeIsNoOpOnEmptyStore() {
        XCTAssertEqual(persistence.purgeExpiredHistory(), 0)
    }

    func testPurgeHonoursCustomRetentionWindow() {
        let context = persistence.viewContext
        let now = Date()
        persistence.insertHistory(targets: [CleanupTarget(url: URL(fileURLWithPath: "/tmp/week-old"))],
                                  cleanedAt: now.addingTimeInterval(-10 * 86_400),
                                  in: context)
        persistence.save(context: context)

        XCTAssertEqual(persistence.purgeExpiredHistory(olderThan: 30, now: now), 0)
        XCTAssertEqual(persistence.purgeExpiredHistory(olderThan: 7, now: now), 1)
    }

    func testIsExpiredMatchesPurgeBehaviour() {
        let context = persistence.viewContext
        let now = Date()
        persistence.insertHistory(targets: [CleanupTarget(url: URL(fileURLWithPath: "/tmp/x"))],
                                  cleanedAt: now.addingTimeInterval(-31 * 86_400),
                                  in: context)
        persistence.save(context: context)

        let item = persistence.fetchHistory().first
        XCTAssertEqual(item?.isExpired(asOf: now), true)
    }

    // MARK: - Delete all

    func testDeleteAllHistoryClearsStore() {
        let context = persistence.viewContext
        for index in 0..<3 {
            persistence.insertHistory(targets: [CleanupTarget(url: URL(fileURLWithPath: "/tmp/\(index)"))],
                                      in: context)
        }
        persistence.save(context: context)

        XCTAssertEqual(persistence.deleteAllHistory(), 3)
        XCTAssertTrue(persistence.fetchHistory().isEmpty)
    }

    // MARK: - Isolation

    func testInMemoryControllersDoNotShareState() {
        let context = persistence.viewContext
        persistence.insertHistory(targets: [CleanupTarget(url: URL(fileURLWithPath: "/tmp/only-here"))],
                                  in: context)
        persistence.save(context: context)

        let other = PersistenceController(inMemory: true)
        XCTAssertTrue(other.fetchHistory().isEmpty)
    }

    // MARK: - RiskLevel bridging

    func testRiskLevelPersistenceKeyRoundTrips() {
        for level in RiskLevel.allCases {
            XCTAssertEqual(RiskLevel(persistenceKey: level.persistenceKey), level)
        }
        XCTAssertNil(RiskLevel(persistenceKey: "bogus"))
        XCTAssertNil(RiskLevel(persistenceKey: nil))
    }

    func testUnknownRiskStringFallsBackToRecommended() {
        let context = persistence.viewContext
        let item = CleanupHistoryItem(context: context)
        item.id = UUID()
        item.path = "/tmp/legacy"
        item.cleanedAt = Date()
        item.riskLevel = "not-a-level"
        persistence.save(context: context)

        XCTAssertEqual(persistence.fetchHistory().first?.risk, .recommended)
    }

    // MARK: - Cleanup DTOs

    func testCleanupOutcomeAggregates() {
        let ok = URL(fileURLWithPath: "/tmp/ok")
        let bad = URL(fileURLWithPath: "/tmp/bad")
        let outcome = CleanupOutcome(succeeded: [ok],
                                     failed: [CleanupFailure(url: bad, reason: "permission denied")],
                                     skipped: [],
                                     freedBytes: 2048)

        XCTAssertEqual(outcome.successCount, 1)
        XCTAssertEqual(outcome.freedBytes, 2048)
        XCTAssertFalse(outcome.isFullySuccessful)
        XCTAssertTrue(CleanupOutcome.empty.isFullySuccessful)
    }

    func testDefaultCleanupConfiguration() {
        let config = CleanupConfiguration.default
        XCTAssertEqual(config.warnHandling, .skip)
        XCTAssertTrue(config.moveToTrash)
        XCTAssertTrue(config.recordHistory)
        XCTAssertEqual(config.retentionDays, 30)
    }
}
