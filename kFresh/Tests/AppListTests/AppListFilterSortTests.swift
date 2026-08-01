import XCTest
import AppKit
@testable import kFresh

@MainActor
final class AppListFilterSortTests: XCTestCase {
    func makeApp(name: String, bundleID: String, size: Int64, source: AppSource = .userInstalled) -> InstalledApp {
        InstalledApp(
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            displayName: name,
            bundleID: bundleID,
            version: "1.0",
            icon: NSImage(),
            sizeBytes: size,
            source: source,
            isRunning: false,
            lastUsedDate: Date()
        )
    }

    private func makeViewModel() -> AppListViewModel {
        AppListViewModel(
            catalog: AppCatalogService(),
            historyRepo: UninstallHistoryRepository(),
            fdaProbe: FDAPermissionProbe()
        )
    }

    func testSearchFiltersByDisplayName() {
        let vm = makeViewModel()
        vm.apps = [
            makeApp(name: "Xcode", bundleID: "com.apple.xcode", size: 1024),
            makeApp(name: "Slack", bundleID: "com.tinyspeck.chatlyio", size: 512)
        ]
        vm.searchText = "xcod"
        XCTAssertEqual(vm.filteredApps.map(\.displayName), ["Xcode"])
    }

    func testSearchMatchesBundleID() {
        let vm = makeViewModel()
        vm.apps = [
            makeApp(name: "Chat", bundleID: "com.tinyspeck.chatlyio", size: 512)
        ]
        vm.searchText = "tinyspeck"
        XCTAssertEqual(vm.filteredApps.map(\.displayName), ["Chat"])
    }

    func testCategoryFilterSelectsOnlyMatchingSource() {
        let vm = makeViewModel()
        vm.apps = [
            makeApp(name: "Xcode", bundleID: "com.apple.xcode", size: 1024, source: .appleBuiltIn),
            makeApp(name: "Slack", bundleID: "com.tinyspeck.chatlyio", size: 512, source: .userInstalled)
        ]
        vm.category = .user
        XCTAssertEqual(vm.filteredApps.map(\.displayName), ["Slack"])
    }

    func testSystemCategoryIncludesSystemAndAppleBuiltIn() {
        let vm = makeViewModel()
        vm.apps = [
            makeApp(name: "Finder", bundleID: "com.apple.finder", size: 10, source: .system),
            makeApp(name: "Terminal", bundleID: "com.apple.Terminal", size: 20, source: .appleBuiltIn),
            makeApp(name: "Slack", bundleID: "com.tinyspeck.chatlyio", size: 30, source: .userInstalled)
        ]
        vm.category = .system
        XCTAssertEqual(vm.filteredApps.map(\.displayName), ["Finder", "Terminal"])
    }

    func testRecentlyInstalledFiltersOnLastUsedDate() {
        let vm = makeViewModel()
        let fresh = makeApp(name: "Fresh", bundleID: "com.example.fresh", size: 100)
        var stale = makeApp(name: "Stale", bundleID: "com.example.stale", size: 200)
        stale = InstalledApp(
            url: stale.url,
            displayName: stale.displayName,
            bundleID: stale.bundleID,
            version: stale.version,
            icon: stale.icon,
            sizeBytes: stale.sizeBytes,
            source: stale.source,
            isRunning: false,
            lastUsedDate: Date().addingTimeInterval(-30 * 24 * 3600)
        )
        vm.apps = [fresh, stale]
        vm.category = .recentlyInstalled
        XCTAssertEqual(vm.filteredApps.map(\.displayName), ["Fresh"])
    }

    func testSortBySizeDescending() {
        let vm = makeViewModel()
        vm.apps = [
            makeApp(name: "Small", bundleID: "a", size: 100),
            makeApp(name: "Big", bundleID: "b", size: 9999),
            makeApp(name: "Medium", bundleID: "c", size: 1024)
        ]
        vm.sortKey = .size
        vm.sortAscending = false
        XCTAssertEqual(vm.filteredApps.map(\.displayName), ["Big", "Medium", "Small"])
    }

    func testSortByNameAscending() {
        let vm = makeViewModel()
        vm.apps = [
            makeApp(name: "Zoom", bundleID: "a", size: 100),
            makeApp(name: "Atom", bundleID: "b", size: 9999),
            makeApp(name: "Brave", bundleID: "c", size: 1024)
        ]
        vm.sortKey = .name
        vm.sortAscending = true
        XCTAssertEqual(vm.filteredApps.map(\.displayName), ["Atom", "Brave", "Zoom"])
    }
}
