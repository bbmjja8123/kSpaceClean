import CoreData

@objc(UninstallHistory)
public class UninstallHistory: NSManagedObject {
    var residues: [ResidueFile] {
        get { (residueData as? Data).flatMap { try? JSONDecoder().decode([ResidueFile].self, from: $0) } ?? [] }
        set { residueData = try? JSONEncoder().encode(newValue) as NSData }
    }
}
