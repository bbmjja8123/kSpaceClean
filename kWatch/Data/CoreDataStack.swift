import Foundation
import CoreData

/// Owns the Core Data container used by kWatch persistence repositories.
///
/// The managed object model is created programmatically so the kWatch target
/// remains portable without an `.xcdatamodeld` resource.
public final class CoreDataStack: @unchecked Sendable {
    public let container: NSPersistentContainer

    public var viewContext: NSManagedObjectContext { container.viewContext }

    public init(inMemory: Bool = false, appGroupIdentifier: String? = nil) throws {
        let model = Self.buildModel()
        container = NSPersistentContainer(name: "kWatch", managedObjectModel: model)

        if inMemory {
            let description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
            container.persistentStoreDescriptions = [description]
        } else if let appGroupIdentifier {
            guard let groupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
            ) else {
                throw CoreDataStackError.appGroupContainerUnavailable(appGroupIdentifier)
            }
            let storeURL = groupURL.appendingPathComponent("kWatch.sqlite")
            container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: storeURL)]
        }

        let semaphore = DispatchSemaphore(value: 0)
        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
            semaphore.signal()
        }
        semaphore.wait()
        if let loadError {
            throw loadError
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    public func save() throws {
        let context = viewContext
        if context.hasChanges {
            try context.save()
        }
    }

    private static func buildModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let history = NSEntityDescription()
        history.name = "MetricHistoryRecord"
        history.managedObjectClassName = NSStringFromClass(MetricHistoryRecord.self)
        history.properties = [
            attribute("timestamp", .dateAttributeType),
            attribute("cpuPercent", .doubleAttributeType),
            attribute("memoryPercent", .doubleAttributeType),
            attribute("diskPercent", .doubleAttributeType),
            attribute("networkReceiveBytesPerSecond", .integer64AttributeType),
            attribute("networkSendBytesPerSecond", .integer64AttributeType),
            attribute("temperatureCelsius", .doubleAttributeType, optional: true),
            attribute("fanRPM", .doubleAttributeType, optional: true),
            attribute("batteryPercent", .doubleAttributeType, optional: true)
        ]

        let alert = NSEntityDescription()
        alert.name = "AlertRecord"
        alert.managedObjectClassName = NSStringFromClass(AlertRecord.self)
        alert.properties = [
            attribute("id", .UUIDAttributeType),
            attribute("kindRaw", .stringAttributeType),
            attribute("operatorRaw", .stringAttributeType),
            attribute("threshold", .doubleAttributeType),
            attribute("isEnabled", .booleanAttributeType),
            attribute("cooldownSeconds", .integer32AttributeType),
            attribute("lastTriggeredAt", .dateAttributeType, optional: true)
        ]

        model.entities = [history, alert]
        return model
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool = false
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        return attribute
    }
}

private enum CoreDataStackError: LocalizedError, Sendable {
    case appGroupContainerUnavailable(String)

    var errorDescription: String? {
        switch self {
        case let .appGroupContainerUnavailable(identifier):
            return "App Group container is unavailable: \(identifier)"
        }
    }
}
