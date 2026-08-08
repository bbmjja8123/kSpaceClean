import CoreData
import Foundation

@objc(VaultItemEntity)
public final class VaultItemEntity: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var originalPath: String
    @NSManaged public var vaultPath: String
    @NSManaged public var vaultedAt: Date
    @NSManaged public var expiresAt: Date
    @NSManaged public var originalSize: Int64
    @NSManaged public var sha256: String
    /// The CleanupSession this item belonged to. Items outlive sessions when
    /// restored (they linger 7 days as history) and when sessions are purged.
    @NSManaged public var parentSessionId: UUID
    /// Raw value of `VaultItemStatus` ("vaulted" | "restored").
    @NSManaged public var status: String
}

extension VaultItemEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<VaultItemEntity> {
        NSFetchRequest<VaultItemEntity>(entityName: "VaultItemEntity")
    }
}
