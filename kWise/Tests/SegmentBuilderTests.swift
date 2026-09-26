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

    /// category → subCategory → action → leaf, sized 600 / 300 / 5 / 3.
    /// The last category's leaves are tiny so the category collapses into 其他.
    ///
    /// `totalSize` is a *stored* property on `ScanCategory` / `ScanSubCategory`
    /// / `ScanAction` (only `ScanResult` derives it), so every level has to be
    /// sized explicitly here — omitting it leaves the node at 0 and the map's
    /// `filter { $0.totalSize > 0 }` drops the whole forest.
    private func makeTree() -> [ScanCategory] {
        func subCategory(_ id: String, _ title: String, leaves: [ScanResult]) -> ScanSubCategory {
            let size = leaves.reduce(Int64(0)) { $0 + $1.totalSize }
            let action = ScanAction(
                actionID: "\(id).action",
                actionType: .cache,
                title: "\(id) action",
                totalSize: size,
                results: leaves
            )
            return ScanSubCategory(
                subCategoryID: id,
                title: title,
                totalSize: size,
                actions: [action]
            )
        }

        func category(_ id: String, _ title: String, subs: [ScanSubCategory]) -> ScanCategory {
            ScanCategory(
                categoryID: id,
                title: title,
                totalSize: subs.reduce(Int64(0)) { $0 + $1.totalSize },
                subItems: subs
            )
        }

        let big = category("big", "大项", subs: [subCategory("big.sub", "大项子类", leaves: [makeLeaf("a1", 600)])])
        let mid = category("mid", "中项", subs: [subCategory("mid.sub", "中项子类", leaves: [makeLeaf("m1", 300)])])
        let small = category("small", "小项", subs: [
            subCategory("small.s1", "小项一", leaves: [makeLeaf("s1a", 5)]),
            subCategory("small.s2", "小项二", leaves: [makeLeaf("s2a", 3)]),
        ])
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

    func testAngleProportionalToSize() throws {
        let tree = makeTree()
        let total = tree.reduce(Int64(0)) { $0 + $1.totalSize }
        let segments = SegmentBuilder.flatten(roots: tree)
        let topLevel = segments.filter { $0.depth == 0 }.sorted { $0.size > $1.size }
        // The biggest wedge must occupy exactly its share of the total —
        // derived from the fixture rather than a hardcoded ratio, so the
        // assertion stays honest if the fixture sizes ever change.
        let biggest = try XCTUnwrap(topLevel.first)
        XCTAssertEqual(biggest.fraction, 600.0 / Double(total), accuracy: 1e-9)
        XCTAssertEqual(biggest.size, 600)
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
        // `totalSize` is stored, not derived, on all three intermediate
        // levels — size each one or `rebuild()` filters the forest to empty
        // and every `segments.first!` below crashes.
        let action = ScanAction(
            actionID: "test.action",
            actionType: .cache,
            title: "action",
            totalSize: leaf.totalSize,
            results: [leaf]
        )
        let sub = ScanSubCategory(
            subCategoryID: "test.sub",
            title: "sub",
            totalSize: action.totalSize,
            actions: [action]
        )
        let category = ScanCategory(
            categoryID: "test",
            title: "category",
            totalSize: sub.totalSize,
            subItems: [sub]
        )
        return [category]
    }

    /// Builds a view model over a **stable** forest.
    ///
    /// The provider must return the same instances across calls — production
    /// binds `{ scanResultsViewModel.categories }` (a persistent array), and
    /// `focusedNode()` looks nodes up by `id`. A factory closure like
    /// `rootsProvider: makeTree` mints fresh UUIDs on every `rebuild()`, so
    /// the lookup misses and the map silently falls back to the root level.
    private func makeViewModel() -> (SpaceMapViewModel, [ScanCategory]) {
        let tree = makeTree()
        return (SpaceMapViewModel(rootsProvider: { tree }), tree)
    }

    func testTapDrillsIntoBranchAndBreadcrumbTracks() throws {
        let (vm, _) = makeViewModel()
        vm.rebuild()
        let category = try XCTUnwrap(vm.segments.first { $0.depth == 0 })
        XCTAssertTrue(category.hasChildren)

        vm.tap(category)
        XCTAssertEqual(vm.focusPath.count, 1)
        XCTAssertEqual(vm.focusPath.first?.title, "category")

        // Drill-in shows the children level.
        vm.popTo(levelID: nil)
        XCTAssertTrue(vm.focusPath.isEmpty)
    }

    func testTapOnLeafDoesNotDrill() throws {
        let (vm, _) = makeViewModel()
        vm.rebuild()
        // A result leaf only sits at the focused level after drilling all
        // three intermediate rows — category → sub → action → leaf. Tapping
        // the sub or action row is not a leaf tap (both still have children).
        let category = try XCTUnwrap(vm.segments.first { $0.depth == 0 })
        vm.tap(category)
        let sub = try XCTUnwrap(vm.segments.first { $0.depth == 0 })
        vm.tap(sub)
        let action = try XCTUnwrap(vm.segments.first { $0.depth == 0 })
        vm.tap(action)

        let leaf = try XCTUnwrap(vm.segments.first { $0.depth == 0 })
        XCTAssertFalse(leaf.hasChildren, "Result leaf must have no children")

        let breadcrumbCount = vm.focusPath.count
        vm.tap(leaf)
        XCTAssertEqual(vm.focusPath.count, breadcrumbCount,
                       "Leaf taps must not push a breadcrumb")
    }

    func testCmdClickTogglesUnderlyingNodeState() throws {
        let (vm, _) = makeViewModel()
        vm.rebuild()
        let category = try XCTUnwrap(vm.segments.first { $0.depth == 0 })
        XCTAssertNotEqual(category.node.state, .checked)

        vm.tap(category, modifierHeld: true)
        XCTAssertEqual(category.node.state, .checked, "⌘-tap must check the underlying node")

        vm.tap(category, modifierHeld: true)
        XCTAssertNotEqual(category.node.state, .checked)
    }

    func testSelectionPropagatesToResultsTree() throws {
        let (vm, tree) = makeViewModel()
        vm.rebuild()
        let category = try XCTUnwrap(vm.segments.first { $0.depth == 0 })
        vm.tap(category, modifierHeld: true)

        // Same instance the results tree holds — collectSelected must see it.
        let urls = tree.map { $0.collectSelected() }.flatMap { $0 }
        XCTAssertEqual(urls.count, 1, "Map selection must be visible via the results-tree API")
    }

    /// Regression: `bindFolderRoot` used to omit the root's `totalSize`, so
    /// `rebuild()`'s `filter { $0.totalSize > 0 }` dropped the whole forest
    /// and standalone folder mode rendered an empty map.
    func testFolderModeRendersNonEmptyMap() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory
            .appendingPathComponent("spacemap-folder-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        // Two files so the folder has a measurable size to map.
        try Data(count: 4_000).write(to: folder.appendingPathComponent("a.bin"))
        try Data(count: 6_000).write(to: folder.appendingPathComponent("b.bin"))

        let vm = SpaceMapViewModel()
        vm.bindFolderRoot(folder)

        XCTAssertFalse(vm.segments.isEmpty, "Folder mode must produce segments")
        let total = vm.segments.filter { $0.depth == 0 }.reduce(Int64(0)) { $0 + $1.size }
        XCTAssertEqual(total, 10_000, "Mapped size must equal the folder contents")
    }
}
