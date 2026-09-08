import Foundation
import PowerScope

/// Honest accounting of what a scan (or cleanup) actually covered versus
/// what the current power scope left untouched.
///
/// Attached to `ScanProgress` completions and `CleanupResult`s so the UI
/// can say "已扫描 12 GB · 主目录未授权，还有约 40 GB 未检查" instead of
/// silently presenting a partial result as complete.
public struct ScopeCoverage: Equatable, Sendable {
    public struct SkippedRegion: Equatable, Sendable, Identifiable {
        public let id: String
        /// Human-readable region name (localized at the view layer).
        public let displayName: String
        /// Best-effort byte estimate of what the region *might* hold.
        public let estimatedBytes: Int64?

        public init(id: String, displayName: String, estimatedBytes: Int64? = nil) {
            self.id = id
            self.displayName = displayName
            self.estimatedBytes = estimatedBytes
        }
    }

    public let scannedBytes: Int64
    public let scannedFiles: Int
    /// Regions the current scope could not read.
    public let skippedRegions: [SkippedRegion]

    public init(scannedBytes: Int64,
                scannedFiles: Int,
                skippedRegions: [SkippedRegion] = []) {
        self.scannedBytes = scannedBytes
        self.scannedFiles = scannedFiles
        self.skippedRegions = skippedRegions
    }

    /// `true` when the scan covered everything the current scope allows.
    public var isCompleteForScope: Bool { skippedRegions.isEmpty }
}
