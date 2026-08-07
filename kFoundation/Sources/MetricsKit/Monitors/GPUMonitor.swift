import Foundation

public final class GPUMonitor: MetricMonitor, @unchecked Sendable {
    public let kind: MetricKind = .gpu
    private let provider: any SMCReadingProvider
    public init(provider: any SMCReadingProvider) { self.provider = provider }
    public func sample() async throws -> MetricSample {
        guard provider.isSupported else {
            return MetricSample(kind: .gpu, value: .unavailable(.unsupported("SMC is unavailable on this Mac")), availability: .unsupported(reason: "SMC is unavailable on this Mac"), timestamp: Date())
        }
        do {
            let gpuTemp = try provider.read(key: .gpuTemperature)
            return MetricSample(kind: .gpu, value: .degreesCelsius(gpuTemp), availability: .available, timestamp: Date())
        } catch let error as MetricError {
            return MetricSample(kind: .gpu, value: .unavailable(error), availability: .unsupported(reason: String(describing: error)), timestamp: Date())
        } catch {
            return MetricSample(kind: .gpu, value: .unavailable(.systemCall("SMC", -1)), availability: .unsupported(reason: String(describing: error)), timestamp: Date())
        }
    }
}