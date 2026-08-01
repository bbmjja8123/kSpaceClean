import XCTest
@testable import kSpaceClean

@MainActor
final class ScanTreeFilterTests: XCTestCase {
    func testHiddenFlagDefaultsToFalse() {
        let result = ScanResult(
            url: URL(fileURLWithPath: "/tmp/foo"),
            path: "/tmp/foo",
            title: "foo",
            fileSize: 1024,
            cleanType: .cache
        )
        let action = ScanAction(
            actionID: "a1",
            actionType: .cache,
            title: "Cache",
            results: [result]
        )
        let sub = ScanSubCategory(subCategoryID: "s1", title: "Xcode", actions: [action])
        let cat = ScanCategory(categoryID: "c1", title: "Dev", subItems: [sub])

        XCTAssertFalse(result.isHiddenByFilter)
        XCTAssertFalse(action.isHiddenByFilter)
        XCTAssertFalse(sub.isHiddenByFilter)
        XCTAssertFalse(cat.isHiddenByFilter)
    }

    func testHiddenFlagMutable() {
        let action = ScanAction(actionID: "a2", actionType: .cache, title: "Cache", results: [])
        action.isHiddenByFilter = true
        XCTAssertTrue(action.isHiddenByFilter)
    }
}

@MainActor
final class ScanResultsViewModelFilterTests: XCTestCase {
    func testApplyFiltersAnnotatesHiddenDoesNotDelete() {
        let big = ScanResult(
            url: URL(fileURLWithPath: "/tmp/big"), path: "/tmp/big",
            title: "big", fileSize: 10_000_000, cleanType: .cache
        )
        let small = ScanResult(
            url: URL(fileURLWithPath: "/tmp/small"), path: "/tmp/small",
            title: "small", fileSize: 100, cleanType: .cache
        )
        let action = ScanAction(
            actionID: "a1", actionType: .cache, title: "Cache", results: [big, small]
        )
        let sub = ScanSubCategory(subCategoryID: "s1", title: "TestApp", actions: [action])
        let cat = ScanCategory(categoryID: "c1", title: "Test", subItems: [sub])

        let options = ScanFilterOptions(minimumSizeBytes: 102_400)  // 100 KB
        let result = ScanResultsViewModel.annotateHidden(
            [cat], options: options, now: Date()
        )

        let resultCat = try! XCTUnwrap(result.first)
        let resultSub = try! XCTUnwrap(resultCat.subItems.first)
        let resultAction = try! XCTUnwrap(resultSub.actions.first)
        XCTAssertEqual(resultAction.results.count, 2,
                       "all results must remain in tree, only isHiddenByFilter changes")
        XCTAssertFalse(resultAction.results[0].isHiddenByFilter) // 10 MB → visible
        XCTAssertTrue(resultAction.results[1].isHiddenByFilter)   // 100 B → hidden
    }

    func testApplyFiltersPreservesSixSkeletons() {
        let cats = (1...6).map { i in
            ScanCategory(categoryID: "c\(i)", title: "Cat \(i)", subItems: [])
        }
        let result = ScanResultsViewModel.annotateHidden(
            cats, options: .default, now: Date()
        )
        XCTAssertEqual(result.count, 6,
                       "empty categories must remain as skeletons, not be deleted")
        XCTAssertTrue(result.allSatisfy { !$0.isHiddenByFilter },
                      "empty skeleton categories must stay VISIBLE, not fold up hidden")
    }
}

@MainActor
final class ScanResultsViewHiddenRenderingTests: XCTestCase {
    func testHiddenNodeVisibilityFollowsShowAllHidden() {
        let hiddenResult = ScanResult(
            url: URL(fileURLWithPath: "/tmp/hidden"),
            path: "/tmp/hidden",
            title: "hidden",
            fileSize: 100,
            cleanType: .cache,
            isHiddenByFilter: true
        )
        let node = RecursiveTreeNode(
            node: hiddenResult,
            level: 0,
            expandedIDs: [],
            showAllHidden: false,
            onToggleExpand: { _ in },
            onToggleSelect: { _ in }
        )
        XCTAssertFalse(node.isVisibleWhenHidden(showAllHidden: false),
                       "hidden node must not render when showAllHidden is off")
        XCTAssertTrue(node.isVisibleWhenHidden(showAllHidden: true),
                      "hidden node must render when showAllHidden is on")
    }

    func testRecursiveTreeNodeEqualityIncludesShowAllHidden() {
        let result = ScanResult(
            url: URL(fileURLWithPath: "/tmp/v"),
            path: "/tmp/v",
            title: "v",
            fileSize: 10_000_000,
            cleanType: .cache
        )
        let hidden = RecursiveTreeNode(
            node: result, level: 0, expandedIDs: [],
            showAllHidden: false, onToggleExpand: { _ in }, onToggleSelect: { _ in }
        )
        let shown = RecursiveTreeNode(
            node: result, level: 0, expandedIDs: [],
            showAllHidden: true, onToggleExpand: { _ in }, onToggleSelect: { _ in }
        )
        XCTAssertNotEqual(hidden, shown,
                          "flipping showAllHidden must invalidate row equality so the tree re-renders")
    }
}
