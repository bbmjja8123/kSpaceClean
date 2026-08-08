import CoreData
import Foundation

/// Core Data-backed incremental index storage, sharing the main kSift store.
///
/// Persisting wholesale-replaces the stored record set after every scan so the
/// index never drifts from the files actually seen on disk.
public actor IncrementalIndexRepositoryCoreData: IncrementalIndexRepositoryProtocol {
    private let controller: PersistenceController

    public init(controller: PersistenceController = .shared) {
        self.controller = controller
    }

    public func loadRecords() async throws -> [IncrementalIndexRecord] {
        let context = controller.container.newBackgroundContext()
        return try await context.perform {
            let request = IncrementalIndexEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "path", ascending: true)]
            request.fetchBatchSize = 2000
            let results = try context.fetch(request)
            return results.map { entity in
                IncrementalIndexRecord(
                    path: entity.path,
                    size: entity.size,
                    modificationDate: entity.modificationDate,
                    inode: entity.inode > 0 ? UInt64(entity.inode) : nil,
                    fingerprint: entity.fingerprint,
                    hash: entity.sha256
                )
            }
        }
    }

    public func saveRecords(_ records: [IncrementalIndexRecord]) async throws {
        let context = controller.container.newBackgroundContext()
        try await context.perform {
            let delete = NSBatchDeleteRequest(fetchRequest: IncrementalIndexEntity.fetchRequest())
            delete.resultType = .resultTypeCount
            _ = try context.execute(delete)

            for record in records {
                let entity = IncrementalIndexEntity(context: context)
                entity.path = record.path
                entity.size = record.size
                entity.modificationDate = record.modificationDate
                entity.inode = Int64(record.inode ?? 0)
                entity.fingerprint = record.fingerprint
                entity.sha256 = record.hash
            }
            try context.save()
        }
    }
}
