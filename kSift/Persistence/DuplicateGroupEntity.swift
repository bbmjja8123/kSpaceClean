import CoreData
import Foundation

@objc(DuplicateGroupEntity)
public final class DuplicateGroupEntity: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var category: String
    @NSManaged public var totalSize: Int64
    @NSManaged public var fileCount: Int64
    @NSManaged public var evidenceData: Data?
    @NSManaged public var similarity: Double
    @NSManaged public var files: Set<FileItemEntity>
    @NSManaged public var scanRecord: ScanRecordEntity?
}

extension DuplicateGroupEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<DuplicateGroupEntity> {
        NSFetchRequest<DuplicateGroupEntity>(entityName: "DuplicateGroupEntity")
    }
}
