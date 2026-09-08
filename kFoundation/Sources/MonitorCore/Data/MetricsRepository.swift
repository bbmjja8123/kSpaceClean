import Foundation
import MetricsKit

/// App Group-backed cache for the most recent immutable metric snapshot.
public final class MetricsRepository: @unchecked Sendable {
    private let lock = NSLock()
    private var cachedLatest: MetricSnapshot?
    private let defaults: UserDefaults
    private let latestKey = "kWatch.latestSnapshot"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        self.cachedLatest = Self.decode(defaults: defaults, key: latestKey)
    }

    public var latest: MetricSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return cachedLatest
    }

    public func saveLatest(_ snapshot: MetricSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        cachedLatest = snapshot
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: latestKey)
        }
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        cachedLatest = nil
        defaults.removeObject(forKey: latestKey)
    }

    private static func decode(defaults: UserDefaults, key: String) -> MetricSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(MetricSnapshot.self, from: data)
    }
}
