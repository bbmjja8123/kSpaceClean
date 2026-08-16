import Foundation
import Combine

/// View-model backing `TCCOverviewView`.
///
/// Wraps ``TCCReader`` and exposes only the publish bits the view needs.
/// On refresh, if the reader returned no rows (typical when FDA hasn't been
/// granted), the VM seeds `categories` with ``TCCReader/fallbackCategories()``
/// so the view can render a populated grid with the FDA prompt on top.
///
/// - SeeAlso: `docs/superpowers/plans/2026-08-09-kwise-v1.5-plan.md` Task 9
@MainActor
public final class TCCOverviewViewModel: ObservableObject {
    @Published public private(set) var categories: [PermissionCategory] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastError: TCCReaderError?
    @Published public private(set) var lastRefreshedAt: Date?

    private let reader: TCCReader

    public init(reader: TCCReader = TCCReader()) {
        self.reader = reader
    }

    /// Refresh from TCC.db. Falls back to ``TCCReader.fallbackCategories()``
    /// when the real database is unreadable so the user always sees a grid.
    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        await reader.refresh()
        if reader.categories.isEmpty {
            categories = reader.fallbackCategories()
        } else {
            categories = reader.categories
        }
        lastError = reader.lastError
        lastRefreshedAt = reader.lastRefreshedAt
    }

    /// Whether the reader flagged the last refresh as needing Full Disk Access.
    /// Drives the "打开系统设置" prompt at the top of the overview.
    public var needsFullDiskAccess: Bool {
        if case .databaseUnreadable = (reader.lastError ?? self.lastError) {
            return true
        }
        return false
    }
}