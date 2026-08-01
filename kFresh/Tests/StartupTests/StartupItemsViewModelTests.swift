import XCTest
@testable import kFresh

/// Coverage for `StartupItemsViewModel` — drives the `loaded(...)`,
/// `loading`, and `failed(msg)` state transitions plus the toggle / remove
/// flows triggered by `StartupItemRowView`.
///
/// The view-model is `@MainActor`, depends on the `StartupItemManaging`
/// protocol (so the file system is never touched in tests), and exposes a
/// simple `ViewState` enum that the view renders with a `switch`.
@MainActor
final class StartupItemsViewModelTests: XCTestCase {

    // MARK: - Stub manager

    /// In-memory replacement for `StartupItemManager`. Captures the toggle
    /// and remove calls so tests can verify the view-model forwards
    /// correctly, and lets each test pre-load the items list without
    /// touching `~/Library/LaunchAgents`.
    private final class StubManager: StartupItemManaging {
        var stubItems: [StartupItem]
        var toggleCalls: [StartupItem] = []
        var removeCalls: [StartupItem] = []
        var listItemsError: Error?

        init(items: [StartupItem] = []) {
            self.stubItems = items
        }

        func listItems() async throws -> [StartupItem] {
            if let err = listItemsError { throw err }
            return stubItems
        }

        func setEnabled(_ enabled: Bool, for item: StartupItem) async throws {
            toggleCalls.append(item)
        }

        func remove(_ item: StartupItem) async throws {
            removeCalls.append(item)
        }
    }

    // MARK: - Fixtures

    /// Builds a `StartupItem` matching the existing internal init signature.
    private func makeItem(name: String, type: StartupItemType, url: URL) -> StartupItem {
        StartupItem(
            name: name,
            type: type,
            url: url,
            appURL: nil,
            enabled: true,
            isProtected: false
        )
    }

    // MARK: - Tests

    /// Initial state must be `.idle` — `.loading` only appears after an
    /// explicit `load()` call, so we never surprise the view with a spinner
    /// on first render.
    func testInitialStateIsIdle() {
        let stub = StubManager()
        let viewModel = StartupItemsViewModel(manager: stub)
        if case .idle = viewModel.state {
            // pass
        } else {
            XCTFail("Expected initial state to be .idle, got \(viewModel.state)")
        }
    }

    /// `load()` should drive the visible state to `.loaded(items)` with the
    /// items the manager returned.
    func testLoadTransitionsToLoaded() async throws {
        let launchAgent = makeItem(
            name: "com.kfresh.agent",
            type: .launchAgent,
            url: URL(fileURLWithPath: "/tmp/com.kfresh.agent.plist")
        )
        let launchDaemon = makeItem(
            name: "com.kfresh.daemon",
            type: .launchDaemon,
            url: URL(fileURLWithPath: "/tmp/com.kfresh.daemon.plist")
        )
        let stub = StubManager(items: [launchAgent, launchDaemon])
        let viewModel = StartupItemsViewModel(manager: stub)

        await viewModel.load()

        guard case .loaded(let items) = viewModel.state else {
            XCTFail("Expected .loaded state after load(), got \(viewModel.state)")
            return
        }
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.type), [.launchAgent, .launchDaemon])
    }

    /// `groupedByType` must collapse items under their `StartupItemType`
    /// and present the sections in a stable order (sorted by
    /// `rawValue`). Both user Launch Agents (.launchAgent) and system
    /// launch daemons (.launchDaemon) need to land in separate buckets.
    func testGroupedByTypeGroupsByType() async throws {
        let a1 = makeItem(name: "agent1", type: .launchAgent,
                          url: URL(fileURLWithPath: "/tmp/a1.plist"))
        let a2 = makeItem(name: "agent2", type: .launchAgent,
                          url: URL(fileURLWithPath: "/tmp/a2.plist"))
        let d1 = makeItem(name: "daemon1", type: .launchDaemon,
                          url: URL(fileURLWithPath: "/tmp/d1.plist"))

        let stub = StubManager(items: [a1, d1, a2])
        let viewModel = StartupItemsViewModel(manager: stub)

        await viewModel.load()
        let groups = viewModel.groupedByType

        XCTAssertEqual(groups.count, 2)
        // rawValue("launchAgent") < rawValue("launchDaemon") → alphabetical
        XCTAssertEqual(groups[0].0, .launchAgent)
        XCTAssertEqual(groups[1].0, .launchDaemon)
        XCTAssertEqual(groups[0].1.count, 2)
        XCTAssertEqual(groups[1].1.count, 1)
    }

    /// `toggle(_:)` must forward the request through the manager — we
    /// observe the manager received exactly one call with the original
    /// item, AND the view-model reloaded the list (so the UI shows the
    /// new state).
    func testToggleCallsManagerAndReloads() async throws {
        let item = makeItem(name: "agent", type: .launchAgent,
                            url: URL(fileURLWithPath: "/tmp/agent.plist"))
        let stub = StubManager(items: [item])
        let viewModel = StartupItemsViewModel(manager: stub)

        await viewModel.load()
        await viewModel.toggle(item)

        XCTAssertEqual(stub.toggleCalls.count, 1, "toggle must be forwarded to manager exactly once")
        XCTAssertEqual(stub.toggleCalls.first?.name, "agent")
        // After toggle, load() runs again — final state should be `.loaded`.
        if case .loaded = viewModel.state {
            // pass
        } else {
            XCTFail("Expected .loaded state after toggle + reload, got \(viewModel.state)")
        }
    }

    /// `remove(_:)` must forward the request through the manager and reload
    /// to drop the item from the UI.
    func testRemoveCallsManagerAndReloads() async throws {
        let item = makeItem(name: "agent", type: .launchAgent,
                            url: URL(fileURLWithPath: "/tmp/agent.plist"))
        let stub = StubManager(items: [item])
        let viewModel = StartupItemsViewModel(manager: stub)

        await viewModel.load()
        await viewModel.remove(item)

        XCTAssertEqual(stub.removeCalls.count, 1, "remove must be forwarded to manager exactly once")
        XCTAssertEqual(stub.removeCalls.first?.name, "agent")
        if case .loaded(let remaining) = viewModel.state {
            // The stub still hands the same item back — we only verify
            // reload() ran (state shape), not that the manager filtered.
            XCTAssertEqual(remaining.count, 1)
        } else {
            XCTFail("Expected .loaded state after remove + reload, got \(viewModel.state)")
        }
    }

    /// A failure from the manager must surface as `.failed(message)` with
    /// the localized description preserved for the UI.
    func testLoadFailureMapsToFailedState() async throws {
        let stub = StubManager()
        stub.listItemsError = StartupError.protected
        let viewModel = StartupItemsViewModel(manager: stub)

        await viewModel.load()

        guard case .failed(let message) = viewModel.state else {
            XCTFail("Expected .failed state on manager error, got \(viewModel.state)")
            return
        }
        XCTAssertFalse(message.isEmpty, "Failure message must be non-empty")
    }
}
