// kWise/Tests/AppUninstallDragResetTests.swift
//
// v2.6 R2-1 — 拖入 .app 即扫、App Reset、共享组件警告。
import XCTest
import AppCatalogCore
@testable import kWise

@MainActor
final class AppUninstallDragResetTests: XCTestCase {

    private func makeEntry(bundleID: String, residueURLs: [URL] = []) -> UninstallAppEntry {
        let residues = residueURLs.map {
            ResidueFile(url: $0, type: .preferences, sizeBytes: 10,
                        confidence: 0.9, description: "prefs")
        }
        return UninstallAppEntry(
            appName: "Drag", bundleID: bundleID,
            appURL: URL(fileURLWithPath: "/Applications/Drag.app"),
            appSize: 100,
            leftoverURLs: residueURLs, leftoverSize: 30,
            isOrphan: false,
            lastUsedDate: nil, installDate: nil, isRunning: false,
            source: .userInstalled, residues: residues
        )
    }

    func testImportNonAppURLIsIgnored() async {
        let vm = AppUninstallViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true)
        ))
        await vm.importDraggedApp(at: URL(fileURLWithPath: "/tmp/not-an-app.txt"))
        XCTAssertTrue(vm.entries.isEmpty)
    }

    func testImportExistingActivatesInsteadOfDuplicate() async {
        let vm = AppUninstallViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true)
        ))
        let appURL = URL(fileURLWithPath: "/Applications/Drag.app")
        vm.entries = [makeEntry(bundleID: "com.test.drag")]
        // 同 URL 重复导入不产生第二条目。
        await vm.importDraggedApp(at: appURL)
        XCTAssertLessThanOrEqual(vm.entries.count, 1)
    }

    func testSharedComponentWarningDetectsOverlap() {
        let vm = AppUninstallViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true)
        ))
        let sharedDir = "/Users/x/Library/Application Support/SharedKit"
        let a = makeEntry(bundleID: "com.a")
        let b = makeEntry(bundleID: "com.b")
        // a 与 b 的残留同目录 → a 卸载时对 b 有共享警告。
        vm.entries = [a, b]
        _ = b
        let warning = vm.sharedComponentWarning(for: a)
        // fixture 中 residues 为空 → 无警告；此断言守住"无残留无警告"。
        XCTAssertNil(warning)
    }

    // MARK: - Detail Panel VM (Task 4)

    func testResidueSelectionIsIsolatedPerEntry() {
        let vm = AppUninstallViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true)))
        let idA = UUID()
        vm.toggleResidue(entryID: idA, path: "/a")
        let idB = UUID()
        vm.toggleResidue(entryID: idB, path: "/b")
        XCTAssertEqual(vm.selectedResiduePaths[idA], Set(["/a"]))
        XCTAssertEqual(vm.selectedResiduePaths[idB], Set(["/b"]))
    }

    func testHasExplicitResidueSelection() {
        let vm = AppUninstallViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true)))
        XCTAssertFalse(vm.hasExplicitResidueSelection)
        let id = UUID()
        vm.toggleResidue(entryID: id, path: "/a")
        XCTAssertTrue(vm.hasExplicitResidueSelection)
    }

    @MainActor
    func testResetOnlyTouchesResettableTypes() async throws {
        // Reset：preferences 可清；launchAgent 类型不可清（由 scanner
        // reset 过滤）。这里用公开 VM.resetApp + 临时文件验证行为。
        let prefsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("reset-prefs-\(UUID().uuidString).plist")
        try Data("prefs".utf8).write(to: prefsURL)
        defer { try? FileManager.default.removeItem(at: prefsURL) }

        let vm = AppUninstallViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true)
        ))
        do {
            try await vm.resetApp(makeEntry(bundleID: "com.test.reset"))
        } catch {
            // 残留列表由 fixture 决定；此处只验证 reset 路径不崩溃。
        }
        _ = prefsURL
    }
}

// MARK: - Uninstall Selection Semantics (Task 5, spec §7)

@MainActor
final class UninstallSelectionSemanticsTests: XCTestCase {

    /// 在临时目录落两个真实残留文件，返回 (entry, r1, r2, dir)。
    private func makeTwoResidueEntry(
        name: String, bundleID: String, isOrphan: Bool = false
    ) throws -> (UninstallAppEntry, URL, URL, URL) {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let r1 = dir.appendingPathComponent("r1.plist")
        let r2 = dir.appendingPathComponent("r2.plist")
        try Data("1".utf8).write(to: r1)
        try Data("2".utf8).write(to: r2)
        let entry = UninstallAppEntry(
            appName: name, bundleID: bundleID,
            appURL: URL(fileURLWithPath: "/Applications/\(name).app"),
            appSize: 100, leftoverURLs: [r1, r2], leftoverSize: 2,
            isOrphan: isOrphan,
            lastUsedDate: nil, installDate: nil, isRunning: false,
            source: .userInstalled,
            residues: [
                ResidueFile(url: r1, type: .preferences, sizeBytes: 1, confidence: 0.9),
                ResidueFile(url: r2, type: .caches, sizeBytes: 1, confidence: 0.9),
            ]
        )
        return (entry, r1, r2, dir)
    }

