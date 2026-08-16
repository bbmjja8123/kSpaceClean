import AppKit
import Combine
import Foundation

/// Backing state for the AppList main page: scan lifecycle, the filtered /
/// sorted view of the catalog, and the recent-uninstall section.
///
/// Owned by ``AppListView`` as a `@StateObject`. Every mutation runs on the
/// main actor so the `@Published` projections can drive SwiftUI directly.
@MainActor
final class AppListViewModel: ObservableObject {
    // MARK: - Nested types

    enum SortKey: String, CaseIterable, Identifiable {
        case name, size, installDate, lastUsedDate
        var id: String { rawValue }
    }

    enum Category: String, CaseIterable, Identifiable {
        case all, user, system, recentlyInstalled
        var id: String { rawValue }
    }

    enum ScanState: Equatable {
        case idle
        case scanning(progress: Double)
        case completed(count: Int)
        case failed(message: String)
    }

    // MARK: - Published state

    /// Every app discovered by the last catalog scan.
    ///
    /// The setter is internal so the test suite can seed a deterministic
    /// list; production code only mutates it from ``startScan()``.
    @Published internal(set) var apps: [InstalledApp] = []
    @Published private(set) var scanState: ScanState = .idle
    /// Uninstall records from the last 30 days, newest first.
    @Published private(set) var uninstalledApps: [UninstallRecord] = []
    /// Maps `InstalledApp.bundleID` to its on-disk size in bytes.
    ///
    /// Populated in the background by ``AppSizeCalculator`` after the catalog
    /// scan returns so the list view renders immediately with placeholder
    /// zeros and gradually fills in real numbers without blocking the UI.
    @Published private(set) var sizeMap: [String: Int64] = [:]
    /// `true` while ``AppSizeCalculator`` is still measuring app bundles.
    @Published private(set) var isSizeScanning = false
    @Published var searchText = ""
    @Published var category: Category = .all
    @Published var sortKey: SortKey = .name
    @Published var sortAscending = true

    // MARK: - Dependencies

    private let catalog: AppCatalogService
    private let historyRepo: UninstallHistoryRepository
    private let fdaProbe: FDAPermissionProbe
    private let sizeCalculator: AppSizeCalculator

    // MARK: - Init

    init(catalog: AppCatalogService,
         historyRepo: UninstallHistoryRepository,
         fdaProbe: FDAPermissionProbe,
         sizeCalculator: AppSizeCalculator? = nil) {
        self.catalog = catalog
        self.historyRepo = historyRepo
        self.fdaProbe = fdaProbe
        self.sizeCalculator = sizeCalculator ?? AppSizeCalculator(catalogService: catalog)
    }

    /// Returns the measured size for an app, falling back to the model value
    /// when the background computation has not finished yet (or could not
    /// read the bundle — sandbox denial returns `0`).
    func sizeBytes(for app: InstalledApp) -> Int64 {
        sizeMap[app.bundleID] ?? app.sizeBytes
    }

    // MARK: - Derived list

    /// Apps after applying the category filter, the search query, and the
    /// current sort order. This is the row source of the content-column
    /// `List` in ``AppListView``.
    var filteredApps: [InstalledApp] {
        var result = apps

        // Category filter.
        switch category {
        case .all:
            break
        case .user:
            result = result.filter {
                $0.source == .userInstalled || $0.source == .mas
                    || $0.source == .homebrew || $0.source == .setapp
            }
        case .system:
            result = result.filter { $0.source == .system || $0.source == .appleBuiltIn }
        case .recentlyInstalled:
            let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
            result = result.filter {
                guard let date = $0.installDate else { return false }
                return date > cutoff
            }
        }

        // Search filter.
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            result = result.filter {
                $0.displayName.lowercased().contains(query)
                    || $0.bundleID.lowercased().contains(query)
            }
        }

