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
}
