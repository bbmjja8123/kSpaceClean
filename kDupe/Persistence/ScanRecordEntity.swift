import CoreData
import Foundation

@objc(ScanRecordEntity)
public final class ScanRecordEntity: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var timestamp: Date
    @NSManaged public var profileType: String
    @NSManaged public var totalFilesScanned: Int64
    @NSManaged public var totalDuplicatesFound: Int64
    @NSManaged public var totalWasteSize: Int64
    @NSManaged public var duration: Double
    @NSManaged public var groups: Set<DuplicateGroupEntity>
}

extension ScanRecordEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ScanRecordEntity> {
        NSFetchRequest<ScanRecordEntity>(entityName: "ScanRecordEntity")
    }
}
