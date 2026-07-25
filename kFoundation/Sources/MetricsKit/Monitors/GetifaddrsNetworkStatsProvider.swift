#if canImport(Darwin)
import Darwin
import Foundation

/// Darwin adapter that reads interface counters using `getifaddrs`.
public final class GetifaddrsNetworkStatsProvider: NetworkStatsProvider, @unchecked Sendable {
    public init() {}

    public func read() throws -> InterfaceBytes {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else {
            throw MetricError.systemCall("getifaddrs", errno)
        }
        defer { freeifaddrs(head) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = current {
            let flags = ptr.pointee.ifa_flags
            let isUp = (flags & UInt32(IFF_UP)) != 0
            let isLoopback = (flags & UInt32(IFF_LOOPBACK)) != 0
            if isUp, !isLoopback {
                let address = ptr.pointee.ifa_addr
                if let address, address.pointee.sa_family == AF_LINK, let data = ptr.pointee.ifa_data {
                    let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                    received &+= UInt64(networkData.ifi_ibytes)
                    sent &+= UInt64(networkData.ifi_obytes)
                }
            }
            current = ptr.pointee.ifa_next
        }
        return InterfaceBytes(receivedBytes: received, sentBytes: sent)
    }
}
#endif
