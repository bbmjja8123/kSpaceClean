import Foundation

public final class FanMonitor: MetricMonitor, @unchecked Sendable {
    public let kind: MetricKind = .fan
    private let provider: any SMCReadingProvider
    public init(provider: any SMCReadingProvider) { self.provider = provider }
    public func sample() async throws -> MetricSample {
        guard provider.isSupported else {
            return MetricSample(kind: .fan, value: .unavailable(.unsupported("SMC is unavailable on this Mac")), availability: .unsupported(reason: "SMC is unavailable on this Mac"), timestamp: Date())
        }
        do {
            let rpm = try provider.read(key: .fan1RPM)
            return MetricSample(kind: .fan, value: .revolutionsPerMinute(rpm), availability: .available, timestamp: Date())
        } catch let error as MetricError {
            return MetricSample(kind: .fan, value: .unavailable(error), availability: .unsupported(reason: String(describing: error)), timestamp: Date())
        } catch {
            return MetricSample(kind: .fan, value: .unavailable(.systemCall("SMC", -1)), availability: .unsupported(reason: String(describing: error)), timestamp: Date())
        }
    }
}