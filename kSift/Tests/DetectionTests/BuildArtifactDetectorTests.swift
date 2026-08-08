import XCTest
@testable import kSift

final class BuildArtifactDetectorTests: XCTestCase {
    func testCompiledFileExtensionsMapToEvidencePatterns() async {
        let detector = BuildArtifactDetector()
        let cases: [(String, BuildPattern)] = [
            ("main.o", .objectFile),
            ("cache.pyc", .pythonBytecode),
            ("Main.class", .javaClass),
            ("libCore.a", .staticLibrary),
            ("Core.lib", .staticLibrary),
            ("Core.obj", .staticLibrary),
        ]

        for (path, expected) in cases {
            let match = await detector.match(for: URL(fileURLWithPath: "/tmp/\(path)"))
            XCTAssertEqual(match?.pattern, expected)
        }
    }

    func testNodeModulesFilesCollapseIntoOneGroup() async throws {
        let root = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let modules = root.appendingPathComponent("node_modules/package")
        try FileManager.default.createDirectory(at: modules, withIntermediateDirectories: true)
        let first = try createTempFile(named: "a.js", in: modules, withSize: 100)
        let second = try createTempFile(named: "b.js", in: modules, withSize: 50)

        let groups = await BuildArtifactDetector().detect(
            [first, second],
            controller: ScanController()
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].fileCount, 2)
        XCTAssertEqual(groups[0].totalSize, 150)
        guard case .buildArtifact(let pattern) = groups[0].categoryEvidence else {
            return XCTFail("Expected build-artifact evidence")
        }
        XCTAssertEqual(pattern, .nodeModules)
    }

    func testXcodeAndSwiftDirectoryPatterns() async {
        let detector = BuildArtifactDetector()
        let cases: [(String, BuildPattern)] = [
            ("/tmp/DerivedData/App/Build/file", .xcodeDerivedData),
            ("/tmp/App.xcworkspace/xcuserdata/user.xcuserdatad/file", .xcodeUserData),
            ("/tmp/Package/.build/debug/file", .swiftBuild),
            ("/tmp/Package/.swiftpm/configuration/file", .swiftPM),
        ]

        for (path, expected) in cases {
            let match = await detector.match(for: URL(fileURLWithPath: path))
            XCTAssertEqual(match?.pattern, expected)
        }
    }

    func testRustGoCocoaPodsAndCarthagePatterns() async {
        let detector = BuildArtifactDetector()
        let cases: [(String, BuildPattern)] = [
            ("/tmp/rust/target/debug/app", .rustTarget),
            ("/tmp/rust/target/release/app", .rustTarget),
            ("/tmp/go/vendor/module/file.go", .goVendor),
            ("/tmp/ios/Pods/Library/file", .cocoaPods),
            ("/tmp/ios/Carthage/Build/Mac/lib.framework/file", .carthageBuild),
        ]

        for (path, expected) in cases {
            let match = await detector.match(for: URL(fileURLWithPath: path))
            XCTAssertEqual(match?.pattern, expected)
        }
    }

    func testCacheAndGenericBuildPatterns() async {
        let detector = BuildArtifactDetector()
        let cases: [(String, BuildPattern)] = [
            ("/tmp/web/.next/cache/file", .nextCache),
            ("/tmp/node/.cache/file", .cache),
            ("/tmp/android/.gradle/cache/file", .gradle),
            ("/tmp/project/build/output", .genericBuild),
            ("/tmp/project/dist/output", .genericBuild),
        ]

        for (path, expected) in cases {
            let match = await detector.match(for: URL(fileURLWithPath: path))
            XCTAssertEqual(match?.pattern, expected)
        }
    }

    func testSeparateArtifactRootsRemainSeparateGroups() async throws {
        let root = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstRoot = root.appendingPathComponent("one/node_modules")
        let secondRoot = root.appendingPathComponent("two/node_modules")
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        let first = try createTempFile(named: "file.js", in: firstRoot, withSize: 10)
        let second = try createTempFile(named: "file.js", in: secondRoot, withSize: 10)

        let groups = await BuildArtifactDetector().detect(
            [first, second],
            controller: ScanController()
        )

        XCTAssertEqual(groups.count, 2)
    }

    func testNonmatchingSourceFilesAreExcluded() async throws {
        let root = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let swift = try createTempFile(named: "Source.swift", in: root, withSize: 10)
        let markdown = try createTempFile(named: "README.md", in: root, withSize: 10)

        let groups = await BuildArtifactDetector().detect(
            [swift, markdown],
            controller: ScanController()
        )

        XCTAssertTrue(groups.isEmpty)
    }

    func testCancellationReturnsEarly() async throws {
        let root = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let object = try createTempFile(named: "main.o", in: root, withSize: 10)
        let controller = ScanController()
        controller.cancel()

        let groups = await BuildArtifactDetector().detect([object], controller: controller)

        XCTAssertTrue(groups.isEmpty)
    }
}
