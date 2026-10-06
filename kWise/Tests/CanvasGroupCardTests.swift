// kWise/Tests/CanvasGroupCardTests.swift
//
// P2 T3 — 画布组卡组件的逻辑映射（纯函数部分，不渲染快照）：
// - 动词映射：GroupAction → 按钮文案 key（.rehearse→就地清理 /
//   .guidance→正确解法 / .migrate→迁出引导 / .none→无按钮）
// - 五色徽章 → 色 / SF Symbol 映射（spec §8 五色语义系统）
// - 展示层截断：组卡只渲染 prefix(displayEntryLimit)，「还有 N 项」行
import XCTest
import SwiftUI
import AppKit
import DesignSystem
@testable import kWise

@MainActor
final class CanvasGroupCardTests: XCTestCase {

    // MARK: - 动词映射

    /// 动词映射钉住 key（而非具体语言字符串）—— 文案改动不破坏映射契约，
    /// 三语完整性由 LocalizationCompletenessTests 兜底。
    func testActionVerbMapping() {
        XCTAssertEqual(CanvasGroupCardCopy.actionTitle(for: .rehearse),
                       String(localized: String.LocalizationValue("canvas.action.rehearse")),
                       ".rehearse → 就地清理")
        XCTAssertEqual(CanvasGroupCardCopy.actionTitle(for: .guidance(text: "tmutil")),
                       String(localized: String.LocalizationValue("canvas.action.guidance")),
                       ".guidance → 正确解法")
        XCTAssertEqual(CanvasGroupCardCopy.actionTitle(for: .migrate),
                       String(localized: String.LocalizationValue("canvas.action.migrate")),
                       ".migrate → 迁出引导")
        XCTAssertNil(CanvasGroupCardCopy.actionTitle(for: .none),
                     ".none → 无按钮")
    }

    // MARK: - 五色徽章

    func testBadgeColorAndSymbolMapping() {
        XCTAssertEqual(CanvasGroupCardCopy.color(for: .recyclable), Color.success,
                       "绿 ✓ 可回收")
        XCTAssertEqual(CanvasGroupCardCopy.color(for: .migrate), Color.brandSecondary,
                       "蓝 迁出引导")
        XCTAssertEqual(CanvasGroupCardCopy.color(for: .attention), Color.warning,
                       "橙 ⚠ 注意")
        XCTAssertEqual(CanvasGroupCardCopy.color(for: .dataNotJunk), Color.danger,
                       "红 数据·不属垃圾")
        // 灰 不动·不敢判 —— kWise 本地 token `textSecondary`（#999999）。
        // app target 内同名 token 以本模块扩展优先，测试里直接比 RGB 字面量
        // （`import DesignSystem` 后 `Color.textSecondary` 二义）。
        XCTAssertEqual(CanvasGroupCardCopy.color(for: .leaveAlone),
                       Color(red: 0.600, green: 0.600, blue: 0.600),
                       "灰 不动·不敢判")

        XCTAssertFalse(CanvasGroupCardCopy.symbol(for: .recyclable).isEmpty)
        XCTAssertFalse(CanvasGroupCardCopy.symbol(for: .migrate).isEmpty)
        XCTAssertFalse(CanvasGroupCardCopy.symbol(for: .attention).isEmpty)
        XCTAssertFalse(CanvasGroupCardCopy.symbol(for: .dataNotJunk).isEmpty)
        XCTAssertFalse(CanvasGroupCardCopy.symbol(for: .leaveAlone).isEmpty)
        // SF Symbol 必须是已注册符号名——用 NSImage 校验存在性。
        for badge in [BadgeKind.recyclable, .migrate, .attention, .dataNotJunk, .leaveAlone] {
            XCTAssertNotNil(NSImage(systemSymbolName: CanvasGroupCardCopy.symbol(for: badge),
                                    accessibilityDescription: nil),
                            "\(badge) 的 symbol 必须是有效 SF Symbol")
        }
    }

    func testBadgeLabelMapping() {
        XCTAssertEqual(CanvasGroupCardCopy.badgeTitle(for: .recyclable),
                       String(localized: String.LocalizationValue("canvas.badge.recyclable")))
        XCTAssertEqual(CanvasGroupCardCopy.badgeTitle(for: .migrate),
                       String(localized: String.LocalizationValue("canvas.badge.migrate")))
        XCTAssertEqual(CanvasGroupCardCopy.badgeTitle(for: .attention),
                       String(localized: String.LocalizationValue("canvas.badge.attention")))
        XCTAssertEqual(CanvasGroupCardCopy.badgeTitle(for: .dataNotJunk),
                       String(localized: String.LocalizationValue("canvas.badge.dataNotJunk")))
        XCTAssertEqual(CanvasGroupCardCopy.badgeTitle(for: .leaveAlone),
                       String(localized: String.LocalizationValue("canvas.badge.leaveAlone")))
    }

    // MARK: - 展示层截断（T2 fix r1 契约：数据层全量，渲染层 prefix）

    func testDisplayEntriesTruncateAtRenderLayer() {
        let entries = (0..<30).map { i in
            CanvasEntry(title: "f\(i)", bytes: Int64(i), badge: .recyclable,
                        detail: "/tmp/f\(i)", target: nil)
        }
        let group = CanvasGroup(id: .duplicates, icon: "doc.on.doc", title: "重复文件",
                                subtitle: "", totalBytes: 435, entries: entries,
                                action: .rehearse)
        // 数据层保持全量（T6 下钻契约）。
        XCTAssertEqual(group.entries.count, 30)
        // 渲染层只取前 20 条 + truncatedCount 驱动「还有 N 项」行。
        XCTAssertEqual(CanvasGroupCard.displayEntries(in: group).count,
                       CanvasGroup.displayEntryLimit)
        XCTAssertEqual(group.truncatedCount, 10)
    }

    func testDisplayEntriesAtOrBelowLimitShowAll() {
        let entries = (0..<20).map { i in
            CanvasEntry(title: "f\(i)", bytes: Int64(i), badge: .recyclable)
        }
        let group = CanvasGroup(id: .largeFiles, icon: "externaldrive", title: "大文件",
                                subtitle: "", totalBytes: 190, entries: entries,
                                action: .migrate)
        XCTAssertEqual(CanvasGroupCard.displayEntries(in: group).count, 20)
        XCTAssertEqual(group.truncatedCount, 0, "恰在上限时不显示「还有 N 项」")
    }
}
