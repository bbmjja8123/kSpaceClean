import Foundation
import CoreData
import MetricsKit

/// Persistence boundary for sampled metric history.
public protocol HistoryRepositoryProtocol: Sendable {
    func append(_ snapshot: MetricSnapshot) throws
    func samples(since start: Date) throws -> [MetricSnapshot]
    func purge(olderThan cutoff: Date) throws
}

/// Core Data-backed metric history repository.
public final class HistoryRepository: HistoryRepositoryProtocol, @unchecked Sendable {
    private let stack: CoreDataStack
    private let context: NSManagedObjectContext

    public init(stack: CoreDataStack) {
        self.stack = stack
        self.context = stack.viewContext
    }

    public func append(_ snapshot: MetricSnapshot) throws {
        try context.performAndWait {
            let record = MetricHistoryRecord(context: context)
            record.timestamp = snapshot.timestamp
            record.cpuPercent = snapshot.values[.cpu].flatMap(valueToDouble) ?? 0
            record.memoryPercent = snapshot.values[.memory].flatMap(valueToDouble) ?? 0
            record.diskPercent = snapshot.values[.disk].flatMap(valueToDouble) ?? 0
            // MetricValue.bytesPerSecond carries only the combined rate; the real
            // send/receive split exists at the provider level but is not propagated
            // through MetricValue yet.
            // TODO: split via /proc/net/dev and persist per-direction values.
            if case let .bytesPerSecond(bytesPerSecond) = snapshot.values[.network] {
                record.networkReceiveBytesPerSecond = bytesPerSecond
                record.networkSendBytesPerSecond = 0
            } else {
                record.networkReceiveBytesPerSecond = 0
                record.networkSendBytesPerSecond = 0
            }
            if case let .degreesCelsius(temperature) = snapshot.values[.temperature] {
                record.temperatureCelsius = NSNumber(value: temperature)
            }
            if case let .revolutionsPerMinute(rpm) = snapshot.values[.fan] {
                record.fanRPM = NSNumber(value: rpm)
            }
            if case let .percentage(battery) = snapshot.values[.battery] {
                record.batteryPercent = NSNumber(value: battery)
            }
            try stack.save()
        }
    }

    public func samples(since start: Date) throws -> [MetricSnapshot] {
        try context.performAndWait {
            let request = NSFetchRequest<MetricHistoryRecord>(entityName: "MetricHistoryRecord")
            request.predicate = NSPredicate(format: "timestamp >= %@", start as NSDate)
            request.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: true)]
            let records = try context.fetch(request)
            return records.map { record in
                var values: [MetricKind: MetricValue] = [:]
                values[.cpu] = .percentage(record.cpuPercent)
                values[.memory] = .percentage(record.memoryPercent)
                values[.disk] = .percentage(record.diskPercent)
                let totalNetwork = record.networkReceiveBytesPerSecond
                    + record.networkSendBytesPerSecond
                values[.network] = .bytesPerSecond(totalNetwork)
                if let temperature = record.temperatureCelsius?.doubleValue {
                    values[.temperature] = .degreesCelsius(temperature)
                }
                if let rpm = record.fanRPM?.doubleValue {
                    values[.fan] = .revolutionsPerMinute(rpm)
                }
                if let battery = record.batteryPercent?.doubleValue {
                    values[.battery] = .percentage(battery)
                }
                return MetricSnapshot(timestamp: record.timestamp, values: values)
            }
        }
    }

    public func purge(olderThan cutoff: Date) throws {
        try context.performAndWait {
            let request = NSFetchRequest<NSFetchRequestResult>(entityName: "MetricHistoryRecord")
            request.predicate = NSPredicate(format: "timestamp < %@", cutoff as NSDate)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
            try context.execute(deleteRequest)
        }
    }

    private func valueToDouble(_ value: MetricValue) -> Double? {
        switch value {
        case let .percentage(number):
            return number
        default:
            return nil
        }
    }
}

/// In-memory metric history for tests and previews.
public final class InMemoryHistoryRepository: HistoryRepositoryProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [MetricSnapshot]

    public init(snapshots: [MetricSnapshot] = []) {
        self.snapshots = snapshots
    }

    public func append(_ snapshot: MetricSnapshot) throws {
        lock.lock()
        defer { lock.unlock() }
        snapshots.append(snapshot)
    }

    public func samples(since start: Date) throws -> [MetricSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return snapshots
            .filter { $0.timestamp >= start }
            .sorted { $0.timestamp < $1.timestamp }
    }

    public func purge(olderThan cutoff: Date) throws {
        lock.lock()
        defer { lock.unlock() }
        snapshots.removeAll { $0.timestamp < cutoff }
    }
}
