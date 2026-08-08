import CoreData
import Foundation

@objc(CleanupSessionEntity)
public final class CleanupSessionEntity: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var timestamp: Date
    @NSManaged public var profileType: String
    @NSManaged public var totalReclaimable: Int64
}

extension CleanupSessionEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CleanupSessionEntity> {
        NSFetchRequest<CleanupSessionEntity>(entityName: "CleanupSessionEntity")
    }
}
