import XCTest
import FileScanner
@testable import kSift

// MARK: - Stub File Walker

/// Walks exactly one directory (the temp dir) instead of the profile preset
/// directories (~/Desktop etc.), so orchestration tests are hermetic and fast.
struct StubFileWalker: FileWalkerProtocol {
    let root: URL

    func walk(target: ScanTarget, controller: ScanController,
              progress: @escaping @Sendable (FileEnumerator.ScanResult) -> Void) async throws -> [URL] {
        let collector = URLCollector()
        try await FileEnumerator().enumerate(
            root: root,
            progressHandler: { result in
                collector.append(result.url)
                progress(result)
            },
            cancellationToken: controller.fileToken
        )
        return collector.files
    }
}

/// Thread-safe URL collector for the stub walker's @Sendable callback.
private final class URLCollector: @unchecked Sendable {
    private var _files: [URL] = []
    private let lock = NSLock()

    var files: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return _files
    }

    func append(_ url: URL) {
        lock.lock()
        _files.append(url)
        lock.unlock()
    }
}

// MARK: - Mock Repository

/// An in-memory `DuplicateRepositoryProtocol` that records all calls for later assertion.
actor MockDuplicateRepository: DuplicateRepositoryProtocol {
    private var _savedRecords: [ScanRecord] = []
    private var _deletedRecordIDs: [UUID] = []
    private var _loadedRecordID: UUID?
    private var _recordsToReturn: [ScanRecord] = []

    init(records: [ScanRecord] = []) {
        _recordsToReturn = records
    }

    func saveScanRecord(_ record: ScanRecord) async throws {
        _savedRecords.append(record)
    }

    func loadScanRecords() async throws -> [ScanRecord] {
        _recordsToReturn
    }

    func loadScanRecord(id: UUID) async throws -> ScanRecord? {
        _loadedRecordID = id
        return _recordsToReturn.first { $0.id == id }
    }

    func deleteScanRecord(id: UUID) async throws {
        _deletedRecordIDs.append(id)
    }

    func saveCleanupAction(_ action: CleanupAction) async throws {
        // no-op for scan orchestrator tests
    }

    func loadCleanupHistory() async throws -> [CleanupRecord] {
        []
    }

    // MARK: Test accessors (called from outside the actor)

    func savedRecords() async -> [ScanRecord] { _savedRecords }
    func deletedRecordIDs() async -> [UUID] { _deletedRecordIDs }
    func loadedRecordID() async -> UUID? { _loadedRecordID }
}

// MARK: - Tests

final class ScanOrchestratorTests: XCTestCase {
    /// A config that scans only the caller's temp dir via the stub walker.
    private func config(for dir: URL) -> ProfileConfig {
        ProfileConfig(
            type: .designer,
            customDirectories: [dir.path],
            exclusions: [],
            minFileSize: 1,
            enablePerceptualScan: false
        )
    }

    /// Collects all `.progress` phases in order.
    private func phases(from stream: AsyncStream<ScanEvent>) async -> [ScanPhase] {
        var phases: [ScanPhase] = []
        for await event in stream {
            if case .progress(let p) = event {
                phases.append(p.phase)
            }
        }
        return phases
    }

    func testScanPipelineCompletes() async throws {
        let mockRepo = MockDuplicateRepository()
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try createTempFile(named: "data.bin", in: dir, withSize: 500)
        try createIdenticalFilePair(in: dir)

        let orchestrator = ScanOrchestrator(fileWalker: StubFileWalker(root: dir), repository: mockRepo)
        let controller = ScanController()

        let stream = await orchestrator.run(config: config(for: dir), controller: controller)
        var receivedPhases: [ScanPhase] = []
        var completedSummary: ScanSummary?
        for await event in stream {
            switch event {
            case .progress(let p): receivedPhases.append(p.phase)
            case .completed(let s): completedSummary = s
            default: break
            }
        }

        XCTAssertEqual(receivedPhases.first, .enumerating)
        XCTAssertTrue(receivedPhases.contains(.completed))
        XCTAssertNotNil(completedSummary)
    }

    func testProgressStreamEmitsExpectedPhases() async throws {
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try createTempFile(named: "sample.txt", in: dir, withSize: 200)

        let orchestrator = ScanOrchestrator(fileWalker: StubFileWalker(root: dir), repository: MockDuplicateRepository())
        let controller = ScanController()

        let phases = await phases(from: await orchestrator.run(config: config(for: dir), controller: controller))

        XCTAssertEqual(phases.first, .enumerating)
        XCTAssertEqual(phases.last, .completed)
        // Should include at least the major phases
        XCTAssertTrue(phases.contains(.byteIdentical))
        XCTAssertTrue(phases.contains(.directoryDedup))
        XCTAssertTrue(phases.contains(.largeFiles))
        XCTAssertTrue(phases.contains(.buildArtifacts))
        XCTAssertTrue(phases.contains(.rawJPEG))
    }

    func testCancellationStopsScan() async throws {
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try createTempFile(named: "test.txt", in: dir, withSize: 100)

        let controller = ScanController()
        // Cancel before the scan has a chance to complete.
        controller.cancel()

        let orchestrator = ScanOrchestrator(fileWalker: StubFileWalker(root: dir), repository: MockDuplicateRepository())
        let phases = await phases(from: await orchestrator.run(config: config(for: dir), controller: controller))

        // The scan was cancelled before starting, so it should NOT reach .completed.
        XCTAssertFalse(phases.contains(.completed),
                       "Cancelled scan should not reach the completed phase")
    }

