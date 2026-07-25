import Foundation

public enum SMCKey: String, Sendable {
    case cpuTemperature = "TC0P"
    case gpuTemperature = "TG0P"
    case fan1RPM = "F0Ac"
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