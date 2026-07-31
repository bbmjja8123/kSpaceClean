import XCTest
@testable import kFresh

final class AuditLoggerTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() async throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("audit-\(UUID().uuidString).jsonl")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    func testLogEventPersistsToFile() async throws {
        let logger = try AuditLogger(logURL: tempURL)
        let event = AuditEvent(
            timestamp: Date(),
            action: "trash",
            bundleID: "com.example.test",
            paths: ["/Applications/Test.app"],
            status: "success",
            errorMessage: nil
        )
        try await logger.log(event)

        let events = await logger.recentEvents(limit: 10)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.bundleID, "com.example.test")
    }

    func testLogFailureCapturesErrorMessage() async throws {
        let logger = try AuditLogger(logURL: tempURL)
        let event = AuditEvent(
            timestamp: Date(),
            action: "trash",
            bundleID: "com.example.fail",
            paths: ["/Applications/Fail.app"],
            status: "failure",
            errorMessage: "permission denied"
        )
        try await logger.log(event)

        let events = await logger.recentEvents(limit: 10)
        XCTAssertEqual(events.first?.errorMessage, "permission denied")
    }

    /// Covers the JSONL append branch (`FileHandle` + `seekToEnd` + `write`)
    /// and the round-trip multi-event format: newest-first order, accurate limit.
    /// The single-event tests only exercise the createFile first-write path.
    func testAppendMultipleEventsReturnsInReverseChronologicalOrder() async throws {
        let logger = try AuditLogger(logURL: tempURL)

        // Log three events sequentially. Each event carries a unique bundleID
        // so we can assert ordering strictly by content rather than timestamps.
        let bundleIDs = ["com.example.first", "com.example.second", "com.example.third"]
        for bundleID in bundleIDs {
            let event = AuditEvent(
                timestamp: Date(),
                action: "trash",
                bundleID: bundleID,
                paths: ["/Applications/\(bundleID).app"],
                status: "success",
                errorMessage: nil
            )
            try await logger.log(event)
        }

        // newest first: third, second, first
        let events = await logger.recentEvents(limit: 10)
        XCTAssertEqual(events.count, 3, "All three events should round-trip via the JSONL append branch")
        XCTAssertEqual(events.map(\.bundleID), ["com.example.third", "com.example.second", "com.example.first"])

        // Limit cuts the oldest entries, preserves newest-first ordering
        let newestTwo = await logger.recentEvents(limit: 2)
        XCTAssertEqual(newestTwo.map(\.bundleID), ["com.example.third", "com.example.second"])
    }
}