    func testSaveResultsRecordsData() async throws {
        let mockRepo = MockDuplicateRepository()
        let orchestrator = ScanOrchestrator(repository: mockRepo)

        let files = [
            FileItem.mock(url: URL(fileURLWithPath: "/tmp/a.txt"), size: 100),
            FileItem.mock(url: URL(fileURLWithPath: "/tmp/b.txt"), size: 100),
        ]
        let groups = [
            DuplicateGroup.mock(category: .identical, totalSize: 100, fileCount: 2, files: files),
            DuplicateGroup.mock(category: .largeFile, totalSize: 500, fileCount: 1),
        ]
        let config = ProfileConfig.default

        try await orchestrator.saveResults(groups, config: config, duration: 2.5, filesScanned: 50)

        let records = await mockRepo.savedRecords()
        XCTAssertEqual(records.count, 1)

        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.totalFilesScanned, 50)
        XCTAssertEqual(record.totalDuplicatesFound, 3) // 2 + 1
        XCTAssertEqual(record.profileType, .developer)
        XCTAssertEqual(record.duration, 2.5, accuracy: 0.01)
    }

    func testEmptyDirectoryYieldsCompletedScan() async throws {
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // No files in the directory.
        let orchestrator = ScanOrchestrator(fileWalker: StubFileWalker(root: dir), repository: MockDuplicateRepository())
        let controller = ScanController()

        let phases = await phases(from: await orchestrator.run(config: config(for: dir), controller: controller))

        XCTAssertTrue(phases.contains(.completed))
        XCTAssertEqual(phases.first, .enumerating)
    }

    func testGroupEventsFlowForIdenticalDuplicates() async throws {
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try createIdenticalFilePair(in: dir)

        let orchestrator = ScanOrchestrator(fileWalker: StubFileWalker(root: dir), repository: MockDuplicateRepository())
        let controller = ScanController()

        let stream = await orchestrator.run(config: config(for: dir), controller: controller)
        var groups: [DuplicateGroup] = []
        for await event in stream {
            if case .group(let group) = event {
                groups.append(group)
            }
        }

        XCTAssertTrue(groups.contains { $0.category == .identical && $0.files.count == 2 })
    }

    func testLargeFilesEventFlows() async throws {
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let big = try createTempFile(named: "big.bin", in: dir, withSize: 2048)

        let orchestrator = ScanOrchestrator(
            fileWalker: StubFileWalker(root: dir),
            largeFileDetector: LargeFileDetector(threshold: 1024),
            repository: MockDuplicateRepository()
        )
        let controller = ScanController()

        let stream = await orchestrator.run(config: config(for: dir), controller: controller)
        var largeFiles: [FileItem] = []
        for await event in stream {
            if case .largeFiles(let items) = event {
                largeFiles = items
            }
        }

        // FileEnumerator resolves the /private prefix, so canonicalize both sides.
        XCTAssertEqual(
            largeFiles.map { $0.url.resolvingSymlinksInPath() },
            [big.resolvingSymlinksInPath()]
        )
    }

    func testCompletedSummaryReportsMetrics() async throws {
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try createIdenticalFilePair(in: dir) // 2 identical text files

        let orchestrator = ScanOrchestrator(fileWalker: StubFileWalker(root: dir), repository: MockDuplicateRepository())
        let controller = ScanController()

        let stream = await orchestrator.run(config: config(for: dir), controller: controller)
        var summary: ScanSummary?
        for await event in stream {
            if case .completed(let s) = event {
                summary = s
            }
        }

        let s = try XCTUnwrap(summary)
        XCTAssertEqual(s.filesScanned, 2)
        XCTAssertEqual(s.groupsFound, 1)
        XCTAssertEqual(s.groupCounts[.identical], 1)
        XCTAssertGreaterThan(s.totalReclaimable, 0)
        XCTAssertGreaterThan(s.duration, 0)
    }

    func testPerceptualPhaseRespectsConfigFlag() async throws {
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try createTempFile(named: "img.png", in: dir, withSize: 2048) // non-decodable image is skipped

        var enabledConfig = config(for: dir)
        enabledConfig.enablePerceptualScan = true
        let orchestrator = ScanOrchestrator(fileWalker: StubFileWalker(root: dir), repository: MockDuplicateRepository())

        let enabledPhases = await phases(from: await orchestrator.run(config: enabledConfig, controller: ScanController()))
        XCTAssertTrue(enabledPhases.contains(.perceptual), "Perceptual phase should run when enabled")

        let disabledPhases = await phases(from: await orchestrator.run(config: config(for: dir), controller: ScanController()))
        XCTAssertFalse(disabledPhases.contains(.perceptual), "Perceptual phase should be skipped when disabled")
    }

    func testWarningsFlowForUnreadableFile() async throws {
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let content = "same length content for warning test"
        try createTextFile(named: "a.txt", in: dir, content: content)
        let locked = try createTextFile(named: "b.txt", in: dir, content: content)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }

        let orchestrator = ScanOrchestrator(fileWalker: StubFileWalker(root: dir), repository: MockDuplicateRepository())
        let controller = ScanController()

        let stream = await orchestrator.run(config: config(for: dir), controller: controller)
        var warnings: [ScanWarning] = []
        for await event in stream {
            if case .warning(let warning) = event {
                warnings.append(warning)
            }
        }

        XCTAssertTrue(warnings.contains {
            $0.url?.resolvingSymlinksInPath() == locked.resolvingSymlinksInPath() && $0.phase == .byteIdentical
        },
        "Unreadable file of matching size should surface a byteIdentical warning")
    }
}
