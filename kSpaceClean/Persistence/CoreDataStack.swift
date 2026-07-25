import CoreData

public final class CoreDataStack {
    public static let shared = CoreDataStack()

    public lazy var persistentContainer: NSPersistentContainer = {
        let container = NSPersistentContainer(name: "kSpaceClean")
        let storeURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.app.kraftly.shared")!
            .appendingPathComponent("kSpaceClean.sqlite")
        container.persistentStoreDescriptions = [
            NSPersistentStoreDescription(url: storeURL)
        ]
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data load failed: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }()

    public var viewContext: NSManagedObjectContext {
        persistentContainer.viewContext
    }

    public func save() {
        guard viewContext.hasChanges else { return }
        try? viewContext.save()
    }

    public func backgroundContext() -> NSManagedObjectContext {
        persistentContainer.newBackgroundContext()
    }
}
