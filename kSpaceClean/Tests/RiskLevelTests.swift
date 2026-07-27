import XCTest
@testable import kSpaceClean

final class RiskLevelTests: XCTestCase {
    func test_riskLevel_rawValues() {
        XCTAssertEqual(RiskLevel.recommended.rawValue, 0)
        XCTAssertEqual(RiskLevel.optional.rawValue, 1)
        XCTAssertEqual(RiskLevel.caution.rawValue, 2)
        XCTAssertEqual(RiskLevel.dangerous.rawValue, 3)
    }

    func test_riskLevel_allCases() {
        XCTAssertEqual(RiskLevel.allCases.count, 4)
    }

    func test_checkState_threeStates() {
        let states: [CheckState] = [.unchecked, .mixed, .checked]
        XCTAssertEqual(states.count, 3)
    }

    func test_checkState_fromBools() {
        XCTAssertTrue(CheckState.from(selected: true, total: 5, selectedCount: 5) == .checked)
        XCTAssertTrue(CheckState.from(selected: false, total: 5, selectedCount: 0) == .unchecked)
        XCTAssertTrue(CheckState.from(selected: false, total: 5, selectedCount: 2) == .mixed)
    }

    func test_recommendPolicy_defaultIsDefault() {
        let policy = RecommendPolicy.default
        XCTAssertEqual(policy, .default)
    }
}
