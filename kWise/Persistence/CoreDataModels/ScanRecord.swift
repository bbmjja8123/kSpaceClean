import Foundation
import CoreData

@objc(ScanRecord)
public class ScanRecord: NSManagedObject {

}

extension ScanRecord {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ScanRecord> {
        return NSFetchRequest<ScanRecord>(entityName: "ScanRecord")
    }

    @NSManaged public var category: String?
    @NSManaged public var finishedAt: Date?
    @NSManaged public var freedBytes: Int64
    @NSManaged public var id: UUID?
    @NSManaged public var startedAt: Date?
    @NSManaged public var totalBytes: Int64
    @NSManaged public var entries: NSSet?
}

// MARK: Generated accessors for entries
extension ScanRecord {
    @objc(addEntriesObject:)
    @NSManaged public func addToEntries(_ value: FileEntry)

    @objc(removeEntriesObject:)
    @NSManaged public func removeFromEntries(_ value: FileEntry)

    @objc(addEntries:)
    @NSManaged public func addToEntries(_ values: NSSet)

    @objc(removeEntries:)
    @NSManaged public func removeFromEntries(_ values: NSSet)
}
