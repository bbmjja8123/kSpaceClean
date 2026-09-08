// kWise/Tests/ToolboxGroupMappingTests.swift
//
// v2.3 Phase 1 — DetectionCore → ToolboxGroup mapping: identity preservation,
// strategy re-application, honest clone reclaim math, evidence badges.
import XCTest
import DetectionCore
@testable import kWise

final class ToolboxGroupMappingTests: XCTestCase {

    private func engineGroup(cloneSet: Bool = false, count: Int = 3,
                             size: Int64 = 1_000) -> DetectionCore.DuplicateGroup {
        let files: [DetectionCore.FileItem] = (0..<count).map { i in
            DetectionCore.FileItem(
                id: UUID(),
                url: URL(fileURLWithPath: "/tmp/copy\(i).bin"),
                size: size,
                modificationDate: Date(timeIntervalSince1970: Double(100 + i)),
                creationDate: nil,
                hash: "same-hash",
                fingerprint: nil,
                inode: cloneSet ? 42 : UInt64(i),
                isAPFSClone: cloneSet,
                physicalSize: cloneSet ? size : nil
            )
        }
        let evidence: CategoryEvidence = cloneSet
            ? .apfsClone(sha256: "h")
            : .byteIdentical(sha256: "h", byteVerified: true)
        return DetectionCore.DuplicateGroup(
            id: UUID(), category: .identical,
            totalSize: size * Int64(count), fileCount: count, files: files,
            categoryEvidence: evidence, similarity: nil, scanTimestamp: Date()
        )
    }

    func testMapPreservesIdentityAndEvidence() {
        let engine = engineGroup()
        let group = ToolboxGroup.map(engine, strategy: .keepNewest, scanRoots: [])
        XCTAssertEqual(group.id, engine.id)
        XCTAssertNil(group.similarity)
        XCTAssertEqual(group.files.count, 3)
        XCTAssertTrue(group.evidenceSummary.contains("字节级相同"))
    }

    func testKeepNewestSelectsRemovalsAndLabelsKeep() {
        let group = ToolboxGroup.map(engineGroup(), strategy: .keepNewest, scanRoots: [])
        let checked = group.files.filter(\.isSelected)
        XCTAssertEqual(checked.count, 2, "keepNewest pre-checks all but the newest copy")
        let keep = group.files.first { !$0.isSelected }
        XCTAssertEqual(keep?.reason, "Kept — most recently modified copy")
        XCTAssertFalse(checked.contains { $0.id == keep?.id })
    }

    func testReapplyingStrategyChangesKeep() {
        var group = ToolboxGroup.map(engineGroup(), strategy: .keepNewest, scanRoots: [])
        let newestKeep = group.files.first { !$0.isSelected }?.id
        group.reapplying(strategy: .keepOldest, scanRoots: [])
        let oldestKeep = group.files.first { !$0.isSelected }?.id
        XCTAssertNotEqual(newestKeep, oldestKeep)
        XCTAssertEqual(group.files.filter(\.isSelected).count, 2)
    }

    func testCloneSetReclaimsNothing() {
        let cloneGroup = ToolboxGroup.map(engineGroup(cloneSet: true), strategy: .keepNewest, scanRoots: [])
        XCTAssertEqual(cloneGroup.honestlyReclaimable, 0,
                       "APFS clone sets share extents — honest reclaim is zero")

        let byteGroup = ToolboxGroup.map(engineGroup(), strategy: .keepNewest, scanRoots: [])
        XCTAssertEqual(byteGroup.honestlyReclaimable, 2_000)
    }

    func testEvidenceBadges() {
        XCTAssertTrue(badge(for: .apfsClone(sha256: "h")).contains("克隆"))
        XCTAssertTrue(badge(for: .perceptualSimilarity(distance: 0.2, method: .visionFeaturePrint)).contains("80%"))
        XCTAssertTrue(badge(for: .nameHeuristic(stem: "IMG_1", variantCount: 4)).contains("IMG_1"))
    }
}

import AppKit

final class NullDuplicateRepositoryTests: XCTestCase {
    func testAllMethodsAreNoOps() async throws {
        let repo = NullDuplicateRepository()
        try await repo.saveScanRecord(ScanRecord(
            id: UUID(), timestamp: Date(), profileType: .custom,
            totalFilesScanned: 0, totalDuplicatesFound: 0,
            totalWasteSize: 0, duration: 1, groups: []
        ))
        let records = try await repo.loadScanRecords()
        XCTAssertTrue(records.isEmpty)
        let byID = try await repo.loadScanRecord(id: UUID())
        XCTAssertNil(byID)
        try await repo.deleteScanRecord(id: UUID())
        try await repo.saveCleanupAction(CleanupAction(
            id: UUID(),
            file: FileItem(id: UUID(),
                           url: URL(fileURLWithPath: "/tmp/x"), size: 1,
                           modificationDate: Date(), creationDate: nil, hash: nil,
                           fingerprint: nil, inode: nil, isAPFSClone: false, physicalSize: nil),
            method: .trash, timestamp: Date()
        ))
        let history = try await repo.loadCleanupHistory()
        XCTAssertTrue(history.isEmpty)
    }
}
