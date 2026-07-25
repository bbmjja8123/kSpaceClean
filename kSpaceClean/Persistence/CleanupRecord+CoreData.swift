import CoreData

@objc(CleanupRecord)
public class CleanupRecord: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var cleanedAt: Date
    @NSManaged public var totalBytes: Int64
    @NSManaged public var entries: NSSet?
    @NSManaged public var isRestored: Bool
}

extension CleanupRecord {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CleanupRecord> {
        NSFetchRequest<CleanupRecord>(entityName: "CleanupRecord")
    }
}