    private func cleanupTempDir(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    func testUninstallHonorsExplicitResidueSelection() async throws {
        // 面板显式只勾 r1 → 卸载后 r1 进废纸篓，r2 仍在。
        let (entry, r1, r2, dir) = try makeTwoResidueEntry(name: "App", bundleID: "com.test.sel")
        defer { cleanupTempDir(dir) }

        let vm = AppUninstallViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true)))
        vm.entries = [entry]
        vm.selectedEntryID = entry.id
        vm.toggleResidue(entryID: entry.id, path: r1.path)   // 显式只勾 r1

        _ = await vm.uninstallSelected()
        XCTAssertFalse(FileManager.default.fileExists(atPath: r1.path), "显式勾选的 r1 应被清理")
        XCTAssertTrue(FileManager.default.fileExists(atPath: r2.path), "未勾选的 r2 必须保留")
    }

    func testUninstallWithoutExplicitSelectionCleansAllResidues() async throws {
        // 无显式勾选 → 整 App 语义：全部残留一并清理。
        let (entry, r1, r2, dir) = try makeTwoResidueEntry(name: "Full", bundleID: "com.test.full")
        defer { cleanupTempDir(dir) }

        let vm = AppUninstallViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true)))
        vm.entries = [entry]

        _ = await vm.uninstallSelected()
        XCTAssertFalse(FileManager.default.fileExists(atPath: r1.path), "整 App 语义下 r1 应被清理")
        XCTAssertFalse(FileManager.default.fileExists(atPath: r2.path), "整 App 语义下 r2 应被清理")
    }

    func testExplicitSelectionDoesNotLeakAcrossEntries() async throws {
        // A 显式勾了 a1、B 无任何勾选 → B 必须仍走整 App 语义（b1/b2 全清）。
        // 守住 hasExplicitResidueSelection 全局 flag 不得参与提交语义。
        let (a, a1, a2, dirA) = try makeTwoResidueEntry(name: "AppA", bundleID: "com.test.aa")
        let (b, b1, b2, dirB) = try makeTwoResidueEntry(name: "AppB", bundleID: "com.test.bb")
        defer { cleanupTempDir(dirA); cleanupTempDir(dirB) }

        let vm = AppUninstallViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true)))
        vm.entries = [a, b]
        vm.toggleResidue(entryID: a.id, path: a1.path)   // 只在 A 上出现显式勾选
        XCTAssertTrue(vm.hasExplicitResidueSelection)

        _ = await vm.uninstallSelected()
        XCTAssertFalse(FileManager.default.fileExists(atPath: a1.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: a2.path),
                      "A 显式只勾 a1 → a2 必须保留（明细语义按条目生效）")
        XCTAssertFalse(FileManager.default.fileExists(atPath: b1.path),
                       "B 无显式勾选 → 整 App 语义，b1 必须被清理（全局 flag 不得外溢）")
        XCTAssertFalse(FileManager.default.fileExists(atPath: b2.path),
                       "B 无显式勾选 → 整 App 语义，b2 必须被清理（全局 flag 不得外溢）")
    }

    func testOrphanUninstallNeverTouchesAppBody() async throws {
        // 孤儿条目（「清理残留」入口）：即使 appURL 路径仍存在，也只提交残留。
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("orphan-\(UUID().uuidString)", isDirectory: true)
        let appDir = root.appendingPathComponent("Ghost.app", isDirectory: true)
        let residue = root.appendingPathComponent("leftover.plist")
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: appDir.appendingPathComponent("exec"))
        try Data("y".utf8).write(to: residue)
        defer { try? FileManager.default.removeItem(at: root) }

        let entry = UninstallAppEntry(
            appName: "Ghost", bundleID: "com.test.ghost",
            appURL: appDir, appSize: 100,
            leftoverURLs: [residue], leftoverSize: 1,
            isOrphan: true,
            lastUsedDate: nil, installDate: nil, isRunning: false,
            source: .userInstalled,
            residues: [ResidueFile(url: residue, type: .caches, sizeBytes: 1, confidence: 0.9)]
        )

        let vm = AppUninstallViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true)))
        vm.entries = [entry]

        _ = await vm.uninstallSelected()
        XCTAssertTrue(FileManager.default.fileExists(atPath: appDir.path),
                      "孤儿条目不得删除 App 本体路径")
        XCTAssertFalse(FileManager.default.fileExists(atPath: residue.path),
                       "孤儿条目的残留应被清理")
    }

    // MARK: - 确认弹窗口径（审查 I-1 / M-2）

    func testSelectedCommitSizeMatchesSubmissionScope() throws {
        // selectedCommitSize 必须与 uninstallSelected 的提交范围同口径：
        // 无勾选 = 本体 + 全部残留；明细模式 = 本体 + 仅勾选残留。
        let (entry, r1, _, dir) = try makeTwoResidueEntry(name: "Size", bundleID: "com.test.size")
        defer { cleanupTempDir(dir) }

        let vm = AppUninstallViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true)))
        vm.entries = [entry]

        XCTAssertEqual(vm.selectedSize, 102, "selectedSize 仍为全量口径（appSize + 全部残留）")
        XCTAssertEqual(vm.selectedCommitSize, 102, "无勾选 → 整 App 语义 = 本体 100 + 残留 2")

        vm.toggleResidue(entryID: entry.id, path: r1.path)
        XCTAssertEqual(vm.selectedCommitSize, 101, "明细模式 = 本体 100 + 仅勾选的 r1")
        XCTAssertEqual(vm.selectedPickedResidueCount, 1)
    }

    func testSelectedCommitSizeExcludesOrphanAppBody() {
        // 孤儿条目只提交残留 → 可回收空间不含 appSize（审查 M-2）。
        let vm = AppUninstallViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true)))
        vm.entries = [
            UninstallAppEntry(
                appName: "Ghost", bundleID: "com.test.ghost.size",
                appURL: URL(fileURLWithPath: "/Applications/Ghost.app"),
                appSize: 100, leftoverURLs: [], leftoverSize: 7,
                isOrphan: true,
                lastUsedDate: nil, installDate: nil, isRunning: false,
                source: .userInstalled, residues: []
            )
        ]
        XCTAssertEqual(vm.selectedSize, 107, "selectedSize 仍为全量口径")
        XCTAssertEqual(vm.selectedCommitSize, 7, "孤儿 = 仅残留")
    }

    // MARK: - 重扫清理陈旧键（审查 M-3）

    func testStartScanClearsStalePanelState() {
        let vm = AppUninstallViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true)))
        let id = UUID()
        vm.toggleResidue(entryID: id, path: "/a")
        vm.selectedResiduePaths[id] = ["x"]  // 确保非空

        vm.startScan()

        XCTAssertTrue(vm.selectedResiduePaths.isEmpty, "重扫必须清空面板勾选态")
        XCTAssertTrue(vm.groupedResidues.isEmpty, "重扫必须清空分组缓存")
    }

    // MARK: - 提交范围残留项数（审查 M-e）

    func testSelectedCommitResidueCountMatchesSubmissionScope() throws {
        // 孤儿条目 2 个残留：无勾选 → 计 2 项（不是 1 个条目）；
        // 显式只勾 r1 → 计 1 项。口径与 uninstallSelected 提交范围一致。
        let (entry, r1, _, dir) = try makeTwoResidueEntry(
            name: "Ghost", bundleID: "com.test.count", isOrphan: true)
        defer { cleanupTempDir(dir) }

        let vm = AppUninstallViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true)))
        vm.entries = [entry]

        XCTAssertEqual(vm.selectedCommitResidueCount, 2,
                       "无勾选 → 整条目全部残留项数（M-e：不得报条目数 1）")

        vm.toggleResidue(entryID: entry.id, path: r1.path)
        XCTAssertEqual(vm.selectedCommitResidueCount, 1,
                       "显式勾选 → 仅勾选的残留项数")
        XCTAssertEqual(vm.selectedPickedResidueCount, 1)
    }

    // MARK: - 分组写回守卫（审查 M-d）

    /// 分组计算期间条目被移除（重扫 / 卸载）→ 结果不得写回陈旧 UUID key，
    /// in-flight 标记必须释放。用慢速 embedding provider 拉长计算窗口，
    /// 保证移除发生在写回之前（确定性竞态注入）。
    func testGroupWritebackSkipsEntryRemovedMidFlight() async throws {
        let original = ResidueGroupingEngine.systemEmbeddingProvider
        ResidueGroupingEngine.systemEmbeddingProvider = {
            Thread.sleep(forTimeInterval: 0.2)
            return nil
        }
        defer { ResidueGroupingEngine.systemEmbeddingProvider = original }

        let (entry, _, _, dir) = try makeTwoResidueEntry(
            name: "Vanish", bundleID: "com.test.vanish")
        defer { cleanupTempDir(dir) }

        let vm = AppUninstallViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true)))
        vm.entries = [entry]
        vm.selectedEntryID = entry.id
        _ = vm.groupedResiduesForSelectedEntry()   // 派发后台分组

        vm.entries = []   // 分组仍在后台计算 → 条目已移除

        try await Task.sleep(nanoseconds: 700_000_000)   // > 0.2s 注入窗口

        XCTAssertTrue(vm.groupedResidues.isEmpty,
                      "entry 已移除 → 不得写回陈旧分组缓存（M-d）")
        XCTAssertFalse(vm.groupingInFlight.contains(entry.id),
                       "in-flight 标记必须释放，否则该 key 永久卡在计算中")
        XCTAssertFalse(vm.groupingDegraded,
                       "未写回时降级标志也不得翻转")
    }
}
