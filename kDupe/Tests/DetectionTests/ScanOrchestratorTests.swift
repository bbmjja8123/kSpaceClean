import XCTest
@testable import kDupe

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
    func testScanPipelineCompletes() async throws {
        let mockRepo = MockDuplicateRepository()
        let orchestrator = ScanOrchestrator(repository: mockRepo)
        let controller = ScanController()
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try createTempFile(named: "data.bin", in: dir, withSize: 500)
        try createIdenticalFilePair(in: dir)

        let config = ProfileConfig(
            type: .simple,
            customDirectories: [dir.path],
            exclusions: [],
            minFileSize: 1,
            enablePerceptualScan: false
        )

        let stream = orchestrator.run(config: config, controller: controller)
        var phases: [ScanPhase] = []
        for await progress in stream {
            phases.append(progress.phase)
        }

        XCTAssertTrue(phases.contains(.enumerating))
        XCTAssertTrue(phases.contains(.completed))
        XCTAssertGreaterThanOrEqual(phases.count, 2)
    }

    func testProgressStreamEmitsExpectedPhases() async throws {
        let mockRepo = MockDuplicateRepository()
        let orchestrator = ScanOrchestrator(repository: mockRepo)
        let controller = ScanController()
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try createTempFile(named: "sample.txt", in: dir, withSize: 200)

        let config = ProfileConfig(
            type: .simple,
            customDirectories: [dir.path],
            exclusions: [],
            minFileSize: 1,
            enablePerceptualScan: false
        )

        let stream = orchestrator.run(config: config, controller: controller)
        var phases: [ScanPhase] = []
        for await progress in stream {
            phases.append(progress.phase)
        }

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
        let mockRepo = MockDuplicateRepository()
        let orchestrator = ScanOrchestrator(repository: mockRepo)
        let controller = ScanController()

        // Cancel before the scan has a chance to complete.
        controller.cancel()

        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try createTempFile(named: "test.txt", in: dir, withSize: 100)

        let config = ProfileConfig(
            type: .simple,
            customDirectories: [dir.path],
            exclusions: [],
            minFileSize: 1,
            enablePerceptualScan: false
        )

        let stream = orchestrator.run(config: config, controller: controller)
        var phases: [ScanPhase] = []
        for await progress in stream {
            phases.append(progress.phase)
        }

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

    func testDefaultConfigProducesOutput() async throws {
        let mockRepo = MockDuplicateRepository()
        let orchestrator = ScanOrchestrator(repository: mockRepo)
        let controller = ScanController()
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        try createTempFile(named: "sample.txt", in: dir, withSize: 2000)

        var config = ProfileConfig.default
        config.customDirectories = [dir.path]
        config.minFileSize = 1

        let stream = orchestrator.run(config: config, controller: controller)
        var hasProgress = false
        for await _ in stream {
            hasProgress = true
        }
        XCTAssertTrue(hasProgress, "Scan should produce at least one progress event")
    }

    func testEmptyDirectoryYieldsCompletedScan() async throws {
        let mockRepo = MockDuplicateRepository()
        let orchestrator = ScanOrchestrator(repository: mockRepo)
        let controller = ScanController()
        let dir = try createTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        // No files in the directory.
        let config = ProfileConfig(
            type: .simple,
            customDirectories: [dir.path],
            exclusions: [],
            minFileSize: 1,
            enablePerceptualScan: false
        )

        let stream = orchestrator.run(config: config, controller: controller)
        var phases: [ScanPhase] = []
        for await progress in stream {
            phases.append(progress.phase)
        }

        XCTAssertTrue(phases.contains(.completed))
        XCTAssertEqual(phases.first, .enumerating)
    }
}
