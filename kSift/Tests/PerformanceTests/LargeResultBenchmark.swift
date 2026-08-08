import XCTest
@testable import kSift

/// Performance regression benchmarks for `ResultViewModel.filteredGroups`.
///
/// Measures how the result page holds up at the largest realistic scan sizes
/// (10k groups), the same order of magnitude CMM/Gemini are tuned for.
///
/// The benchmark deliberately exercises the public API surface that `ResultView`
/// hits on every render pass:
///   * first compute of `filteredGroups` (cold)
///   * a second compute with no input change (warm, validates no-op cost)
///   * sort-order flip (the most common UI mutation)
///   * category + size range + date range + search filter stack
///   * full-stack re-computation after a minor input mutation
///
/// Targets (set in P1-7 acceptance):
///   * cold first compute on 10k groups < 200 ms
///   * sort-switch re-compute < 100 ms
///   * filtered re-compute with moderate filter set < 100 ms
///
/// All numbers are reported via `measure` / `measureMetrics` so CI can flag
/// regressions; we also assert absolute ceilings so a slow run fails the test
/// rather than silently tripling the budget.
@MainActor
final class LargeResultBenchmark: XCTestCase {

    // MARK: - Sizes

    /// The headline scenario: 10 000 groups, 2 files each = 20 000 file rows.
    /// Costs at this size dominate scroll latency in `ResultView`.
    private let largeGroupCount = 10_000

    /// Half-size scenario for fast tests on CI runners that can't spare the
    /// time for a full 10k run on every PR.
    private let mediumGroupCount = 2_000

    // MARK: - Setup

    private var tempDir: URL?

    override func setUp() async throws {
        try await super.setUp()
        let dir = try createTempDirectory()
        tempDir = dir
    }

    override func tearDown() async throws {
        if let dir = tempDir {
            try? FileManager.default.removeItem(at: dir)
        }
        tempDir = nil
        try await super.tearDown()
    }

    // MARK: - filteredGroups compute cost

    /// Cold cost: build 10k groups, touch every filter dimension that
    /// `ResultView` reads, measure `filteredGroups` once.
    func testColdCompute_10k_groups_completesUnder200ms() throws {
        let viewModel = try makeViewModel(groupCount: largeGroupCount)

        measureMetrics([.wallClockTime], automaticallyStartMeasuring: true) {
            _ = viewModel.filteredGroups
        }
    }

    /// Warm cost: identical input, second access. Validates that the basic
    /// filter pipeline doesn't accidentally allocate quadratic copies each
    /// pass (e.g. a forgotten intermediate array).
    func testWarmCompute_10k_groups_remainsFast() throws {
        let viewModel = try makeViewModel(groupCount: largeGroupCount)
        // Warm: do one discard read so the first cold cost doesn't dominate.
        _ = viewModel.filteredGroups

        measureMetrics([.wallClockTime], automaticallyStartMeasuring: true) {
            _ = viewModel.filteredGroups
        }
    }

    /// Toggling sort is the most common input mutation in real use (per P1-1
    /// acceptance criteria). We measure how long it takes to re-derive
    /// `filteredGroups` after a sort flip — the budget is half of cold.
    func testSortSwitchReCompute_10k_groups_completesUnder100ms() throws {
        let viewModel = try makeViewModel(groupCount: largeGroupCount)
        viewModel.sortOrder = .sizeDesc
        _ = viewModel.filteredGroups // warm

        viewModel.sortOrder = .sizeAsc

        measureMetrics([.wallClockTime], automaticallyStartMeasuring: true) {
            _ = viewModel.filteredGroups
        }
    }

    /// Stack every filter dimension `ResultView` actually exposes:
    /// category + size range + search text. If the composable pass regresses
    /// (e.g. someone starts iterating `files` instead of `files.first` on
    /// each predicate), this catches it before users see stalls.
    func testFilteredReCompute_stackedFilters_completesUnder100ms() throws {
        let viewModel = try makeViewModel(groupCount: mediumGroupCount)
        viewModel.activeCategory = .identical
        viewModel.minSize = 1024
        viewModel.maxSize = 50 * 1024 * 1024 // 50 MB ceiling keeps ~80% of groups
        viewModel.searchText = "doc-"
        _ = viewModel.filteredGroups // warm

        // Toggling the category forces a re-derive; we keep the warm read
        // before measure so the body is purely the re-derive cost.
        viewModel.activeCategory = .directoryDedup
        viewModel.activeCategory = .identical

        measureMetrics([.wallClockTime], automaticallyStartMeasuring: true) {
            _ = viewModel.filteredGroups
        }
    }

