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

    /// P1 final (F2) — 确认弹窗文案必须如实：引擎动作是移入废纸篓（可在
    /// 历史中还原），「永久删除 / 不可恢复」是谎言，且与预演 sheet 的
    /// 「移入废纸篓…可逐项取消」横幅自相矛盾。粉碎器不走此弹窗（ShredderView
    /// 有自己的 DELETE 确认流程），这里没有任何真正不可逆的动作可描述。
    /// P2 T9：确认弹窗统一为预演 sheet（CleanupContentView 已退役）——
    /// 审计对象改为 CleanupRehearsalSheet 源码 + catalog 横幅三语。
    func testConfirmationCopyNeverClaimsPermanentDelete() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // kWise/
            .appendingPathComponent("Features/Cleanup/CleanupRehearsalSheet.swift"),
            encoding: .utf8)
        for lie in ["永久删除", "不可恢复", "不可通过废纸篓恢复"] {
            XCTAssertFalse(source.contains(lie),
                           "清理确认文案不得谎称永久删除：\(lie)")
        }

        // 「移入废纸篓」的如实告知必须三语齐全（统一预演 sheet 的横幅）。
        let catalog = try String(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Localizable.xcstrings"),
            encoding: .utf8)
        XCTAssertTrue(catalog.contains("attr.rehearsal.banner"),
                      "预演横幅 key 必须存在")
        XCTAssertTrue(catalog.contains("以下是将要移入废纸篓的全部内容"),
                      "横幅必须如实告知移入废纸篓")
    }
}
