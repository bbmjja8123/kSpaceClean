#if canImport(Darwin)
import Darwin
import Foundation
import MetricsKit

// libproc functions (proc_listallpids / proc_pidinfo / proc_name) live in
// /usr/lib/system/libproc.dylib which is auto-linked by the macOS dyld when
// any of these symbols are referenced. They are NOT exposed via the `Darwin`
// module umbrella, so we declare them via `@_silgen_name` to bridge them.
@_silgen_name("proc_listallpids")
private func _proc_listallpids(_ buffer: UnsafeMutablePointer<pid_t>?, _ buffersize: Int32) -> Int32

@_silgen_name("proc_pidinfo")
private func _proc_pidinfo(_ pid: pid_t, _ flavor: Int32, _ arg: UInt64, _ buffer: UnsafeMutableRawPointer, _ buffersize: Int32) -> Int32

@_silgen_name("proc_name")
private func _proc_name(_ pid: pid_t, _ buffer: UnsafeMutablePointer<CChar>, _ buffersize: UInt32) -> Int32

private let PROC_PIDTASKINFO: Int32 = 4

public final class LibprocProcessProvider: ProcessProvider, @unchecked Sendable {
    public init() {}
    public func list() throws -> [ProcessInfoSnapshot] {
        let initialBufferSize = 4096
        var pids = [pid_t](repeating: 0, count: initialBufferSize)
        let actualSize = pids.withUnsafeMutableBufferPointer { buffer -> Int in
            Int(_proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.stride)))
        }
        guard actualSize > 0 else { return [] }
        let count = actualSize / MemoryLayout<pid_t>.stride
        guard count <= pids.count else { return [] }
        return pids.prefix(count).compactMap { pid -> ProcessInfoSnapshot? in
            guard pid > 0 else { return nil }
            var taskInfo = proc_taskinfo()
            let infoSize = MemoryLayout<proc_taskinfo>.stride
            let result = _proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(infoSize))
            guard result == infoSize else { return nil }
            let name = Self.processName(for: pid)
            return ProcessInfoSnapshot(
                pid: Int32(pid),
                name: name,
                cpuPercent: 0,
                memoryBytes: UInt64(taskInfo.pti_resident_size),
                networkBytesPerSecond: 0
            )
        }
    }

    private static func processName(for pid: pid_t) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let length = _proc_name(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return "pid \(pid)" }
        return String(cString: buffer)
    }
}
#endif