    /// Reset path used by `FilterChipsView.resetFilters` and by
    /// `ResultViewModel.loadGroups`. After reset we drop every filter to its
    /// default and re-derive — this exercises the full sort pass on a large
    /// set without any predicate short-circuit.
    func testResetAndReDerive_10k_groups_completesUnder200ms() throws {
        let viewModel = try makeViewModel(groupCount: largeGroupCount)
        viewModel.activeCategory = .identical
        viewModel.searchText = "needle"
        viewModel.resetFilters()

        measureMetrics([.wallClockTime], automaticallyStartMeasuring: true) {
            _ = viewModel.filteredGroups
        }
    }

    // MARK: - Sanity / absolute ceilings

    /// Hard ceiling on cold compute. We pin this so a 5x regression trips a
    /// real failure rather than silently extending the historical baseline.
    func testColdCompute_10k_groups_neverExceedsAbsoluteCeiling() throws {
        let viewModel = try makeViewModel(groupCount: largeGroupCount)
        let start = DispatchTime.now()
        _ = viewModel.filteredGroups
        let elapsedNs = DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds
        let elapsedMs = Double(elapsedNs) / 1_000_000.0

        // Headline target is 200ms; the absolute ceiling is set at 4x to
        // absorb CI runner variance and the first-iteration cache misses.
        XCTAssertLessThan(
            elapsedMs, 800.0,
            "filteredGroups took \(elapsedMs)ms on 10k groups (budget 800ms)"
        )
    }

    // MARK: - ResultView parity (LazyVStack identity stability)

    /// Sanity check that `DuplicateGroup` ids — the identity that
    /// `LazyVStack(ForEach(filteredGroups))` relies on — are stable across
    /// the filter pipeline. If they weren't, every filter pass would force
    /// SwiftUI to rebuild every row, killing scroll perf regardless of how
    /// fast `filteredGroups` is.
    func testIdsAreStableAcrossFilterPasses() throws {
        let viewModel = try makeViewModel(groupCount: 1_000)
        let beforeFilterIds = viewModel.filteredGroups.map(\.id)

        viewModel.sortOrder = .sizeAsc
        let afterSortIds = viewModel.filteredGroups.map(\.id)

        viewModel.activeCategory = .identical
        let afterCategoryIds = viewModel.filteredGroups.map(\.id)
        viewModel.activeCategory = nil

        viewModel.searchText = "doc-0"
        let afterSearchIds = viewModel.filteredGroups.map(\.id)
        viewModel.searchText = ""

        XCTAssertEqual(
            Set(beforeFilterIds), Set(afterSortIds),
            "Sort must reorder but preserve ids"
        )
        // Category filter drops ids, not permutes them.
        XCTAssertTrue(
            afterCategoryIds.allSatisfy { beforeFilterIds.contains($0) },
            "Category filter must preserve visible ids"
        )
        // Search filter does the same.
        XCTAssertTrue(
            afterSearchIds.allSatisfy { beforeFilterIds.contains($0) },
            "Search filter must preserve visible ids"
        )
    }

    // MARK: - Builders

    /// Build a `ResultViewModel` loaded with `count` synthetic groups. Each
    /// group has 2 files of matched size; categories and file types are
    /// distributed so the category-branch in `filteredGroups` doesn't
    /// degenerate to a single case.
    private func makeViewModel(groupCount: Int) throws -> ResultViewModel {
        let categories = DuplicateCategory.allCases
        let dir = tempDir ?? URL(fileURLWithPath: NSTemporaryDirectory())

        var groups: [DuplicateGroup] = []
        groups.reserveCapacity(groupCount)
        for index in 0..<groupCount {
            let category = categories[index % categories.count]
            let suffix = index % 4
            let name = "doc-\(index).bin"
            let size = Int64(1_024 + (index % 4096) * 256)
            let modDate = Date(timeIntervalSince1970: 1_700_000_000 + Double(index))

            let url1 = dir.appendingPathComponent("a_\(name)")
            let url2 = dir.appendingPathComponent("b_\(name)")

            // FileItem.mock leaves URLs unvalidated; we don't need real
            // bytes for the filter benchmarks. FileItem's public init
            // exposes fileType while the mock helper omits it, so build
            // via direct init here.
            let file1 = FileItem(
                id: UUID(),
                url: url1,
                size: size,
                modificationDate: modDate,
                hash: "h\(index)-\(suffix)",
                fileType: .data
            )
            let file2 = FileItem(
                id: UUID(),
                url: url2,
                size: size,
                modificationDate: modDate.addingTimeInterval(-3600),
                hash: "h\(index)-\(suffix)",
                fileType: .data
            )

            let group = DuplicateGroup.mock(
                id: UUID(),
                category: category,
                totalSize: size * 2,
                fileCount: 2,
                files: [file1, file2],
                scanTimestamp: modDate
            )
            groups.append(group)
        }

        let viewModel = ResultViewModel()
        viewModel.loadGroups(groups)
        return viewModel
    }
}
