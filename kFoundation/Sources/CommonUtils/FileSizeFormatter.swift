import Foundation

public struct FileSizeFormatter {
    public static func string(from bytes: Int64) -> String {
        // Pin the locale: byte formatting otherwise follows the system locale
        // ("500 字节" on zh-CN), which breaks parsing/comparison at call sites
        // and makes tests environment-dependent. (Note: `ByteCountFormatter`
        // no longer exposes a `locale` property on recent SDKs — use the
        // `ByteCountFormatStyle` instead, which does.)
        bytes.formatted(.byteCount(style: .file).locale(Locale(identifier: "en_US")))
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
