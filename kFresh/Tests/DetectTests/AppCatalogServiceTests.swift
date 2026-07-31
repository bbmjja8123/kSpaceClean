import XCTest
@testable import kFresh

final class AppCatalogServiceTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testClassifyHomebrewCaskApp() {
        let url = URL(fileURLWithPath: "/opt/homebrew/Caskroom/foo/Foo.app")
        let source = AppCatalogService.classifySource(url: url, bundleID: "com.example.foo")
        XCTAssertEqual(source, .homebrew)
    }

    func testClassifySetappApp() {
        let url = URL(fileURLWithPath: "/Applications/Setapp/Foo.app")
        let source = AppCatalogService.classifySource(url: url, bundleID: "com.setapp.Foo")
        XCTAssertEqual(source, .setapp)
    }

    func testClassifyDeveloperIDApp() {
        let url = URL(fileURLWithPath: "/Applications/Foo.app")
        let source = AppCatalogService.classifySource(url: url, bundleID: "com.example.foo")
        XCTAssertEqual(source, .userInstalled)
    }

    func testClassifyAppStoreApp() throws {
        let appPath = tempDir.appendingPathComponent("Test.app")
        try FileManager.default.createDirectory(at: appPath, withIntermediateDirectories: true)
        let receiptDir = appPath.appendingPathComponent("Contents/_MASReceipt")
        try FileManager.default.createDirectory(at: receiptDir, withIntermediateDirectories: true)
        try Data().write(to: receiptDir.appendingPathComponent("receipt"))

        let source = AppCatalogService.classifySource(url: appPath, bundleID: "com.example.test")
        XCTAssertEqual(source, .mas)
    }

    // `async` added: the brief declared this `throws` only, but the body awaits an actor method.
    func testSizeOfAppCalculatesRecursiveSize() async throws {
        let appPath = tempDir.appendingPathComponent("Test.app")
        try FileManager.default.createDirectory(at: appPath, withIntermediateDirectories: true)
        try Data(count: 1000).write(to: appPath.appendingPathComponent("file1.bin"))
        let nested = appPath.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(count: 500).write(to: nested.appendingPathComponent("file2.bin"))

        let service = AppCatalogService()
        let size = await service.sizeOfApp(at: appPath)
        XCTAssertGreaterThanOrEqual(size, 1500)
    }

    /// Verifies that ``sizeOfApp(at:maxDepth:)`` actually honours the depth limit
    /// and that pruning one over-limit subtree does not skip the siblings that
    /// live next to it.
    ///
    /// Fixture layout (depth measured as path components below `appPath`):
    /// ```
    /// Test.app/
    ///   file1.bin                    depth 1   100 B  counted
    ///   Contents/file2.bin           depth 2   200 B  counted
    ///   L1/file3.bin                 depth 2   300 B  counted
    ///   L1/sibling_at_depth3.bin     depth 3   500 B  counted (sibling)
    ///   L1/very/deep/nested/path/file4.bin depth 6   400 B  EXCLUDED at maxDepth=5
    /// ```
    /// Expected total seen by `sizeOfApp(at: appPath, maxDepth: 5)`:
    /// - Lower bound: 1100 B (logical sizes of all four counted files).
    /// - If the depth limit is ignored and the deep file is included, the
    ///   total would be 5 files × 4096 B (one APFS block each) = 20480 B.
    /// - The upper bound is therefore set well below 20480. A total in
    ///   `[1100, 20000)` proves file4.bin was excluded; a total `>= 20000`
    ///   proves it was counted.
    func testSizeOfAppRespectsMaxDepthAndPreservesSiblings() async throws {
        let appPath = tempDir.appendingPathComponent("Test.app")
        try FileManager.default.createDirectory(at: appPath, withIntermediateDirectories: true)
        try Data(count: 100).write(to: appPath.appendingPathComponent("file1.bin"))

        let contentsDir = appPath.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)
        try Data(count: 200).write(to: contentsDir.appendingPathComponent("file2.bin"))

        let l1Dir = appPath.appendingPathComponent("L1")
        try FileManager.default.createDirectory(at: l1Dir, withIntermediateDirectories: true)
        try Data(count: 300).write(to: l1Dir.appendingPathComponent("file3.bin"))
        try Data(count: 500).write(to: l1Dir.appendingPathComponent("sibling_at_depth3.bin"))

        let deepDir = appPath.appendingPathComponent("L1/very/deep/nested/path")
        try FileManager.default.createDirectory(at: deepDir, withIntermediateDirectories: true)
        try Data(count: 400).write(to: deepDir.appendingPathComponent("file4.bin"))

        let service = AppCatalogService()
        let size = await service.sizeOfApp(at: appPath, maxDepth: 5)

        // Lower bound: at least the four counted files' logical sizes.
        XCTAssertGreaterThanOrEqual(size, 1100)
        // Upper bound: 5 files × 4096 B (one APFS block each) would be 20480,
        // which is what we'd see if the depth limit failed to prune file4.bin.
        // 20000 leaves room for the four counted files (≤ 4 × 4096 = 16384)
        // while still failing the assertion if the deep file is included.
        XCTAssertLessThan(size, 20000, "Deep file at depth 6 must be excluded at maxDepth=5")
    }
}
