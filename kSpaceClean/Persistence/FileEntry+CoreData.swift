import CoreData

@objc(FileEntry)
public class FileEntry: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var path: String
    @NSManaged public var size: Int64
    @NSManaged public var category: String
    @NSManaged public var confidence: Double
    @NSManaged public var scanRecord: ScanRecord?
}

extension FileEntry {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<FileEntry> {
        NSFetchRequest<FileEntry>(entityName: "FileEntry")
    }
}
