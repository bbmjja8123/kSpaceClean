import Foundation
import CoreData

@objc(CleanupRecord)
public class CleanupRecord: NSManagedObject {

}

extension CleanupRecord {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<CleanupRecord> {
        return NSFetchRequest<CleanupRecord>(entityName: "CleanupRecord")
    }

    @NSManaged public var cleanedAt: Date?
    @NSManaged public var id: UUID?
    @NSManaged public var isRestored: Bool
    @NSManaged public var totalBytes: Int64
    @NSManaged public var entries: NSSet?
}

// MARK: Generated accessors for entries
extension CleanupRecord {
    @objc(addEntriesObject:)
    @NSManaged public func addToEntries(_ value: FileEntry)

    @objc(removeEntriesObject:)
    @NSManaged public func removeFromEntries(_ value: FileEntry)

    @objc(addEntries:)
    @NSManaged public func addToEntries(_ values: NSSet)

    @objc(removeEntries:)
    @NSManaged public func removeFromEntries(_ values: NSSet)
}
