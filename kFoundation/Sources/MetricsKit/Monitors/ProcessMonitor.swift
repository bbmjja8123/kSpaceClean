import Foundation

public struct ProcessInfoSnapshot: Sendable, Equatable {
    public let pid: Int32
    public let name: String
    /// Application bundle identifier when known (e.g. `com.apple.Safari`),
    /// or `nil` for system / kernel processes.
    public let bundleID: String?
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    /// Download rate in bytes/sec averaged over the last sample window.
    public let networkBytesDownload: UInt64
    /// Upload rate in bytes/sec averaged over the last sample window.
    public let networkBytesUpload: UInt64

    /// Sum of upload + download. Convenience accessor for sort orderings
    /// that don't distinguish direction.
    public var networkBytesPerSecond: UInt64 {
        networkBytesDownload + networkBytesUpload
    }

    public init(
        pid: Int32,
        name: String,
        bundleID: String? = nil,
        cpuPercent: Double,
        memoryBytes: UInt64,
        networkBytesDownload: UInt64 = 0,
        networkBytesUpload: UInt64 = 0
    ) {
        self.pid = pid
        self.name = name
        self.bundleID = bundleID
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.networkBytesDownload = networkBytesDownload
        self.networkBytesUpload = networkBytesUpload
    }
}

public enum ProcessSort: Sendable {
    case cpu, memory, network, networkDownload, networkUpload
}

public protocol ProcessProvider: Sendable {
    func list() throws -> [ProcessInfoSnapshot]
}

public final class ProcessMonitor: @unchecked Sendable {
    public let provider: any ProcessProvider
    private let networkProvider: (any ProcessNetworkSampling)?
    public init(
        provider: any ProcessProvider,
        networkProvider: (any ProcessNetworkSampling)? = nil
    ) {
        self.provider = provider
        self.networkProvider = networkProvider
    }

    public func top(limit: Int, sort: ProcessSort) throws -> [ProcessInfoSnapshot] {
        var processes = try provider.list()
        if let networkProvider {
            if let throughput = try? networkProvider.sampleThroughput() {
                processes = processes.map { process in
                    guard let bytes = throughput[process.pid] else { return process }
                    return ProcessInfoSnapshot(
                        pid: process.pid,
                        name: process.name,
                        bundleID: process.bundleID,
                        cpuPercent: process.cpuPercent,
                        memoryBytes: process.memoryBytes,
                        networkBytesDownload: bytes.download,
                        networkBytesUpload: bytes.upload
                    )
                }
            }
        }
        let sorted: [ProcessInfoSnapshot]
        switch sort {
        case .cpu: sorted = processes.sorted { $0.cpuPercent > $1.cpuPercent }
        case .memory: sorted = processes.sorted { $0.memoryBytes > $1.memoryBytes }
        case .network: sorted = processes.sorted { $0.networkBytesPerSecond > $1.networkBytesPerSecond }
        case .networkDownload: sorted = processes.sorted { $0.networkBytesDownload > $1.networkBytesDownload }
        case .networkUpload: sorted = processes.sorted { $0.networkBytesUpload > $1.networkBytesUpload }
        }
        return Array(sorted.prefix(limit))
    }
}