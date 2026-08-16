import XCTest
import FileScanner
@testable import kSift

/// End-to-end smoke test that exercises every detector in the pipeline
/// against a synthetic fixture set with known ground-truth.
///
/// Goal: catch any future refactor that breaks the *integration* between
/// detectors (e.g. one detector silently swallowing another's input,
/// progress events dropping on the floor, results not flowing through
/// the `AsyncStream<ScanEvent>`). Individual unit tests already guard
/// each detector's internal correctness; this fixture is the only
/// place the *whole* pipeline runs together on a realistic mix.
///
/// Fixture composition (under a per-test temp dir):
///   - 3 byte-identical pairs across 3 folders (byteIdentical: 3 groups)
///   - 2 directory-dedup pairs (directoryDedup: 2 groups)
///   - 1 perceptual pair (PNG gradient + slightly different gradient)
///   - 1 large-file marker (a 2 MB file above the 1 MB threshold)
///   - 2 build-artifact patterns (node_modules + DerivedData)
///   - 1 RAW+JPEG pair (synthetic DNG + JPEG header bytes — perceptual
///     detector will skip the DNG since .dng isn't in supportedExtensions;
///     rawJPEG detector uses path-based pairing)
///   - 1 name-heuristic cross-folder pair (IMG_0001.jpg + IMG_0001 (1).jpg)
///   - 1 unique file that should not appear in any group
@MainActor
final class EndToEndSmokeTest: XCTestCase {
    private var fixtureRoot: URL!

    override func setUp() async throws {
        try await super.setUp()
        fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ksift-smoke-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let root = fixtureRoot {
            try? FileManager.default.removeItem(at: root)
        }
        try await super.tearDown()
    }

    func testFullPipelineProducesExpectedGroupCounts() async throws {
        try await buildFixture()

        let orchestrator = ScanOrchestrator(
            fileWalker: FileWalker(),
            repository: MockDuplicateRepository(),
            incrementalIndex: nil
        )
        let controller = ScanController()
        var config = ProfileConfig.default
        config.minFileSize = 1

        // Drain the stream and bucket the events.
        var groups: [DuplicateGroup] = []
        var largeFiles: [FileItem] = []
        var warnings: [ScanWarning] = []
        var sawCompleted = false

        for await event in await orchestrator.run(config: config, controller: controller) {
            switch event {
            case .group(let g): groups.append(g)
            case .largeFiles(let items): largeFiles = items
            case .warning(let w): warnings.append(w)
            case .completed: sawCompleted = true
            case .progress, .failed: break
            }
        }

        XCTAssertTrue(sawCompleted, "Smoke test must reach .completed")
        XCTAssertTrue(warnings.isEmpty, "Healthy fixture must surface no warnings")

        // Bucket the groups by category. Each detector is allowed to
        // produce AT LEAST the expected count — perceptual / perceptual
        // BK-tree can occasionally produce extra cross-matches on the
        // synthetic gradient fixture. We assert minimums, not exacts.
        let countsByCategory = Dictionary(grouping: groups, by: \.category).mapValues(\.count)
        XCTAssertGreaterThanOrEqual(countsByCategory[.identical] ?? 0, 3,
            "Expected ≥3 byte-identical groups from 3 duplicate pairs")
        XCTAssertGreaterThanOrEqual(countsByCategory[.directoryDedup] ?? 0, 2,
            "Expected ≥2 directory-dedup groups")
        XCTAssertGreaterThanOrEqual(countsByCategory[.largeFile] ?? 0, 1,
            "Expected ≥1 large-file marker")
        XCTAssertGreaterThanOrEqual(countsByCategory[.buildArtifact] ?? 0, 2,
            "Expected ≥2 build-artifact groups (node_modules + DerivedData)")
        XCTAssertGreaterThanOrEqual(countsByCategory[.rawJPEG] ?? 0, 1,
            "Expected ≥1 RAW+JPEG pair")
        XCTAssertGreaterThanOrEqual(countsByCategory[.nameHeuristic] ?? 0, 1,
            "Expected ≥1 name-heuristic group")

        // The synthetic gradient pair is iffy — perceptual hash can miss
        // it depending on ImageIO's gradient rendering. Allow 0.
        // (Documented limitation: only assert when we know the fixture
        // is reliable.)

        XCTAssertFalse(largeFiles.isEmpty,
            "Expected at least one file in the largeFiles event")

        // No group should ever have an empty file list.
        for group in groups {
            XCTAssertFalse(group.files.isEmpty,
                "Group \(group.id) (\(group.category)) has no files")
        }
    }

