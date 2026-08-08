import CoreData
import Foundation

@objc(IncrementalIndexEntity)
public final class IncrementalIndexEntity: NSManagedObject {
    @NSManaged public var path: String
    @NSManaged public var size: Int64
    @NSManaged public var modificationDate: Date
    /// 0 means "unknown" (Core Data has no optional scalar NSManagedObject properties).
    @NSManaged public var inode: Int64
    @NSManaged public var fingerprint: String
    @NSManaged public var sha256: String
}

extension IncrementalIndexEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<IncrementalIndexEntity> {
        NSFetchRequest<IncrementalIndexEntity>(entityName: "IncrementalIndexEntity")
    }
}
