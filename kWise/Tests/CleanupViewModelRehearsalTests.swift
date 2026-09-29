// kWise/Tests/CleanupViewModelRehearsalTests.swift
//
// P1 T4 — CleanupViewModel 两段式（预演 → 确认执行）契约测试。
// 红线：预演 == 执行（1:1 同序）、空 pendingTargets 绝不兜底执行上次清单。
import XCTest
@testable import kWise

@MainActor
final class CleanupViewModelRehearsalTests: XCTestCase {
    private func makeVM(attributions: [SpaceAttribution]) -> (CleanupViewModel, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rehearsal-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let vm = CleanupViewModel(engine: CleanupEngine(
            persistence: PersistenceController(inMemory: true), quota: nil))
        vm.attributionLookup = { attributions }
        return (vm, root)
    }

    func testRehearsalMirrorsSelectedURLsOneToOne() async {
        let (vm, root) = makeVM(attributions: [])
        let a = root.appendingPathComponent("a.bin"); let b = root.appendingPathComponent("b.bin")
        try? Data("x".utf8).write(to: a); try? Data("y".utf8).write(to: b)

        let items = await vm.makeRehearsal(sizes: [a: 1, b: 2],
                                           urls: [a, b])
        XCTAssertEqual(items.map(\.target.url), [a, b], "预演 == 执行（1:1 同序）")
        XCTAssertEqual(vm.pendingTargets.count, 2)
    }

    func testExecuteUsesPendingTargetsExactly() async {
        let (vm, root) = makeVM(attributions: [])
        let a = root.appendingPathComponent("a.bin")
        try? Data("x".utf8).write(to: a)
        _ = await vm.makeRehearsal(sizes: [a: 1], urls: [a])

        await vm.executeConfirmedCleanup(sizes: [a: 1])
        XCTAssertTrue(vm.lastOutcome?.succeeded.isEmpty == false,
                      "确认后执行必须真正清理 pendingTargets")
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.path))
    }

    /// 红线自审项：空 pendingTargets 时 execute 必须是 no-op ——
    /// 绝不把「上次预演的 targets」当成兜底执行。
    func testExecuteWithEmptyPendingTargetsIsNoOp() async {
        let (vm, root) = makeVM(attributions: [])
        let a = root.appendingPathComponent("a.bin")
        try? Data("x".utf8).write(to: a)

        await vm.executeConfirmedCleanup(sizes: nil)
        XCTAssertTrue(vm.lastOutcome == nil, "空 pendingTargets 不产生任何 outcome")
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.path), "文件原样保留")
    }

    /// 预演项必须带归因（来自 attributionLookup），缺席时诚实为 nil。
    func testRehearsalCarriesAttributionFromLookup() async {
        let attr = SpaceAttribution(
            scope: .fileTree, paths: [], bytes: 1, owner: .system, cause: .cache,
            reclaim: .recycles(expectedDays: 3), confidence: .certain,
            source: .rule, ruleID: "caches.app-generic", evidence: [], lastModified: nil)
        let (vm, root) = makeVM(attributions: [attr])
        let a = root.appendingPathComponent("a.bin")
        try? Data("x".utf8).write(to: a)

        // CleanRehearsal.build 按路径首段匹配 —— 这里让归因覆盖该路径。
        let covering = SpaceAttribution(
            scope: .fileTree, paths: [a.path], bytes: 1, owner: .system, cause: .cache,
            reclaim: .recycles(expectedDays: 3), confidence: .certain,
            source: .rule, ruleID: "caches.app-generic", evidence: [], lastModified: nil)
        vm.attributionLookup = { [covering] }

        let items = await vm.makeRehearsal(sizes: [a: 1], urls: [a])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].attribution?.ruleID, "caches.app-generic")
        XCTAssertEqual(items[0].target.size, 1, "预演 target 的大小来自 sizes 入参")
    }
}
