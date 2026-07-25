import CoreData

actor AppAnalysisRepository {
    private let context = CoreDataStack.shared.context

    func recordUsage(bundleID: String, displayName: String) {
        let fetch = NSFetchRequest<AppAnalysis>(entityName: "AppAnalysis")
        fetch.predicate = NSPredicate(format: "bundleID == %@", bundleID)
        fetch.fetchLimit = 1

        if let existing = try? context.fetch(fetch).first {
            existing.usedCount += 1
            existing.lastUsedDate = Date()
        } else {
            let analysis = AppAnalysis(context: context)
            analysis.id = UUID()
            analysis.bundleID = bundleID
            analysis.displayName = displayName
            analysis.firstDetectedDate = Date()
            analysis.usedCount = 1
            analysis.isAnalyzed = false
        }
        CoreDataStack.shared.save()
    }

    func analyze() {
        let fetch = NSFetchRequest<AppAnalysis>(entityName: "AppAnalysis")
        fetch.predicate = NSPredicate(format: "isAnalyzed == NO")
        guard let results = try? context.fetch(fetch) else { return }

        for analysis in results {
            if let lastUsed = analysis.lastUsedDate,
               lastUsed < Date().addingTimeInterval(-86400 * 90) {
                analysis.suggestedAction = "uninstall"
            } else if analysis.usedCount < 3 {
                analysis.suggestedAction = "never_used"
            } else {
                analysis.suggestedAction = "keep"
            }
            analysis.isAnalyzed = true
        }
        CoreDataStack.shared.save()
    }

    func fetchAnalysis(bundleID: String) -> AppAnalysis? {
        let fetch = NSFetchRequest<AppAnalysis>(entityName: "AppAnalysis")
        fetch.predicate = NSPredicate(format: "bundleID == %@", bundleID)
        fetch.fetchLimit = 1
        return try? context.fetch(fetch).first
    }
}
