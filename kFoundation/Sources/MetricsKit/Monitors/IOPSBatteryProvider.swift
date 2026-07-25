#if canImport(Darwin)
import Darwin
import Foundation
import IOKit.ps

public final class IOPSBatteryProvider: BatteryReadingProvider, @unchecked Sendable {
    public init() {}
    public func read() throws -> BatteryReading {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            throw MetricError.unsupported("No power source info available")
        }
        guard let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            throw MetricError.unsupported("No power sources available")
        }
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            if let current = desc[kIOPSCurrentCapacityKey as String] as? Int,
               let max = desc[kIOPSMaxCapacityKey as String] as? Int,
               max > 0 {
                let percent = Double(current) / Double(max) * 100
                let charging = (desc[kIOPSPowerSourceStateKey as String] as? String) == kIOPSACPowerValue
                return BatteryReading(chargePercent: percent, isCharging: charging, voltage: 0)
            }
        }
        throw MetricError.unsupported("No battery power source found")
    }
}
#endif