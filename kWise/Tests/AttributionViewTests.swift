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

    func testEvidenceTextContainsArguments() {
        let text = AttributionCopy.evidenceText(
            Evidence(kind: .ruleCitation, textKey: "attr.ev.ruleCitation",
                     arguments: ["wechat.files"]))
        XCTAssertTrue(text.contains("wechat.files"), "证据文本必须带上参数（可引用）")
    }
}

@MainActor
final class AnatomyViewModelTests: XCTestCase {
    /// 与 T2 的 StubProvider 同模式 —— `SemanticAttributionProviding` 是协议，
    /// 闭包不能直接当参数传，用小 struct 包装。
    private struct StubSemanticProvider: SemanticAttributionProviding {
        let handler: @Sendable (String) -> AttributionCause?
        func probableCause(for path: String) -> AttributionCause? { handler(path) }
    }

    private func makeVM(rules: [AttributionRule],
                        usedBytes: Int64? = 10_000,
                        semanticProvider: SemanticAttributionProviding? = nil) -> AnatomyViewModel {
        let service = AttributionService(
            engine: AttributionRuleEngine(
                corpus: AttributionRuleCorpus(schemaVersion: 1, rules: rules),
                homeDirectory: "/Users/t"),
            volumeReader: nil,
            rootURL: URL(fileURLWithPath: "/Users/t"),
            volumeUsedBytesProvider: { usedBytes },
            semanticProvider: semanticProvider)
        return AnatomyViewModel(service: service)
    }

    private func category(paths: [(String, Int64)]) -> [ScanCategory] {
        let results = paths.map {
            ScanResult(url: URL(fileURLWithPath: $0.0), path: $0.0, title: "x",
                       fileSize: $0.1, cleanType: .cache)
        }
        let action = ScanAction(actionID: "a", actionType: .cache, title: "a", results: results)
        return [ScanCategory(categoryID: "c", title: "c",
                             subItems: [ScanSubCategory(subCategoryID: "s", title: "s",
                                                        actions: [action])])]
    }

    func testGroupedByCauseSortedByBytes() async {
        let vm = makeVM(rules: [
            AttributionRule(id: "xcode.derived-data",
                            match: AttributionRuleMatch(pathGlob: "~/Library/Developer/Xcode/**"),
                            owner: .app(bundleID: "com.apple.dt.Xcode", appName: "Xcode"),
                            cause: .developerCache, reclaim: .recycles(expectedDays: 30),
                            notesKey: "attr.notes.xcode.derived-data"),
            AttributionRule(id: "caches.app-generic",
                            match: AttributionRuleMatch(pathGlob: "~/Library/Caches/**"),
                            owner: .bundleDir, cause: .cache,
                            reclaim: .recycles(expectedDays: 3),
                            notesKey: "attr.notes.caches.app-generic"),
        ])
        vm.rebindCategories { self.category(paths: [
            ("/Users/t/Library/Developer/Xcode/DerivedData/a", 700),
            ("/Users/t/Library/Caches/b", 200),
            ("/Users/t/Library/Caches/c", 100),
        ]) }
        await vm.refresh()

        let sections = vm.groupedSections
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections.first?.id, .developerCache, "总字节降序：700 > 300")
        XCTAssertEqual(sections.first?.totalBytes, 700)
        XCTAssertEqual(sections.last?.totalBytes, 300)
        XCTAssertEqual(sections.last?.items.map(\.bytes), [200, 100], "组内字节降序")
    }

    func testProbableSeparatedFromRefused() async {
        let vm = makeVM(rules: [], usedBytes: nil, semanticProvider: StubSemanticProvider {
            $0.contains("chat") ? .chatFiles : nil
        })
        vm.rebindCategories { self.category(paths: [
            ("/Users/t/chat-store/blob", 900_000_000),
            ("/Users/t/unknown-thing", 900_000_000),
        ]) }
        await vm.refresh()
        XCTAssertEqual(vm.probableItems.count, 1)
        XCTAssertEqual(vm.probableItems.first?.cause, .chatFiles)
        XCTAssertEqual(vm.refusedItems.count, 1)
    }

    func testRefreshConsumesProviderOnceAndReportsUsedBytes() async {
        var calls = 0
        let vm = makeVM(rules: [
            AttributionRule(id: "caches.app-generic",
                            match: AttributionRuleMatch(pathGlob: "~/Library/Caches/**"),
                            owner: .bundleDir, cause: .cache,
                            reclaim: .recycles(expectedDays: 3),
                            notesKey: "attr.notes.caches.app-generic"),
        ])
        vm.rebindCategories {
            calls += 1
            return self.category(paths: [("/Users/t/Library/Caches/big", 900)])
        }
        await vm.refresh()
        XCTAssertEqual(calls, 1, "refresh 恰好消费一次 provider")
        XCTAssertEqual(vm.usedBytes, 10_000)
        XCTAssertEqual(vm.report?.blackBox.status, .reconciled)
        XCTAssertEqual(vm.probableItems.count, 0)
        XCTAssertEqual(vm.refusedItems.count, 0)
    }
}
