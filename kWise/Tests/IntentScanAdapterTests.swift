import XCTest
@testable import kWise

final class IntentScanAdapterTests: XCTestCase {
    /// adapter 的核心职责是把新扫描树的叶子收敛成 CleanupTarget——
    /// 用注入的合成树直接测推荐挑选收敛（不 spawn 真扫描）。
    func testRecommendedPicksCollectOnlyDefaultCheckedLeaves() {
        let category = ScanCategory(categoryID: "c", title: "c", subItems: [
            ScanSubCategory(subCategoryID: "s", title: "s", actions: [ScanAction(
                actionID: "a", actionType: .cache, title: "a", results: [
                    ScanResult(url: URL(fileURLWithPath: "/tmp/safe"), path: "/tmp/safe",
                               title: "safe", fileSize: 10, cleanType: .cache,
                               riskLevel: .recommended),
                    ScanResult(url: URL(fileURLWithPath: "/tmp/risky"), path: "/tmp/risky",
                               title: "risky", fileSize: 20, cleanType: .preference,
                               riskLevel: .dangerous),
                ])])])
        let targets = IntentScanAdapter.targetsFromRecommendedPicks(in: [category])
        XCTAssertEqual(targets.map(\.url.path), ["/tmp/safe"],
                       "危险项绝不进 Intents 的自动清理集（R4/C4 红线）")
    }

    /// 收敛出的 CleanupTarget 必须携带扫描时的 size 与 `.recommended` risk
    /// ——history 行与 freedBytes 都依赖这两个字段（C4：Intents 链路上的
    /// risk 恒为推荐级，绝不静默提升/降级）。
    func testRecommendedTargetsCarryScannedSizeAndRecommendedRisk() {
        let category = ScanCategory(categoryID: "c", title: "c", subItems: [
            ScanSubCategory(subCategoryID: "s", title: "s", actions: [ScanAction(
                actionID: "a", actionType: .cache, title: "a", results: [
                    ScanResult(url: URL(fileURLWithPath: "/tmp/safe"), path: "/tmp/safe",
                               title: "safe", fileSize: 1234, cleanType: .cache,
                               riskLevel: .recommended),
                ])])])
        let targets = IntentScanAdapter.targetsFromRecommendedPicks(in: [category])
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets.first?.size, 1234)
        XCTAssertEqual(targets.first?.risk, .recommended)
    }

    /// 判定基准是 `riskLevel.defaultChecked` 而非 `isRecommended` 标志：
    /// 旧规则集时代的 flag 可能与 risk 等级不一致（危险文件挂着推荐
    /// flag）。即使 flag 为 true，`.dangerous` 叶子也必须被排除。
    func testDangerousLeafIsExcludedEvenWhenRecommendedFlagIsSet() {
        let category = ScanCategory(categoryID: "c", title: "c", subItems: [
            ScanSubCategory(subCategoryID: "s", title: "s", actions: [ScanAction(
                actionID: "a", actionType: .cache, title: "a", results: [
                    // isRecommended 缺省即为 true —— 与 riskLevel 不一致。
                    ScanResult(url: URL(fileURLWithPath: "/tmp/risky"), path: "/tmp/risky",
                               title: "risky", fileSize: 20, cleanType: .preference,
                               riskLevel: .dangerous),
                ])])])
        XCTAssertTrue(IntentScanAdapter.recommendedEntries(in: [category]).isEmpty)
    }

    /// 空树收敛为空集（扫描零结果时 Intents 必须返回 0 项，而不是崩溃）。
    func testEmptyTreeYieldsNoTargets() {
        XCTAssertTrue(IntentScanAdapter.targetsFromRecommendedPicks(in: []).isEmpty)
    }
}
