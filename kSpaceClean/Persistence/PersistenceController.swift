// kSpaceClean/Persistence/PersistenceController.swift
import CoreData
import Foundation

/// The one and only `NSManagedObjectModel` for kSpaceClean.
///
/// Core Data resolves `NSManagedObject` subclasses to entities by scanning *every* loaded
/// model. Loading the same `.momd` twice therefore produces
/// "Failed to find a unique match for an NSEntityDescription to a managed object subclass"
/// and `Entity(context:)` silently falls back to the wrong description. Every container in
/// the app — production and test — must be built from this single cached instance.
enum CoreDataModel {
    static let shared: NSManagedObjectModel = {
        let bundle = Bundle(for: CleanupHistoryItem.self)
        guard let model = NSManagedObjectModel.mergedModel(from: [bundle]) else {
            fatalError("Failed to load Core Data model from \(bundle.bundlePath)")
        }
        return model
    }()
}

/// Core Data entry point for cleanup history (Task C1).
///
/// ## Why this exists alongside `CoreDataStack`
/// `CoreDataStack` is a `@MainActor` `ObservableObject` owned by the SwiftUI layer.
/// `CleanupEngine` (Task C2) is an `actor` and must reach Core Data off the main actor,
/// so it needs a non-isolated handle. `PersistenceController` is that handle: in
/// production it *shares* `CoreDataStack`'s `NSPersistentContainer` — one store, one set
/// of contexts, no duplicate SQLite file — while `init(inMemory: true)` builds an
/// isolated container for tests.
///
/// ## Retention
/// History rows expire after `CleanupHistoryRetention.days` (30). Expiry is lazy:
/// nothing runs on a timer. Callers invoke `purgeExpiredHistory()` when they next touch
/// the history — typically after a cleanup finishes or when the History tab appears.
public final class PersistenceController: @unchecked Sendable {

    /// Shared production controller, backed by the app-wide `CoreDataStack` container.
    ///
    /// `@MainActor` only guards *construction* — reaching `CoreDataStack.shared.container`
    /// requires the main actor. Once built, the instance itself is non-isolated, which is
    /// the whole point: `CleanupEngine` is an `actor` and needs off-main access. Actors
    /// resolve `.shared` once via `await` and then use it freely.
    @MainActor
    public static let shared = PersistenceController(stack: CoreDataStack.shared)

    /// The container backing every context handed out by this controller.
    public let container: NSPersistentContainer

    /// Main-queue context, for SwiftUI fetch requests.
    public var viewContext: NSManagedObjectContext { container.viewContext }

    // MARK: - Init

    /// Production initializer — adopts an existing `CoreDataStack`'s container so the app
    /// has exactly one store on disk.
    @MainActor
    public init(stack: CoreDataStack) {
        self.container = stack.container
    }

    /// Test initializer.
    /// - Parameter inMemory: when `true`, backs the store with `NSInMemoryStoreType`
    ///   so each test gets a clean slate and nothing touches disk. `false` builds a
    ///   separate on-disk container and is intended only for diagnostics.
    public init(inMemory: Bool) {
        let container = NSPersistentContainer(name: "kSpaceClean",
                                              managedObjectModel: CoreDataModel.shared)

        if inMemory, let desc = container.persistentStoreDescriptions.first {
            desc.url = URL(fileURLWithPath: "/dev/null")
            desc.type = NSInMemoryStoreType
        }

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError {
            fatalError("Core Data store failed to load: \(loadError)")
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
        self.container = container
    }

    // MARK: - Saving

    /// Saves `viewContext` if it has pending changes.
    ///
    /// Failures are logged rather than thrown: a failed history write must never abort a
    /// cleanup that already moved files to the trash.
    public func save() {
        save(context: viewContext)
    }

    /// Saves an arbitrary context if it has pending changes.
    public func save(context: NSManagedObjectContext) {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("[Persistence] Save failed: \(error)")
        }
    }

    /// A fresh background context for write-heavy work (history inserts during cleanup).
    public func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    // MARK: - Cleanup history

    /// Inserts one history row per target. Does **not** save — the caller batches the save
    /// so a whole cleanup run commits atomically.
    /// - Returns: the inserted objects, in the order given.
    @discardableResult
    public func insertHistory(targets: [CleanupTarget],
                              cleanedAt: Date = Date(),
                              in context: NSManagedObjectContext) -> [CleanupHistoryItem] {
        targets.map { target in
            let item = CleanupHistoryItem(context: context)
            item.id = target.id
            item.path = target.url.path
            item.size = target.size
            item.cleanedAt = cleanedAt
            item.bundleID = target.bundleID
            item.categoryID = target.categoryID
            item.risk = target.risk
            return item
        }
    }

    /// Fetches history rows newest-first.
    /// - Parameter limit: maximum rows to return; `0` means unlimited.
    public func fetchHistory(limit: Int = 0,
                             in context: NSManagedObjectContext? = nil) -> [CleanupHistoryItem] {
        let context = context ?? viewContext
        let request = CleanupHistoryItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "cleanedAt", ascending: false)]
        if limit > 0 { request.fetchLimit = limit }
        do {
            return try context.fetch(request)
        } catch {
            print("[Persistence] History fetch failed: \(error)")
            return []
        }
    }

    /// Lazy 30-day expiry: deletes history rows older than the retention window.
    ///
    /// Call sites trigger this opportunistically (after a cleanup, on History tab appear)
    /// rather than on a timer, so an app that is never opened costs nothing.
    ///
    /// - Parameters:
    ///   - days: retention window in days.
    ///   - now: injectable clock for tests.
    /// - Returns: number of rows deleted.
    @discardableResult
    public func purgeExpiredHistory(olderThan days: Int = CleanupHistoryRetention.days,
                                    now: Date = Date(),
                                    in context: NSManagedObjectContext? = nil) -> Int {
        let context = context ?? viewContext
        let cutoff = CleanupHistoryRetention.cutoff(from: now, days: days)

        let request = CleanupHistoryItem.fetchRequest()
        // Rows with a nil `cleanedAt` are malformed; sweep them too rather than leaking
        // rows that can never satisfy a date predicate.
        request.predicate = NSPredicate(format: "cleanedAt < %@ OR cleanedAt == nil",
                                        cutoff as NSDate)

        let expired: [CleanupHistoryItem]
        do {
            expired = try context.fetch(request)
        } catch {
            print("[Persistence] Purge fetch failed: \(error)")
            return 0
        }

        guard !expired.isEmpty else { return 0 }
        expired.forEach(context.delete)
        save(context: context)
        return expired.count
    }

    /// Deletes every history row. Used by Settings → "清除清理历史".
    /// - Returns: number of rows deleted.
    @discardableResult
    public func deleteAllHistory(in context: NSManagedObjectContext? = nil) -> Int {
        let context = context ?? viewContext
        let items = fetchHistory(in: context)
        guard !items.isEmpty else { return 0 }
        items.forEach(context.delete)
        save(context: context)
        return items.count
    }
}
