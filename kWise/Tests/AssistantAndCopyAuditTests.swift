// kWise/Tests/AssistantAndCopyAuditTests.swift
//
// v2.0 Phase 8 — assistant intent matching (zh-Hans/en) + copy/network
// audits for the v2.0 surfaces. The localization of the remaining v2.0
// literals is tracked as debt in CLAUDE.md §7; this audit pins the
// C-5/C-6 invariants (no scareware, no network in the assistant).
import XCTest
@testable import kWise

final class AssistantIntentMatcherTests: XCTestCase {

    private let matcher = AssistantIntentMatcher()

    func testVideoQuestionMapsToLargestFiles() {
        XCTAssertEqual(matcher.match("哪些视频最占空间？"), .largestFiles(kind: .video))
        XCTAssertEqual(matcher.match("哪个电影最大"), .largestFiles(kind: .video))
    }

    func testKindSpecificQuestions() {
        XCTAssertEqual(matcher.match("哪些照片占空间"), .largestFiles(kind: .image))
        XCTAssertEqual(matcher.match("biggest music files"), .largestFiles(kind: .audio))
        XCTAssertEqual(matcher.match("找出大文件"), .largestFiles(kind: nil))
    }

    func testOtherIntents() {
        XCTAssertEqual(matcher.match("磁盘什么时候会满？"), .diskForecast)
        XCTAssertEqual(matcher.match("清理重复文件"), .duplicates)
        XCTAssertEqual(matcher.match("应用残留有哪些？"), .appLeftovers)
        XCTAssertEqual(matcher.match("startup items list"), .startupItems)
        XCTAssertEqual(matcher.match("彻底删除文件"), .shredHelp)
    }

    func testUnrelatedChatterReturnsNil() {
        XCTAssertNil(matcher.match("今天天气怎么样"))
        XCTAssertNil(matcher.match("hello world what is love"))
    }

    /// P1 T8 — 聊天框退役，问答内嵌到 DetailPanel（AssistantNodePanelModel）。
    /// 没有自由输入 → 建议问题集就是全部入口：每条必须命中 matcher 模板表
    /// （建议集与模板表脱节 = UI 给出永远答不了的问题）；无关输入必须诚实拒答。
    @MainActor
    func testNodePanelAnswersFromMatcherWithoutChatInput() {
        // 节点问答不走自由输入——建议问题集必须命中 matcher 表。
        let panel = AssistantNodePanelModel(scanResultsProvider: { nil })
        for question in AssistantNodePanelModel.suggestedQuestions {
            if let intent = AssistantIntentMatcher().match(question) {
                // builder 在 scanVM 为 nil 时的诚实行为：要么 nil 要么无数据答案卡。
                _ = panel.answer(question: question)
                _ = intent
            } else {
                XCTFail("建议问题 \(question) 必须能被 matcher 命中——建议集与模板表脱节")
            }
        }
        XCTAssertNil(panel.answer(question: "今天天气怎么样"),
                     "无关输入必须诚实拒答")
    }

    /// The assistant is a zero-network surface — a URLSession reference in
    /// its source is a compliance bug.
    func testAssistantModuleHasNoNetworking() throws {
        let dir = URL(fileURLWithPath: "/Users/torsys/Documents/aicoding/kWise/kWise/Features/Assistant")
        // Worktree-relative fallback for CI runners.
        let base = FileManager.default.fileExists(atPath: dir.path)
            ? dir
            : URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Tests/
                .deletingLastPathComponent() // kWise/
                .appendingPathComponent("Features/Assistant")
        let files = try FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(source.contains("URLSession"), "\(file.lastPathComponent) must not network")
            XCTAssertFalse(source.contains("dataTask"), "\(file.lastPathComponent) must not network")
        }
    }
}

/// v2.0 surfaces must respect C-5/C-6: no countdown pressure, no fabricated
/// danger counts, no "立即…否则…" phrasing.
final class NewCopyAuditTests: XCTestCase {

