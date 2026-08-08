import CoreData
import Foundation

/// Core Data-backed vault storage, sharing the main kSift store.
///
/// Items are upserted by id (restored items are re-flagged in place rather than
/// re-created). Cleanup sessions are stored detached from items — the
/// `vaultItemIds` list is reconstructed by grouping items on `parentSessionId`.
public actor VaultRepositoryCoreData: VaultRepositoryProtocol {
    private let controller: PersistenceController

    public init(controller: PersistenceController = .shared) {
        self.controller = controller
    }

    public func loadVaultItems() async throws -> [VaultItem] {
        let context = controller.container.newBackgroundContext()
        return try await context.perform {
            let request = VaultItemEntity.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "vaultedAt", ascending: false)]
            let results = try context.fetch(request)
            return results.map { $0.toVaultItem() }
        }
    }

    public func upsertVaultItems(_ items: [VaultItem]) async throws {
        let context = controller.container.newBackgroundContext()
        try await context.perform {
            for item in items {
                let entity = try self.findOrCreateEntity(matching: item.id, in: context)
                entity.id = item.id
                entity.originalPath = item.originalURL.path
                entity.vaultPath = item.vaultPath.path
                entity.vaultedAt = item.vaultedAt
                entity.expiresAt = item.expiresAt
                entity.originalSize = item.originalSize
                entity.sha256 = item.sha256
                entity.parentSessionId = item.parentSessionId
                entity.status = item.status.rawValue
            }
            try context.save()
        }
    }

    public func deleteVaultItems(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        let context = controller.container.newBackgroundContext()
        try await context.perform {
            let request: NSFetchRequest<NSFetchRequestResult> = VaultItemEntity.fetchRequest()
            request.predicate = NSPredicate(format: "id IN %@", ids as [CVarArg])
            let delete = NSBatchDeleteRequest(fetchRequest: request)
            _ = try context.execute(delete)
        }
    }

    public func loadCleanupSessions() async throws -> [CleanupSession] {
        let context = controller.container.newBackgroundContext()
        return try await context.perform {
            let sessionRequest = CleanupSessionEntity.fetchRequest()
            sessionRequest.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            let sessions = try context.fetch(sessionRequest)

            let itemRequest = VaultItemEntity.fetchRequest()
            itemRequest.resultType = .dictionaryResultType
            itemRequest.propertiesToFetch = ["id", "parentSessionId"]
            let rows = try context.fetch(itemRequest) as? [[String: Any]] ?? []

            var idsBySession: [UUID: [UUID]] = [:]
            for row in rows {
                guard let id = row["id"] as? UUID,
                      let parent = row["parentSessionId"] as? UUID else { continue }
                idsBySession[parent, default: []].append(id)
            }
            return sessions.map { session in
                CleanupSession(
                    id: session.id,
                    timestamp: session.timestamp,
                    profileType: session.profileType,
                    totalReclaimable: session.totalReclaimable,
                    vaultItemIds: idsBySession[session.id] ?? []
                )
            }
        }
    }

    public func saveCleanupSession(_ session: CleanupSession) async throws {
        let context = controller.container.newBackgroundContext()
        try await context.perform {
            let entity = try self.findOrCreateSession(matching: session.id, in: context)
            entity.id = session.id
            entity.timestamp = session.timestamp
            entity.profileType = session.profileType
            entity.totalReclaimable = session.totalReclaimable
            try context.save()
        }
    }

    // MARK: - Helpers

    private func findOrCreateEntity(matching id: UUID, in context: NSManagedObjectContext) throws -> VaultItemEntity {
        let request = VaultItemEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first {
            return existing
        }
        return VaultItemEntity(context: context)
    }

    private func findOrCreateSession(matching id: UUID, in context: NSManagedObjectContext) throws -> CleanupSessionEntity {
        let request = CleanupSessionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        if let existing = try context.fetch(request).first {
            return existing
        }
        return CleanupSessionEntity(context: context)
    }
}

// MARK: - Mapping

private extension VaultItemEntity {
    func toVaultItem() -> VaultItem {
        VaultItem(
            id: id,
            originalURL: URL(fileURLWithPath: originalPath),
            vaultPath: URL(fileURLWithPath: vaultPath),
            vaultedAt: vaultedAt,
            expiresAt: expiresAt,
            originalSize: originalSize,
            sha256: sha256,
            parentSessionId: parentSessionId,
            status: VaultItemStatus(rawValue: status) ?? .vaulted
        )
    }
}
