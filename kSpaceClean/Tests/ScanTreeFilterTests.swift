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
