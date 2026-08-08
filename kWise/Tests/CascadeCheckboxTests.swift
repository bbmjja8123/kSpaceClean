import XCTest
@testable import kWise

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

    /// Regression for C4 — a `.dangerous` leaf must NOT be auto-selected when
    /// its grandparent (Category) flips ON. The whole point of the cascade
    /// fix is to make `showAction == false` cascades respect
    /// `riskLevel.defaultChecked` so a Category→SubCategory→Result tree
    /// containing a `.dangerous` file does not auto-trash the file.
    func testParentOn_DangerousSubcategoryLeafNotAutoSelected() {
        // Build a sub-category with `showAction == false` (direct results)
        // whose single result is classified `.dangerous`.
        let dangerousResult = makeResult(riskLevel: .dangerous)
        let sub = ScanSubCategory(
            subCategoryID: "sub1",
            title: "Dangerous sub",
            directResults: [dangerousResult],
            showAction: false,
            riskLevel: .caution
        )
        let category = ScanCategory(
            categoryID: "cat1",
            title: "Container",
            subItems: [sub],
            riskLevel: .recommended
        )

        // Flip the category ON. The sub-category has riskLevel=.caution
        // (defaultChecked == false), so the C4 fix deliberately leaves it
        // OFF — and the .dangerous leaf must stay OFF regardless.
        category.setState(.on)

        XCTAssertEqual(category.state, .on)
        XCTAssertEqual(sub.state, .off,
                       "C4 regression: a .caution sub-category must NOT auto-mirror the parent on .on (its riskLevel.defaultChecked is false)")
        XCTAssertEqual(dangerousResult.state, .off,
                       "C4 regression: a .dangerous leaf must NOT be auto-selected when its ancestor flips ON")
    }

    /// Regression for C4 — same rule applies to the showAction==true path:
    /// a `.dangerous` `ScanAction` is not auto-selected when its sub-category
    /// flips ON, even if its `recommend` flag is true. The gate is
    /// `riskLevel.defaultChecked`, which is `true` only for `.recommended`.
    func testParentOn_DangerousActionNotAutoSelected() {
        let dangerousAction = ScanAction(
            actionID: "a1",
            actionType: .cache,
            title: "Risky cleanup",
            recommend: true,
            riskLevel: .dangerous
        )
        let recAction = ScanAction(
            actionID: "a2",
            actionType: .cache,
            title: "Safe cleanup",
            recommend: true,
            riskLevel: .recommended
        )
        let sub = ScanSubCategory(
            subCategoryID: "sub1",
            title: "Sub",
            actions: [dangerousAction, recAction],
            showAction: true
        )

        sub.setState(.on)

        XCTAssertEqual(dangerousAction.state, .off,
                       "C4 regression: a .dangerous action with recommend=true must NOT auto-select")
        XCTAssertEqual(recAction.state, .on)
    }

    /// Regression for the final-review I1 finding: a `.dangerous` RESULT inside a
    /// `.recommended` ACTION must not be auto-selected when the action flips ON —
    /// neither via the sub-category cascade nor via a manual action-level toggle.
    func testParentOn_DangerousResultInRecommendedActionNotSelected() {
        let safe = makeResult(riskLevel: .recommended)
        let risky = makeResult(riskLevel: .dangerous)
        let action = ScanAction(
            actionID: "a1",
            actionType: .cache,
            title: "缓存",
            results: [safe, risky],
            recommend: true,
            riskLevel: .recommended
        )
        let sub = ScanSubCategory(
            subCategoryID: "sub1",
            title: "Sub",
            actions: [action],
            showAction: true
        )

        // Path 1: cascade-ON — sub-category flips ON, action auto-selects.
        sub.setState(.on)

        XCTAssertEqual(action.state, .on)
        XCTAssertEqual(safe.state, .on,
                       "a .recommended result inside a .recommended action auto-selects")
        XCTAssertEqual(risky.state, .off,
                       "I1 regression: a .dangerous result must NOT auto-select when its action flips ON")

        // Path 2: manual-ON — user clicks the action row directly.
        let action2 = ScanAction(
            actionID: "a2",
            actionType: .cache,
            title: "缓存",
            results: [makeResult(riskLevel: .dangerous)],
            recommend: true,
            riskLevel: .recommended
        )
        action2.setState(.on)

        XCTAssertEqual(action2.state, .on)
        XCTAssertEqual(action2.results.first?.state, .off,
                       "I1 regression: manual action toggle must respect the per-result risk gate")
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
