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
    @Published var searchText = ""
    @Published var category: Category = .all
    @Published var sortKey: SortKey = .name
    @Published var sortAscending = true

    // MARK: - Dependencies

    private let catalog: AppCatalogService
    private let historyRepo: UninstallHistoryRepository
    private let fdaProbe: FDAPermissionProbe

    // MARK: - Init

    init(catalog: AppCatalogService,
         historyRepo: UninstallHistoryRepository,
         fdaProbe: FDAPermissionProbe) {
        self.catalog = catalog
        self.historyRepo = historyRepo
        self.fdaProbe = fdaProbe
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
                ascending = a.sizeBytes < b.sizeBytes
            case .installDate:
                ascending = (a.installDate ?? .distantPast) < (b.installDate ?? .distantPast)
            case .lastUsedDate:
                ascending = (a.lastUsedDate ?? .distantPast) < (b.lastUsedDate ?? .distantPast)
            }
            return sortAscending ? ascending : !ascending
        }
        return result
    }

    // MARK: - Actions

    /// Runs a catalog scan, then refreshes the recent-uninstall section.
    ///
    /// All three dependencies are non-throwing, so a scan that cannot read a
    /// directory degrades to a partial catalog instead of an error state.
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
    }

    /// Re-runs the scan, preserving the user's filter / sort / selection.
    func refresh() async {
        await startScan()
    }
}
