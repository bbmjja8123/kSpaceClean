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

    // MARK: - 文件夹级级联 (v2.6 第二轮)

    /// 目录级组：folderA(2 文件) + folderB(1 文件)，B 中的 f3 为保留件。
    private func makeFolderVM() -> (DuplicateViewModel, UUID) {
        let vm = makeVM()
        let groupID = UUID()
        func file(_ name: String, selected: Bool) -> ToolboxFile {
            ToolboxFile(id: UUID(), url: URL(fileURLWithPath: name), size: 100,
                        modificationDate: Date(), isAPFSClone: false,
                        isSelected: selected, reason: nil)
        }
        vm.groups = [ToolboxGroup(
            id: groupID, category: .directoryDedup, similarity: nil,
            evidenceSummary: "目录级重复（3 个文件）",
            files: [
                file("/tmp/folderA/f1.bin", selected: false),
                file("/tmp/folderA/f2.bin", selected: false),
                file("/tmp/folderB/f3.bin", selected: false),  // 保留件
            ],
            isExpanded: true, honestlyReclaimable: 200)]
        return (vm, groupID)
    }

    func testSelectFolderCascadesWithinPrefixOnly() {
        let (vm, groupID) = makeFolderVM()
        vm.selectFolder(in: groupID, folderURL: URL(fileURLWithPath: "/tmp/folderA"),
                        selected: true)
        let a = vm.groups[0].files.filter { $0.url.path.hasPrefix("/tmp/folderA") }
        let b = vm.groups[0].files.filter { $0.url.path.hasPrefix("/tmp/folderB") }
        XCTAssertTrue(a.allSatisfy(\.isSelected))
        XCTAssertTrue(b.allSatisfy { !$0.isSelected }, "其他文件夹的保留件不受级联影响")
    }

    func testSelectFolderDeselectActuallyClearsSelection() {
        let (vm, groupID) = makeFolderVM()
        let urlA = URL(fileURLWithPath: "/tmp/folderA")
        vm.selectFolder(in: groupID, folderURL: urlA, selected: true)
        vm.selectFolder(in: groupID, folderURL: urlA, selected: false)
        XCTAssertTrue(vm.groups[0].files.allSatisfy { !$0.isSelected },
                      "取消勾选文件夹必须真的清掉勾选（回归：反逻辑守卫曾使取消变 no-op）")
    }

    func testCleanupOlderFoldersSkipsKeepFolder() {
        let (vm, groupID) = makeFolderVM()
        // 模拟 reapplyStrategy 后的真实状态：保留件 f3 未勾选，其余预勾选。
        for fi in vm.groups[0].files.indices {
            vm.groups[0].files[fi].isSelected = vm.groups[0].files[fi].url.path != "/tmp/folderB/f3.bin"
        }
        vm.cleanupOlderFolders(in: groupID)
        let a = vm.groups[0].files.filter { $0.url.path.hasPrefix("/tmp/folderA") }
        let b = vm.groups[0].files.filter { $0.url.path.hasPrefix("/tmp/folderB") }
        XCTAssertTrue(a.allSatisfy(\.isSelected), "保留件所在文件夹之外整体勾选")
        XCTAssertTrue(b.allSatisfy { !$0.isSelected }, "保留件所在文件夹不动")
    }

    // MARK: - 会话累计

    func testSessionFreedAccumulates() {
        let vm = makeVM()
        XCTAssertEqual(vm.sessionFreed, 0)
        vm.recordSessionFreed(1_500)
        vm.recordSessionFreed(500)
        XCTAssertEqual(vm.sessionFreed, 2_000)
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
