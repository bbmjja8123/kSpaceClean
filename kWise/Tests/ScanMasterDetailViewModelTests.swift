// kWise/Tests/ScanMasterDetailViewModelTests.swift
//
// UX 重构 Phase 2 — master-detail row suppliers (caps / ordering / search),
// incremental-vs-full summary equivalence, ancestor-chain equivalence, and
// the selection-driven cleanup bridge.
import XCTest
@testable import kWise

final class ScanMasterDetailViewModelTests: XCTestCase {

    // MARK: - Fixture

    /// 40 app buckets × 30 leaves each — big enough to exercise both caps.
    private func makeCategories() -> [ScanCategory] {
        var subs: [ScanSubCategory] = []
        for i in (0..<40).reversed() {
            var leaves: [ScanResult] = []
            for j in (0..<30).reversed() {
                leaves.append(ScanResult(
                    url: URL(fileURLWithPath: "/tmp/app\(i)/file\(j).bin"),
                    path: "/tmp/app\(i)/file\(j).bin",
                    title: "file\(j).bin",
                    fileSize: Int64(j * 1000),
                    riskLevel: .recommended
                ))
            }
            let action = ScanAction(actionID: "a\(i)", actionType: .cache,
                                    title: "缓存", results: leaves)
            subs.append(ScanSubCategory(
                subCategoryID: "app\(i)",
                title: "应用 \(i)",
                bundleID: "com.test.app\(i)",
                appName: "应用 \(i)",
                totalSize: Int64(i * 10_000),
                actions: [action],
                showAction: true
            ))
        }
        return [ScanCategory(categoryID: "app.cache", title: "应用缓存", subItems: subs)]
    }

    @MainActor
    private func makeViewModel() -> ScanResultsViewModel {
        let vm = ScanResultsViewModel(engine: nil)
        var snapshot = ScanResultsViewModel.ScanSnapshot()
        snapshot.categories = makeCategories()
        snapshot.hasScanned = true
        vm.assign(snapshot: snapshot)
        vm.rebuildIndices()
        return vm
    }

    // MARK: - Caps

    @MainActor
    func testSubcategoryCapReturnsSliceAndRemaining() {
        let vm = makeViewModel()
        let category = vm.categories[0]
        let rows = vm.visibleSubcategories(in: category)
        XCTAssertEqual(rows.count, ScanResultsViewModel.ScanListCap.subcategories,
                       "Level-2 list must render at most the cap")
        XCTAssertEqual(vm.remainingSubcategoryCount(in: category),
                       40 - ScanResultsViewModel.ScanListCap.subcategories)

        vm.capLiftedIDs.insert(category.id)
        XCTAssertEqual(vm.visibleSubcategories(in: category).count, 40)
        XCTAssertEqual(vm.remainingSubcategoryCount(in: category), 0)
    }

    @MainActor
    func testFileCapReturnsSliceAndRemaining() {
        let vm = makeViewModel()
        let sub = vm.categories[0].subItems[0]
        let files = vm.visibleFiles(in: sub)
        XCTAssertEqual(files.count, ScanResultsViewModel.ScanListCap.files,
                       "Level-3 list must render at most the cap")
        XCTAssertEqual(vm.remainingFileCount(in: sub), 30 - ScanResultsViewModel.ScanListCap.files)

        vm.capLiftedIDs.insert(sub.id)
        XCTAssertEqual(vm.visibleFiles(in: sub).count, 30)
    }

    // MARK: - Ordering + search

    @MainActor
    func testRowsSortedSizeDescending() {
        let vm = makeViewModel()
        let rows = vm.visibleSubcategories(in: vm.categories[0])
        let sizes = rows.compactMap { ($0 as? ScanSubCategory)?.totalSize }
        XCTAssertEqual(sizes, sizes.sorted(by: >), "Level-2 rows must be size-descending")

        let sub = vm.categories[0].subItems[0]
        let fileSizes = vm.visibleFiles(in: sub).compactMap { ($0 as? ScanResult)?.fileSize }
        XCTAssertEqual(fileSizes, fileSizes.sorted(by: >), "Level-3 rows must be size-descending")
    }

