import XCTest
import AppKit
@testable import kFresh

@MainActor
final class AppListViewModelTests: XCTestCase {
    func makeApp(name: String, bundleID: String, size: Int64, installDate: Date? = Date()) -> InstalledApp {
        InstalledApp(
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            displayName: name,
            bundleID: bundleID,
            version: "1.0",
            icon: NSImage(),
            sizeBytes: size,
            source: .userInstalled,
            isRunning: false,
            lastUsedDate: Date(),
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

    func testStartScanTransitionsToCompleted() async {
        let vm = makeViewModel()
        XCTAssertEqual(vm.scanState, .idle)
        await vm.startScan()
        if case .completed(let count) = vm.scanState {
            XCTAssertEqual(count, vm.apps.count,
                           "completed state must report the number of apps the scan actually found")
        } else {
            XCTFail("Expected .completed, got \(vm.scanState)")
        }
    }

    func testUninstalledAppsStaysEmptyWithEmptyHistory() async {
        let vm = makeViewModel()
        await vm.startScan()
        XCTAssertTrue(vm.uninstalledApps.isEmpty, "Fresh repository must surface no uninstall records")
    }

    func testScanPopulatesApps() async {
        let vm = makeViewModel()
        XCTAssertTrue(vm.apps.isEmpty)
        await vm.startScan()
        XCTAssertFalse(vm.apps.isEmpty, "Real catalog scan must find at least the running kFresh host app")
    }

    func testSortDirectionToggles() {
        let vm = makeViewModel()
        vm.apps = [
            makeApp(name: "Alpha", bundleID: "com.example.alpha", size: 100),
            makeApp(name: "Beta", bundleID: "com.example.beta", size: 200),
            makeApp(name: "Gamma", bundleID: "com.example.gamma", size: 300)
        ]
        vm.sortKey = .name
        vm.sortAscending = true
        let ascending = vm.filteredApps.map(\.displayName)
        vm.sortAscending = false
        let descending = vm.filteredApps.map(\.displayName)
        XCTAssertEqual(ascending, ["Alpha", "Beta", "Gamma"])
        XCTAssertEqual(descending, ascending.reversed())
    }

    func testRefreshRunsScanAgain() async {
        let vm = makeViewModel()
        await vm.refresh()
        if case .completed = vm.scanState {
            // pass
        } else {
            XCTFail("Expected .completed after refresh, got \(vm.scanState)")
        }
    }

    func testInstallDateSortPinsNilDatesToBottomBothDirections() {
        let vm = makeViewModel()
        vm.apps = [
            makeApp(name: "Alpha", bundleID: "com.example.alpha", size: 100, installDate: Date(timeIntervalSince1970: 1_000_000)),
            makeApp(name: "Beta", bundleID: "com.example.beta", size: 200, installDate: Date(timeIntervalSince1970: 2_000_000)),
            makeApp(name: "Gamma", bundleID: "com.example.gamma", size: 300, installDate: nil)
        ]
        vm.sortKey = .installDate
        vm.sortAscending = true
        XCTAssertEqual(vm.filteredApps.map(\.displayName), ["Alpha", "Beta", "Gamma"],
                       "nil install dates must sort to the bottom in ascending order")
        vm.sortAscending = false
        XCTAssertEqual(vm.filteredApps.map(\.displayName), ["Beta", "Alpha", "Gamma"],
                       "nil install dates must stay at the bottom in descending order")
    }
}
