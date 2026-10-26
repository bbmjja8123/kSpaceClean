// kWise/Tests/HousekeepingDetectorTests.swift
//
// Task 8 — 家务三组检测器：iOS 设备备份 / 下载分诊 / 废纸篓大项。
// 全部走临时目录夹具（只读探测，检测器零写入）；container-only（homeURL
// nil）返回空 —— 上画布诊断由 CanvasScanCoordinator 负责（见该文件测试）。
import XCTest
@testable import kWise

final class HousekeepingDetectorTests: XCTestCase {

    private func makeTempHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("hh-\(UUID().uuidString)", isDirectory: true)
        for rel in ["Library/Application Support/MobileSync/Backup/DEV1",
                    "Downloads", ".Trash"] {
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(rel), withIntermediateDirectories: true)
        }
        return home
    }

    func testDetectsIOSBackupDirs() async throws {
        let home = try makeTempHome()
        let backup = home.appendingPathComponent("Library/Application Support/MobileSync/Backup/DEV1")
        try Data(repeating: 0, count: 5_000_000).write(to: backup.appendingPathComponent("Manifest.db"))

        let findings = await HousekeepingDetector().scan(homeURL: home)
        let backups = findings.filter { $0.kind == .iosBackup }
        XCTAssertEqual(backups.count, 1, "MobileSync/Backup 每台设备一个子目录 → 一个 finding")
        // temp 目录经 /var → /private/var 符号链接，按 standardized path 比较。
        XCTAssertEqual(backups.first?.url.standardizedFileURL.path,
                       backup.standardizedFileURL.path)
        XCTAssertGreaterThan(backups.first?.bytes ?? 0, 0, "备份目录字节 = 目录递归合计")
    }

    func testStaleDownloadsThreshold() async throws {
        let home = try makeTempHome()
        let dl = home.appendingPathComponent("Downloads")
        let old = dl.appendingPathComponent("old-video.mp4")
        try Data(repeating: 0, count: 20_000_000).write(to: old)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-14 * 86400 - 60)], ofItemAtPath: old.path)
        let fresh = dl.appendingPathComponent("fresh.mp4")
        try Data(repeating: 0, count: 20_000_000).write(to: fresh)

        let stale = await HousekeepingDetector().scan(homeURL: home)
        let staleOnly = stale.filter { $0.kind == .staleDownloads }
        XCTAssertEqual(staleOnly.map { $0.url.standardizedFileURL.path },
                       [old.standardizedFileURL.path], "14 天阈值：仅旧文件入组")
        XCTAssertEqual(staleOnly.first?.daysIdle, 14, "daysIdle 取整天数")
    }

    func testTrashLargeItems() async throws {
        let home = try makeTempHome()
        let big = home.appendingPathComponent(".Trash/big.dmg")
        try Data(repeating: 0, count: 30_000_000).write(to: big)
        let small = home.appendingPathComponent(".Trash/small.txt")
        try Data("x".utf8).write(to: small)

        let trash = await HousekeepingDetector().scan(homeURL: home)
        let trashOnly = trash.filter { $0.kind == .trashLargeItems }
        XCTAssertEqual(trashOnly.map { $0.url.standardizedFileURL.path },
                       [big.standardizedFileURL.path], ">10MB 才入组")
    }

    func testContainerOnlyYieldsNothingNotCrash() async {
        let findings = await HousekeepingDetector().scan(homeURL: nil)
        XCTAssertTrue(findings.isEmpty, "container-only → 空结果（诚实降级，由 coordinator 上诊断）")
    }
}
