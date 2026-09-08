// kWise/Tests/SegmentBuilderTests.swift
//
// v2.0 Phase 4 — sunburst/treemap segment building: angle conservation,
// depth collapse, and drill-down/selection behaviour.
import XCTest
@testable import kWise

final class SegmentBuilderTests: XCTestCase {

    // MARK: - Fixture helpers

    private func makeLeaf(_ title: String, _ size: Int64, risk: RiskLevel = .recommended) -> ScanResult {
        ScanResult(
            url: URL(fileURLWithPath: "/tmp/\(title)"),
            path: "/tmp/\(title)",
            title: title,
            fileSize: size,
            cleanType: .cache,
            riskLevel: risk
        )
    }

    /// category → subCategory → action → leaf, sized 60% / 30% / 5% / 5%.
    /// The last category's actions are tiny so they collapse into 其他.
    private func makeTree() -> [ScanCategory] {
        func subCategory(_ id: String, _ title: String, leaves: [ScanResult]) -> ScanSubCategory {
            let action = ScanAction(
                actionID: "\(id).action",
                actionType: .cache,
                title: "\(id) action",
                results: leaves
            )
            return ScanSubCategory(
                subCategoryID: id,
                title: title,
                actions: [action]
            )
        }

        let big = ScanCategory(
            categoryID: "big",
            title: "大项",
            subItems: [subCategory("big.sub", "大项子类", leaves: [makeLeaf("a1", 600)])]
        )
        let mid = ScanCategory(
            categoryID: "mid",
            title: "中项",
            subItems: [subCategory("mid.sub", "中项子类", leaves: [makeLeaf("m1", 300)])]
        )
        let small = ScanCategory(
            categoryID: "small",
            title: "小项",
            subItems: [
                subCategory("small.s1", "小项一", leaves: [makeLeaf("s1a", 5)]),
                subCategory("small.s2", "小项二", leaves: [makeLeaf("s2a", 3)]),
            ]
        )
        return [big, mid, small]
    }

    // MARK: - Builder

    func testAngularRangesSumToTwoPi() {
        let segments = SegmentBuilder.flatten(roots: makeTree())
        let topLevel = segments.filter { $0.depth == 0 }
        let totalSweep = topLevel.reduce(0.0) { $0 + ($1.endAngle - $1.startAngle) }
        XCTAssertEqual(totalSweep, 2 * .pi, accuracy: 1e-9,
                       "Top-level angular ranges must cover the full circle exactly")
    }

    func testAngleProportionalToSize() {
        let segments = SegmentBuilder.flatten(roots: makeTree())
        let topLevel = segments.filter { $0.depth == 0 }.sorted { $0.size > $1.size }
        // 600 / 1000 total = 0.6 of the circle.
        let biggest = try? XCTUnwrap(topLevel.first)
        if let biggest {
            XCTAssertEqual(biggest.fraction, 0.6, accuracy: 1e-9)
        }
    }

    func testSizeConservationAcrossDepths() {
        let segments = SegmentBuilder.flatten(roots: makeTree(), maxDepth: 3)
        let tree = makeTree()
        let expected = tree.reduce(Int64(0)) { $0 + $1.totalSize }
        let topLevel = segments.filter { $0.depth == 0 }
        let actual = topLevel.reduce(Int64(0)) { $0 + $1.size }
        XCTAssertEqual(actual, expected, "Top-level sizes must sum to the forest total")
    }

    func testSmallChildrenCollapseIntoBucket() {
        let segments = SegmentBuilder.flatten(roots: makeTree(), maxDepth: 3, minFraction: 0.02)
        let buckets = segments.filter { $0.isCollapsedBucket }
        XCTAssertFalse(buckets.isEmpty, "The 5+3 byte children must collapse into 其他")
        XCTAssertTrue(buckets.allSatisfy { $0.title == "其他" })
        XCTAssertEqual(buckets.reduce(Int64(0)) { $0 + $1.size }, 8)
    }

    func testEmptyForestYieldsNoSegments() {
        XCTAssertTrue(SegmentBuilder.flatten(roots: []).isEmpty)
    }

    func testMaxDepthBoundsRecursion() {
        let segments = SegmentBuilder.flatten(roots: makeTree(), maxDepth: 2)
        XCTAssertTrue(segments.allSatisfy { $0.depth < 2 })
    }
}

@MainActor
final class SpaceMapViewModelTests: XCTestCase {

    private func makeTree() -> [ScanCategory] {
        let leaf = ScanResult(
            url: URL(fileURLWithPath: "/tmp/leaf"),
            path: "/tmp/leaf",
            title: "leaf",
            fileSize: 100,
            cleanType: .cache
        )
        let action = ScanAction(
            actionID: "test.action",
            actionType: .cache,
            title: "action",
            results: [leaf]
        )
        let sub = ScanSubCategory(subCategoryID: "test.sub", title: "sub", actions: [action])
        let category = ScanCategory(categoryID: "test", title: "category", subItems: [sub])
        return [category]
    }

    func testTapDrillsIntoBranchAndBreadcrumbTracks() {
        let vm = SpaceMapViewModel(rootsProvider: makeTree)
        vm.rebuild()
        let category = vm.segments.first { $0.depth == 0 }!
        XCTAssertTrue(category.hasChildren)

        vm.tap(category)
        XCTAssertEqual(vm.focusPath.count, 1)
        XCTAssertEqual(vm.focusPath.first?.title, "category")

        // Drill-in shows the children level.
        vm.popTo(levelID: nil)
        XCTAssertTrue(vm.focusPath.isEmpty)
    }

    func testTapOnLeafDoesNotDrill() {
        let vm = SpaceMapViewModel(rootsProvider: makeTree)
        vm.rebuild()
        let category = vm.segments.first { $0.depth == 0 }!
        vm.tap(category)
        // Leaf at the focused level (result leaf has no children).
        let leaf = vm.segments.first { $0.depth == 0 }!
        XCTAssertFalse(leaf.hasChildren)
        vm.tap(leaf)
        XCTAssertEqual(vm.focusPath.count, 1, "Leaf taps must not push a breadcrumb")
    }

    func testCmdClickTogglesUnderlyingNodeState() {
        let vm = SpaceMapViewModel(rootsProvider: makeTree)
        vm.rebuild()
        let category = vm.segments.first { $0.depth == 0 }!
        XCTAssertNotEqual(category.node.state, .checked)

        vm.tap(category, modifierHeld: true)
        XCTAssertEqual(category.node.state, .checked, "⌘-tap must check the underlying node")

        vm.tap(category, modifierHeld: true)
        XCTAssertNotEqual(category.node.state, .checked)
    }

    func testSelectionPropagatesToResultsTree() {
        let tree = makeTree()
        let vm = SpaceMapViewModel(rootsProvider: { tree })
        vm.rebuild()
        let category = vm.segments.first { $0.depth == 0 }!
        vm.tap(category, modifierHeld: true)

        // Same instance the results tree holds — collectSelected must see it.
        let urls = tree.map { $0.collectSelected() }.flatMap { $0 }
        XCTAssertEqual(urls.count, 1, "Map selection must be visible via the results-tree API")
    }
}
