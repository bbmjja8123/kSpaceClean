// kWise/Tests/DefaultSelectionTests.swift
//
// v2.3 — 扫描完成后默认选中：推荐项自动勾选，谨慎/危险项不勾选。
// 对标 CleanMyMac：扫描完成即给出可清理建议，选中量不可能为 0 KB。
import XCTest
@testable import kWise

@MainActor
final class DefaultSelectionTests: XCTestCase {

    private func makeCategory() -> ScanCategory {
        let recommended = ScanResult(
            url: URL(fileURLWithPath: "/tmp/cache/safe.cache"),
            path: "/tmp/cache/safe.cache", title: "safe",
            fileSize: 1_000, cleanType: .cache, riskLevel: .recommended
        )
        let caution = ScanResult(
            url: URL(fileURLWithPath: "/tmp/cache/user.data"),
            path: "/tmp/cache/user.data", title: "caution",
            fileSize: 2_000, cleanType: .preference, riskLevel: .caution
        )
        let dangerous = ScanResult(
            url: URL(fileURLWithPath: "/tmp/cache/system.file"),
            path: "/tmp/cache/system.file", title: "danger",
            fileSize: 4_000, cleanType: .preference, riskLevel: .dangerous
        )
        let action = ScanAction(
            actionID: "test.action", actionType: .cache, title: "action",
            results: [recommended, caution, dangerous]
        )
        let sub = ScanSubCategory(subCategoryID: "test.sub", title: "sub", actions: [action])
        return ScanCategory(categoryID: "test", title: "test", subItems: [sub])
    }

    /// 推荐项默认勾选（状态 .checked 且被计入 selectedSize）。
    func testRecommendedItemsPreChecked() {
        let category = makeCategory()
        ScanResultsViewModel.applyDefaultSelection(to: [category])

        let recommended = category.subItems[0].actions[0].results[0]
        XCTAssertEqual(recommended.state, .checked, "推荐项必须默认勾选")

        // 级联聚合：部分勾选 → 父级 .mixed
        XCTAssertEqual(category.state, .mixed)
    }

    /// 谨慎/危险项保持未勾选（用户显式选择才清理）。
    func testCautionAndDangerousNotPreChecked() {
        let category = makeCategory()
        ScanResultsViewModel.applyDefaultSelection(to: [category])

        let caution = category.subItems[0].actions[0].results[1]
        let dangerous = category.subItems[0].actions[0].results[2]
        XCTAssertEqual(caution.state, .unchecked, "谨慎项不得默认勾选")
        XCTAssertEqual(dangerous.state, .unchecked, "危险项不得默认勾选")
    }

    /// 选中量 > 0：扫描完成后汇总栏不可能显示 0 KB。
    func testSelectedSizeNonZeroAfterDefaultSelection() {
        let category = makeCategory()
        ScanResultsViewModel.applyDefaultSelection(to: [category])

        let selected = category.collectSelected()
        XCTAssertGreaterThan(selected.count, 0)
        XCTAssertGreaterThan(category.selectedSize, 0, "默认选中量必须大于 0 KB")
    }
}
