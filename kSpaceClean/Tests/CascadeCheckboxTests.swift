import XCTest
@testable import kSpaceClean

final class CascadeCheckboxTests: XCTestCase {
    func testParentOn_RecommendedAutoSelects() {
        let recAction = ScanAction(
            actionID: "a1",
            actionType: .cache,
            title: "缓存",
            recommend: true,
            riskLevel: .recommended
        )
        recAction.results = [makeResult(riskLevel: .recommended)]
        let cauAction = ScanAction(
            actionID: "a2",
            actionType: .log,
            title: "日志",
            recommend: false,
            riskLevel: .caution
        )
        cauAction.results = [makeResult(riskLevel: .caution)]
        let sub = ScanSubCategory(
            subCategoryID: "s1",
            title: "微信",
            actions: [recAction, cauAction],
            showAction: true
        )

        sub.setState(.on)

        XCTAssertEqual(recAction.state, .on)
        XCTAssertEqual(cauAction.state, .off)
    }

    func testParentOff_AllChildrenOff() {
        let recAction = ScanAction(
            actionID: "a1",
            actionType: .cache,
            title: "缓存",
            recommend: true,
            riskLevel: .recommended
        )
        recAction.results = [makeResult(riskLevel: .recommended)]
        let sub = ScanSubCategory(
            subCategoryID: "s1",
            title: "微信",
            state: .on,
            actions: [recAction],
            showAction: true
        )
        recAction.setState(.on)

        sub.setState(.off)

        XCTAssertEqual(recAction.state, .off)
    }

    func testChildChange_AggregatesToParentMixed() {
        let r1 = makeResult(riskLevel: .recommended)
        let r2 = makeResult(riskLevel: .caution)
        let action = ScanAction(
            actionID: "a1",
            actionType: .cache,
            title: "缓存",
            results: [r1, r2],
            recommend: true,
            riskLevel: .recommended
        )

        r1.setState(.on)
        action.refreshState()

        XCTAssertEqual(action.state, .mixed)
    }

    func testAllChildrenSame_ParentAggregates() {
        let r1 = makeResult(riskLevel: .recommended)
        let r2 = makeResult(riskLevel: .recommended)
        let action = ScanAction(
            actionID: "a1",
            actionType: .cache,
            title: "缓存",
            results: [r1, r2],
            recommend: true,
            riskLevel: .recommended
        )

        r1.setState(.on)
        r2.setState(.on)
        action.refreshState()

        XCTAssertEqual(action.state, .on)
    }

    func testDangerousManualCheck_Allowed() {
        let result = makeResult(riskLevel: .dangerous)

        result.setState(.on)

        XCTAssertEqual(result.state, .on)
    }

    private func makeResult(riskLevel: RiskLevel) -> ScanResult {
        ScanResult(
            url: URL(fileURLWithPath: "/tmp/test"),
            path: "/tmp/test",
            title: "test",
            fileSize: 1_024,
            cleanType: .cache,
            riskLevel: riskLevel
        )
    }
}
