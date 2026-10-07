// kWise/Tests/SurfaceRetirementAuditTests.swift
//
// P2 T9 — 退役清扫审计（spec §2「~20 表面 → 6 表面」/ §9 退役清单的规格执法）：
// 1. 旧表面类型在 Features/ 源码中零残留 —— ToolboxView（杂物抽屉）、
//    SpaceMapView + SpaceMapViewModel + SegmentBuilder（画布即地图）、
//    CleanupContentView（并入预演流 + 历史）、SmartCareHeroView（快捷回收
//    并入画布 hero）、MonthlyReportView（T7 已并入历史叙事头）。
// 2. NavigationItem 收敛为 3 case（.anatomy / .history / .settings），
//    rail 常量与之完全一致 —— 深链 / Widget / 菜单栏全部落在这三个面上。
//
// 审计方式：直接读 Features/ 源文件做 grep 断言（与 AttributionCopyAuditTests
// 同源做法），任何把退役类型写回源码的改动都会在这里失败。
import XCTest
@testable import kWise

final class SurfaceRetirementAuditTests: XCTestCase {

    /// Features/ 目录（源码 grep 范围；Tests/ 不在内）。
    private var featuresDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // kWise/
            .appendingPathComponent("Features")
    }

    private func featureSources() throws -> [(path: String, source: String)] {
        let enumerator = FileManager.default.enumerator(
            at: featuresDirectory,
            includingPropertiesForKeys: nil)
        var results: [(String, String)] = []
        while let element = enumerator?.nextObject() as? URL {
            guard element.pathExtension == "swift" else { continue }
            let source = try String(contentsOf: element, encoding: .utf8)
            results.append((element.lastPathComponent, source))
        }
        return results
    }

    // MARK: - 退役表面零残留

    /// 每个退役表面的类型名（含注释里也不许复活 —— 名字出现即说明有人
    /// 在引用或缅怀它，一律拒绝）。
    private static let retiredSurfaceNames = [
        "ToolboxView",
        "ToolTabBar",
        "SpaceMapView",
        "SpaceMapViewModel",
        "SegmentBuilder",
        "CleanupContentView",
        "SmartCareHeroView",
        "MonthlyReportView",
        "ScanResultsView",
        "HistoryContentView",
        "DetailPanelView",
    ]

    func testRetiredSurfaceTypesHaveZeroResidueInFeatures() throws {
        var residue: [String] = []
        for (path, source) in try featureSources() {
            for name in Self.retiredSurfaceNames {
                // 词边界匹配 —— 存活类型（如 ScanResultsViewModel）不得因
                // 子串误伤，注释里的裸名同样算残留。
                guard source.range(of: "\\b" + name + "\\b",
                                   options: .regularExpression) != nil else { continue }
                residue.append("\(path): \(name)")
            }
        }
        XCTAssertTrue(residue.isEmpty,
                      "退役表面类型在 Features/ 残留（P2 spec §2/§9）:\n"
                        + residue.sorted().joined(separator: "\n"))
    }

    // MARK: - NavigationItem 收敛（spec §2：rail = [.anatomy, .history, .settings]）

    func testNavigationItemConvergesToThreeCases() {
        XCTAssertEqual(AppState.NavigationItem.allCases.count, 3,
                       "P2 T9：NavigationItem 必须收敛为 anatomy/history/settings 3 case")
        XCTAssertEqual(Set(AppState.NavigationItem.allCases),
                       [.anatomy, .history, .settings])
    }

    func testRailIsIntactAndMatchesAllCases() {
        let rail = AppState.NavigationItem.railItems
        XCTAssertEqual(rail, [.anatomy, .history, .settings],
                       "rail 3 项完好（P2 T1 收敛后不再变）")
        XCTAssertEqual(rail, AppState.NavigationItem.allCases,
                       "rail 与全部 case 一致 —— 不再存在 rail 之外的可导航面")
        XCTAssertEqual(rail.first, .anatomy, "解剖画布是 rail 头 / 首屏")
    }
}
