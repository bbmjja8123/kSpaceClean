// kWise/Tests/DrillDownQuickLookTests.swift
import XCTest
@testable import kWise

final class DrillDownQuickLookTests: XCTestCase {
    // 下钻行只有文件系统里的真实目标才能预览 —— 组装器映射的 target.url
    // 必须存在且是常规文件；目录/虚拟条目不接 QuickLook（诚实降级）。
    func testPreviewableEntriesMapToRegularFiles() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ql-fix-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("a.log")
        try Data("x".utf8).write(to: file)

        XCTAssertTrue(KWQuickLookEligibility.isPreviewable(file))
        XCTAssertFalse(KWQuickLookEligibility.isPreviewable(dir))
        XCTAssertFalse(KWQuickLookEligibility.isPreviewable(URL(fileURLWithPath: "/nonexistent-\(UUID())")))
        try? FileManager.default.removeItem(at: dir)
    }

    // 可预览性缓存的语义：entries 是 let 且 init 后无重设路径，判定在
    // init 一次性冻结 —— 之后文件消失，VM 仍报可预览（行渲染/Space 键
    // 只查表，绝不在 body 重求值里做文件系统 stat；文件消失的实际后果
    // 由 QuickLook sheet 自身呈现，不属本缓存职责）。
    @MainActor
    func testEligibilityCachedForEntriesLifetime() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ql-cache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("cached.bin")
        try Data("x".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: dir) }

        let entry = CanvasEntry(title: "cached.bin", bytes: 1,
                                badge: .recyclable,
                                target: CleanupTarget(url: file, size: 1))
        let group = try XCTUnwrap(CanvasGroupAssembler.assemble(
            kind: .largeFiles, icon: "doc", entries: [entry], totalBytes: 1))
        let model = GroupDrillDownModel(group: group, entries: [entry])

        XCTAssertTrue(model.isPreviewable(entry.id))

        try FileManager.default.removeItem(at: file)
        XCTAssertFalse(KWQuickLookEligibility.isPreviewable(file), "文件系统侧已不可预览")
        XCTAssertTrue(model.isPreviewable(entry.id), "VM 缓存冻结于 init，不随后续 stat 翻转")
    }
}
