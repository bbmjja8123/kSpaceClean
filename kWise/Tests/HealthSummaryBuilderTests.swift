// kWise/Tests/HealthSummaryBuilderTests.swift
import XCTest
@testable import kWise
import CommonUtils

final class HealthSummaryBuilderTests: XCTestCase {

    /// 固定基准时间：所有日期都用它反推、所有 build 都显式传它，消除跨日界 flake。
    private let now = Date()

    private func entry(appSize: Int64 = 10_000, leftoverSize: Int64 = 500,
                       installedDaysAgo: Int? = 100,
                       lastUsedDaysAgo: Int? = 7,
                       isOrphan: Bool = false) -> UninstallAppEntry {
        UninstallAppEntry(
            appName: "App", bundleID: "com.test",
            appURL: URL(fileURLWithPath: isOrphan ? "/nonexistent/App.app" : "/Applications/App.app"),
            appSize: appSize, leftoverURLs: [], leftoverSize: leftoverSize,
            isOrphan: isOrphan,
            lastUsedDate: lastUsedDaysAgo.map { now.addingTimeInterval(-Double($0) * 86_400) },
            installDate: installedDaysAgo.map { now.addingTimeInterval(-Double($0) * 86_400) },
            isRunning: false, source: .userInstalled, residues: []
        )
    }

    func testCleanGrade() {
        let summary = HealthSummaryBuilder.build(for: entry(appSize: 10_000, leftoverSize: 500), now: now)
        XCTAssertEqual(summary.grade, .clean)
    }

    /// 注意：比率路径仅在 leftoverSize ≥ 50MB（I-1 绝对阈值之后）才生效，故用大尺寸用例。
    func testNormalGrade() {
        let summary = HealthSummaryBuilder.build(
            for: entry(appSize: 200_000_000, leftoverSize: 60_000_000), now: now)
        XCTAssertEqual(summary.grade, .normal)
    }

    func testBloatedGrade() {
        let summary = HealthSummaryBuilder.build(
            for: entry(appSize: 100_000_000, leftoverSize: 60_000_000), now: now)
        XCTAssertEqual(summary.grade, .bloated)
    }

    func testOrphanIsAlwaysBloated() {
        let summary = HealthSummaryBuilder.build(for: entry(appSize: 0, leftoverSize: 500, isOrphan: true), now: now)
        XCTAssertEqual(summary.grade, .bloated, "孤儿条目固定臃肿（残留即全部）")
    }

    /// 孤儿优先级：ratio 0.01 本应 clean，orphan 翻转为 bloated（同时锁住孤儿 > 50MB/比率的判定顺序）。
    func testOrphanFlipsCleanRatioToBloated() {
        let summary = HealthSummaryBuilder.build(
            for: entry(appSize: 10_000, leftoverSize: 100, isOrphan: true), now: now)
        XCTAssertEqual(summary.grade, .bloated)
        XCTAssertEqual(summary.gradeText, "臃肿")
    }

    /// 50MB 绝对阈值（I-1）：leftoverSize < 50MB 直接 clean，优先于比率判定——
    /// 此处 ratio ≈ 5242（远 > 0.5），若无 50MB 规则会被误判 bloated。
    func testLeftoverUnder50MBIsCleanEvenWithHighRatio() {
        let summary = HealthSummaryBuilder.build(
            for: entry(appSize: 10_000, leftoverSize: 50 * 1_048_576 - 1), now: now)
        XCTAssertEqual(summary.grade, .clean)
    }

    /// 边界：leftoverSize 恰好 50MB 不触发绝对阈值，落入比率判定（ratio ≈ 0.26 → normal）。
    func testExactly50MBFallsThroughToRatio() {
        let summary = HealthSummaryBuilder.build(
            for: entry(appSize: 200_000_000, leftoverSize: 50 * 1_048_576), now: now)
        XCTAssertEqual(summary.grade, .normal)
    }

    /// 边界：ratio 恰好 0.5（不 > 0.5）且 leftover ≥ 50MB → normal 而非 bloated。
    func testRatioExactlyHalfIsNormal() {
        let summary = HealthSummaryBuilder.build(
            for: entry(appSize: 104_857_600, leftoverSize: 52_428_800), now: now)
        XCTAssertEqual(summary.grade, .normal)
    }

    /// 边界：ratio 恰好 0.1（≥ 0.1）→ normal 而非 clean。
    func testRatioExactlyTenthIsNormal() {
        let summary = HealthSummaryBuilder.build(
            for: entry(appSize: 524_288_000, leftoverSize: 52_428_800), now: now)
        XCTAssertEqual(summary.grade, .normal)
    }

    /// 摘要卡其余字段（review #4）：gradeText / totalSizeText / residueRatio。
    func testSummaryFields() {
        let summary = HealthSummaryBuilder.build(for: entry(), now: now)
        XCTAssertEqual(summary.grade, .clean)
        XCTAssertEqual(summary.gradeText, "干净")
        XCTAssertEqual(summary.residueRatio, 0.05, accuracy: 0.0001)
        XCTAssertEqual(summary.totalSizeText, FileSizeFormatter.abbreviated(from: 10_500))
    }

    func testUnknownLastUsed() {
        let summary = HealthSummaryBuilder.build(for: entry(lastUsedDaysAgo: nil), now: now)
        XCTAssertEqual(summary.lastUsedText, "未知")
    }

    func testDaysInstalled() {
        let summary = HealthSummaryBuilder.build(for: entry(installedDaysAgo: 342), now: now)
        XCTAssertEqual(summary.daysInstalled, 342)
    }
}
