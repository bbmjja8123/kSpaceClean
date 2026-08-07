import Foundation

/// Asynchronously computes on-disk sizes for a batch of installed apps.
///
/// Runs every `AppCatalogService.sizeOfApp(at:)` call inside a `TaskGroup`
/// so the UI can publish results as soon as the first few apps finish,
/// rather than waiting for the slowest one. The returned dictionary is
/// keyed by `InstalledApp.bundleID` so callers can merge the result into
/// their existing list without rebuilding it.
actor AppSizeCalculator {
    private let catalogService: AppCatalogService

    init(catalogService: AppCatalogService) {
        self.catalogService = catalogService
    }

    /// Computes sizes for all apps concurrently, returning as they complete.
    ///
    /// - Parameter apps: The apps whose bundle directories should be measured.
    /// - Returns: Dictionary keyed by `bundleID`, mapping to size in bytes.
    ///   Apps whose size could not be measured (sandbox denial, missing
    ///   bundle) contribute an entry of `0`.
    func computeSizes(for apps: [InstalledApp]) async -> [String: Int64] {
        await withTaskGroup(of: (String, Int64).self) { group in
            for app in apps {
                group.addTask { [catalogService] in
                    let size = await catalogService.sizeOfApp(at: app.url)
                    return (app.bundleID, size)
                }
            }
            var results: [String: Int64] = [:]
            for await (bundleID, size) in group {
                results[bundleID] = size
            }
            return results
        }
    }
}
