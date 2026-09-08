#if canImport(Darwin)
import Darwin
import Foundation

/// Wire-level constants of the AppleSMC IOKit user client.
///
/// Public knowledge reproduced from the open-source osx-cpu-temp implementation
/// (no Apple private SDK). The user client exposes exactly one external method
/// (index 2); the *command* travels inside the struct's `data8` byte:
/// 9 = read key info, 5 = read key bytes. There is deliberately **no** separate
/// user-client "open" method — calling selector 0/5/9 directly returns
/// `kIOReturnUnsupported` (verified on-device, macOS 15.7 Intel).
enum SMCUserClient {
    /// The single external method index used for every key operation.
    static let methodIndex: UInt32 = 2
    static let readBytes: UInt8 = 5
    static let readKeyInfo: UInt8 = 9
    static let success: UInt8 = 0
    static let keyNotFound: UInt8 = 0x84
}

/// Mirrors the kernel's `SMCParamStruct` (80 bytes on arm64/x86_64).
///
/// Layout risk note: an earlier draft of this struct used Swift tuples, whose
/// padding does not match the kernel's C layout. This implementation instead
/// stores an explicit 80-byte buffer with hard-coded offsets taken from the
/// canonical C definition, verified two ways on the target machine (Intel/T2
/// MacBookPro15,1, macOS 15.7.8): (1) by compiling the C struct and printing
/// `offsetof`, and (2) by reading real keys (TC0P → 60.938°C, exactly
/// matching the osx-cpu-temp reference in the same minute):
///
/// | offset | field                  | size | type            |
/// |-------:|------------------------|-----:|-----------------|
/// | 0      | key                    | 4    | UInt32 (fourCC) |
/// | 4      | vers                   | 6    | SMCVersion      |
/// | 10     | (padding)              | 2    | —               |
/// | 12     | plimit                 | 16   | SMCPLimitData   |
/// | 28     | keyInfo.dataSize       | 4    | IOByteCount     |
/// | 32     | keyInfo.dataType       | 4    | UInt32 (fourCC) |
/// | 36     | keyInfo.dataAttributes | 1    | UInt8           |
/// | 37..40 | (padding)              | 3    | —               |
/// | 40     | result                 | 1    | UInt8           |
/// | 41     | status                 | 1    | UInt8           |
/// | 42     | data8 (SMC command)    | 1    | UInt8           |
/// | 44     | data32                 | 4    | UInt32          |
/// | 48     | data (bytes)           | 32   | SMCBytes        |
///
/// Only the fields kWatch uses are exposed as accessors; the rest stay zero.
public struct SMCParamStruct: Sendable, Equatable {
    static let size = 80
    static let offsetKey = 0
    static let offsetKeyInfoDataSize = 28
    static let offsetKeyInfoType = 32
    static let offsetKeyInfoDataAttributes = 36
    static let offsetResult = 40
    static let offsetStatus = 41
    static let offsetData8 = 42
    static let offsetData32 = 44
    static let offsetData = 48
    static let dataCapacity = 32

    /// Raw wire buffer. `fileprivate` so the connector in the same file can
    /// pass a stable pointer to `IOConnectCallStructMethod`.
    fileprivate var bytes: [UInt8]

    public init() {
        bytes = [UInt8](repeating: 0, count: Self.size)
    }

    /// SMC four-character key as a native-endian UInt32 (e.g. 'TC0P' = 0x5443_3050).
    public var key: UInt32 {
        get { Self.readUInt32(bytes, offset: Self.offsetKey) }
        set { Self.writeUInt32(&bytes, offset: Self.offsetKey, value: newValue) }
    }

    /// Payload size in bytes (also carries the read length on `readBytes` replies).
    public var keyInfoDataSize: UInt32 {
        get { Self.readUInt32(bytes, offset: Self.offsetKeyInfoDataSize) }
        set { Self.writeUInt32(&bytes, offset: Self.offsetKeyInfoDataSize, value: newValue) }
    }

    /// SMC type fourCC as a native-endian UInt32 (e.g. 'sp78' = 0x7370_3738).
    public var keyInfoType: UInt32 {
        get { Self.readUInt32(bytes, offset: Self.offsetKeyInfoType) }
        set { Self.writeUInt32(&bytes, offset: Self.offsetKeyInfoType, value: newValue) }
    }

    public var keyInfoDataAttributes: UInt8 {
        get { bytes[Self.offsetKeyInfoDataAttributes] }
        set { bytes[Self.offsetKeyInfoDataAttributes] = newValue }
    }

    /// SMC result code (0 = success, 0x84 = key not found).
    public var result: UInt8 {
        get { bytes[Self.offsetResult] }
        set { bytes[Self.offsetResult] = newValue }
    }

    public var status: UInt8 {
        get { bytes[Self.offsetStatus] }
        set { bytes[Self.offsetStatus] = newValue }
    }

    /// SMC command byte: 9 = read key info, 5 = read key bytes.
    public var data8: UInt8 {
        get { bytes[Self.offsetData8] }
        set { bytes[Self.offsetData8] = newValue }
    }

    public var data32: UInt32 {
        get { Self.readUInt32(bytes, offset: Self.offsetData32) }
        set { Self.writeUInt32(&bytes, offset: Self.offsetData32, value: newValue) }
    }

