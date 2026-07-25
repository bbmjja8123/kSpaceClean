import CoreData
import Foundation

public final class PersistenceController: Sendable {
    public static let shared = PersistenceController()

    nonisolated(unsafe) public let container: NSPersistentContainer

    private init() {
        let bundle = Bundle(for: ScanRecordEntity.self)
        guard let modelURL = bundle.url(forResource: "kDupe", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Failed to load Core Data model")
        }

        let container = NSPersistentContainer(name: "kDupe", managedObjectModel: model)
        let storeURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.app.kraftly.kdupe")!
            .appendingPathComponent("kDupe.sqlite")

        container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: storeURL)]
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Core Data store failed: \(error)")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        self.container = container
    }

    public func saveContext() {
        let context = container.viewContext
        if context.hasChanges {
            try? context.save()
        }
    }
}
