// kWise/Tests/DuplicateToolboxScanTests.swift
//
// v2.3 Phase 2 — duplicate tool VM: PowerScope-honest default scan roots,
// strategy application, engine event mapping, honest reclaim math.
import XCTest
import DetectionCore
import PowerScope
@testable import kWise

@MainActor
final class DuplicateToolboxScanTests: XCTestCase {

    private func makeVM() -> DuplicateViewModel {
        DuplicateViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true)
        ))
    }

    /// The pre-v2.3 bug: default scanPaths = NSHomeDirectory() = the sandbox
    /// CONTAINER home under MAS. Defaults must never point there.
    func testDefaultScanPathsNeverPointInsideContainer() {
        let vm = makeVM()
        let containerPath = NSHomeDirectory()  // In a sandboxed test host this IS the container.
        for url in vm.scanPaths {
            XCTAssertFalse(url.path == containerPath,
                           "Default scan root must not be the container home")
        }
    }

    func testStrategyReapplyFlipsSelection() {
        let vm = makeVM()
        vm.groups = [ToolboxGroup.map(makeEngineGroup(), strategy: .keepNewest, scanRoots: [])]
        let before = vm.groups[0].files.first { !$0.isSelected }?.id

        vm.strategy = .keepOldest
        let after = vm.groups[0].files.first { !$0.isSelected }?.id
        XCTAssertNotEqual(before, after, "Switching strategy must re-run SelectionPlanner")
        XCTAssertEqual(vm.groups[0].files.filter(\.isSelected).count, 2)
    }

    func testEngineGroupEventIsMappedWithEvidence() {
        let vm = makeVM()
        vm.groups = [ToolboxGroup.map(makeEngineGroup(), strategy: .keepNewest, scanRoots: [])]
        XCTAssertTrue(vm.groups[0].evidenceSummary.contains("字节级相同"))
    }

    func testHonestWastedUsesReclaimableNotLyingMath() {
        let vm = makeVM()
        vm.groups = [ToolboxGroup.map(makeEngineGroup(), strategy: .keepNewest, scanRoots: [])]
        XCTAssertEqual(vm.totalWasted, 2_000)  // 1000 × (3−1), byte-identical set
    }

    // MARK: - Helpers

    private func makeEngineGroup() -> DetectionCore.DuplicateGroup {
        let files: [DetectionCore.FileItem] = (0..<3).map { i in
            DetectionCore.FileItem(
                id: UUID(),
                url: URL(fileURLWithPath: "/tmp/dup/copy\(i).bin"),
                size: 1_000,
                modificationDate: Date(timeIntervalSince1970: Double(200 + i)),
                creationDate: nil, hash: "h", fingerprint: nil, inode: UInt64(i),
                isAPFSClone: false, physicalSize: nil
            )
        }
        return DetectionCore.DuplicateGroup(
            id: UUID(), category: .identical,
            totalSize: 3_000, fileCount: 3, files: files,
            categoryEvidence: .byteIdentical(sha256: "h", byteVerified: true),
            similarity: nil, scanTimestamp: Date()
        )
    }
}
