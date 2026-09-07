import Foundation

/// Decodes SMC sensor payloads into `Double`s.
///
/// SMC keys carry a 4-character type tag. For fixed-point tags the **trailing
/// hex digit of the tag is the fractional-bit count** (e.g. `"sp78"` → 8
/// fractional bits → divisor 256; `"fpe2"` → 2 → divisor 4; `"fp1f"` → 15 →
/// divisor 32768). `sp78` / `fpe2` / `flt ` / `ui8` / `ui16` are the tags
/// observed by the public osx-cpu-temp implementation; the remaining tags
/// follow the same documented convention but have not been observed by kWatch
/// on-device.
public enum SMCValueDecoder {
    /// - Parameters:
    ///   - type: the SMC type fourCC (e.g. `"sp78"`, `"fpe2"`, `"flt "`).
    ///   - data: the raw payload bytes, up to 32.
    /// - Returns: the decoded value, or `nil` when the type is unknown or the
    ///   payload is too short for that type. Never fabricates a value.
    public static func decode(type: String, data: [UInt8]) -> Double? {
        switch type {
        case "sp78", "sp87", "fp78", "fp87", "fpe2", "fp1f", "fp4c", "fp5a":
            // Signed fixed-point, big-endian. Divisor = 2^(fractional bits),
            // where the fractional-bit count is the trailing hex digit of the
            // type tag ("78" → 8, "87" → 7, "e2" → 2, "1f" → 15, "4c" → 12,
            // "5a" → 10).
            guard data.count >= 2 else { return nil }
            guard let lastHexDigit = type.last?.hexDigitValue, lastHexDigit <= 15 else { return nil }
            let raw = Int16(truncatingIfNeeded: UInt16(data[0]) << 8 | UInt16(data[1]))
            return Double(raw) / Double(1 << lastHexDigit)
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
