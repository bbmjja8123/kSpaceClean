import XCTest
@testable import kFresh

final class FDAPermissionProbeTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FDAPermissionProbeTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    // MARK: - Initial state

    func testStatusIsUnknownBeforeProbing() async {
        let probe = FDAPermissionProbe(protectedPaths: [tempDir])
        let status = await probe.currentStatus()
        XCTAssertEqual(status, .unknown, "currentStatus() must not implicitly probe")
    }

    // MARK: - Full access

    func testProbeReturnsFullWhenProtectedPathIsEnumerable() async {
        // tempDir is created by this test, so it is enumerable — the same signal
        // a TCC-protected directory gives once Full Disk Access is granted.
        let probe = FDAPermissionProbe(protectedPaths: [tempDir])
        let status = await probe.probe()
        XCTAssertEqual(status, .full)
    }

    // MARK: - Restricted access

    func testProbeReturnsBasicWhenProtectedPathIsNotEnumerable() async {
        // A path that cannot be enumerated stands in for a TCC denial.
        let unreadable = tempDir.appendingPathComponent("does-not-exist", isDirectory: true)
        let probe = FDAPermissionProbe(protectedPaths: [unreadable])
        let status = await probe.probe()
        XCTAssertEqual(status, .basic)
    }

    func testProbeReturnsBasicWhenNoProtectedPathsConfigured() async {
        let probe = FDAPermissionProbe(protectedPaths: [])
        let status = await probe.probe()
        XCTAssertEqual(status, .basic)
    }

    /// Any one readable protected path is sufficient evidence of Full Disk Access.
    func testProbeReturnsFullWhenAnyProtectedPathIsEnumerable() async {
        let unreadable = tempDir.appendingPathComponent("does-not-exist", isDirectory: true)
        let probe = FDAPermissionProbe(protectedPaths: [unreadable, tempDir])
        let status = await probe.probe()
        XCTAssertEqual(status, .full)
    }

    // MARK: - Caching

    func testCurrentStatusReturnsLastProbedValue() async {
        let probe = FDAPermissionProbe(protectedPaths: [tempDir])
        let probed = await probe.probe()
        let cached = await probe.currentStatus()
        XCTAssertEqual(cached, probed)
        XCTAssertEqual(cached, .full)
    }

    func testProbeIsRepeatableAndPicksUpNewlyGrantedAccess() async {
        let granted = tempDir.appendingPathComponent("granted", isDirectory: true)
        let probe = FDAPermissionProbe(protectedPaths: [granted])

        let before = await probe.probe()
        XCTAssertEqual(before, .basic)

        // Simulate the user granting access while the app is running.
        XCTAssertNoThrow(
            try FileManager.default.createDirectory(at: granted, withIntermediateDirectories: true)
        )

        let after = await probe.probe()
        XCTAssertEqual(after, .full, "probe() must re-check rather than return a stale value")
    }

    // MARK: - Real-system default

    /// The default initializer must target genuinely TCC-gated paths, never a
    /// path that is readable inside the sandbox without Full Disk Access.
    func testDefaultProtectedPathsAreTCCGated() {
        let defaults = FDAPermissionProbe.defaultProtectedPaths
        XCTAssertFalse(defaults.isEmpty)

        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        for path in defaults {
            XCTAssertNotEqual(
                path.standardizedFileURL, appSupport?.standardizedFileURL,
                "~/Library/Application Support is readable without FDA and cannot gate the probe"
            )
        }
    }
}
