import CoreData
import Foundation

@MainActor
public final class CoreDataStack: ObservableObject {
    public static let shared = CoreDataStack()

    private let modelName = "kSpaceClean"
    private let isTestEnvironment: Bool

    public private(set) lazy var container: NSPersistentContainer = {
        let bundle = Bundle(for: FileEntry.self)
        guard let model = NSManagedObjectModel.mergedModel(from: [bundle]) else {
            fatalError("Failed to load Core Data model")
        }
        let container = NSPersistentContainer(name: modelName, managedObjectModel: model)

        if isTestEnvironment {
            // In-memory store for tests
            if let desc = container.persistentStoreDescriptions.first {
                desc.url = URL(fileURLWithPath: "/dev/null")
                desc.type = NSInMemoryStoreType
            }
        } else {
            // Production: use app group container if available, fall back to Application Support
            let storeURL: URL? = {
                if let groupURL = FileManager.default
                    .containerURL(forSecurityApplicationGroupIdentifier: "group.app.kraftly.sclean") {
                    return groupURL.appendingPathComponent("\(modelName).sqlite")
                }
                // Fallback when not sandboxed (e.g. Debug / no code signing)
                let appSupport = FileManager.default.urls(
                    for: .applicationSupportDirectory, in: .userDomainMask
                ).first
                let dir = appSupport?.appendingPathComponent("kSpaceClean")
                if let dir {
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                }
                return dir?.appendingPathComponent("\(modelName).sqlite")
            }()

            if let desc = container.persistentStoreDescriptions.first {
                desc.url = storeURL
                print("[CoreData] Store URL: \(storeURL?.path ?? "nil")")
            }
        }

        container.loadPersistentStores { _, error in
            if let error = error {
                print("[CoreData] Store load error: \(error)")
                if self.isTestEnvironment {
                    fatalError("Test Core Data stack failed: \(error)")
                }
            } else {
                print("[CoreData] Store loaded successfully")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }()

    public var viewContext: NSManagedObjectContext { container.viewContext }

    private init(isTestEnvironment: Bool = false) {
        self.isTestEnvironment = isTestEnvironment
    }

    public static func createTestInstance() -> CoreDataStack {
        let stack = CoreDataStack(isTestEnvironment: true)
        _ = stack.container
        return stack
    }

    public func save() {
        guard viewContext.hasChanges else { return }
        try? viewContext.save()
    }

    public func backgroundContext() -> NSManagedObjectContext {
        container.newBackgroundContext()
    }
}
