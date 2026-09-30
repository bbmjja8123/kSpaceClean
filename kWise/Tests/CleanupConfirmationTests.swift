import XCTest
@testable import kWise

final class CleanupConfirmationTests: XCTestCase {
    func test_cleanupRiskLevel_lowRisk() {
        let items: [RiskLevel] = [.recommended, .optional, .recommended]
        XCTAssertEqual(CleanupConfirmationLevel.from(riskLevels: items, hasWarnItems: false), .low)
    }
    func test_cleanupRiskLevel_hasCaution() {
        let items: [RiskLevel] = [.recommended, .caution, .optional]
        XCTAssertEqual(CleanupConfirmationLevel.from(riskLevels: items, hasWarnItems: false), .medium)
    }

    func test_cleanupRiskLevel_hasDangerous() {
        let items: [RiskLevel] = [.recommended, .dangerous]
        XCTAssertEqual(CleanupConfirmationLevel.from(riskLevels: items, hasWarnItems: false), .high)
    }

    func test_cleanupRiskLevel_hasWarnItems() {
        let items: [RiskLevel] = [.recommended]
        XCTAssertEqual(CleanupConfirmationLevel.from(riskLevels: items, hasWarnItems: true), .high)
    }

    /// P1 final (F2) — 确认弹窗文案必须如实：引擎动作是移入废纸篓（30 天
    /// 内可在历史中还原），「永久删除 / 不可恢复」是谎言，且与预演 sheet 的
    /// 「移入废纸篓…可还原」横幅自相矛盾。粉碎器不走此弹窗（ShredderView
    /// 有自己的 DELETE 确认流程），这里没有任何真正不可逆的动作可描述。
    func testConfirmationCopyNeverClaimsPermanentDelete() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // kWise/
            .appendingPathComponent("Features/Cleanup/CleanupContentView.swift"),
            encoding: .utf8)
        for lie in ["永久删除", "不可恢复", "不可通过废纸篓恢复"] {
            XCTAssertFalse(source.contains(lie),
                           "清理确认文案不得谎称永久删除：\(lie)")
        }
        XCTAssertTrue(source.contains("30 天内可在历史中还原"),
                      "必须如实告知：移入废纸篓且 30 天内可还原")
    }
}
