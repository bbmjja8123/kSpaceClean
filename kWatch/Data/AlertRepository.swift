import Foundation
import CoreData
import MetricsKit

/// A persisted threshold rule for one metric.
public struct MetricAlert: Codable, Sendable, Equatable, Identifiable {
    /// Persisted comparison direction. This is intentionally separate from the
    /// generic UI-facing `AlertOperator` preferences type.
    public enum Operator: String, Codable, Sendable {
        case above
        case below
    }

    public let id: UUID
    public let kind: MetricKind
    public let op: Operator
    public let threshold: Double
    public let isEnabled: Bool
    public let cooldownSeconds: Int
    public let lastTriggeredAt: Date?

    public init(
        id: UUID = UUID(),
        kind: MetricKind,
        op: Operator,
        threshold: Double,
        isEnabled: Bool = true,
        cooldownSeconds: Int = 60,
        lastTriggeredAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.op = op
        self.threshold = threshold
        self.isEnabled = isEnabled
        self.cooldownSeconds = cooldownSeconds
        self.lastTriggeredAt = lastTriggeredAt
    }
}

/// Persistence boundary for metric threshold alerts.
public protocol AlertRepositoryProtocol: Sendable {
    func all() throws -> [MetricAlert]
    func upsert(_ alert: MetricAlert) throws
    func delete(id: UUID) throws
    func recordTriggered(id: UUID, at: Date) throws
}

/// Core Data-backed metric alert repository.
public final class AlertRepository: AlertRepositoryProtocol, @unchecked Sendable {
    private let stack: CoreDataStack
    private let context: NSManagedObjectContext

    public init(stack: CoreDataStack) {
        self.stack = stack
        self.context = stack.viewContext
    }

    public func all() throws -> [MetricAlert] {
        try context.performAndWait {
            let request = NSFetchRequest<AlertRecord>(entityName: "AlertRecord")
            request.sortDescriptors = [NSSortDescriptor(key: "kindRaw", ascending: true)]
            return try context.fetch(request).map(Self.toDomain)
        }
    }

    public func upsert(_ alert: MetricAlert) throws {
        try context.performAndWait {
            let request = NSFetchRequest<AlertRecord>(entityName: "AlertRecord")
            request.predicate = NSPredicate(format: "id == %@", alert.id as CVarArg)
            request.fetchLimit = 1
            let record = try context.fetch(request).first ?? AlertRecord(context: context)
            record.id = alert.id
            record.kindRaw = alert.kind.rawValue
            record.operatorRaw = alert.op.rawValue
            record.threshold = alert.threshold
            record.isEnabled = alert.isEnabled
            record.cooldownSeconds = Int32(alert.cooldownSeconds)
            record.lastTriggeredAt = alert.lastTriggeredAt
            try stack.save()
        }
    }

    public func delete(id: UUID) throws {
        try context.performAndWait {
            let request = NSFetchRequest<AlertRecord>(entityName: "AlertRecord")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            if let record = try context.fetch(request).first {
                context.delete(record)
                try stack.save()
            }
        }
    }

    public func recordTriggered(id: UUID, at date: Date) throws {
        try context.performAndWait {
            let request = NSFetchRequest<AlertRecord>(entityName: "AlertRecord")
            request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            request.fetchLimit = 1
            if let record = try context.fetch(request).first {
                record.lastTriggeredAt = date
                try stack.save()
            }
        }
    }

    private static func toDomain(_ record: AlertRecord) -> MetricAlert {
        MetricAlert(
            id: record.id,
            kind: MetricKind(rawValue: record.kindRaw) ?? .cpu,
            op: MetricAlert.Operator(rawValue: record.operatorRaw) ?? .above,
            threshold: record.threshold,
            isEnabled: record.isEnabled,
            cooldownSeconds: Int(record.cooldownSeconds),
            lastTriggeredAt: record.lastTriggeredAt
        )
    }
}

/// In-memory alert storage for tests and previews.
public final class InMemoryAlertRepository: AlertRepositoryProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var alerts: [UUID: MetricAlert] = [:]

    public init() {}

    public func all() throws -> [MetricAlert] {
        lock.lock()
        defer { lock.unlock() }
        return alerts.values.sorted { $0.kind.rawValue < $1.kind.rawValue }
    }

    public func upsert(_ alert: MetricAlert) throws {
        lock.lock()
        defer { lock.unlock() }
        alerts[alert.id] = alert
    }

    public func delete(id: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        alerts.removeValue(forKey: id)
    }

    public func recordTriggered(id: UUID, at date: Date) throws {
        lock.lock()
        defer { lock.unlock() }
        guard let alert = alerts[id] else { return }
        alerts[id] = MetricAlert(
            id: alert.id,
            kind: alert.kind,
            op: alert.op,
            threshold: alert.threshold,
            isEnabled: alert.isEnabled,
            cooldownSeconds: alert.cooldownSeconds,
            lastTriggeredAt: date
        )
    }
}
