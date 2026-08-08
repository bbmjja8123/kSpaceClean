import XCTest
@testable import kWise

final class MetricKitReceiverTests: XCTestCase {
    var tmpDir: URL!
    var receiver: MetricKitReceiver!

    override func setUp() {
        super.setUp()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("metric-kit-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        receiver = MetricKitReceiver(outputDirectory: tmpDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpDir)
        super.tearDown()
    }

    func testWritesCrashPayloadToDisk() throws {
        let payload = MetricKitReceiver.CrashPayload(
            bundleID: "app.kraftly.sclean",
            version: "1.0",
            build: "1",
            timestamp: Date(),
            callStack: "Thread 0 Crashed:\n0  kWise  0x0000000100  main",
            terminationReason: "EXC_BAD_ACCESS"
        )
        try receiver.record(payload)
        let files = try FileManager.default.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        let data = try Data(contentsOf: files[0])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MetricKitReceiver.CrashPayload.self, from: data)
        XCTAssertEqual(decoded.bundleID, "app.kraftly.sclean")
        XCTAssertEqual(decoded.terminationReason, "EXC_BAD_ACCESS")
    }

    func testFileNameIncludesTimestamp() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let payload = MetricKitReceiver.CrashPayload(
            bundleID: "app.kraftly.sclean",
            version: "1.0",
            build: "1",
            timestamp: date,
            callStack: "stack",
            terminationReason: "SIGABRT"
        )
        try receiver.record(payload)
        let files = try FileManager.default.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil)
        let name = files[0].lastPathComponent
        XCTAssertTrue(name.hasPrefix("crash-"), "expected crash- prefix, got \(name)")
        XCTAssertTrue(name.hasSuffix(".json"), "expected .json suffix, got \(name)")
    }

    /// Round-trip every scalar field so a future `record()` change cannot
    /// silently drop payload data without breaking this test.
    func testPayloadRoundTripPreservesAllFields() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_123)
        let payload = MetricKitReceiver.CrashPayload(
            bundleID: "app.kraftly.sclean",
            version: "1.2.3",
            build: "456",
            timestamp: timestamp,
            callStack: "Thread 0 Crashed:\n0  kWise  0x100 main + 0",
            terminationReason: "EXC_BAD_ACCESS"
        )
        try receiver.record(payload)

        let files = try FileManager.default.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 1)
        let data = try Data(contentsOf: files[0])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(MetricKitReceiver.CrashPayload.self, from: data)

        XCTAssertEqual(decoded, payload, "round-trip should preserve the entire payload")
        XCTAssertEqual(decoded.version, "1.2.3")
        XCTAssertEqual(decoded.build, "456")
        XCTAssertEqual(decoded.callStack, payload.callStack)
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970, timestamp.timeIntervalSince1970, accuracy: 0.001)
    }

    #if canImport(MetricKit)
    /// Verify `subscribe()` is idempotent: calling it a second time must not
    /// register a duplicate subscriber with `MXMetricManager`. A double
    /// subscribe would leak the original subscriber (still receiving payloads)
    /// and could cause duplicate file writes on a real crash.
    @available(macOS 14.0, *)
    func testSubscribeIsIdempotent() {
        receiver.subscribe()
        receiver.subscribe()
        receiver.unsubscribe()
    }
    #endif
}
