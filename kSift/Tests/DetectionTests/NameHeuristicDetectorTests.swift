import XCTest
@testable import kSift

final class NameHeuristicDetectorTests: XCTestCase {
    private var root: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nameheuristic-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
        super.tearDown()
    }

    func testGroupsFilesWithSameStemAcrossDistinctDirectories() async throws {
        try createFile(at: root.appendingPathComponent("Downloads/IMG_1234.jpg"), size: 100)
        try createFile(at: root.appendingPathComponent("Pictures/Holiday/IMG_1234.jpg"), size: 100)

        let files = try collectFileItems()
        let groups = await NameHeuristicDetector().detect(files: files, controller: ScanController())

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].files.count, 2)
        XCTAssertEqual(groups[0].category, .nameHeuristic)
        guard case .nameHeuristic(let stem, let variantCount) = groups[0].categoryEvidence else {
            return XCTFail("Expected nameHeuristic evidence")
        }
        XCTAssertEqual(stem, "img_1234")
        XCTAssertEqual(variantCount, 2)
    }

    func testNormalizesMacOSDuplicateSuffix() async throws {
        try createFile(at: root.appendingPathComponent("Downloads/IMG_1234.jpg"), size: 100)
        try createFile(at: root.appendingPathComponent("Downloads/IMG_1234 (1).jpg"), size: 100)
        try createFile(at: root.appendingPathComponent("Downloads/IMG_1234 (2).jpg"), size: 100)

        let files = try collectFileItems()
        let groups = await NameHeuristicDetector().detect(files: files, controller: ScanController())

        // All three collapse to stem "img_1234" — but they live in the
        // SAME directory. detector must skip this because real duplicates
        // in one folder are already caught by the byte detector.
        XCTAssertTrue(groups.isEmpty,
                     "Same-directory duplicates belong to byte detector, not name heuristic")
    }

    func testStripsDifferentExtensions() async throws {
        try createFile(at: root.appendingPathComponent("Downloads/IMG_1234.jpg"), size: 100)
        try createFile(at: root.appendingPathComponent("Pictures/IMG_1234.png"), size: 100)
        try createFile(at: root.appendingPathComponent("RAW/IMG_1234.cr2"), size: 100)

        let files = try collectFileItems()
        let groups = await NameHeuristicDetector().detect(files: files, controller: ScanController())

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].files.count, 3)
    }

    func testIgnoresUniqueNames() async throws {
        try createFile(at: root.appendingPathComponent("A/a.txt"), size: 100)
        try createFile(at: root.appendingPathComponent("B/b.txt"), size: 100)
        try createFile(at: root.appendingPathComponent("C/c.txt"), size: 100)

        let files = try collectFileItems()
        let groups = await NameHeuristicDetector().detect(files: files, controller: ScanController())
        XCTAssertTrue(groups.isEmpty)
    }

    func testCancellationReturnsEarly() async throws {
        try createFile(at: root.appendingPathComponent("A/a.txt"), size: 100)
        try createFile(at: root.appendingPathComponent("B/a.txt"), size: 100)

        let controller = ScanController()
        controller.cancel()

        let files = try collectFileItems()
        let groups = await NameHeuristicDetector().detect(files: files, controller: controller)
        XCTAssertTrue(groups.isEmpty)
    }

    // MARK: - Helpers

    private func createFile(at relativePath: String, size: Int) throws {
        let url = URL(fileURLWithPath: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(count: size).write(to: url)
    }

    private func collectFileItems() throws -> [FileItem] {
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var items: [FileItem] = []
        while let next = enumerator?.nextObject() as? URL {
            let values = try next.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .totalFileAllocatedSizeKey])
            guard values.isRegularFile == true else { continue }
            items.append(FileItem.fromMetadata(next)!)
        }
        return items
    }
}