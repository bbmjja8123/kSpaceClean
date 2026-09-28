import XCTest
@testable import kWise

@MainActor
final class AttributionViewTests: XCTestCase {
    func testRulesViewModelFormatsRows() {
        let corpus = AttributionRuleCorpus(schemaVersion: 1, rules: [
            AttributionRule(id: "wechat.files",
                            match: AttributionRuleMatch(
                                pathGlob: "~/Library/Containers/com.tencent.xinWeChat/**"),
                            owner: .app(bundleID: "com.tencent.xinWeChat", appName: "微信"),
                            cause: .chatFiles, reclaim: .uncertain,
                            notesKey: "attr.notes.wechat.files"),
        ])
        let viewModel = AttributionRulesViewModel()
        viewModel.load(corpus: corpus)
        XCTAssertEqual(viewModel.rows.count, 1)
        let row = viewModel.rows[0]
        XCTAssertEqual(row.id, "wechat.files")
        XCTAssertEqual(row.ownerText, "微信")
        XCTAssertFalse(row.causeText.isEmpty)
        XCTAssertFalse(row.reclaimText.isEmpty)
        XCTAssertFalse(row.notesText.isEmpty, "notes 必须走 xcstrings 装配，不许空串")
    }

    func testPreviewVMSortsTopItemsByBytes() async {
        var calls = 0
        let engine = AttributionRuleEngine(corpus: AttributionRuleCorpus(schemaVersion: 1, rules: [
            AttributionRule(id: "caches.app-generic",
                            match: AttributionRuleMatch(pathGlob: "~/Library/Caches/**"),
                            owner: .bundleDir, cause: .cache,
                            reclaim: .recycles(expectedDays: 3), notesKey: "attr.notes.caches.app-generic"),
        ]), homeDirectory: "/Users/tester")
        let service = AttributionService(engine: engine, volumeReader: nil,
                                         rootURL: URL(fileURLWithPath: "/Users/tester"),
                                         volumeUsedBytesProvider: { 9_999 })
        let viewModel = AttributionPreviewViewModel(service: service)
        viewModel.rebindCategories {
            calls += 1
            let action = ScanAction(actionID: "a", actionType: .cache, title: "a", results: [
                ScanResult(url: URL(fileURLWithPath: "/Users/tester/Library/Caches/big"),
                           path: "/Users/tester/Library/Caches/big", title: "big",
                           fileSize: 900, cleanType: .cache),
                ScanResult(url: URL(fileURLWithPath: "/Users/tester/Library/Caches/small"),
                           path: "/Users/tester/Library/Caches/small", title: "small",
                           fileSize: 100, cleanType: .cache),
            ])
            let sub = ScanSubCategory(subCategoryID: "s", title: "s", actions: [action])
            return [ScanCategory(categoryID: "c", title: "c", subItems: [sub])]
        }
        await viewModel.refresh()
        XCTAssertEqual(calls, 1, "refresh 恰好消费一次 provider")
        XCTAssertEqual(viewModel.topItems.count, 2)
        XCTAssertEqual(viewModel.topItems.first?.bytes, 900, "按字节降序")
        XCTAssertEqual(viewModel.report?.blackBox.status, .reconciled)
    }

    func testEvidenceTextContainsArguments() {
        let text = AttributionCopy.evidenceText(
            Evidence(kind: .ruleCitation, textKey: "attr.ev.ruleCitation",
                     arguments: ["wechat.files"]))
        XCTAssertTrue(text.contains("wechat.files"), "证据文本必须带上参数（可引用）")
    }
}
