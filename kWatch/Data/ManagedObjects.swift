import Foundation
import CoreData

/// NSManagedObject subclass for one historical sample.
///
/// Created via the programmatic `NSManagedObjectModel` in `CoreDataStack`; the
/// kWatch target intentionally has no `.xcdatamodeld` file.
@objc(MetricHistoryRecord)
public final class MetricHistoryRecord: NSManagedObject {
    @NSManaged public var timestamp: Date
    @NSManaged public var cpuPercent: Double
    @NSManaged public var memoryPercent: Double
    @NSManaged public var diskPercent: Double
    @NSManaged public var networkReceiveBytesPerSecond: UInt64
    @NSManaged public var networkSendBytesPerSecond: UInt64
    @NSManaged public var temperatureCelsius: NSNumber?
    @NSManaged public var fanRPM: NSNumber?
    @NSManaged public var batteryPercent: NSNumber?
}

/// NSManagedObject subclass for one configured threshold alert.
@objc(AlertRecord)
public final class AlertRecord: NSManagedObject {
    @NSManaged public var id: UUID
    @NSManaged public var kindRaw: String
    @NSManaged public var operatorRaw: String
    @NSManaged public var threshold: Double
    @NSManaged public var isEnabled: Bool
    @NSManaged public var cooldownSeconds: Int32
    @NSManaged public var lastTriggeredAt: Date?
}