    private static let v2FeatureFiles = [
        "Features/Shredder/ShredderView.swift",
        "Features/Shredder/FileShredder.swift",
        "Features/History/TimelineView.swift",
        "Features/Report/MonthlyReport.swift",
        // P1 T8: AssistantView.swift 退役；问答内嵌面板继承审计位。
        "Features/Assistant/AssistantNodePanel.swift",
        "Features/PhotoClean/PhotoSimilarityScanner.swift",
        "Features/AppUninstall/UninstallBackupStore.swift",
        "Features/AppUninstall/ResidueGroupingEngine.swift",
        "Features/AppUninstall/ResidueExplainer.swift",
        // P1 final (F1)：onboarding 是「信任契约」的第一块面板——虚假的
        // CoreML 承诺绝不允许在这里复活。
        "Features/Onboarding/OnboardingPages.swift",
        // P2 T9：工具/地图/快捷回收表面随单一主画布退役（spec §2/§9）——
        // ToolboxView / StartupItemsView / SpaceMapView / SmartCareHeroView /
        // PhotoCleanView / AppUninstallDetailPanel 不再出现在审计清单，
        // 退役本身由 SurfaceRetirementAuditTests 钉住。
    ]

    private static let bannedPhrases = [
        "立即清理，否则",
        "您的电脑已感染",
        "系统严重受损",
        "垃圾文件正在危害",
    ]

    func testNoScarewareCopyInV2Surfaces() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // kWise/

        for relative in Self.v2FeatureFiles {
            let file = root.appendingPathComponent(relative)
            guard FileManager.default.fileExists(atPath: file.path) else {
                XCTFail("v2 feature file missing: \(relative)")
                continue
            }
            let source = try String(contentsOf: file, encoding: .utf8)
            for phrase in Self.bannedPhrases {
                XCTAssertFalse(source.contains(phrase),
                               "\(relative) must not contain scareware copy: \(phrase)")
            }
        }
    }

    /// The shredder's honest-SSD copy must ship (C-5): no fake "military
    /// grade multi-pass" claims, and the standard note explains 1 pass.
    func testShredderCopyIsHonestAboutSSD() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Features/Shredder/ShredderView.swift"),
                                encoding: .utf8)
        XCTAssertTrue(source.contains("对 SSD 已足够"),
                      "The 1-pass-is-enough-on-SSD note is mandatory copy")
    }

    /// P1 final (F1) — onboarding 不得虚构 CoreML 分类能力：实际实现是
    /// 本机规则归因 + 端上语义推测（零网络）。措辞升级时禁止把「AI 智能分类 /
    /// CoreML」类夸大叙事带回来。
    ///
    /// P2 T8 — 5→3 页收敛追加：授权能力与诚实承诺必须在合并页存活，旧
    /// 独立页类型（Page4 授权页 / Page5 就绪页）零残留。
    func testOnboardingCopyIsHonestAboutAttribution() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(contentsOf:
            root.appendingPathComponent("Features/Onboarding/OnboardingPages.swift"),
            encoding: .utf8)
        for overclaim in ["AI 智能分类", "CoreML", "精准分类"] {
            XCTAssertFalse(source.contains(overclaim),
                           "onboarding 不得虚构能力：\(overclaim)")
        }
        XCTAssertTrue(source.contains("本机规则归因"),
                      "归因能力必须按真实实现描述（本机规则归因）")
        XCTAssertTrue(source.contains("零数据上报"), "隐私承诺必须保留")
        XCTAssertTrue(source.contains("智能扫描"), "三类承诺之一：智能扫描")
        XCTAssertTrue(source.contains("一键清理"), "三类承诺之一：一键清理")
        // 授权路径在合并页存活（P0 验收手册的三屏路径）。
        XCTAssertTrue(source.contains("授权主目录"), "合并页必须保留授权入口")
        XCTAssertTrue(source.contains("已授权"), "授权成功反馈必须保留")
        XCTAssertTrue(source.contains("跳过此步骤"), "跳过授权的出口必须保留")
        XCTAssertTrue(source.contains("appScope.grant"),
                      "授权动作必须真实接线（PowerScope grant）")
        // 旧 5 页独立类型零残留。
        XCTAssertFalse(source.contains("OnboardingPage4"), "独立授权页类型应已合并删除")
        XCTAssertFalse(source.contains("OnboardingPage5"), "独立就绪页类型应已合并删除")
    }
}

