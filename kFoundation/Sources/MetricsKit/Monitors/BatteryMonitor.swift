import Foundation

public struct BatteryReading: Sendable, Equatable {
    public let chargePercent: Double
    public let isCharging: Bool
    public let voltage: Double
    public init(chargePercent: Double, isCharging: Bool, voltage: Double) {
        self.chargePercent = chargePercent; self.isCharging = isCharging; self.voltage = voltage
    }
}

public protocol BatteryReadingProvider: Sendable {
    func read() throws -> BatteryReading
}

public final class BatteryMonitor: MetricMonitor, @unchecked Sendable {
    public let kind: MetricKind = .battery
    private let provider: any BatteryReadingProvider
    public init(provider: any BatteryReadingProvider) { self.provider = provider }
    public func sample() async throws -> MetricSample {
        do {
            let reading = try provider.read()
            return MetricSample(kind: .battery, value: .percentage(min(max(reading.chargePercent, 0), 100)), availability: .available, timestamp: Date())
        } catch {
            return MetricSample(kind: .battery, value: .unavailable(.systemCall("IOKit power", -1)), availability: .unavailable(reason: String(describing: error)), timestamp: Date())
        }
    }
}