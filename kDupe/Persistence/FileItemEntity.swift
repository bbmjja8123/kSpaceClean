import CoreData
import Foundation

@objc(FileItemEntity)
public final class FileItemEntity: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var filePath: String
    @NSManaged public var size: Int64
    @NSManaged public var modificationDate: Date
    @NSManaged public var hashValue: String?
    @NSManaged public var group: DuplicateGroupEntity?
}

extension FileItemEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<FileItemEntity> {
        NSFetchRequest<FileItemEntity>(entityName: "FileItemEntity")
    }
}
