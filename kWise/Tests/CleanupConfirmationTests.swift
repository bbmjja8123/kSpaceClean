import XCTest
@testable import kWise

final class CleanupConfirmationTests: XCTestCase {
    func test_cleanupRiskLevel_lowRisk() {
        let items: [RiskLevel] = [.recommended, .optional, .recommended]
        XCTAssertEqual(CleanupConfirmationLevel.from(riskLevels: items, hasWarnItems: false), .low)
    }

    func test_cleanupRiskLevel_hasCaution() {
        let items: [RiskLevel] = [.recommended, .caution, .optional]
        XCTAssertEqual(CleanupConfirmationLevel.from(riskLevels: items, hasWarnItems: false), .medium)
    }

    func test_cleanupRiskLevel_hasDangerous() {
        let items: [RiskLevel] = [.recommended, .dangerous]
        XCTAssertEqual(CleanupConfirmationLevel.from(riskLevels: items, hasWarnItems: false), .high)
    }

    func test_cleanupRiskLevel_hasWarnItems() {
        let items: [RiskLevel] = [.recommended]
        XCTAssertEqual(CleanupConfirmationLevel.from(riskLevels: items, hasWarnItems: true), .high)
    }
}
