import CoreData
import os

@objc(UninstallHistory)
public class UninstallHistory: NSManagedObject {
    private static let logger = Logger(subsystem: "app.kraftly.kfresh", category: "UninstallHistory")

    var residues: [ResidueFile] {
        get {
            guard let data = residueData as? Data else { return [] }
            do {
                return try JSONDecoder().decode([ResidueFile].self, from: data)
            } catch {
                Self.logger.error("Failed to decode residue data: \(error.localizedDescription)")
                return []
            }
        }
        set {
            do {
                let data = try JSONEncoder().encode(newValue)
                residueData = data as NSData
            } catch {
                Self.logger.error("Failed to encode residue data: \(error.localizedDescription)")
            }
        }
    }
}
