import CoreData
import Foundation

@objc(CleanupActionEntity)
public final class CleanupActionEntity: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var filePath: String
    @NSManaged public var fileSize: Int64
    @NSManaged public var method: String
    @NSManaged public var timestamp: Date
    @NSManaged public var isCompleted: Bool
    @NSManaged public var scanRecord: ScanRecordEntity?
}

extension CleanupActionEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CleanupActionEntity> {
        NSFetchRequest<CleanupActionEntity>(entityName: "CleanupActionEntity")
    }
}