/// P1 T6 — SmartCare 降级文案审计（spec §3.1）。次级页不得再宣称「一键焕新」
/// 级叙事（本地化值里也不得复活——文案实际所在处一并扫，口径同
/// AttributionCopyAuditTests）。
/// P2 T9：SmartCareHeroView 源文件随单一主画布退役 —— 源码级断言
/// （hero 源码扫描 / 授权卡）由 SurfaceRetirementAuditTests 的零残留审计
/// 取代；catalog 级断言（快捷回收诚实文案三语）原样保留。
final class SmartCareDemotionCopyAuditTests: XCTestCase {

    // 实测 catalog 每条 value 是 { extractionState?, comment?, localizations }，
    // 不能直接当 [String: Unit] 解——只取 localizations（同 AttributionCopyAuditTests）。
    private struct Catalog: Decodable { let strings: [String: Entry] }
    private struct Entry: Decodable { let localizations: [String: Unit]? }
    private struct Unit: Decodable { struct SU: Decodable { let value: String? }; let stringUnit: SU? }

    private func catalogLocalizations() throws -> [String: [String: Unit]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Localizable.xcstrings")
        let catalog = try JSONDecoder().decode(Catalog.self,
                                               from: Data(contentsOf: url))
        return catalog.strings.compactMapValues { $0.localizations }
    }

    /// 「焕然如新」也不得借本地化值复活（key 本身就是中文文案，一并扫）。
    func testNoRejuvenationPromiseInCatalogKeysOrValues() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Localizable.xcstrings")
        let catalog = try JSONDecoder().decode(Catalog.self,
                                               from: Data(contentsOf: url))
        for (key, entry) in catalog.strings {
            XCTAssertFalse(key.contains("焕然如新"),
                           "catalog key 含焕新级口号: \(key)")
            for (lang, unit) in entry.localizations ?? [:] {
                guard let value = unit.stringUnit?.value else { continue }
                XCTAssertFalse(value.contains("焕然如新"),
                               "\(key) [\(lang)] 含焕新级口号")
            }
        }
    }

    /// 降级后的诚实说明行（自动重建 + 30 天可还原）必须三语齐全。
    func testSafeQuickCleanSubtitleShipsInAllLanguages() throws {
        let unit = try XCTUnwrap(try catalogLocalizations()["attr.safeclean.subtitle"])
        XCTAssertTrue(try XCTUnwrap(unit["zh-Hans"]?.stringUnit?.value).contains("可自动重建"))
        XCTAssertTrue(try XCTUnwrap(unit["zh-Hans"]?.stringUnit?.value).contains("30 天"))
        XCTAssertTrue(try XCTUnwrap(unit["en"]?.stringUnit?.value).contains("auto-rebuildable"))
        XCTAssertTrue(try XCTUnwrap(unit["en"]?.stringUnit?.value).contains("30 days"))
        XCTAssertTrue(try XCTUnwrap(unit["ja"]?.stringUnit?.value).contains("自動再生成"))
        XCTAssertTrue(try XCTUnwrap(unit["ja"]?.stringUnit?.value).contains("30 日間"))
    }

    /// rail / tooltip 退役后，`nav.smartCare` 三语值仍由 catalog 固定 ——
    /// 防止旧降级名被改成焕新级口号后复活。
    func testNavSmartCareIsDemotedInAllLanguages() throws {
        let unit = try XCTUnwrap(try catalogLocalizations()["nav.smartCare"])
        XCTAssertEqual(unit["zh-Hans"]?.stringUnit?.value, "安全快捷回收")
        XCTAssertEqual(unit["en"]?.stringUnit?.value, "Safe Quick Clean")
        XCTAssertEqual(unit["ja"]?.stringUnit?.value, "安全なクイッククリーン")
    }
}
