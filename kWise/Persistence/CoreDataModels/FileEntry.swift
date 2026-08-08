import Foundation
import CoreData

@objc(FileEntry)
public class FileEntry: NSManagedObject {

}

extension FileEntry {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<FileEntry> {
        return NSFetchRequest<FileEntry>(entityName: "FileEntry")
    }

    @NSManaged public var category: String?
    @NSManaged public var confidence: Double
    @NSManaged public var id: UUID?
    @NSManaged public var path: String?
    @NSManaged public var size: Int64
    @NSManaged public var subCategoryID: Int64
    @NSManaged public var actionID: Int64
    @NSManaged public var isRecommended: Bool
    @NSManaged public var cleanupRecord: CleanupRecord?
    @NSManaged public var scanRecord: ScanRecord?
}
