import XCTest
@testable import kSpaceClean

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
            callStack: "Thread 0 Crashed:\n0  kSpaceClean  0x0000000100  main",
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
}
