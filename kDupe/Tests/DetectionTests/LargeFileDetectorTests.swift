import XCTest
@testable import kSift

final class LargeFileDetectorTests: XCTestCase {
    func testFileAboveThresholdIsReturnedDirectly() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try createTempFile(named: "large.bin", in: directory, withSize: 100)

        let files = await LargeFileDetector(threshold: 10).detect(
            [url],
            controller: ScanController()
        )

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].url, url)
        XCTAssertEqual(files[0].size, 100)
    }

    func testFileBelowThresholdIsExcluded() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try createTempFile(named: "small.bin", in: directory, withSize: 10)

        let files = await LargeFileDetector(threshold: 100).detect(
            [url],
            controller: ScanController()
        )

        XCTAssertTrue(files.isEmpty)
    }

    func testFileAtThresholdIsIncluded() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try createTempFile(named: "exact.bin", in: directory, withSize: 100)

        let files = await LargeFileDetector(threshold: 100).detect(
            [url],
            controller: ScanController()
        )

        XCTAssertEqual(files.map(\.url), [url])
    }

    func testResultsAreSortedBySizeDescending() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let small = try createTempFile(named: "small.bin", in: directory, withSize: 20)
        let large = try createTempFile(named: "large.bin", in: directory, withSize: 200)
        let medium = try createTempFile(named: "medium.bin", in: directory, withSize: 100)

        let files = await LargeFileDetector(threshold: 1).detect(
            [small, large, medium],
            controller: ScanController()
        )

        XCTAssertEqual(files.map(\.size), [200, 100, 20])
    }

    func testURLDetectionLoadsFilesystemMetadata() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try createTempFile(named: "metadata.bin", in: directory, withSize: 64)

        let detected = await LargeFileDetector(threshold: 1).detect(
            [url],
            controller: ScanController()
        )
        let file = try XCTUnwrap(detected.first)

        XCTAssertNotEqual(file.modificationDate, .distantPast)
        XCTAssertNotNil(file.physicalSize)
    }

    func testPreenumeratedFileKeepsIdentityAndHash() async {
        let id = UUID()
        let item = FileItem.mock(
            id: id,
            url: URL(fileURLWithPath: "/tmp/large.bin"),
            size: 200,
            hash: "verified"
        )

        let files = await LargeFileDetector(threshold: 100).detect(
            files: [item],
            controller: ScanController()
        )

        XCTAssertEqual(files.first?.id, id)
        XCTAssertEqual(files.first?.hash, "verified")
    }

    func testEmptyInputReturnsEmptyList() async {
        let files = await LargeFileDetector(threshold: 1).detect(
            [],
            controller: ScanController()
        )

        XCTAssertTrue(files.isEmpty)
    }

    func testCancellationReturnsEarly() async throws {
        let directory = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try createTempFile(named: "large.bin", in: directory, withSize: 100)
        let controller = ScanController()
        controller.cancel()

        let files = await LargeFileDetector(threshold: 1).detect([url], controller: controller)

        XCTAssertTrue(files.isEmpty)
    }
}
