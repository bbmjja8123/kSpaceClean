import CoreData
import Foundation
import os

public final class PersistenceController: @unchecked Sendable {
    public static let shared = PersistenceController()

    public let container: NSPersistentContainer

    private static let log = Logger(subsystem: "app.kraftly.ksift", category: "persistence")

    private init() {
        let bundle = Bundle(for: ScanRecordEntity.self)
        guard let modelURL = bundle.url(forResource: "kSift", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Failed to load Core Data model")
        }

        let container = NSPersistentContainer(name: "kSift", managedObjectModel: model)

        // Prefer the App Group container so the Finder Sync extension can
        // share the same store; fall back to Application Support if the
        // entitlement is missing (development machines, unsigned runs).
        let storeURL: URL
        if let appGroup = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.app.kraftly.ksift") {
            storeURL = appGroup.appendingPathComponent("kSift.sqlite")
        } else {
            Self.log.warning("App Group container unavailable — falling back to Application Support. Check kSift.entitlements.")
            let fallback = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
            storeURL = fallback.appendingPathComponent("kSift.sqlite")
        }

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
