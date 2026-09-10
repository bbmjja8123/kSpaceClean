// kWise/Tests/HealthSummaryBuilderTests.swift
import XCTest
@testable import kWise

final class HealthSummaryBuilderTests: XCTestCase {

    private func entry(appSize: Int64 = 10_000, leftoverSize: Int64 = 500,
                       installedDaysAgo: Int? = 100,
                       lastUsedDaysAgo: Int? = 7,
                       isOrphan: Bool = false) -> UninstallAppEntry {
        UninstallAppEntry(
            appName: "App", bundleID: "com.test",
            appURL: URL(fileURLWithPath: isOrphan ? "/nonexistent/App.app" : "/Applications/App.app"),
            appSize: appSize, leftoverURLs: [], leftoverSize: leftoverSize,
            isOrphan: isOrphan,
            lastUsedDate: lastUsedDaysAgo.map { Date().addingTimeInterval(-Double($0) * 86_400) },
            installDate: installedDaysAgo.map { Date().addingTimeInterval(-Double($0) * 86_400) },
            isRunning: false, source: .userInstalled, residues: []
        )
    }

    func testCleanGrade() {
        let summary = HealthSummaryBuilder.build(for: entry(appSize: 10_000, leftoverSize: 500))
        XCTAssertEqual(summary.grade, .clean)
    }

    func testNormalGrade() {
        let summary = HealthSummaryBuilder.build(for: entry(appSize: 10_000, leftoverSize: 3_000))
        XCTAssertEqual(summary.grade, .normal)
    }

    func testBloatedGrade() {
        let summary = HealthSummaryBuilder.build(for: entry(appSize: 10_000, leftoverSize: 8_000))
        XCTAssertEqual(summary.grade, .bloated)
    }

    func testOrphanIsAlwaysBloated() {
        let summary = HealthSummaryBuilder.build(for: entry(appSize: 0, leftoverSize: 500, isOrphan: true))
        XCTAssertEqual(summary.grade, .bloated, "孤儿条目固定臃肿（残留即全部）")
    }

    func testUnknownLastUsed() {
        let summary = HealthSummaryBuilder.build(for: entry(lastUsedDaysAgo: nil))
        XCTAssertEqual(summary.lastUsedText, "未知")
    }

    func testDaysInstalled() {
        let summary = HealthSummaryBuilder.build(for: entry(installedDaysAgo: 342))
        XCTAssertEqual(summary.daysInstalled, 342)
    }
}
