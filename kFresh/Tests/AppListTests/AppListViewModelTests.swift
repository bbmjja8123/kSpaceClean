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

    // MARK: - Drag-and-drop ingestion (Wave 2 P1, G-KF-03)

    /// Drop a real `.app` bundle (laid out on disk via the helper) and
    /// assert it lands in the apps list with a synthesized display name.
    func testIngestDroppedAppAddsVirtualEntry() throws {
        let vm = makeViewModel()
        let url = try makeFakeAppBundle(named: "DroppedApp")

        let before = vm.apps.count
        vm.ingestDroppedApp(url: url)
        XCTAssertEqual(vm.apps.count, before + 1,
                       "Dropped .app must appear as a new entry in the list")

        let dropped = vm.apps.first { $0.bundleID == "dropped.DroppedApp" }
            ?? vm.apps.first { $0.displayName == "DroppedApp" }
        XCTAssertNotNil(dropped, "Dropped app must be discoverable by name or bundle ID")
        XCTAssertEqual(dropped?.sizeBytes, 0, "Virtual entry starts with placeholder size")
        XCTAssertEqual(dropped?.source, .unknown,
                       "Dropped apps with no CFBundleIdentifier default to .unknown source")
    }

    /// Dropping the same `.app` twice must NOT create a duplicate entry —
    /// the second call short-circuits on the existing bundle ID.
    func testIngestDroppedAppIsIdempotent() throws {
        let vm = makeViewModel()
        let url = try makeFakeAppBundle(named: "DoubleDrop")

        vm.ingestDroppedApp(url: url)
        let countAfterFirst = vm.apps.count
        vm.ingestDroppedApp(url: url)
        XCTAssertEqual(vm.apps.count, countAfterFirst,
                       "Second drop of the same .app must be a no-op")
    }

    /// The "drop a folder containing the .app" gesture must walk into
    /// the inner `.app` so users don't have to drill down themselves.
    func testIngestDroppedAppWalksIntoSingleAppFolder() throws {
        let vm = makeViewModel()
        let container = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kFreshDropContainer-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }

        let innerName = "InnerApp.app"
        try FileManager.default.createDirectory(
            at: container.appendingPathComponent(innerName, isDirectory: true),
            withIntermediateDirectories: true
        )

        let before = vm.apps.count
        vm.ingestDroppedApp(url: container)

        XCTAssertEqual(vm.apps.count, before + 1)
        // The synthetic bundle ID uses the inner app's folder name.
        let dropped = vm.apps.first { $0.bundleID == "dropped.InnerApp" }
        XCTAssertNotNil(dropped)
        XCTAssertEqual(dropped?.url.lastPathComponent, innerName)
    }

    /// A non-app URL (e.g. a random .txt) is silently ignored — no
    /// exception, no row added.
    func testIngestDroppedAppRejectsNonAppURL() {
        let vm = makeViewModel()
        let txt = URL(fileURLWithPath: "/tmp/notes.txt") // never created on disk
        let before = vm.apps.count
        vm.ingestDroppedApp(url: txt)
        XCTAssertEqual(vm.apps.count, before,
                       "Non-app drop must be a silent no-op (matches AppCleaner / Pearcleaner)")
    }

    /// Build a fake `.app` bundle directory on disk for the drop tests.
    /// The directory must exist for `fileExists(atPath:)` to pass inside
    /// ``ingestDroppedApp(url:)``; we don't need a real `Info.plist` —
    /// the resolver falls back to a synthetic bundle ID derived from
    /// the folder name.
    private func makeFakeAppBundle(named name: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("kFreshDropTest-\(UUID().uuidString)/\(name).app",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
