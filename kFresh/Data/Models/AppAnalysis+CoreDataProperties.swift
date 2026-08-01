import CoreData
import Foundation

extension AppAnalysis {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<AppAnalysis> {
        NSFetchRequest<AppAnalysis>(entityName: "AppAnalysis")
    }

    @NSManaged public var id: UUID
    @NSManaged public var bundleID: String
    @NSManaged public var displayName: String
    @NSManaged public var lastUsedDate: Date?
    @NSManaged public var firstDetectedDate: Date
    @NSManaged public var usedCount: Int32
    @NSManaged public var isAnalyzed: Bool
    @NSManaged public var suggestedAction: String?
}
