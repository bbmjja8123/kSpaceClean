import CoreData

@objc(ScanRecord)
public class ScanRecord: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var startedAt: Date
    @NSManaged public var finishedAt: Date?
    @NSManaged public var totalBytes: Int64
    @NSManaged public var freedBytes: Int64
    @NSManaged public var category: String
    @NSManaged public var entries: NSSet?
}

extension ScanRecord {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ScanRecord> {
        NSFetchRequest<ScanRecord>(entityName: "ScanRecord")
    }
}
