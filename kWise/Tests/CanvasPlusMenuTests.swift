// kWise/Tests/CanvasPlusMenuTests.swift
//
// P2 T4 — 「+」菜单注册 + 整窗拖放粉碎状态机（逻辑层，不渲染快照）：
// - CanvasPlusMenuItem 两项注册（粉碎窗 / 归因规则；P2 T9 旧版空间地图项
//   随 SpaceMapView 退役）+
//   CanvasPlusMenuActions 按 item 分发到各自回调（标题钉 key，三语完整性由
//   LocalizationCompletenessTests 兜底）
// - DragToShredModel：非文件 URL / 目录 / 混合批次拒绝（全有或全无）、
//   全部为普通文件才转发粉碎窗（spy 记录）、投放落定后悬停态归零
// - ShredderViewModel.performDrop 公开入口：普通文件预填、目录拒绝
// 红线：本层只做「打开粉碎窗 + 预填」——粉碎的 DELETE 确认链在
// ShredderView(DangerousConfirmDialog) → shredStaged，此处不触碰。
import XCTest
import Foundation
@testable import kWise

@MainActor
final class CanvasPlusMenuTests: XCTestCase {

    private var tempDirectory: URL!
    private var regularFileURL: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("canvas-plus-menu-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory,
                                                withIntermediateDirectories: true)
        regularFileURL = tempDirectory.appendingPathComponent("sensitive.txt")
        try Data("shred me".utf8).write(to: regularFileURL)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - 「+」菜单注册

    /// 菜单四项、顺序稳定 —— P3：应用卸载（M5）与启动项（M2）重接入；
    /// P2 T9 旧版空间地图逃生口随 SpaceMapView 退役（画布即地图）。
    func testPlusMenuRegistersExactlyFourItemsInOrder() {
        XCTAssertEqual(CanvasPlusMenuItem.allCases,
                       [.uninstall, .startupItems, .shredder, .attributionRules],
                       "「+」菜单 = 卸载 · 启动项 · 粉碎窗 · 归因规则")
    }

    /// 标题钉 key（文案改动不破坏映射契约），且 key 能经本地化表取值。
    func testPlusMenuItemTitlesResolveLocalizedKeys() {
        XCTAssertEqual(CanvasPlusMenuItem.shredder.titleKey, "canvas.plusMenu.shredder")
        XCTAssertEqual(CanvasPlusMenuItem.attributionRules.titleKey, "canvas.plusMenu.attributionRules")
        XCTAssertEqual(CanvasPlusMenuItem.uninstall.titleKey, "canvas.plusMenu.uninstall")
        XCTAssertEqual(CanvasPlusMenuItem.startupItems.titleKey, "canvas.plusMenu.startupItems")
        for item in CanvasPlusMenuItem.allCases {
            XCTAssertEqual(item.title,
                           String(localized: String.LocalizationValue(item.titleKey)),
                           "\(item.rawValue) 标题必须走 xcstrings key")
        }
    }

    /// 动作分发：每个 case 各自路由到自己的回调（互不串线）。
    func testMenuActionDispatchRoutesEachItemToItsOwnHandler() {
        var calls: [CanvasPlusMenuItem] = []
        let actions = CanvasPlusMenuActions(
            onUninstall: { calls.append(.uninstall) },
            onStartupItems: { calls.append(.startupItems) },
            onShredder: { calls.append(.shredder) },
            onAttributionRules: { calls.append(.attributionRules) })

        // 故意以非枚举顺序触发 —— 断言看的是「每项命中自己的处理器」，
        // 而非调用顺序。
        let invocationOrder: [CanvasPlusMenuItem] = [.attributionRules, .shredder,
                                                     .startupItems, .uninstall]
        for item in invocationOrder { actions(item) }

        XCTAssertEqual(calls, invocationOrder, "菜单项逐一命中自己的处理器")
    }

    // MARK: - DragToShredModel（拖放覆盖层状态机）

    private func makeModel(recorder: @escaping ([URL]) -> Void) -> DragToShredModel {
        let model = DragToShredModel()
        model.onShredRequested = recorder
        return model
    }

    /// 非文件 URL（promise/网页等）拒绝 —— 返回 false、不转发粉碎窗。
    func testNonFileURLIsRejected() {
        var forwarded: [[URL]] = []
        let model = makeModel { forwarded.append($0) }

        XCTAssertFalse(model.urlsDropped([URL(string: "https://example.com/payload.bin")!]),
                       "非 file:// URL 必须被拒绝")
        XCTAssertTrue(forwarded.isEmpty, "拒绝的批次不得进入粉碎窗")
    }

    /// 目录不是普通文件 —— 拒绝（粉碎窗内的护栏仍是第二道防线）。
    func testDirectoryIsRejected() {
        var forwarded: [[URL]] = []
        let model = makeModel { forwarded.append($0) }

        XCTAssertFalse(model.urlsDropped([tempDirectory]))
        XCTAssertTrue(forwarded.isEmpty)
    }

    /// 全部为普通文件 → 返回 true，转发给粉碎窗（spy 记录 URL）。
    func testRegularFileForwardsToShredWindow() {
        var forwarded: [[URL]] = []
        let model = makeModel { forwarded.append($0) }

        XCTAssertTrue(model.urlsDropped([regularFileURL]))
        XCTAssertEqual(forwarded, [[regularFileURL]], "接受后原样转发给粉碎窗")
    }

    /// 混合批次全有或全无：只要有一个非普通文件，整批拒绝。
    func testMixedBatchIsRejectedAsAWhole() {
        var forwarded: [[URL]] = []
        let model = makeModel { forwarded.append($0) }

        XCTAssertFalse(model.urlsDropped([regularFileURL, tempDirectory]))
        XCTAssertTrue(forwarded.isEmpty, "不得部分转发（破坏性 UI 只接受完整合法批次）")
    }

    /// 空批次拒绝。
    func testEmptyDropIsRejected() {
        var forwarded: [[URL]] = []
        let model = makeModel { forwarded.append($0) }

        XCTAssertFalse(model.urlsDropped([]))
        XCTAssertTrue(forwarded.isEmpty)
    }

    /// 悬停态翻转：投放落定（无论接受或拒绝）后 isHovering 归零，
    /// 覆盖层随之淡出。
    func testHoveringClearsWhenDropResolves() {
        var forwarded: [[URL]] = []
        let model = makeModel { forwarded.append($0) }

        model.isHovering = true
        XCTAssertTrue(model.urlsDropped([regularFileURL]))
        XCTAssertFalse(model.isHovering, "接受的投放落定后悬停态归零")

        model.isHovering = true
        XCTAssertFalse(model.urlsDropped([tempDirectory]))
        XCTAssertFalse(model.isHovering, "拒绝的投放落定后同样归零")
    }

    // MARK: - ShredderViewModel.performDrop（公开外部入口）

    /// 公开入口：普通文件预填进暂存区（不触发任何清理动作）。
    func testShredderPublicDropEntryStagesRegularFiles() {
        let viewModel = ShredderViewModel(persistence: PersistenceController(inMemory: true))

        viewModel.performDrop(urls: [regularFileURL])

        XCTAssertEqual(viewModel.stagedURLs, [regularFileURL])
    }

    /// 公开入口：目录被护栏拒绝，暂存区保持为空。
    func testShredderPublicDropEntryRefusesDirectories() {
        let viewModel = ShredderViewModel(persistence: PersistenceController(inMemory: true))

        viewModel.performDrop(urls: [tempDirectory])

        XCTAssertTrue(viewModel.stagedURLs.isEmpty)
    }
}