        // Sort.
        result.sort { a, b in
            let ascending: Bool
            switch sortKey {
            case .name:
                ascending = a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
            case .size:
                ascending = sizeBytes(for: a) < sizeBytes(for: b)
            case .installDate:
                return Self.sortByDate(a.installDate, b.installDate, ascending: sortAscending)
            case .lastUsedDate:
                return Self.sortByDate(a.lastUsedDate, b.lastUsedDate, ascending: sortAscending)
            }
            return sortAscending ? ascending : !ascending
        }
        return result
    }

    /// Orders two optional dates with nil pinned to the bottom in both
    /// directions: an app with an unknown install/last-used date never ranks
    /// above an app that has one.
    private static func sortByDate(_ lhs: Date?, _ rhs: Date?, ascending: Bool) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return false
        case (nil, _): return false
        case (_, nil): return true
        case (let lhs?, let rhs?): return ascending ? lhs < rhs : lhs > rhs
        }
    }

    // MARK: - Actions

    /// Runs a catalog scan, then refreshes the recent-uninstall section.
    ///
    /// All three dependencies are non-throwing, so a scan that cannot read a
    /// directory degrades to a partial catalog instead of an error state.
    /// Size computation is fired off in the background after the catalog
    /// returns so the list renders immediately and numbers fill in
    /// progressively.
    func startScan() async {
        scanState = .scanning(progress: 0)

        // Warm the FDA probe cache so later flows (detail scan, onboarding
        // re-check) observe a fresh status instead of `.unknown`.
        _ = await fdaProbe.probe()

        let scanned = await catalog.scan()
        apps = scanned
        scanState = .completed(count: scanned.count)

        let records = await historyRepo.fetchAll(within: 30)
        uninstalledApps = records

        // Background size pass — list is already on screen with zeros, sizes
        // fill in as each bundle is measured.
        isSizeScanning = true
        let sizes = await sizeCalculator.computeSizes(for: scanned)
        sizeMap = sizes
        isSizeScanning = false
    }

    /// Re-runs the scan, preserving the user's filter / sort / selection.
    func refresh() async {
        await startScan()
    }

    // MARK: - Drag-and-drop ingestion (Wave 2 P1, G-KF-03)

    /// Ingests a Finder-dropped URL as a virtual app entry.
    ///
    /// The full catalog scan lives behind a wall-clock budget the user
    /// shouldn't pay for a single app they're already holding in their
    /// hand. The drop handler turns "drop the .app on the window" into
    /// the same flow as "find the row in the list" without forcing a
    /// full rescan first.
    ///
    /// - The dropped URL must point at an existing `.app` bundle (or a
    ///   folder whose only child is one) — anything else is silently
    ///   ignored, mirroring the AppCleaner / Pearcleaner drop contract.
    /// - The new entry is merged into ``apps`` by bundle ID, so a second
    ///   drop of the same `.app` replaces the prior virtual entry rather
    ///   than duplicating the row.
    /// - `isRunning` defaults to `false` because a Finder drop is
    ///   presumed-intentional, not a side effect of the user launching
    ///   the app.
    func ingestDroppedApp(url: URL) {
        let resolvedURL = resolveAppURL(from: url)
        guard FileManager.default.fileExists(atPath: resolvedURL.path),
              resolvedURL.pathExtension == "app" else {
            return
        }
        let bundle = Bundle(url: resolvedURL)
        let bundleID = bundle?.bundleIdentifier
            ?? "dropped.\(resolvedURL.deletingPathExtension().lastPathComponent)"
        let displayName = bundle?.infoDictionary?["CFBundleName"] as? String
            ?? resolvedURL.deletingPathExtension().lastPathComponent
        let version = bundle?.infoDictionary?["CFBundleVersion"] as? String ?? "1.0"
        let source = AppCatalogService.classifySource(url: resolvedURL, bundleID: bundleID)

        // If a real catalog row already exists for this bundle ID, the
        // user just dropped an already-installed app — do nothing so we
        // don't double-list it.
        if apps.contains(where: { $0.bundleID == bundleID }) { return }

        let dropped = InstalledApp(
            url: resolvedURL,
            displayName: displayName,
            bundleID: bundleID,
            version: version,
            icon: NSImage(),
            sizeBytes: 0,
            source: source,
            isRunning: false,
            lastUsedDate: nil,
            residues: []
        )
        apps.append(dropped)
    }

    /// Walk one level deep if the drop URL is a folder whose only child
    /// is an `.app` bundle — that catches the common "drag a folder
    /// containing the app" Finder gesture without forcing the user to
    /// drop the inner `.app` exactly.
    private func resolveAppURL(from url: URL) -> URL {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
              isDir.boolValue else {
            return url
        }
        let children = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        if children.count == 1,
           let only = children.first,
           only.hasSuffix(".app") {
            return url.appendingPathComponent(only, isDirectory: true)
        }
        return url
    }
}
