import XCTest
@testable import kSpaceClean

final class RiskLevelTests: XCTestCase {
    /// Brief §Step 1: raw values must increase monotonically.
    func testRiskLevelOrder() {
        XCTAssertLessThan(RiskLevel.recommended.rawValue, RiskLevel.optional.rawValue)
        XCTAssertLessThan(RiskLevel.optional.rawValue, RiskLevel.caution.rawValue)
        XCTAssertLessThan(RiskLevel.caution.rawValue, RiskLevel.dangerous.rawValue)
    }

    /// Brief §Step 1: only `.recommended` is selected by default.
    func testDefaultCheckedStates() {
        XCTAssertTrue(RiskLevel.recommended.defaultChecked)
        XCTAssertFalse(RiskLevel.optional.defaultChecked)
        XCTAssertFalse(RiskLevel.caution.defaultChecked)
        XCTAssertFalse(RiskLevel.dangerous.defaultChecked)
    }

    /// Brief §Step 1: only `.dangerous` requires double confirmation.
    func testRequiresDoubleConfirm() {
        XCTAssertFalse(RiskLevel.recommended.requiresDoubleConfirm)
        XCTAssertFalse(RiskLevel.optional.requiresDoubleConfirm)
        XCTAssertFalse(RiskLevel.caution.requiresDoubleConfirm)
        XCTAssertTrue(RiskLevel.dangerous.requiresDoubleConfirm)
    }

    // MARK: - Extended coverage (preserves tests from prior RiskLevel pass)

    func test_riskLevel_rawValues() {
        XCTAssertEqual(RiskLevel.recommended.rawValue, 0)
        XCTAssertEqual(RiskLevel.optional.rawValue, 1)
        XCTAssertEqual(RiskLevel.caution.rawValue, 2)
        XCTAssertEqual(RiskLevel.dangerous.rawValue, 3)
    }

    func test_riskLevel_allCases() {
        XCTAssertEqual(RiskLevel.allCases.count, 4)
    }

    func test_labelAndIcon_notEmpty() {
        for level in RiskLevel.allCases {
            XCTAssertFalse(level.label.isEmpty, "label empty for \(level)")
            XCTAssertFalse(level.iconName.isEmpty, "iconName empty for \(level)")
        }
    }

    func test_checkState_threeStates() {
        let states: [CheckState] = [.unchecked, .mixed, .checked]
        XCTAssertEqual(states.count, 3)
    }

    func test_checkState_fromBools() {
        XCTAssertEqual(CheckState.from(selected: true, total: 5, selectedCount: 5), .checked)
        XCTAssertEqual(CheckState.from(selected: false, total: 5, selectedCount: 0), .unchecked)
        XCTAssertEqual(CheckState.from(selected: false, total: 5, selectedCount: 2), .mixed)
    }

    func test_recommendPolicy_defaultIsDefault() {
        let policy = RecommendPolicy.default
        XCTAssertEqual(policy, .default)
    }
}