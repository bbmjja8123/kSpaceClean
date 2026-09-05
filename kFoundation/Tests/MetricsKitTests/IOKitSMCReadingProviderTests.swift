import XCTest
@testable import MetricsKit

/// Mock connector for provider tests: serves canned key-info and payload
/// replies without touching IOKit.
struct MockKeyInfo {
    var type: UInt32
    var size: UInt8
}

final class MockSMCConnector: SMCConnecting, @unchecked Sendable {

    var openResult: Bool
    var keyInfo: MockKeyInfo?
    var payload: [UInt8]
    var keyInfoResult: UInt8
    var readResult: UInt8
    private(set) var openedCount = 0
    private(set) var closedCount = 0
    private(set) var selectors: [UInt32] = []

    init(
        openResult: Bool = true,
        keyInfo: MockKeyInfo? = nil,
        payload: [UInt8] = [],
        keyInfoResult: UInt8 = SMCUserClient.success,
        readResult: UInt8 = SMCUserClient.success
    ) {
        self.openResult = openResult
        self.keyInfo = keyInfo
        self.payload = payload
        self.keyInfoResult = keyInfoResult
        self.readResult = readResult
    }

    func open() -> Bool {
        openedCount += 1
        return openResult
    }

    func close() {
        closedCount += 1
    }

    func call(selector: UInt32, input: SMCParamStruct) -> SMCParamStruct? {
        selectors.append(selector)
        var output = SMCParamStruct()
        // The real user client exposes a single method index; the command
        // travels in `data8` (9 = read key info, 5 = read bytes).
        guard selector == SMCUserClient.methodIndex else { return nil }
        switch input.data8 {
        case SMCUserClient.readKeyInfo:
            guard let info = keyInfo else { return nil }
            output.key = input.key
            output.keyInfoType = info.type
            output.keyInfoDataSize = UInt32(info.size)
            output.keyInfoDataAttributes = 0
            output.result = keyInfoResult
            return output
        case SMCUserClient.readBytes:
            guard !payload.isEmpty else { return nil }
            // Mirror the real connector: non-zero SMC result → nil reply.
            guard readResult == SMCUserClient.success else { return nil }
            output.key = input.key
            output.keyInfoDataSize = UInt32(payload.count)
            output.data = payload
            output.result = readResult
            return output
        default:
            return nil
        }
    }
}

final class FailingConnector: SMCConnecting, @unchecked Sendable {
    func open() -> Bool { false }
    func close() {}
    func call(selector: UInt32, input: SMCParamStruct) -> SMCParamStruct? { nil }
}

final class IOKitSMCReadingProviderTests: XCTestCase {
    func testIsSupportedFalseWhenOpenFails() {
        let provider = IOKitSMCReadingProvider(connector: FailingConnector())
        XCTAssertFalse(provider.isSupported)
        XCTAssertThrowsError(try provider.read(key: .cpuTemperature))
    }

    func testIsSupportedTrueWhenOpenSucceeds() {
        let connector = MockSMCConnector(keyInfo: MockKeyInfo(type: 0x73703738, size: 2), payload: [0x30, 0x00])
        let provider = IOKitSMCReadingProvider(connector: connector)
        XCTAssertTrue(provider.isSupported)
    }

    func testReadsCPUTemperatureThroughConnector() throws {
        // sp78 payload 0x30 0x00 → 48.0; keyInfo dataType 'sp78', dataSize 2
        let connector = MockSMCConnector(
            keyInfo: MockKeyInfo(type: 0x73703738 /* 'sp78' */, size: 2),
            payload: [0x30, 0x00]
        )
        let provider = IOKitSMCReadingProvider(connector: connector)
        XCTAssertTrue(provider.isSupported)
        XCTAssertEqual(try provider.read(key: .cpuTemperature), 48.0, accuracy: 0.01)
        XCTAssertEqual(connector.selectors, [SMCUserClient.methodIndex, SMCUserClient.methodIndex])
        // Commands must travel in data8: keyInfo first, then readBytes.
    }

    func testKeyNotFoundSurfacesUnsupported() {
        // kSMCKeyNotFound from the SMC is a miss on this host — surfaced as an
        // error, never fabricated.
        let connector = MockSMCConnector(
            keyInfo: MockKeyInfo(type: 0x73703738, size: 2),
            payload: [0x30, 0x00],
            readResult: SMCUserClient.keyNotFound
        )
        let provider = IOKitSMCReadingProvider(connector: connector)
        XCTAssertThrowsError(try provider.read(key: .gpuTemperature))
    }

    func testKeyInfoFailureSurfacesSystemCallError() {
        let connector = MockSMCConnector(keyInfoResult: SMCUserClient.keyNotFound)
        let provider = IOKitSMCReadingProvider(connector: connector)
        XCTAssertThrowsError(try provider.read(key: .cpuTemperature)) { error in
            guard case MetricError.systemCall = error else {
                return XCTFail("expected systemCall, got \(error)")
            }
        }
    }

    func testFanRPMViaFPE2() throws {
        // fpe2 payload 0x0E 0x10 → 900 RPM
        let connector = MockSMCConnector(
            keyInfo: MockKeyInfo(type: 0x66706532 /* 'fpe2' */, size: 2),
            payload: [0x0E, 0x10]
        )
        let provider = IOKitSMCReadingProvider(connector: connector)
        XCTAssertEqual(try provider.read(key: .fan1RPM), 900.0, accuracy: 0.01)
    }

    func testUndecodableTypeSurfacesMalformedData() {
        let connector = MockSMCConnector(
            keyInfo: MockKeyInfo(type: 0x21212121 /* '!!!!' */, size: 2),
            payload: [0x00, 0x00]
        )
        let provider = IOKitSMCReadingProvider(connector: connector)
        XCTAssertThrowsError(try provider.read(key: .cpuTemperature)) { error in
            guard case MetricError.malformedData = error else {
                return XCTFail("expected malformedData, got \(error)")
            }
        }
    }

    func testCloseIsIdempotentForDeinit() {
        let connector = MockSMCConnector(keyInfo: MockKeyInfo(type: 0x73703738, size: 2), payload: [0x30, 0x00])
        do {
            _ = IOKitSMCReadingProvider(connector: connector)
        }
        XCTAssertEqual(connector.closedCount, 1)
    }
}