    /// The 32-byte payload window at offset 48.
    public var data: [UInt8] {
        get { Array(bytes[Self.offsetData..<(Self.offsetData + Self.dataCapacity)]) }
        set {
            precondition(newValue.count <= Self.dataCapacity, "SMC payload must be <= 32 bytes")
            bytes.replaceSubrange(
                Self.offsetData..<(Self.offsetData + Self.dataCapacity),
                with: newValue + [UInt8](repeating: 0, count: Self.dataCapacity - newValue.count)
            )
        }
    }

    /// Decodes `keyInfoType` into its 4-character ASCII tag (e.g. "sp78").
    public var keyInfoTypeString: String {
        // fourCC values are compared big-endian: 0x7370_3738 == "sp78".
        let big = keyInfoType.bigEndian
        let typeBytes = withUnsafeBytes(of: big) { Array($0) }
        return String(bytes: typeBytes, encoding: .ascii) ?? "????"
    }

    private static func readUInt32(_ buffer: [UInt8], offset: Int) -> UInt32 {
        UInt32(buffer[offset])
            | UInt32(buffer[offset + 1]) << 8
            | UInt32(buffer[offset + 2]) << 16
            | UInt32(buffer[offset + 3]) << 24
    }

    private static func writeUInt32(_ buffer: inout [UInt8], offset: Int, value: UInt32) {
        buffer[offset] = UInt8(value & 0xFF)
        buffer[offset + 1] = UInt8((value >> 8) & 0xFF)
        buffer[offset + 2] = UInt8((value >> 16) & 0xFF)
        buffer[offset + 3] = UInt8((value >> 24) & 0xFF)
    }
}

/// Injectable seam over the AppleSMC user client so the reading provider can
/// be tested without IOKit.
public protocol SMCConnecting: Sendable {
    func open() -> Bool
    func close()
    /// Performs one user-client call. Returns the reply struct (nil when the
    /// kernel call failed or the SMC reported a non-zero `result`) together
    /// with the raw `kern_return_t` (or the SMC `result` code widened when the
    /// kernel call itself succeeded but the SMC errored) so callers can put a
    /// precise diagnostic code into `MetricError.systemCall`.
    func call(selector: UInt32, input: SMCParamStruct) -> (reply: SMCParamStruct?, kernelResult: Int32)
}

/// Real IOKit AppleSMC user-client connector.
///
/// `@unchecked Sendable`: the sole mutable state is `connect`, an
/// `io_connect_t` handle owned by this instance. All access is serialised
/// through a private serial queue, and `io_connect_t` is a Mach port handle
/// that is safe to use from any single thread at a time.
public final class AppleSMCConnector: SMCConnecting, @unchecked Sendable {
    private var connect: io_connect_t = 0
    private let queue = DispatchQueue(label: "app.kraftly.kwatch.AppleSMCConnector")

    public init() {}

    public func open() -> Bool {
        queue.sync { self.openLocked() }
    }

    public func close() {
        queue.sync { self.closeLocked() }
    }

    public func call(selector: UInt32, input: SMCParamStruct) -> (reply: SMCParamStruct?, kernelResult: Int32) {
        queue.sync { self.callLocked(selector: selector, input: input) }
    }

    /// `IOServiceOpen` alone establishes the connection; there is no
    /// user-client open method (see `SMCUserClient.methodIndex`).
    private func openLocked() -> Bool {
        guard connect == 0 else { return true }
        var service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        var handle: io_connect_t = 0
        let kr = IOServiceOpen(service, mach_task_self_, 0, &handle)
        guard kr == KERN_SUCCESS else { return false }
        connect = handle
        return true
    }

    private func closeLocked() {
        guard connect != 0 else { return }
        IOServiceClose(connect)
        connect = 0
    }

    private func callLocked(selector: UInt32, input: SMCParamStruct) -> (reply: SMCParamStruct?, kernelResult: Int32) {
        guard connect != 0 else { return (nil, kIOReturnNotOpen) }
        var inputCopy = input
        var output = SMCParamStruct()
        var outputSize = SMCParamStruct.size
        // IMPORTANT: use the *method* form `array.withUnsafeMutableBytes {}`.
        // The free function `withUnsafeMutableBytes(of: &array)` (inout
        // coroutine accessor) yields a pointer that makes the AppleSMC user
        // client fail with kIOReturnBadArgument (0xE00002C2) even though the
        // bytes are identical — verified on-device against a working C
        // reference implementation.
        let kr = inputCopy.bytes.withUnsafeMutableBytes { inBuf -> kern_return_t in
            output.bytes.withUnsafeMutableBytes { outBuf -> kern_return_t in
                IOConnectCallStructMethod(
                    connect,
                    selector,
                    inBuf.baseAddress,
                    SMCParamStruct.size,
                    outBuf.baseAddress,
                    &outputSize
                )
            }
        }
        guard kr == KERN_SUCCESS else { return (nil, kr) }
        guard output.result == SMCUserClient.success else {
            // Kernel call fine; the SMC itself reported an error (e.g.
            // 0x84 key not found). Widen it so diagnostics stay precise.
            return (nil, Int32(output.result))
        }
        return (output, KERN_SUCCESS)
    }
}
#endif
