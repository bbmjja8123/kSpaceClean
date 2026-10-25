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
}
