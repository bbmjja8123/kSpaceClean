#if canImport(Darwin)
import Darwin
import Foundation
import MetricsKit

/// Darwin `CPUStatsProvider` backed by `host_processor_info`.
///
/// Aggregates `CPU_STATE_USER`, `CPU_STATE_NICE`, `CPU_STATE_SYSTEM`,
/// and `CPU_STATE_IDLE` across every logical processor into a single
/// snapshot of cumulative tick counts.
public final class HostCPUStatsProvider: CPUStatsProvider, @unchecked Sendable {
    public init() {}

    public func read() throws -> CPUStats {
        var processorCount: natural_t = 0
        var processorInfo: processor_info_array_t? = nil
        var processorMsgCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorMsgCount
        )
        guard result == KERN_SUCCESS, let info = processorInfo else {
            throw MetricError.systemCall("host_processor_info", Int32(result))
        }
        defer {
            let size = vm_size_t(processorMsgCount) * vm_size_t(MemoryLayout<integer_t>.stride)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }
        var user: UInt64 = 0
        var system: UInt64 = 0
        var idle: UInt64 = 0
        let count = Int(processorCount)
        for i in 0..<count {
            let base = Int(i) * Int(CPU_STATE_MAX)
            user &+= UInt64(info[base + Int(CPU_STATE_USER)])
            user &+= UInt64(info[base + Int(CPU_STATE_NICE)])
            system &+= UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            idle &+= UInt64(info[base + Int(CPU_STATE_IDLE)])
        }
        return CPUStats(user: user, system: system, idle: idle)
    }
}
#endif