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
}