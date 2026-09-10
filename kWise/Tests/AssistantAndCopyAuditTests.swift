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
        "Features/Toolbox/ToolboxView.swift",
        "Features/StartupItems/StartupItemsView.swift",
        "Features/Shredder/ShredderView.swift",
        "Features/Shredder/FileShredder.swift",
        "Features/History/TimelineView.swift",
        "Features/Report/MonthlyReport.swift",
        "Features/Assistant/AssistantView.swift",
        "Features/SpaceMap/SpaceMapView.swift",
        "Features/SmartCare/SmartCareHeroView.swift",
        "Features/PhotoClean/PhotoCleanView.swift",
        "Features/PhotoClean/PhotoSimilarityScanner.swift",
        "Features/AppUninstall/UninstallBackupStore.swift",
        "Features/AppUninstall/ResidueGroupingEngine.swift",
        "Features/AppUninstall/ResidueExplainer.swift",
        "Features/AppUninstall/AppUninstallDetailPanel.swift",
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
}

/// v2.6 卸载详情面板 copy 审计（Task 6 Step 3）。C-1：界面只显示
/// 友好路径，raw path 仅允许出现在 tooltip（`.help`）与勾选逻辑 key 中。
final class UninstallCopyAuditTests: XCTestCase {

    private var panelSource: String {
        get throws {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent() // Tests/
                .deletingLastPathComponent() // kWise/
            return try String(contentsOf:
                root.appendingPathComponent("Features/AppUninstall/AppUninstallDetailPanel.swift"),
                encoding: .utf8)
        }
    }

    func testDetailPanelShowsFriendlyPath() throws {
        XCTAssertTrue(try panelSource.contains("ScanTreeRow.friendlyPath(for:"),
                      "残留行展示必须走 ScanTreeRow.friendlyPath（C-1）")
    }

    /// raw path 不得直接进入任何 `Text(...)` 展示 —— 唯一合法出口是
    /// `.help(residue.url.path)` tooltip。`Text(ScanTreeRow.friendlyPath(
    /// for: ...))` 属于友好路径展示，不算 raw 泄漏。
    func testDetailPanelRawPathIsTooltipOnly() throws {
        let source = try panelSource
        XCTAssertTrue(source.contains(".help(residue.url.path)"),
                      "raw path 必须保留为 tooltip")

        let offending = source.components(separatedBy: .newlines).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("//") == false else { return false }
            return line.contains("Text(")
                && line.contains(".url.path")
                && !line.contains("friendlyPath")
        }
        XCTAssertTrue(offending.isEmpty,
                      "C-1: raw path 不得进入 Text 展示（仅 .help tooltip 允许）: \(offending)")
    }
}
