import XCTest
@testable import kFresh

/// Coverage for `DeepCleanViewModel` — drives the `idle` → `scanning` →
/// `loaded`/`failed` transitions plus the selection and clean flows
/// triggered by ``DeepCleanView``.
///
/// The view-model is `@MainActor` and depends on the `DeepCleanEngining`
/// protocol, so the real filesystem is never touched in these tests.
@MainActor
final class DeepCleanViewModelTests: XCTestCase {

    // MARK: - Stub engine

    /// In-memory replacement for `DeepCleanEngine`. Lets each test pre-load
    /// the item list, force scan/clean errors, and capture exactly which
    /// items were forwarded to `clean(_:)`.
    private final class StubEngine: DeepCleanEngining {
        var stubItems: [SystemCleanItem]
        var scanError: Error?
        var cleanError: Error?
        var cleanResult: Int = 1
        var cleanCalls: [[SystemCleanItem]] = []

        init(items: [SystemCleanItem] = []) {
            self.stubItems = items
        }

        func scan() async throws -> [SystemCleanItem] {
            if let scanError { throw scanError }
            return stubItems
        }

        func clean(_ items: [SystemCleanItem]) async throws -> Int {
            cleanCalls.append(items)
            if let cleanError { throw cleanError }
            return cleanResult
        }
    }

    // MARK: - Fixtures

    /// Builds a deletable `SystemCleanItem` (non-protected).
    private func makeItem(
        name: String,
        category: SystemCleanCategory = .launchAgents,
        path: String = "/tmp/item.plist",
        isProtected: Bool = false
    ) -> SystemCleanItem {
        SystemCleanItem(
            displayName: name,
            url: URL(fileURLWithPath: path),
            category: category,
            sizeBytes: 1024,
            isProtected: isProtected,
            associatedBundleID: nil
        )
    }

    // MARK: - Tests

    /// Initial state must be `.idle` — `.scanning` only appears after an
    /// explicit `load()` call, so the view never shows a spinner before
    /// the engine is queried.
    func testInitialStateIsIdle() {
        let viewModel = DeepCleanViewModel(engine: StubEngine())

        if case .idle = viewModel.state {
            // pass
        } else {
            XCTFail("Expected initial state to be .idle, got \(viewModel.state)")
        }
    }

    /// `load()` must drive the state to `.loaded(items)` and pre-select
    /// every non-protected item (the "safe everything" default).
    func testLoadTransitionsToLoadedAndPreselectsSafeItems() async throws {
        let safe = makeItem(name: "com.example.a")
        let protected = makeItem(name: "com.apple.system", path: "/tmp/system.plist", isProtected: true)
        let stub = StubEngine(items: [safe, protected])
        let viewModel = DeepCleanViewModel(engine: stub)

        await viewModel.load()

        guard case .loaded(let items) = viewModel.state else {
            XCTFail("Expected .loaded state after load(), got \(viewModel.state)")
            return
        }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(viewModel.selectedIDs, [safe.id], "Protected items must never be pre-selected")
    }

    /// A scan failure must surface as `.failed(message)` with the localized
    /// description preserved for the empty-state view.
    func testLoadFailureMapsToFailedState() async throws {
        let stub = StubEngine()
        stub.scanError = NSError(domain: "test", code: 1,
                                 userInfo: [NSLocalizedDescriptionKey: "boom"])
        let viewModel = DeepCleanViewModel(engine: stub)

        await viewModel.load()

        guard case .failed(let message) = viewModel.state else {
            XCTFail("Expected .failed state on scan error, got \(viewModel.state)")
            return
        }
        XCTAssertEqual(message, "boom")
    }

    /// `toggle(_:)` adds/removes the item from the selection and refuses
    /// protected items entirely.
    func testToggleUpdatesSelectionAndIgnoresProtected() async throws {
        let safe = makeItem(name: "com.example.a")
        let protected = makeItem(name: "com.apple.system", path: "/tmp/system.plist", isProtected: true)
        let viewModel = DeepCleanViewModel(engine: StubEngine(items: [safe, protected]))
        await viewModel.load()

        // Pre-selected by default — unselect, then re-select.
        viewModel.toggle(safe)
        XCTAssertFalse(viewModel.isSelected(safe))
        viewModel.toggle(safe)
        XCTAssertTrue(viewModel.isSelected(safe))

        // Protected items must be refused even if explicitly forwarded.
        viewModel.toggle(protected)
        XCTAssertFalse(viewModel.isSelected(protected))
    }

    /// `clean()` must forward ONLY the selected (non-protected) items to
    /// the engine and reload afterwards so deleted rows disappear.
    func testCleanForwardsSelectionAndReloads() async throws {
        let a = makeItem(name: "com.example.a")
        let b = makeItem(name: "com.example.b", path: "/tmp/b.plist")
        let stub = StubEngine(items: [a, b])
        let viewModel = DeepCleanViewModel(engine: stub)
        await viewModel.load()

        // Deselect `b` — only `a` should be forwarded.
        viewModel.toggle(b)
        let deleted = await viewModel.clean()

        XCTAssertEqual(deleted, 1)
        XCTAssertEqual(stub.cleanCalls.count, 1)
        XCTAssertEqual(stub.cleanCalls.first?.map(\.id), [a.id])
        if case .loaded = viewModel.state {
            // pass — reload ran after clean
        } else {
            XCTFail("Expected .loaded state after clean + reload, got \(viewModel.state)")
        }
    }

    /// A clean failure must surface as `.failed(message)` and report zero
    /// deleted items.
    func testCleanFailureMapsToFailedState() async throws {
        let item = makeItem(name: "com.example.a")
        let stub = StubEngine(items: [item])
        stub.cleanError = NSError(domain: "test", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "delete failed"])
        let viewModel = DeepCleanViewModel(engine: stub)
        await viewModel.load()

        let deleted = await viewModel.clean()

        XCTAssertEqual(deleted, 0)
        guard case .failed(let message) = viewModel.state else {
            XCTFail("Expected .failed state on clean error, got \(viewModel.state)")
            return
        }
        XCTAssertEqual(message, "delete failed")
    }

    /// `groupedItems` must bucket items by category and render sections in
    /// alphabetical `rawValue` order.
    func testGroupedItemsSortedByCategory() async throws {
        let agent = makeItem(name: "a", category: .launchAgents)
        let daemon = makeItem(name: "d", category: .launchDaemons)
        let pane = makeItem(name: "p", category: .preferencePanes)
        let viewModel = DeepCleanViewModel(engine: StubEngine(items: [pane, agent, daemon]))
        await viewModel.load()

        let groups = viewModel.groupedItems

        XCTAssertEqual(groups.map(\.0), [.launchAgents, .launchDaemons, .preferencePanes])
        XCTAssertEqual(groups[0].1.map(\.displayName), ["a"])
        XCTAssertEqual(groups[1].1.map(\.displayName), ["d"])
        XCTAssertEqual(groups[2].1.map(\.displayName), ["p"])
    }

    /// `selectedSizeBytes` must aggregate the sizes of the selected items
    /// only — protected items are never selected so they never contribute.
    func testSelectedSizeBytesAggregatesSelection() async throws {
        let a = makeItem(name: "com.example.a", path: "/tmp/a.plist")
        let b = makeItem(name: "com.example.b", path: "/tmp/b.plist")
        let viewModel = DeepCleanViewModel(engine: StubEngine(items: [a, b]))
        await viewModel.load()

        XCTAssertEqual(viewModel.selectedSizeBytes, 2048)
        viewModel.toggle(b)
        XCTAssertEqual(viewModel.selectedSizeBytes, 1024)
    }
}
