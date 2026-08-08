import XCTest
@testable import kSift

final class DirectoryDedupDetectorTests: XCTestCase {
    func testWholeDirectoriesWithSameStructureAreDetected() async throws {
        let fixture = try makeDirectoryPair()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = try createTextFile(named: "common.txt", in: fixture.first, content: "same")
        let second = try createTextFile(named: "common.txt", in: fixture.second, content: "same")

        let groups = await DirectoryDedupDetector().detect(
            [first, second],
            roots: [fixture.root],
            controller: ScanController()
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(
            Set(groups[0].files.map(\.url.path)),
            Set([fixture.first.path, fixture.second.path])
        )
        guard case .directoryDuplicate(_, let fileCount) = groups[0].categoryEvidence else {
            return XCTFail("Expected directory evidence")
        }
        XCTAssertEqual(fileCount, 1)
    }

    func testDifferentRelativePathsAreNotDuplicates() async throws {
        let fixture = try makeDirectoryPair()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = try createTextFile(named: "a.txt", in: fixture.first, content: "same")
        let second = try createTextFile(named: "b.txt", in: fixture.second, content: "same")

        let groups = await DirectoryDedupDetector().detect(
            [first, second],
            roots: [fixture.root],
            controller: ScanController()
        )

        XCTAssertTrue(groups.isEmpty)
    }

    func testDifferentFileContentIsNotDuplicate() async throws {
        let fixture = try makeDirectoryPair()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let first = try createTextFile(named: "same-name.txt", in: fixture.first, content: "AAAA")
        let second = try createTextFile(named: "same-name.txt", in: fixture.second, content: "BBBB")

        let groups = await DirectoryDedupDetector().detect(
            [first, second],
            roots: [fixture.root],
            controller: ScanController()
        )

        XCTAssertTrue(groups.isEmpty)
    }

    func testNestedDirectoryStructureContributesToContentHash() async throws {
        let fixture = try makeDirectoryPair()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let nestedA = fixture.first.appendingPathComponent("nested")
        let nestedB = fixture.second.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nestedA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nestedB, withIntermediateDirectories: true)
        let first = try createTextFile(named: "file.txt", in: nestedA, content: "nested")
        let second = try createTextFile(named: "file.txt", in: nestedB, content: "nested")

        let groups = await DirectoryDedupDetector().detect(
            [first, second],
            roots: [fixture.root],
            controller: ScanController()
        )

        XCTAssertTrue(groups.contains {
            Set($0.files.map(\.url.path)) == Set([fixture.first.path, fixture.second.path])
        })
    }

    func testReclaimableSizeCountsOneDirectoryCopy() async throws {
        let fixture = try makeDirectoryPair()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let firstA = try createTempFile(named: "a.bin", in: fixture.first, withSize: 100)
        let firstB = try createTempFile(named: "b.bin", in: fixture.first, withSize: 50)
        let secondA = try createTempFile(named: "a.bin", in: fixture.second, withSize: 100)
        let secondB = try createTempFile(named: "b.bin", in: fixture.second, withSize: 50)

        let groups = await DirectoryDedupDetector().detect(
            [firstA, firstB, secondA, secondB],
            roots: [fixture.root],
            controller: ScanController()
        )
        let group = try XCTUnwrap(groups.first { $0.files.contains { $0.url.path == fixture.first.path } })

        XCTAssertEqual(group.totalSize, 150)
        XCTAssertEqual(group.files.map(\.size), [150, 150])
    }

    func testFilesInOneDirectoryDoNotCreateDirectoryGroup() async throws {
        let root = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try createTextFile(named: "a.txt", in: root, content: "same")
        let second = try createTextFile(named: "b.txt", in: root, content: "same")

        let groups = await DirectoryDedupDetector().detect(
            [first, second],
            roots: [root],
            controller: ScanController()
        )

        XCTAssertTrue(groups.isEmpty)
    }

    func testPreverifiedFileItemsUseRealSizes() async throws {
        let fixture = try makeDirectoryPair()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let firstURL = try createTextFile(named: "file.txt", in: fixture.first, content: "content")
        let secondURL = try createTextFile(named: "file.txt", in: fixture.second, content: "content")
        let hash = "same-full-hash"
        let files = [
            FileItem.mock(url: firstURL, size: 7, hash: hash),
            FileItem.mock(url: secondURL, size: 7, hash: hash),
        ]

        let groups = await DirectoryDedupDetector().detect(
            files: files,
            roots: [fixture.root],
            controller: ScanController()
        )

        XCTAssertEqual(groups.first?.totalSize, 7)
    }

    func testCancellationReturnsEarly() async throws {
        let root = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = try createTextFile(named: "file.txt", in: root, content: "content")
        let controller = ScanController()
        controller.cancel()

        let groups = await DirectoryDedupDetector().detect(
            [file],
            roots: [root],
            controller: controller
        )

        XCTAssertTrue(groups.isEmpty)
    }

    private func makeDirectoryPair() throws -> (root: URL, first: URL, second: URL) {
        let root = try createTempDirectory()
        let first = root.appendingPathComponent("first")
        let second = root.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        return (root, first, second)
    }
}
