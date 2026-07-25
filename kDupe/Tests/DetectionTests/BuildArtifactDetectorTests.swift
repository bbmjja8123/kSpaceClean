import XCTest
@testable import kDupe

final class BuildArtifactDetectorTests: XCTestCase {
    func testObjectFileExtensionDetected() async throws {
        let detector = BuildArtifactDetector()
        let controller = ScanController()
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try createTempFile(named: "main.o", in: dir, withSize: 100)

        let groups = await detector.detect([dir.appendingPathComponent("main.o")], controller: controller)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.category, .buildArtifact)
    }

    func testAllExtensionPatterns() async throws {
        let detector = BuildArtifactDetector()
        let controller = ScanController()
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let filenames = [
            "module.o", "script.pyc", "Main.class",
            "libfoo.a", "bar.lib", "object.obj",
        ]
        var urls: [URL] = []
        for name in filenames {
            try createTempFile(named: name, in: dir, withSize: 50)
            urls.append(dir.appendingPathComponent(name))
        }

        let groups = await detector.detect(urls, controller: controller)
        XCTAssertEqual(groups.count, filenames.count)
        for group in groups {
            XCTAssertEqual(group.category, .buildArtifact)
        }
    }

    func testBuildDirectoriesDetected() async throws {
        let detector = BuildArtifactDetector()
        let controller = ScanController()
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let buildDirNames = [
            "node_modules", ".build", "DerivedData", "Pods",
            ".gradle", "build", "dist", ".next",
        ]
        var urls: [URL] = []
        for name in buildDirNames {
            let subdir = dir.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
            let file = try createTempFile(named: "artifact.bin", in: subdir, withSize: 50)
            urls.append(file)
        }

        let groups = await detector.detect(urls, controller: controller)
        XCTAssertEqual(groups.count, buildDirNames.count)
        for group in groups {
            XCTAssertEqual(group.category, .buildArtifact)
        }
    }

    func testNonMatchingFilesExcluded() async throws {
        let detector = BuildArtifactDetector()
        let controller = ScanController()
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try createTempFile(named: "source.swift", in: dir, withSize: 100)
        try createTempFile(named: "readme.md", in: dir, withSize: 100)
        try createTempFile(named: "image.png", in: dir, withSize: 100)

        let urls = [
            dir.appendingPathComponent("source.swift"),
            dir.appendingPathComponent("readme.md"),
            dir.appendingPathComponent("image.png"),
        ]
        let groups = await detector.detect(urls, controller: controller)
        XCTAssertTrue(groups.isEmpty)
    }

    func testEmptyURLs() async throws {
        let detector = BuildArtifactDetector()
        let controller = ScanController()
        let groups = await detector.detect([], controller: controller)
        XCTAssertTrue(groups.isEmpty)
    }

    func testCancellationReturnsEarly() async throws {
        let detector = BuildArtifactDetector()
        let controller = ScanController()
        controller.cancel()

        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try createTempFile(named: "test.o", in: dir, withSize: 100)

        let groups = await detector.detect([dir.appendingPathComponent("test.o")], controller: controller)
        XCTAssertTrue(groups.isEmpty, "Cancelled scan should return empty results")
    }
}
