import CoreData
import Foundation

extension UninstallHistory {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<UninstallHistory> {
        NSFetchRequest<UninstallHistory>(entityName: "UninstallHistory")
    }

    @NSManaged public var id: UUID
    @NSManaged public var appName: String
    @NSManaged public var bundleID: String
    @NSManaged public var appPath: String
    @NSManaged public var appSize: Int64
    @NSManaged public var totalResidueSize: Int64
    @NSManaged public var residueCount: Int32
    @NSManaged public var uninstalledAt: Date
    @NSManaged public var isRestored: Bool
    @NSManaged public var backupPath: String
    @NSManaged public var residueData: NSData?
}
