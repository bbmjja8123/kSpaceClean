import Foundation

/// Four-character SMC keys read by kWatch.
///
/// Type on Apple Silicon (validated by the 2026-09 spike): TC0P/TG0P are
/// `sp78` temperatures, F0Ac is an `fpe2` fan speed, VBAT is an `flt`/`ui16`
/// voltage depending on model. Keys are host-specific — a missing key
/// surfaces `MetricError.systemCall`/`kSMCKeyNotFound`, never a fabricated
/// value.
public enum SMCKey: String, Sendable {
    /// CPU proximity temperature, `sp78` °C.
    case cpuTemperature = "TC0P"
    /// GPU proximity temperature, `sp78` °C (Intel fallback path in
    /// `GPUMonitor`; Apple Silicon uses Metal usage telemetry instead).
    case gpuTemperature = "TG0P"
    /// Fan 1 actual RPM, `fpe2`.
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