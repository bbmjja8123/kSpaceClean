#if canImport(Darwin)
import Darwin
import Foundation
import MetricsKit

/// Darwin `MemoryStatsProvider` backed by `host_statistics64`.
///
/// Reports `active + wired + compressed` as the in-use figure and the
/// machine's physical memory from `ProcessInfo` as the total.
public final class HostMemoryStatsProvider: MemoryStatsProvider, @unchecked Sendable {
    public init() {}

    public func read() throws -> MemoryStats {
        var stats = vm_statistics64()
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &size)
            }
        }
        guard result == KERN_SUCCESS else {
            throw MetricError.systemCall("host_statistics64", Int32(result))
        }
        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let totalUsed = active + wired + compressed
        let total = UInt64(ProcessInfo.processInfo.physicalMemory)
        return MemoryStats(totalBytes: total, activeBytes: min(totalUsed, total))
    }
}
#endif