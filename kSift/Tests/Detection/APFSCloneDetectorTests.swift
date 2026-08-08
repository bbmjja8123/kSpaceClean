import Darwin
import XCTest
@testable import kSift

final class APFSCloneDetectorTests: XCTestCase {
    func testPhysicalExtentOverlap() async {
        let detector = APFSCloneDetector()
        let lhs = [APFSCloneDetector.PhysicalExtent(start: 100, length: 50)]
        let rhs = [APFSCloneDetector.PhysicalExtent(start: 125, length: 50)]

        let overlaps = await detector.sharePhysicalBlocks(lhs, rhs)

        XCTAssertTrue(overlaps)
    }

    func testPhysicalExtentBoundaryDoesNotOverlap() async {
        let detector = APFSCloneDetector()
        let lhs = [APFSCloneDetector.PhysicalExtent(start: 100, length: 50)]
        let rhs = [APFSCloneDetector.PhysicalExtent(start: 150, length: 50)]

        let overlaps = await detector.sharePhysicalBlocks(lhs, rhs)

        XCTAssertFalse(overlaps)
    }

    func testPhysicalExtentSearchAcrossMultipleRanges() async {
        let detector = APFSCloneDetector()
        let lhs = [
            APFSCloneDetector.PhysicalExtent(start: 0, length: 10),
            APFSCloneDetector.PhysicalExtent(start: 100, length: 20),
        ]
        let rhs = [
            APFSCloneDetector.PhysicalExtent(start: 20, length: 10),
            APFSCloneDetector.PhysicalExtent(start: 110, length: 20),
        ]

        let overlaps = await detector.sharePhysicalBlocks(lhs, rhs)

        XCTAssertTrue(overlaps)
    }

    func testRegularCopiesAreNotMarkedAsClones() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try createTempFile(named: "first.bin", in: directory, withSize: 64 * 1024)
        let second = try createTempFile(named: "second.bin", in: directory, withSize: 64 * 1024)
        let group = makeGroup(urls: [first, second], size: 64 * 1024)

        let annotated = await APFSCloneDetector().annotate([group])

        XCTAssertEqual(annotated.count, 1)
        XCTAssertFalse(annotated[0].files.contains(where: \.isAPFSClone))
        XCTAssertEqual(annotated[0].totalSize, 64 * 1024)
    }

    func testCloneFilesHaveDistinctInodes() async throws {
        let urls = try makeClonePair()
        defer { try? FileManager.default.removeItem(at: urls.directory) }
        let detector = APFSCloneDetector()

        let firstInode = await detector.inode(of: urls.source)
        let secondInode = await detector.inode(of: urls.clone)

        XCTAssertNotNil(firstInode)
        XCTAssertNotNil(secondInode)
        XCTAssertNotEqual(firstInode, secondInode)
    }

    func testClonePairIsMarkedAndHasZeroReclaimableBytes() async throws {
        let urls = try makeClonePair()
        defer { try? FileManager.default.removeItem(at: urls.directory) }
        let group = makeGroup(urls: [urls.source, urls.clone], size: 64 * 1024)

        let annotated = await APFSCloneDetector().annotate([group])

        XCTAssertEqual(annotated[0].totalSize, 0)
        XCTAssertTrue(annotated[0].files.allSatisfy(\.isAPFSClone))
        guard case .apfsClone(let hash) = annotated[0].categoryEvidence else {
            return XCTFail("Expected APFS clone evidence")
        }
        XCTAssertEqual(hash, "test-hash")
    }

    func testNonIdenticalGroupIsUnchanged() async {
        let file = FileItem.mock(size: 10)
        let group = DuplicateGroup(
            id: UUID(),
            category: .largeFile,
            totalSize: 10,
            fileCount: 1,
            files: [file],
            categoryEvidence: .largeFile
        )

        let annotated = await APFSCloneDetector().annotate([group])

        XCTAssertEqual(annotated[0].id, group.id)
        XCTAssertEqual(annotated[0].totalSize, group.totalSize)
        XCTAssertFalse(annotated[0].files[0].isAPFSClone)
    }

    private func makeGroup(urls: [URL], size: Int64) -> DuplicateGroup {
        let files = urls.map {
            FileItem(
                id: UUID(),
                url: $0,
                size: size,
                modificationDate: Date(),
                hash: "test-hash"
            )
        }
        return DuplicateGroup(
            id: UUID(),
            category: .identical,
            totalSize: size * Int64(max(files.count - 1, 0)),
            fileCount: files.count,
            files: files,
            categoryEvidence: .byteIdentical(sha256: "test-hash", byteVerified: true)
        )
    }

    private func makeClonePair() throws -> (directory: URL, source: URL, clone: URL) {
        let directory = try createTempDirectory()
        let source = try createTempFile(named: "source.bin", in: directory, withSize: 64 * 1024)
        let clone = directory.appendingPathComponent("clone.bin")
        let status: Int32 = source.withUnsafeFileSystemRepresentation { sourcePath in
            clone.withUnsafeFileSystemRepresentation { clonePath -> Int32 in
                guard let sourcePath, let clonePath else { return -1 }
                return Darwin.clonefile(sourcePath, clonePath, 0)
            }
        }
        guard status == 0 else {
            try? FileManager.default.removeItem(at: directory)
            throw XCTSkip("APFS clonefile is unavailable on this volume")
        }
        return (directory, source, clone)
    }
}
