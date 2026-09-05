#if canImport(Darwin)
import Darwin
import Foundation

/// Darwin SMC reading provider backed by the real AppleSMC user client.
///
/// Availability is probed once at init via `SMCConnecting.open()`. When the
/// open fails (App Sandbox policy, VM, unsupported host) the provider degrades
/// to an explicit `.unsupported` error — values are never fabricated.
///
/// Protocol (public osx-cpu-temp knowledge):
/// 1. call method index 2 with `data8 = 9` (READ_KEYINFO) → dataType fourCC +
///    dataSize in `keyInfo`.
/// 2. call method index 2 with `data8 = 5` (READ_BYTES) and `keyInfo.dataSize`
///    pre-filled → payload in `data`, length in `keyInfo.dataSize`.
///
/// `@unchecked Sendable`: all state is immutable after init (`connector` is
/// itself Sendable and serialises its own IOKit calls; `opened` is a `let`).
public final class IOKitSMCReadingProvider: SMCReadingProvider, @unchecked Sendable {
    private let connector: any SMCConnecting
    private let opened: Bool

    public init(connector: any SMCConnecting = AppleSMCConnector()) {
        self.connector = connector
        self.opened = connector.open()
    }

    deinit {
        connector.close()
    }

    public var isSupported: Bool { opened }

    public func read(key: SMCKey) throws -> Double {
        guard opened else {
            throw MetricError.unsupported("SMC is unavailable on this Mac")
        }
        let fourCC = Array(key.rawValue.utf8) // exactly 4 bytes, e.g. "TC0P"
        guard fourCC.count == 4 else {
            throw MetricError.malformedData("SMC key \(key.rawValue) is not a 4-byte fourCC")
        }
        let keyInt = fourCC.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }

        // 1) Key info → type + size
        var info = SMCParamStruct()
        info.key = keyInt
        info.data8 = SMCUserClient.readKeyInfo
        guard let infoReply = connector.call(selector: SMCUserClient.methodIndex, input: info) else {
            throw MetricError.systemCall("SMC getKeyInfo \(key.rawValue)", kIOReturnError)
        }
        let typeName = infoReply.keyInfoTypeString
        let size = Int(infoReply.keyInfoDataSize)
        guard size > 0, size <= SMCParamStruct.dataCapacity else {
            throw MetricError.malformedData("SMC key \(key.rawValue) reports data size \(size)")
        }

        // 2) Read payload (keyInfo.dataSize pre-filled, as osx-cpu-temp does)
        var query = SMCParamStruct()
        query.key = keyInt
        query.keyInfoDataSize = UInt32(size)
        query.data8 = SMCUserClient.readBytes
        guard let reply = connector.call(selector: SMCUserClient.methodIndex, input: query) else {
            throw MetricError.systemCall("SMC readKey \(key.rawValue)", kIOReturnError)
        }
        let payload = Array(reply.data.prefix(size))
        guard let value = SMCValueDecoder.decode(type: typeName, data: payload) else {
            throw MetricError.malformedData("SMC type \(typeName) undecodable for key \(key.rawValue)")
        }
        return value
    }
}
#endif
