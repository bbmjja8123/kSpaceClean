import CoreData
import Foundation

@MainActor
public final class CoreDataStack: ObservableObject {
    public static let shared = CoreDataStack()

    private let modelName = "kWise"
    private let isTestEnvironment: Bool

    public private(set) lazy var container: NSPersistentContainer = {
        // Shared model instance — see `CoreDataModel` for why loading it twice breaks
        // NSManagedObject subclass → entity resolution.
        let container = NSPersistentContainer(name: modelName,
                                              managedObjectModel: CoreDataModel.shared)

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
                let dir = appSupport?.appendingPathComponent("kWise")
                if let dir {
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                }
                return dir?.appendingPathComponent("\(modelName).sqlite")
            }()

            if let desc = container.persistentStoreDescriptions.first {
                desc.url = storeURL
                Log.ui.info("[CoreData] Store URL: \(storeURL?.path ?? "nil")")
            }
        }

        container.loadPersistentStores { _, error in
            if let error = error {
                Log.ui.error("[CoreData] Store load error: \(error)")
                if self.isTestEnvironment {
                    fatalError("Test Core Data stack failed: \(error)")
                }
            } else {
                Log.ui.info("[CoreData] Store loaded successfully")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }()

    public var viewContext: NSManagedObjectContext { container.viewContext }

    private init(isTestEnvironment: Bool? = nil) {
        // Test host (kWiseTests) launches the real app binary — it must
        // never touch the user's real App Group store. On this machine the
        // unsigned test host wedges inside sqlite `guarded_open_np` on that
        // path ("test runner hung before establishing connection", root
        // cause identical to the kSift fix — see project memory). Under
        // XCTest, isolate the store in-memory instead.
        self.isTestEnvironment = isTestEnvironment
            ?? (ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil)
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
