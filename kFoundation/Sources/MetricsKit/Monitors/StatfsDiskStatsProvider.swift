#if canImport(Darwin)
import Darwin
import Foundation

/// Darwin adapter that reads filesystem capacity using `statfs`.
public final class StatfsDiskStatsProvider: DiskStatsProvider, @unchecked Sendable {
    public init() {}

    public func read(path: String) throws -> DiskStats {
        var fs = statfs()
        let result = statfs(path, &fs)
        guard result == 0 else {
            throw MetricError.systemCall("statfs", Int32(result))
        }
        let blockSize = UInt64(fs.f_bsize)
        let total = UInt64(fs.f_blocks) * blockSize
        let free = UInt64(fs.f_bavail) * blockSize
        return DiskStats(totalBytes: total, freeBytes: free)
    }
}
#endif
