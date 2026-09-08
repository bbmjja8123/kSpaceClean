import XCTest
@testable import PowerScope

/// Stub-driven tests: no NSOpenPanel, no real bookmark resolution — the
/// capability semantics are what matters.
final class PowerScopeCapabilityTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "PowerScopeTests.\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }

    func testContainerOnlyCapabilityCannotReadHomePaths() {
        let cap = ScopeCapability(level: .containerOnly,
                                  grantedRoot: nil,
                                  readablePublicDirs: ["~/Library/Caches"])
        XCTAssertFalse(cap.canRead(URL(fileURLWithPath: "~/Documents/secret".resolvingTildeInPath)))
        XCTAssertTrue(cap.canRead(URL(fileURLWithPath: "~/Library/Caches/com.app/x".resolvingTildeInPath)))
    }

    func testHomeGrantedCapabilityCoversRootSubtree() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let cap = ScopeCapability(level: .homeGranted,
                                  grantedRoot: home,
                                  readablePublicDirs: [])
        XCTAssertTrue(cap.canRead(home.appendingPathComponent("Library/Caches/x")))
        XCTAssertFalse(cap.canRead(URL(fileURLWithPath: "/Applications/Safari.app")))
    }

    func testScopeLevelOrdering() {
        XCTAssertLessThan(ScopeLevel.containerOnly, .homeGranted)
    }

    func testBookmarkStoreRoundTripAndClear() {
        let defaults = makeDefaults()
        let store = BookmarkStore(defaults: defaults)
        XCTAssertNil(store.load())
        let blob = Data("bookmark-blob".utf8)
        store.save(bookmark: blob, createdAt: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(store.load(), blob)
        XCTAssertEqual(store.createdAt?.timeIntervalSince1970, 100)
        store.clear()
        XCTAssertNil(store.load())
        XCTAssertNil(store.createdAt)
    }

    func testRefreshWithoutBookmarkReportsContainerOnlyWithProbedDirs() async {
        let scope = PowerScope(bookmarks: BookmarkStore(defaults: makeDefaults()))
        let cap = await scope.refresh()
        XCTAssertEqual(cap.level, .containerOnly)
        XCTAssertNil(cap.grantedRoot)
    }

    func testRefreshWithStaleBookmarkDegradesAndClears() async {
        let defaults = makeDefaults()
        let store = BookmarkStore(defaults: defaults)
        store.save(bookmark: Data("garbage-not-a-bookmark".utf8))
        let scope = PowerScope(bookmarks: store)
        let cap = await scope.refresh()
        XCTAssertEqual(cap.level, .containerOnly)
        XCTAssertNil(cap.grantedRoot)
        XCTAssertNil(store.load(), "stale bookmark must be cleared, not retried every launch")
    }

    func testCapabilityDefaultIsContainerOnly() async {
        let scope = PowerScope(bookmarks: BookmarkStore(defaults: makeDefaults()))
        let cap = await scope.capability()
        XCTAssertEqual(cap.level, .containerOnly)
    }
}

private extension String {
    var resolvingTildeInPath: String {
        (self as NSString).expandingTildeInPath
    }
}
