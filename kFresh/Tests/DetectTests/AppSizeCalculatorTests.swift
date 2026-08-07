import XCTest
import AppKit
@testable import kFresh

/// Tests for `AppSizeCalculator` — the actor that drives the background
/// size-measurement pass after the catalog scan completes. The calculator
/// wraps a `TaskGroup` so every bundle is measured concurrently and the
/// UI sees a gradually filling `sizeMap` instead of a blocking wait on the
/// slowest bundle.
final class AppSizeCalculatorTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Builds a synthetic `InstalledApp` whose `url` points at a temp
    /// bundle directory so `AppCatalogService.sizeOfApp` can actually
    /// measure it. The rest of the model fields are placeholders — the
    /// calculator only reads `url` and `bundleID`.
    private func makeApp(bundleID: String) -> InstalledApp {
        let bundleURL = tempDir.appendingPathComponent("\(bundleID).app")
        return InstalledApp(
            url: bundleURL,
            displayName: bundleID,
            bundleID: bundleID,
            version: "1.0",
            icon: NSImage(),
            sizeBytes: 0,
            source: .userInstalled,
            isRunning: false,
            lastUsedDate: nil,
            installDate: nil
        )
    }

    func testComputeSizesReturnsDictionaryKeyedByBundleID() async {
        let apps = [
            makeApp(bundleID: "com.example.alpha"),
            makeApp(bundleID: "com.example.beta"),
        ]
        let calculator = AppSizeCalculator(catalogService: AppCatalogService())
        let sizes = await calculator.computeSizes(for: apps)

        XCTAssertEqual(sizes.keys.sorted(), ["com.example.alpha", "com.example.beta"],
                       "Every app must produce a size entry even when the bundle is empty")
    }

    func testComputeSizesReturnsZeroForEmptyBundles() async {
        let apps = [makeApp(bundleID: "com.example.empty")]
        let calculator = AppSizeCalculator(catalogService: AppCatalogService())
        let sizes = await calculator.computeSizes(for: apps)

        XCTAssertEqual(sizes["com.example.empty"], 0,
                       "An empty bundle directory should report zero bytes")
    }

    func testComputeSizesSumsActualFileContents() async throws {
        let app = makeApp(bundleID: "com.example.payload")
        let contents = app.url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 256).write(to: contents.appendingPathComponent("payload.bin"))

        let calculator = AppSizeCalculator(catalogService: AppCatalogService())
        let sizes = await calculator.computeSizes(for: [app])

        XCTAssertGreaterThanOrEqual(sizes["com.example.payload"] ?? 0, 256,
                                    "Measured size must reflect the on-disk file contents")
    }

    func testComputeSizesWithEmptyInputReturnsEmptyDictionary() async {
        let calculator = AppSizeCalculator(catalogService: AppCatalogService())
        let sizes = await calculator.computeSizes(for: [])
        XCTAssertTrue(sizes.isEmpty, "Empty input must short-circuit to an empty dictionary")
    }
}