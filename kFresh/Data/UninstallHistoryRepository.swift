import CoreData
import Foundation

/// Persistent store of uninstall records backing the History tab and the
/// restore flow.
///
/// Wave 0 stored records in an in-memory `[UninstallRecord]` array, so
/// history was lost on every relaunch. This iteration is backed by Core Data
/// so uninstall history survives app restarts.
///
/// ## Model
///
/// The `UninstallHistory` entity is built **programmatically** via
/// `NSEntityDescription`/`NSAttributeDescription` (no `.xcdatamodeld` file).
/// That keeps the store entirely inside this file: adding the repository
/// never requires touching `kFresh.xcodeproj` or `generate_project.py`, and
/// the entity matches `UninstallHistory` / `UninstallHistory+CoreDataProperties`.
///
/// ## Threading
///
/// All reads and writes go through a dedicated background context wrapped in
/// `performAndWait`, so the actor's serialised access never races Core Data's
/// queue. A store load failure is logged and the repository degrades to an
/// empty history instead of crashing the app (log-and-continue).
actor UninstallHistoryRepository {
    private let context: NSManagedObjectContext

    /// Creates the repository.
    ///
    /// - Parameter inMemory: When `true`, uses an in-memory store so tests /
    ///   previews never touch the on-disk database. Defaults to `false`, which
    ///   backs the store at
    ///   `~/Library/Application Support/app.kraftly.kfresh/UninstallHistory.sqlite`.
    init(inMemory: Bool = false) {
        let container = NSPersistentContainer(
            name: "UninstallHistory",
            managedObjectModel: Self.makeModel()
        )
        if inMemory {
            container.persistentStoreDescriptions.first?.type = NSInMemoryStoreType
        } else {
            let baseURL = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.temporaryDirectory
            let directoryURL = baseURL.appendingPathComponent("app.kraftly.kfresh", isDirectory: true)
            do {
                try FileManager.default.createDirectory(
                    at: directoryURL,
                    withIntermediateDirectories: true
                )
            } catch {
                NSLog("UninstallHistoryRepository: failed to create store directory: \(error)")
            }
            container.persistentStoreDescriptions.first?.url =
                directoryURL.appendingPathComponent("UninstallHistory.sqlite")
        }
        // Log-and-continue: a corrupt or unopenable store degrades to an empty
        // history instead of crashing the app on launch.
        container.loadPersistentStores { _, error in
            if let error {
                NSLog("UninstallHistoryRepository: failed to load persistent store: \(error)")
            }
        }
        self.context = container.newBackgroundContext()
    }

    /// Appends a new record to history.
    func save(record: UninstallRecord) {
        context.performAndWait {
            let history = UninstallHistory(context: context)
            history.id = record.id
            history.appName = record.appName
            history.bundleID = record.bundleID
            history.appPath = record.appPath
            history.actualTrashPath = record.actualTrashPath
            history.appSize = record.appSize
            history.totalResidueSize = record.totalResidueSize
            history.residueCount = record.residueCount
            history.uninstalledAt = record.uninstalledAt
            history.isRestored = record.isRestored
            history.backupPath = record.backupPath
            history.residues = record.residues
            do {
                try context.save()
            } catch {
                NSLog("UninstallHistoryRepository: save failed: \(error)")
            }
        }
    }

    /// Returns all history records, newest first.
    func fetchAll() -> [UninstallRecord] {
        context.performAndWait {
            let request = UninstallHistory.fetchRequest()
            request.sortDescriptors = [
                NSSortDescriptor(key: "uninstalledAt", ascending: false)
            ]
            do {
                let results = try context.fetch(request)
                return results.map(Self.mapRecord)
            } catch {
                NSLog("UninstallHistoryRepository: fetchAll failed: \(error)")
                return []
            }
        }
    }

    /// Returns uninstall records whose `uninstalledAt` falls within the given
    /// number of days, newest first. Non-throwing so the AppList scan can
    /// refresh the recent-uninstall section without error handling.
    func fetchAll(within days: Int) -> [UninstallRecord] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        return fetchAll().filter { $0.uninstalledAt >= cutoff }
    }

    /// Returns the uninstall record matching `id`, or `nil` if no record with
    /// that ID has been saved. Used by `TrashMover.historyRecord(id:)` and
    /// tests that need to assert post-conditions (e.g. `isRestored` flipped)
    /// without reaching into the private storage.
    func record(id: UUID) -> UninstallRecord? {
        context.performAndWait {
            let request = UninstallHistory.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            do {
                let result = try context.fetch(request).first
                return result.map(Self.mapRecord)
            } catch {
                NSLog("UninstallHistoryRepository: record lookup failed: \(error)")
                return nil
            }
        }
    }

    /// Flips `isRestored` to `true` on the record matching `id`. A missing
    /// record is a no-op (nothing to mark).
    func markRestored(id: UUID) {
        context.performAndWait {
            let request = UninstallHistory.fetchRequest()
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            do {
                guard let history = try context.fetch(request).first else { return }
                history.isRestored = true
                try context.save()
            } catch {
                NSLog("UninstallHistoryRepository: markRestored failed: \(error)")
            }
        }
    }

    /// Returns the most recent `limit` uninstall records (newest first) so
    /// callers (tests included) can inspect stored state without reaching
    /// into private storage.
    func recentRecords(limit: Int) -> [UninstallRecord] {
        Array(fetchAll().prefix(limit))
    }

    /// Deletes records whose `uninstalledAt` predates the given number of
    /// days. Used by the 30-day retention window.
    func deleteExpired(olderThan days: Int) {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        context.performAndWait {
            let request = UninstallHistory.fetchRequest()
            request.predicate = NSPredicate(format: "uninstalledAt < %@", cutoff as NSDate)
            do {
                let results = try context.fetch(request)
                for history in results {
                    context.delete(history)
                }
                try context.save()
            } catch {
                NSLog("UninstallHistoryRepository: deleteExpired failed: \(error)")
            }
        }
    }

    // MARK: - Mapping

    /// Maps a managed object back to its value type. Static because the
    /// `performAndWait` closure runs on the context queue, not the actor.
    private static func mapRecord(_ history: UninstallHistory) -> UninstallRecord {
        UninstallRecord(
            id: history.id,
            appName: history.appName,
            bundleID: history.bundleID,
            appPath: history.appPath,
            actualTrashPath: history.actualTrashPath,
            appSize: history.appSize,
            totalResidueSize: history.totalResidueSize,
            residueCount: history.residueCount,
            uninstalledAt: history.uninstalledAt,
            isRestored: history.isRestored,
            backupPath: history.backupPath,
            residues: history.residues
        )
    }

    /// Builds the `UninstallHistory` entity description matching
    /// `UninstallHistory+CoreDataProperties.swift` plus the `actualTrashPath`
    /// attribute added for the restore-from-actual-path fix.
    private static func makeModel() -> NSManagedObjectModel {
        let entity = NSEntityDescription()
        entity.name = "UninstallHistory"
        entity.managedObjectClassName = NSStringFromClass(UninstallHistory.self)
        entity.properties = [
            attribute("id", type: .UUIDAttributeType),
            attribute("appName", type: .stringAttributeType),
            attribute("bundleID", type: .stringAttributeType),
            attribute("appPath", type: .stringAttributeType),
            attribute("actualTrashPath", type: .stringAttributeType),
            attribute("appSize", type: .integer64AttributeType),
            attribute("totalResidueSize", type: .integer64AttributeType),
            attribute("residueCount", type: .integer32AttributeType),
            attribute("uninstalledAt", type: .dateAttributeType),
            attribute("isRestored", type: .booleanAttributeType),
            attribute("backupPath", type: .stringAttributeType),
        ]

        let residueData = NSAttributeDescription()
        residueData.name = "residueData"
        residueData.attributeType = .binaryDataAttributeType
        residueData.isOptional = true
        entity.properties.append(residueData)

        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }

    /// Convenience factory for a non-optional attribute.
    private static func attribute(_ name: String, type: NSAttributeType) -> NSAttributeDescription {
        let description = NSAttributeDescription()
        description.name = name
        description.attributeType = type
        description.isOptional = false
        return description
    }
}
