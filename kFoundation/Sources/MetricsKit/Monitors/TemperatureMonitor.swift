import Foundation

public final class TemperatureMonitor: MetricMonitor, @unchecked Sendable {
    public let kind: MetricKind = .temperature
    private let provider: any SMCReadingProvider
    public init(provider: any SMCReadingProvider) { self.provider = provider }
    public func sample() async throws -> MetricSample {
        guard provider.isSupported else {
            return MetricSample(kind: .temperature, value: .unavailable(.unsupported("SMC is unavailable on this Mac")), availability: .unsupported(reason: "SMC is unavailable on this Mac"), timestamp: Date())
        }
        do {
            let cpuTemp = try provider.read(key: .cpuTemperature)
            return MetricSample(kind: .temperature, value: .degreesCelsius(cpuTemp), availability: .available, timestamp: Date())
        } catch let error as MetricError {
            return MetricSample(kind: .temperature, value: .unavailable(error), availability: .unsupported(reason: String(describing: error)), timestamp: Date())
        } catch {
            return MetricSample(kind: .temperature, value: .unavailable(.systemCall("SMC", -1)), availability: .unsupported(reason: String(describing: error)), timestamp: Date())
        }
    }
}