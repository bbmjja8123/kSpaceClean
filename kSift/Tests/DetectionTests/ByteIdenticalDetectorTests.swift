import Darwin
import XCTest
@testable import kSift

final class ByteIdenticalDetectorTests: XCTestCase {
    func testIdenticalFilesPassAllFourStages() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try createTextFile(named: "first.txt", in: directory, content: "identical")
        let second = try createTextFile(named: "second.txt", in: directory, content: "identical")

        let groups = await ByteIdenticalDetector().detect(
            [first, second],
            controller: ScanController()
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].files.count, 2)
        XCTAssertEqual(groups[0].totalSize, Int64("identical".utf8.count))
        XCTAssertTrue(groups[0].files.allSatisfy { $0.hash?.count == 64 })
        XCTAssertTrue(groups[0].files.allSatisfy { $0.fingerprint?.count == 64 })
        guard case .byteIdentical(_, let byteVerified) = groups[0].categoryEvidence else {
            return XCTFail("Expected byte-identical evidence")
        }
        XCTAssertTrue(byteVerified)
    }

    func testDifferentSizesAreRejectedBeforeHashing() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try createTempFile(named: "small.bin", in: directory, withSize: 10)
        let second = try createTempFile(named: "large.bin", in: directory, withSize: 11)

        let groups = await ByteIdenticalDetector().detect(
            [first, second],
            controller: ScanController()
        )

        XCTAssertTrue(groups.isEmpty)
    }

    func testSameSizeDifferentContentIsRejected() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try createTextFile(named: "a.txt", in: directory, content: "AAAA")
        let second = try createTextFile(named: "b.txt", in: directory, content: "BBBB")

        let groups = await ByteIdenticalDetector().detect(
            [first, second],
            controller: ScanController()
        )

        XCTAssertTrue(groups.isEmpty)
    }

    func testMidFileDifferenceSurvivesFingerprintButFailsFullVerification() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var firstData = Data(repeating: 0x41, count: 20_000)
        var secondData = firstData
        firstData[10_000] = 0x42
        secondData[10_000] = 0x43
        let first = directory.appendingPathComponent("a.bin")
        let second = directory.appendingPathComponent("b.bin")
        try firstData.write(to: first)
        try secondData.write(to: second)

        let groups = await ByteIdenticalDetector().detect(
            [first, second],
            controller: ScanController()
        )

        XCTAssertTrue(groups.isEmpty)
    }

    func testThreeCopiesCountOnlyDeletableBytes() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = try ["a", "b", "c"].map {
            try createTempFile(named: "\($0).bin", in: directory, withSize: 128)
        }

        let groups = await ByteIdenticalDetector().detect(urls, controller: ScanController())

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].fileCount, 3)
        XCTAssertEqual(groups[0].totalSize, 256)
    }

    func testMinimumSizeExcludesSmallFiles() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try createTempFile(named: "a.bin", in: directory, withSize: 16)
        let second = try createTempFile(named: "b.bin", in: directory, withSize: 16)

        let groups = await ByteIdenticalDetector(minimumSize: 17).detect(
            [first, second],
            controller: ScanController()
        )

        XCTAssertTrue(groups.isEmpty)
    }

    func testEmptyFilesCanBeVerifiedWhenThresholdAllowsThem() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try createTempFile(named: "a.bin", in: directory, withSize: 0)
        let second = try createTempFile(named: "b.bin", in: directory, withSize: 0)

        let groups = await ByteIdenticalDetector(minimumSize: 0).detect(
            [first, second],
            controller: ScanController()
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].totalSize, 0)
    }

    func testUnreadableFileIsIsolatedFromReadableGroup() async throws {
        guard getuid() != 0 else { throw XCTSkip("Permission test is unreliable as root") }
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try createTextFile(named: "a.txt", in: directory, content: "same")
        let second = try createTextFile(named: "b.txt", in: directory, content: "same")
        let unreadable = try createTextFile(named: "secret.txt", in: directory, content: "same")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path)
        }
        let detector = ByteIdenticalDetector()

        let groups = await detector.detect(
            [first, unreadable, second],
            controller: ScanController()
        )
        let failures = await detector.failures

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].files.count, 2)
        XCTAssertEqual(failures.map(\.url), [unreadable])
    }

    func testCancellationReturnsNoNewGroups() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try createTempFile(named: "a.bin", in: directory, withSize: 10)
        let second = try createTempFile(named: "b.bin", in: directory, withSize: 10)
        let controller = ScanController()
        controller.cancel()

        let groups = await ByteIdenticalDetector().detect([first, second], controller: controller)

        XCTAssertTrue(groups.isEmpty)
    }
}