    @MainActor
    func testSearchFiltersByTitleAndBundleID() {
        let vm = makeViewModel()
        vm.categoryQuery = "应用 7"
        let rows = vm.visibleSubcategories(in: vm.categories[0])
        XCTAssertTrue(rows.allSatisfy { ($0 as? ScanSubCategory)?.appName?.contains("应用 7") == true })
        XCTAssertFalse(rows.isEmpty)

        vm.categoryQuery = "com.test.app12"
        let byBundle = vm.visibleSubcategories(in: vm.categories[0])
        XCTAssertEqual(byBundle.count, 1)
    }

    // MARK: - Selection correctness (incremental == full)

    @MainActor
    func testIncrementalSummaryMatchesFullSummary() {
        let vm = makeViewModel()
        let nodes = vm.nodeIndex.values.map { $0 }

        // Deterministic pseudo-random toggle sequence over 40 random nodes.
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func next() -> UInt64 {
            seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17
            return seed
        }
        let all = Array(vm.nodeIndex.values)
        for _ in 0..<60 {
            let node = all[Int(next() % UInt64(all.count))]
            let newState: CheckState = node.state == .checked ? .unchecked : .checked
            node.setState(newState)
            vm.refreshAncestors(of: node.id)
            // Refresh the topmost ancestor's contribution (same as toggleSelect).
            if var cursor = vm.parentIndex[node.id] {
                while let nextID = vm.parentIndex[cursor] { cursor = nextID }
                vm.refreshSummary(forCategory: cursor)
            }
        }

        // Full recompute must agree with the incremental result.
        var expectedSize: Int64 = 0
        var expectedCount = 0
        for category in vm.categories {
            let selected = vm.selectedURLs().count // sanity non-zero path
            _ = selected
            var size: Int64 = 0
            var count = 0
            func walk(_ node: any ScanTreeNode) {
                switch node.state {
                case .checked:
                    size += node.selectedSize
                    count += max(1, node.children.count + 1)
                case .mixed:
                    for child in node.children { walk(child) }
                case .unchecked:
                    return
                }
            }
            walk(category)
            expectedSize += size
            expectedCount += count
        }
        XCTAssertEqual(vm.totalSelectedSize, expectedSize,
                       "Incremental summary must equal a full recompute")
        XCTAssertEqual(vm.totalSelectedCount, expectedCount)
        XCTAssertFalse(nodes.isEmpty)
    }

    @MainActor
    func testAncestorRefreshProducesTriState() {
        let vm = makeViewModel()
        // Check one leaf deep in the tree; the whole ancestor chain must go mixed.
        guard let leaf = vm.categories[0].subItems[0].actions.first?.results.first else {
            return XCTFail("fixture broken")
        }
        leaf.setState(.checked)
        vm.refreshAncestors(of: leaf.id)
        XCTAssertEqual(vm.categories[0].state, .mixed, "One checked leaf → category shows mixed")
        XCTAssertEqual(vm.categories[0].subItems[0].state, .mixed)
    }

    // MARK: - Cleanup bridge

    @MainActor
    func testSelectedURLsAndSizesReflectCheckedLeaves() {
        let vm = makeViewModel()
        vm.selectAll(in: vm.categories[0])
        let urls = vm.selectedURLs()
        XCTAssertEqual(urls.count, 40 * 30)
        let sizes = vm.selectedSizesByURL()
        XCTAssertEqual(sizes.count, 40 * 30)
        XCTAssertEqual(sizes[URL(fileURLWithPath: "/tmp/app39/file29.bin")], 29_000)
    }

    @MainActor
    func testScopedSelectAllLeavesOtherCategoriesUntouched() {
        let vm = makeViewModel()
        // Add a second category that must stay unchecked.
        let other = ScanCategory(categoryID: "other", title: "其他",
                                 subItems: [ScanSubCategory(
                                     subCategoryID: "o1", title: "o",
                                     directResults: [ScanResult(
                                         url: URL(fileURLWithPath: "/tmp/o"),
                                         path: "/tmp/o", title: "o", fileSize: 1)])])
        var snapshot = ScanResultsViewModel.ScanSnapshot()
        snapshot.categories = makeCategories() + [other]
        vm.assign(snapshot: snapshot)
        vm.rebuildIndices()

        vm.selectAll(in: vm.categories[0])
        XCTAssertEqual(other.state, .unchecked, "Scoped 全选 must not touch other categories")
    }
}
