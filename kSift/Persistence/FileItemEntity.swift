import CoreData
import Foundation

@objc(FileItemEntity)
public final class FileItemEntity: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var filePath: String
    @NSManaged public var size: Int64
    @NSManaged public var modificationDate: Date
    @NSManaged public var fileHash: String?
    @NSManaged public var fingerprint: String?
    @NSManaged public var inode: Int64
    @NSManaged public var isAPFSClone: Bool
    @NSManaged public var physicalSize: Int64
    @NSManaged public var fileType: String?
    @NSManaged public var creationDate: Date?
    @NSManaged public var group: DuplicateGroupEntity?
}

extension FileItemEntity {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<FileItemEntity> {
        NSFetchRequest<FileItemEntity>(entityName: "FileItemEntity")
    }
}
