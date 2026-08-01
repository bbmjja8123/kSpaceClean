import XCTest
@testable import kFresh

/// Tests for `DirectorySizeCalculator` — the shared helper used by both
/// `ResidueDetector.directorySize` and `AppCatalogService.sizeOfApp`
/// after the m-4 fix. The helper enforces a single recursive-walk
/// policy (unbounded or depth-limited with `skipDescendants`) so the
/// two call sites cannot drift.
final class DirectorySizeCalculatorTests: XCTestCase {
    private var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testSizeReturnsZeroForEmptyDirectory() {
        XCTAssertEqual(DirectorySizeCalculator.size(of: tempDir), 0)
    }

    func testSizeSumsDirectFileContents() throws {
        try Data("hello".utf8).write(to: tempDir.appendingPathComponent("a.txt"))
        try Data("world!".utf8).write(to: tempDir.appendingPathComponent("b.txt"))
        let size = DirectorySizeCalculator.size(of: tempDir)
        XCTAssertGreaterThanOrEqual(size, 11)
    }

    func testSizeRecursesIntoNestedDirectories() throws {
        let nested = tempDir.appendingPathComponent("nested/deep")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 100).write(to: nested.appendingPathComponent("payload.bin"))
        let size = DirectorySizeCalculator.size(of: tempDir)
        XCTAssertGreaterThanOrEqual(size, 100)
    }

    func testDepthLimitSkipsOverDeepSubtrees() throws {
        let pathComponents = ["a", "b", "c", "d", "e", "f"]
        let nested = pathComponents.reduce(tempDir) { acc, component in
            let next = acc.appendingPathComponent(component)
            try? FileManager.default.createDirectory(at: next, withIntermediateDirectories: true)
            return next
        }
        try Data(repeating: 0x42, count: 64).write(to: nested.appendingPathComponent("payload.bin"))

        // Without depth limit: file is included.
        let fullSize = DirectorySizeCalculator.size(of: tempDir, depth: .unbounded)
        XCTAssertGreaterThanOrEqual(fullSize, 64)

        // With a tight depth limit, the file is below the cap and excluded.
        let limitedSize = DirectorySizeCalculator.size(of: tempDir, depth: .limited(max: 2))
        XCTAssertEqual(limitedSize, 0)
    }

    func testSizeReturnsZeroForNonexistentRoot() {
        let ghost = tempDir.appendingPathComponent("does-not-exist")
        XCTAssertEqual(DirectorySizeCalculator.size(of: ghost), 0)
    }
}