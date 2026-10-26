// kWise/Tests/RehearsalSafetyCopyAuditTests.swift
//
// Task 6（feature sprint）：预演安全感叙事审计 —— 预演 sheet 必须承诺
// 30 天废纸篓回滚（attr.rehearsal.rollbackNote），且为未来的垃圾桶来源
// 永久路径预埋诚实的不可回滚标注（attr.rehearsal.permanentNote）；
// RootView 的 payload 必须携带 isPermanent 以区分两条路径。
// 与 ScarewareCopyAuditTests 同型：走文件系统源码断言，防文案回潮。
import XCTest

final class RehearsalSafetyCopyAuditTests: XCTestCase {
    /// `relative` 以 kWise/ 源码根为基准（Tests/ 在其下，故回退两级）。
    private func source(_ relative: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // kWise/
            .appendingPathComponent(relative)
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func testRehearsalSheetCarriesRollbackPromise() {
        let src = source("Features/Cleanup/CleanupRehearsalSheet.swift")
        XCTAssertTrue(src.contains("attr.rehearsal.rollbackNote"),
                      "预演 sheet 必须承诺 30 天废纸篓回滚（安全感叙事）")
        XCTAssertTrue(src.contains("attr.rehearsal.permanentNote"),
                      "永久路径（垃圾桶大项）必须诚实标注不可回滚")
    }

    func testPayloadCarriesIsPermanent() {
        XCTAssertTrue(source("App/RootView.swift").contains("isPermanent"),
                      "RootView 必须区分废纸篓路径与永久路径")
    }
}
