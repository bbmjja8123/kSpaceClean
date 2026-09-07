import XCTest
@testable import DetectionCore

final class SelectionPlannerTests: XCTestCase {
    // MARK: - Fixtures

    private func file(
        _ name: String,
        folder: String,
        size: Int64 = 100,
        modifiedAgo: TimeInterval = 0
    ) -> FileItem {
        .mock(
            url: URL(fileURLWithPath: "/\(folder)/\(name)"),
            size: size,
            modificationDate: Date(timeIntervalSinceNow: -modifiedAgo)
        )
    }

    private func group(_ files: [FileItem], category: DuplicateCategory = .identical) -> DuplicateGroup {
        .mock(category: category, totalSize: files.reduce(0) { $0 + $1.size }, fileCount: files.count, files: files)
    }

    // MARK: - Edge cases

    func testEmptyGroupYieldsEmptyPlan() {
        let plan = SelectionPlanner.plan(for: group([]), strategy: .keepNewest)
        XCTAssertNil(plan.keep)
        XCTAssertTrue(plan.remove.isEmpty)
        XCTAssertTrue(plan.reasons.isEmpty)
    }

    func testSingleFileGroupKeepsOnlyFile() {
        let only = file("a.bin", folder: "A")
        let plan = SelectionPlanner.plan(for: group([only]), strategy: .keepOldest)
        XCTAssertEqual(plan.keep?.id, only.id)
        XCTAssertTrue(plan.remove.isEmpty, "Nothing to remove in a single-copy group")
        XCTAssertEqual(plan.reasons[only.id], .onlyFile)
    }

    // MARK: - keepNewest / keepOldest

    func testKeepNewestPicksMostRecentlyModified() {
        let old = file("a.bin", folder: "A", modifiedAgo: 3600)
        let new = file("a.bin", folder: "B", modifiedAgo: 0)
        let plan = SelectionPlanner.plan(for: group([old, new]), strategy: .keepNewest)
        XCTAssertEqual(plan.keep?.id, new.id)
        XCTAssertEqual(plan.reasons[new.id], .newestCopy)
        XCTAssertEqual(plan.remove.map(\.id), [old.id])
        XCTAssertEqual(plan.reasons[old.id], .duplicateOfKept)
    }

    func testKeepOldestPicksEarliestModified() {
        let old = file("a.bin", folder: "A", modifiedAgo: 3600)
        let new = file("a.bin", folder: "B", modifiedAgo: 0)
        let plan = SelectionPlanner.plan(for: group([old, new]), strategy: .keepOldest)
        XCTAssertEqual(plan.keep?.id, old.id)
        XCTAssertEqual(plan.reasons[old.id], .oldestCopy)
        XCTAssertEqual(plan.reasons[new.id], .duplicateOfKept)
    }

    // MARK: - keepShortestPath

    func testKeepShortestPathPrefersFewestComponents() {
        let deep = file("a.bin", folder: "Downloads/export (1)/nested")
        let shallow = file("a.bin", folder: "Pictures")
        let plan = SelectionPlanner.plan(for: group([deep, shallow]), strategy: .keepShortestPath)
        XCTAssertEqual(plan.keep?.id, shallow.id)
        XCTAssertEqual(plan.reasons[shallow.id], .shortestPath)
    }

    // MARK: - keepInsideScanRoot

    func testKeepInsideScanRootPrefersCopyInsideRoot() {
        let outside = file("a.bin", folder: "Downloads", modifiedAgo: 0)
        let inside = file("a.bin", folder: "Projects/App", modifiedAgo: 3600)
        let plan = SelectionPlanner.plan(
            for: group([outside, inside]),
            strategy: .keepInsideScanRoot,
            scanRoots: [URL(fileURLWithPath: "/Projects")]
        )
        XCTAssertEqual(plan.keep?.id, inside.id)
        XCTAssertEqual(plan.reasons[inside.id], .insideScanRoot)
    }

    func testKeepInsideScanRootFallsBackToNewest() {
        let old = file("a.bin", folder: "Downloads", modifiedAgo: 3600)
        let new = file("b.bin", folder: "Backup", modifiedAgo: 0)
        let plan = SelectionPlanner.plan(
            for: group([old, new]),
            strategy: .keepInsideScanRoot,
            scanRoots: [URL(fileURLWithPath: "/Nowhere")]
        )
        // No copy inside the root → newest copy wins (usable plan guaranteed).
        XCTAssertEqual(plan.keep?.id, new.id)
        XCTAssertEqual(plan.reasons[new.id], .newestCopy)
    }

    // MARK: - keepDirectoryCanonical

    func testKeepDirectoryCanonicalPicksAlphabeticallyFirstFolder() {
        let backup = file("a.bin", folder: "Backup")
        let documents = file("a.bin", folder: "Documents")
        let plan = SelectionPlanner.plan(
            for: group([backup, documents]),
            strategy: .keepDirectoryCanonical
        )
        XCTAssertEqual(plan.keep?.id, backup.id, "'Backup' sorts before 'Documents'")
        XCTAssertEqual(plan.reasons[backup.id], .canonicalFolder)
    }

    // MARK: - Determinism & completeness

    func testTiesBreakOnLocalizedPathOrder() {
        // Same size, same modification date, same depth → the copy whose
        // path sorts first must win, deterministically.
        let a = file("a.bin", folder: "A")
        let b = file("a.bin", folder: "B")
        let first = SelectionPlanner.plan(for: group([b, a]), strategy: .keepNewest)
        let second = SelectionPlanner.plan(for: group([a, b]), strategy: .keepNewest)
        XCTAssertEqual(first.keep?.id, second.keep?.id, "Plan must not depend on input order")
    }

    func testReasonsCoverEveryFile() {
        let files = [
            file("a.bin", folder: "A", modifiedAgo: 7200),
            file("a.bin", folder: "B", modifiedAgo: 3600),
            file("a.bin", folder: "C", modifiedAgo: 0),
        ]
        let plan = SelectionPlanner.plan(for: group(files), strategy: .keepNewest)
        XCTAssertEqual(Set(plan.reasons.keys), Set(files.map(\.id)), "Every file gets an explainable reason")
        XCTAssertEqual(plan.reasons.values.filter { $0 == .duplicateOfKept }.count, 2)
    }
}
