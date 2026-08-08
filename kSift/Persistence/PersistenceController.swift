import CoreData
import Foundation

public final class PersistenceController: @unchecked Sendable {
    public static let shared = PersistenceController()

    public let container: NSPersistentContainer

    private init() {
        let bundle = Bundle(for: ScanRecordEntity.self)
        guard let modelURL = bundle.url(forResource: "kSift", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Failed to load Core Data model")
        }

        let container = NSPersistentContainer(name: "kSift", managedObjectModel: model)
        let storeURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.app.kraftly.ksift")!
            .appendingPathComponent("kSift.sqlite")

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
