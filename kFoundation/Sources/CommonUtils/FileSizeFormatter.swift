import Foundation

public struct FileSizeFormatter {
    public static func string(from bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    public static func abbreviated(from bytes: Int64) -> String {
        let absBytes = abs(bytes)
        if absBytes < 1024 { return "\(bytes) B" }
        let units = ["KB", "MB", "GB", "TB"]
        var value = Double(bytes) / 1024.0
        for unit in units {
            if abs(value) < 1024 { return String(format: "%.1f %@", value, unit) }
            value /= 1024.0
        }
        return String(format: "%.1f PB", value)
    }
}
