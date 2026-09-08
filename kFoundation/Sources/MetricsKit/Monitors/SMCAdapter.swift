import Foundation

/// Four-character SMC keys read by kWatch.
///
/// Encodings validated by the 2026-09 spike on Intel/T2 only (MacBookPro15,1,
/// macOS 15.7.8; Apple Silicon NOT tested on-device): TC0P/TG0P are `sp78`
/// temperatures, F0Ac is a `flt ` fan speed on that host (public references
/// show `fpe2` on other models). VBAT does not exist on the spike host.
/// Keys are host-specific — a missing key surfaces an error, never a
/// fabricated value.
public enum SMCKey: String, Sendable {
    /// CPU proximity temperature, `sp78` °C.
    case cpuTemperature = "TC0P"
    /// GPU proximity temperature, `sp78` °C (Intel fallback path in
    /// `GPUMonitor`; Apple Silicon uses Metal usage telemetry instead).
    case gpuTemperature = "TG0P"
    /// Fan 1 actual RPM — `flt ` on the spike host, `fpe2` on models
    /// described by public references; both decoders are supported.
    case fan1RPM = "F0Ac"
    /// Battery voltage, model-dependent encoding.
    case batteryVoltage = "VBAT"
}

public protocol SMCReadingProvider: Sendable {
    var isSupported: Bool { get }
    func read(key: SMCKey) throws -> Double
}

public final class UnsupportedSMCAdapter: SMCReadingProvider, @unchecked Sendable {
    public init() {}
    public var isSupported: Bool { false }
    public func read(key: SMCKey) throws -> Double { throw MetricError.unsupported("SMC is unavailable on this Mac") }
}