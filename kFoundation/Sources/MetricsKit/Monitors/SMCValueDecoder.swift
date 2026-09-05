import Foundation

/// Decodes SMC sensor payloads into `Double`s.
///
/// SMC keys carry a 4-character type tag. The supported tags cover every type
/// observed on Intel and Apple Silicon Macs for temperature, fan, and voltage
/// keys (per the public osx-cpu-temp / Stats implementations).
public enum SMCValueDecoder {
    /// - Parameters:
    ///   - type: the SMC type fourCC (e.g. `"sp78"`, `"fpe2"`, `"flt "`).
    ///   - data: the raw payload bytes, up to 32.
    /// - Returns: the decoded value, or `nil` when the type is unknown or the
    ///   payload is too short for that type. Never fabricates a value.
    public static func decode(type: String, data: [UInt8]) -> Double? {
        switch type {
        case "sp78", "sp87", "fp78", "fp87":
            // Signed fixed-point, big-endian: 1 sign + 7 integer bits with
            // 8 (or 7) fractional bits.
            guard data.count >= 2 else { return nil }
            let raw = Int16(truncatingIfNeeded: UInt16(data[0]) << 8 | UInt16(data[1]))
            let fracBits: Double = type.hasSuffix("78") ? 256 : 128
            return Double(raw) / fracBits
        case "fpe2", "fp1f", "fp4c", "fp5a":
            // Signed fixed-point with varying fractional-bit widths.
            guard data.count >= 2 else { return nil }
            let raw = Int16(truncatingIfNeeded: UInt16(data[0]) << 8 | UInt16(data[1]))
            let divisor: Double
            switch type {
            case "fpe2": divisor = 4
            case "fp1f": divisor = 2
            case "fp4c": divisor = 16
            default: divisor = 32 // fp5a
            }
            return Double(raw) / divisor
        case "flt ":
            // 32-bit IEEE754, little-endian byte order.
            guard data.count >= 4 else { return nil }
            let bits = UInt32(data[0]) | UInt32(data[1]) << 8 | UInt32(data[2]) << 16 | UInt32(data[3]) << 24
            return Double(Float(bitPattern: bits))
        case "ui8":
            guard data.count >= 1 else { return nil }
            return Double(data[0])
        case "ui16":
            guard data.count >= 2 else { return nil }
            return Double(UInt16(data[0]) << 8 | UInt16(data[1]))
        case "si8":
            guard data.count >= 1 else { return nil }
            return Double(Int8(bitPattern: data[0]))
        default:
            return nil
        }
    }
}