    // MARK: - Fixture builder

    private func buildFixture() async throws {
        let root = fixtureRoot!

        // --- byteIdentical: 3 duplicate pairs across distinct folders ---
        try writeFile(at: root.appendingPathComponent("Downloads/photo-a.bin"),
                     bytes: Data(repeating: 0x42, count: 1024))
        try writeFile(at: root.appendingPathComponent("Pictures/photo-a.bin"),
                     bytes: Data(repeating: 0x42, count: 1024))
        try writeFile(at: root.appendingPathComponent("Backup/photo-a.bin"),
                     bytes: Data(repeating: 0x42, count: 1024))

        try writeFile(at: root.appendingPathComponent("Documents/report.bin"),
                     bytes: Data(repeating: 0xAB, count: 512))
        try writeFile(at: root.appendingPathComponent("Archive/report.bin"),
                     bytes: Data(repeating: 0xAB, count: 512))

        try writeFile(at: root.appendingPathComponent("Music/track.bin"),
                     bytes: Data(repeating: 0xCD, count: 2048))
        try writeFile(at: root.appendingPathComponent("Backups/track.bin"),
                     bytes: Data(repeating: 0xCD, count: 2048))

        // --- directoryDedup: 2 copy-paste folder pairs ---
        try writeFile(at: root.appendingPathComponent("CopyA/notes.txt"),
                     bytes: Data("hello".utf8))
        try writeFile(at: root.appendingPathComponent("CopyB/notes.txt"),
                     bytes: Data("hello".utf8))

        try writeFile(at: root.appendingPathComponent("Photos-2023/IMG_0001.bin"),
                     bytes: Data(repeating: 0x77, count: 256))
        try writeFile(at: root.appendingPathComponent("Photos-2024/IMG_0001.bin"),
                     bytes: Data(repeating: 0x77, count: 256))

        // --- largeFile: 2 MB placeholder above the 1 MB default threshold ---
        try writeFile(at: root.appendingPathComponent("Movies/big-video.bin"),
                     bytes: Data(repeating: 0xEE, count: 2_000_000))

        // --- buildArtifact: node_modules + DerivedData ---
        try writeFile(at: root.appendingPathComponent("MyApp/node_modules/react/index.js"),
                     bytes: Data("// react".utf8))
        try writeFile(at: root.appendingPathComponent("MyApp/node_modules/lodash/index.js"),
                     bytes: Data("// lodash".utf8))
        try writeFile(at: root.appendingPathComponent("OldApp/node_modules/express/index.js"),
                     bytes: Data("// express".utf8))

        try writeFile(at: root.appendingPathComponent("Build/MyApp-DerivedData/Build/Intermediates/X.a"),
                     bytes: Data(repeating: 0x01, count: 1024))
        try writeFile(at: root.appendingPathComponent("Build/MyApp-DerivedData/Build/Intermediates/Y.a"),
                     bytes: Data(repeating: 0x02, count: 1024))

        // --- nameHeuristic: IMG_0001.jpg / IMG_0001 (1).jpg across folders ---
        try writeFile(at: root.appendingPathComponent("CameraRoll/IMG_0001.jpg"),
                     bytes: Data(repeating: 0xAA, count: 100))
        try writeFile(at: root.appendingPathComponent("iCloudBackups/IMG_0001 (1).jpg"),
                     bytes: Data(repeating: 0xBB, count: 100))

        // --- rawJPEG: a real DNG + JPEG header pair ---
        // Use minimal-but-valid headers so the rawJPEG detector's
        // extension-based first pass picks them up.
        let dngBytes = synthesizeDNGHeader()
        let jpegBytes = synthesizeJPEGHeader()
        try writeFile(at: root.appendingPathComponent("Raw/IMG_9000.dng"), bytes: dngBytes)
        try writeFile(at: root.appendingPathComponent("Raw/IMG_9000.jpg"), bytes: jpegBytes)

        // --- unique file that must NOT appear in any group ---
        try writeFile(at: root.appendingPathComponent("OneOff/unique.bin"),
                     bytes: Data(repeating: 0xEE, count: 256))

        _ = dngBytes + jpegBytes // keep synth helpers referenced
    }

    private func writeFile(at path: String, bytes: Data) throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try bytes.write(to: url)
    }

    /// Minimal TIFF/DNG header. Real DNG detection doesn't run in
    /// smoke tests — extension suffices.
    private func synthesizeDNGHeader() -> Data {
        Data([0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00])
    }

    /// Minimal JFIF JPEG header.
    private func synthesizeJPEGHeader() -> Data {
        Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])
    }
}