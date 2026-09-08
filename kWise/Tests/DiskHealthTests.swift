import XCTest
@testable import kWise

@MainActor
final class DiskHealthTests: XCTestCase {
    // MARK: - SMARTStatus parsing

    func testSMARTStatusParseVerified() {
        XCTAssertEqual(SMARTStatus.parse("Verified"), .verified)
        XCTAssertEqual(SMARTStatus.parse("verified"), .verified)
        XCTAssertEqual(SMARTStatus.parse("VERIFIED"), .verified)
    }

    func testSMARTStatusParseFailing() {
        XCTAssertEqual(SMARTStatus.parse("Failing"), .failing)
    }

    func testSMARTStatusParseNotSupported() {
        XCTAssertEqual(SMARTStatus.parse("Not Supported"), .notSupported)
    }

    func testSMARTStatusParseUnknown() {
        XCTAssertEqual(SMARTStatus.parse(""), .unknown)
        XCTAssertEqual(SMARTStatus.parse("blah"), .unknown)
        XCTAssertEqual(SMARTStatus.parse("OK"), .unknown)
    }

    func testSMARTFriendlyTitle() {
        XCTAssertEqual(SMARTStatus.verified.friendlyTitle, "正常")
        XCTAssertEqual(SMARTStatus.failing.friendlyTitle, "异常")
        XCTAssertEqual(SMARTStatus.notSupported.friendlyTitle, "不支持")
        XCTAssertEqual(SMARTStatus.unknown.friendlyTitle, "未知")
    }

    // MARK: - SMARTReport

    func testUnavailableReportFlaggedAsUnknown() {
        XCTAssertEqual(SMARTReport.unavailable.status, .unknown)
        XCTAssertEqual(SMARTReport.unavailable.deviceNode, "")
    }

    // MARK: - VolumeSnapshot

    func testVolumeSnapshotRequiresFDACount() {
        let snap = VolumeSnapshot(diagnostics: [
            .init(kind: .totalBytes,    title: "总",    detail: "1000", requiresFDA: false),
            .init(kind: .freeBytes,     title: "可用",  detail: "500",  requiresFDA: false),
            .init(kind: .fileSystem,    title: "FS",    detail: "APFS", requiresFDA: true),
        ], readAt: Date())
        XCTAssertEqual(snap.requiresFDACount, 1)
    }

    func testVolumeSnapshotTotalFreeByteAccessors() {
        let snap = VolumeSnapshot(diagnostics: [
            .init(kind: .totalBytes, title: "总",   detail: "1024", requiresFDA: false),
            .init(kind: .freeBytes,  title: "可用", detail: "256",  requiresFDA: false),
        ], readAt: Date())
        XCTAssertEqual(snap.totalBytes, 1024)
        XCTAssertEqual(snap.freeBytes, 256)
        XCTAssertEqual(snap.purgeableBytes, nil)
    }

    func testEmptySnapshotHasNoDiagnostics() {
        XCTAssertTrue(VolumeSnapshot.empty.diagnostics.isEmpty)
        XCTAssertEqual(VolumeSnapshot.empty.totalBytes, nil)
        XCTAssertEqual(VolumeSnapshot.empty.freeBytes, nil)
        XCTAssertEqual(VolumeSnapshot.empty.purgeableBytes, nil)
    }

    // MARK: - HealthGrade derivation

    func testGradeDangerWhenSMARTFailing() {
        let smart = SMARTReport(status: .failing, deviceNode: "disk0", readAt: Date())
        let vol = VolumeSnapshot.empty
        XCTAssertEqual(DiskHealthViewModel.deriveGrade(smart: smart, volume: vol), .danger)
    }

    func testGradeGoodWhenSMARTVerifiedAndVolumePlentyOfRoom() {
        let smart = SMARTReport(status: .verified, deviceNode: "disk0", readAt: Date())
        let vol = VolumeSnapshot(diagnostics: [
            .init(kind: .totalBytes, title: "总",   detail: "100", requiresFDA: false),
            .init(kind: .freeBytes,  title: "可用", detail: "60",  requiresFDA: false),
        ], readAt: Date())
        XCTAssertEqual(DiskHealthViewModel.deriveGrade(smart: smart, volume: vol), .good)
    }

    func testGradeCautionWhenSMARTVerifiedAndVolumeOver95PercentUsed() {
        let smart = SMARTReport(status: .verified, deviceNode: "disk0", readAt: Date())
        let vol = VolumeSnapshot(diagnostics: [
            .init(kind: .totalBytes, title: "总",   detail: "100", requiresFDA: false),
            .init(kind: .freeBytes,  title: "可用", detail: "3",   requiresFDA: false),
        ], readAt: Date())
        XCTAssertEqual(DiskHealthViewModel.deriveGrade(smart: smart, volume: vol), .caution)
    }

    func testGradeUnknownWhenSMARTUnknownRegardlessOfVolume() {
        let smart = SMARTReport.unavailable
        let vol = VolumeSnapshot(diagnostics: [
            .init(kind: .totalBytes, title: "总",   detail: "100", requiresFDA: false),
            .init(kind: .freeBytes,  title: "可用", detail: "3",   requiresFDA: false),
        ], readAt: Date())
        // SMART notSupported/unknown wins over volume pressure.
        XCTAssertEqual(DiskHealthViewModel.deriveGrade(smart: smart, volume: vol), .unknown)
    }

    func testGradeUnknownWhenSMARTNotSupported() {
        let smart = SMARTReport(status: .notSupported, deviceNode: "disk0", readAt: Date())
        let vol = VolumeSnapshot.empty
        XCTAssertEqual(DiskHealthViewModel.deriveGrade(smart: smart, volume: vol), .unknown)
    }

    func testGradeGoodWhenSMARTVerifiedButVolumeIsEmpty() {
        // Edge: no volume diagnostics yet (first scan still in flight). Treat
        // SMART verified as good so we don't flash a danger badge.
        let smart = SMARTReport(status: .verified, deviceNode: "disk0", readAt: Date())
        let vol = VolumeSnapshot.empty
        XCTAssertEqual(DiskHealthViewModel.deriveGrade(smart: smart, volume: vol), .good)
    }

    // MARK: - HealthGrade.friendlyTitle

    func testHealthGradeFriendlyTitle() {
        XCTAssertEqual(DiskHealthViewModel.HealthGrade.good.friendlyTitle, "健康")
        XCTAssertEqual(DiskHealthViewModel.HealthGrade.caution.friendlyTitle, "注意")
        XCTAssertEqual(DiskHealthViewModel.HealthGrade.danger.friendlyTitle, "异常")
        XCTAssertEqual(DiskHealthViewModel.HealthGrade.unknown.friendlyTitle, "未知")
    }
}