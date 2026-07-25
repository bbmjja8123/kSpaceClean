import Foundation

public struct ProcessInfoSnapshot: Sendable, Equatable {
    public let pid: Int32
    public let name: String
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public let networkBytesPerSecond: UInt64
    public init(pid: Int32, name: String, cpuPercent: Double, memoryBytes: UInt64, networkBytesPerSecond: UInt64) {
        self.pid = pid; self.name = name; self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes; self.networkBytesPerSecond = networkBytesPerSecond
    }
}

public enum ProcessSort: Sendable {
    case cpu, memory, network
}

public protocol ProcessProvider: Sendable {
    func list() throws -> [ProcessInfoSnapshot]
}

public final class ProcessMonitor: @unchecked Sendable {
    public let provider: any ProcessProvider
    public init(provider: any ProcessProvider) { self.provider = provider }
    public func top(limit: Int, sort: ProcessSort) throws -> [ProcessInfoSnapshot] {
        let processes = try provider.list()
        let sorted: [ProcessInfoSnapshot]
        switch sort {
        case .cpu: sorted = processes.sorted { $0.cpuPercent > $1.cpuPercent }
        case .memory: sorted = processes.sorted { $0.memoryBytes > $1.memoryBytes }
        case .network: sorted = processes.sorted { $0.networkBytesPerSecond > $1.networkBytesPerSecond }
        }
        return Array(sorted.prefix(limit))
    }
}