import XCTest
import AppKit
@testable import kFresh

@MainActor
final class AppListFilterSortTests: XCTestCase {
    func makeApp(name: String, bundleID: String, size: Int64, source: AppSource = .userInstalled, installDate: Date? = Date(), lastUsedDate: Date? = Date()) -> InstalledApp {
        InstalledApp(
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            displayName: name,
            bundleID: bundleID,
            version: "1.0",
            icon: NSImage(),
            sizeBytes: size,
            source: source,
            isRunning: false,
            lastUsedDate: lastUsedDate,
            installDate: installDate
        )
    }

    private func makeViewModel() -> AppListViewModel {
        AppListViewModel(
            catalog: AppCatalogService(),
            historyRepo: UninstallHistoryRepository(inMemory: true),
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

    func testRecentlyInstalledFiltersOnInstallDate() {
        let vm = makeViewModel()
        // Installed within the 7-day window but never opened since install:
        // must appear in "最近安装" because the filter keys on installDate.
        let freshInstall = makeApp(
            name: "FreshInstall", bundleID: "com.example.fresh", size: 100,
            installDate: Date(),
            lastUsedDate: Date().addingTimeInterval(-30 * 24 * 3600)
        )
        // Installed long ago but opened today: must NOT appear in "最近安装",
        // even though its lastUsedDate is fresh — the two dates are distinct.
        let openedToday = makeApp(
            name: "OpenedToday", bundleID: "com.example.opened", size: 200,
            installDate: Date().addingTimeInterval(-30 * 24 * 3600),
            lastUsedDate: Date()
        )
        vm.apps = [freshInstall, openedToday]
        vm.category = .recentlyInstalled
        XCTAssertEqual(vm.filteredApps.map(\.displayName), ["FreshInstall"])
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

    func testSortByInstallDateOrdersInstallDateNotLastUsedDate() {
        let vm = makeViewModel()
        // Alpha: installed 30 days ago, opened today.
        let alpha = makeApp(
            name: "Alpha", bundleID: "a", size: 100,
            installDate: Date().addingTimeInterval(-30 * 24 * 3600),
            lastUsedDate: Date()
        )
        // Beta: installed today, opened 30 days ago.
        let beta = makeApp(
            name: "Beta", bundleID: "b", size: 200,
            installDate: Date(),
            lastUsedDate: Date().addingTimeInterval(-30 * 24 * 3600)
        )
        vm.apps = [alpha, beta]

        // "安装时间" ascending: older install first — Alpha before Beta.
        vm.sortKey = .installDate
        vm.sortAscending = true
        XCTAssertEqual(vm.filteredApps.map(\.displayName), ["Alpha", "Beta"],
                       "installDate sort must order by installDate, not lastUsedDate")

        // "最近使用" ascending on the same pair flips the order, proving the
        // two sort keys are independent.
        vm.sortKey = .lastUsedDate
        vm.sortAscending = true
        XCTAssertEqual(vm.filteredApps.map(\.displayName), ["Beta", "Alpha"],
                       "lastUsedDate sort must order by lastUsedDate, diverging from installDate")
    }
}
