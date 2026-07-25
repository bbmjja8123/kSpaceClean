import CoreData

public final class CleanupHistory: Sendable {
    private let stack = CoreDataStack.shared

    public init() {}

    public func recordCleanup(snapshot: TrashSnapshot) {
        let ctx = stack.backgroundContext()
        ctx.perform {
            let record = CleanupRecord(context: ctx)
            record.id = UUID()
            record.cleanedAt = Date()
            record.totalBytes = snapshot.fileSize
            record.isRestored = false

            let entry = FileEntry(context: ctx)
            entry.id = UUID()
            entry.path = snapshot.originalPath
            entry.size = snapshot.fileSize
            entry.category = ""
            entry.confidence = 0
            record.entries = NSSet(object: entry)

            try? ctx.save()
        }
    }

    public func restore(record: CleanupRecord) async -> Bool {
        guard let entries = record.entries?.allObjects as? [FileEntry] else { return false }
        var allRestored = true
        for entry in entries {
            let trashDir = FileManager.default.trashDirectory
            let originalURL = URL(fileURLWithPath: entry.path)
            let trashURL = trashDir?.appendingPathComponent(originalURL.lastPathComponent) ?? originalURL
            let fm = FileManager.default

            if fm.fileExists(atPath: trashURL.path) {
                try? fm.createDirectory(at: originalURL.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
                do {
                    try fm.moveItem(at: trashURL, to: originalURL)
                } catch {
                    allRestored = false
                }
            }
        }
        if allRestored {
            let ctx = stack.backgroundContext()
            ctx.perform {
                record.isRestored = true
                try? ctx.save()
            }
        }
        return allRestored
    }

    public func fetchRecent(limit: Int = 50) -> [CleanupRecord] {
        let fetch = CleanupRecord.fetchRequest()
        fetch.sortDescriptors = [NSSortDescriptor(key: "cleanedAt", ascending: false)]
        fetch.fetchLimit = limit
        return (try? stack.viewContext.fetch(fetch)) ?? []
    }
}
