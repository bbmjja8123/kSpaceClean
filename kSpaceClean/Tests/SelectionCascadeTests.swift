import XCTest
import CoreData
@testable import kSpaceClean

@MainActor
final class SelectionCascadeTests: XCTestCase {

    // MARK: - Helpers

    private func makeFileEntry(context: NSManagedObjectContext,
                               path: String = "/test/file.txt",
                               isRecommended: Bool = true) -> FileEntry {
        let entry = FileEntry(context: context)
        entry.id = UUID()
        entry.path = path
        entry.size = 1024
        entry.category = "document"
        entry.confidence = 0.95
        entry.subCategoryID = 1
        entry.actionID = 1
        entry.isRecommended = isRecommended
        return entry
    }

    // MARK: - ScanResultNode.riskLevel

    func test_scanResultNode_hasRiskLevel() {
        let ctx = createTestContext()
        let node = ScanResultNode(
            fileEntry: makeFileEntry(context: ctx),
            appName: nil, cautionID: nil
        )
        // isRecommended=true, cautionID=nil -> .recommended
        XCTAssertEqual(node.riskLevel, .recommended)
    }

    func test_scanResultNode_cautionRiskLevel() {
        let ctx = createTestContext()
        let node = ScanResultNode(
            fileEntry: makeFileEntry(context: ctx),
            appName: nil, cautionID: 1011
        )
        XCTAssertEqual(node.riskLevel, .caution)
    }

    func test_scanResultNode_optionalRiskLevel() {
        let ctx = createTestContext()
        let node = ScanResultNode(
            fileEntry: makeFileEntry(context: ctx, isRecommended: false),
            appName: nil, cautionID: nil
        )
        // isRecommended=false, cautionID=nil -> .optional
        XCTAssertEqual(node.riskLevel, .optional)
    }

    // MARK: - ActionGroup.riskLevel & checkState

    func test_actionGroup_riskLevel() {
        let ctx = createTestContext()
        let nodes = [
            ScanResultNode(fileEntry: makeFileEntry(context: ctx, path: "/a"), cautionID: nil),
            ScanResultNode(fileEntry: makeFileEntry(context: ctx, path: "/b"), cautionID: nil),
        ]
        let group = ActionGroup(id: 1, title: "Test", items: nodes)
        XCTAssertEqual(group.riskLevel, .recommended)
    }

    func test_actionGroup_checkState_allSelected() {
        let ctx = createTestContext()
        let nodes = [
            ScanResultNode(fileEntry: makeFileEntry(context: ctx, path: "/a"), cautionID: nil),
            ScanResultNode(fileEntry: makeFileEntry(context: ctx, path: "/b"), cautionID: nil),
        ]
        // Both have isRecommended=true -> isSelected defaults to true
        let group = ActionGroup(id: 1, title: "Test", items: nodes)
        XCTAssertEqual(group.checkState, .checked)
    }

    func test_checkState_computedFromSelection() {
        let ctx = createTestContext()
        let nodes = [
            ScanResultNode(fileEntry: makeFileEntry(context: ctx, path: "/a"), cautionID: nil),
            ScanResultNode(fileEntry: makeFileEntry(context: ctx, path: "/b"), cautionID: nil),
        ]
        var group = ActionGroup(id: 1, title: "Test", items: nodes)
        // All selected by default (isRecommended=true)
        XCTAssertEqual(group.checkState, .checked)

        group.items[0].isSelected = false
        XCTAssertEqual(group.checkState, .mixed)

        group.items[1].isSelected = false
        XCTAssertEqual(group.checkState, .unchecked)
    }

    // MARK: - ScanResultGroup.highestRisk

    func test_scanResultGroup_highestRisk() {
        let ctx = createTestContext()
        let nodes = [
            ScanResultNode(fileEntry: makeFileEntry(context: ctx, path: "/a"), cautionID: nil),
        ]
        let actionGroup = ActionGroup(id: 1, title: "Test", isRecommended: true, cautionID: nil, items: nodes)
        let group = ScanResultGroup(id: 1, title: "Group", actionGroups: [actionGroup])
        XCTAssertEqual(group.highestRisk, .recommended)
    }

    func test_scanResultGroup_highestRisk_withCaution() {
        let ctx = createTestContext()
        let safeNodes = [
            ScanResultNode(fileEntry: makeFileEntry(context: ctx, path: "/a"), cautionID: nil),
        ]
        let cautionNodes = [
            ScanResultNode(fileEntry: makeFileEntry(context: ctx, path: "/c"), cautionID: 1011),
        ]
        let safeGroup = ActionGroup(id: 1, title: "Safe", items: safeNodes)
        let cautionGroup = ActionGroup(id: 2, title: "Caution", items: cautionNodes)
        let group = ScanResultGroup(id: 1, title: "Group", actionGroups: [safeGroup, cautionGroup])
        // Should be the highest risk among action groups
        XCTAssertEqual(group.highestRisk, .caution)
    }
}
