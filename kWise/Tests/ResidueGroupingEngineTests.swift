// kWise/Tests/ResidueGroupingEngineTests.swift
import XCTest
import NaturalLanguage
import AppCatalogCore
@testable import kWise

final class ResidueGroupingEngineTests: XCTestCase {

    private func residue(_ type: ResidueType, _ path: String) -> ResidueFile {
        ResidueFile(url: URL(fileURLWithPath: path), type: type, sizeBytes: 100,
                    confidence: 0.9, description: "")
    }

    func testRulePassMapsKnownTypes() {
        let groups = ResidueGroupingEngine.group([
            residue(.preferences, "/Users/x/Library/Preferences/com.a.plist"),
            residue(.caches, "/Users/x/Library/Caches/com.a"),
            residue(.launchAgent, "/Users/x/Library/LaunchAgents/com.a.plist"),
            residue(.appSupport, "/Users/x/Library/Application Support/com.a"),
            residue(.webKit, "/Users/x/Library/WebKit/com.a"),
            residue(.savedState, "/Users/x/Library/Saved Application State/com.a.savedState"),
        ], embedding: nil)

        let dict = Dictionary(uniqueKeysWithValues: groups.map { ($0.kind, $0.residues.count) })
        XCTAssertEqual(dict[.preferences], 1)
        XCTAssertEqual(dict[.caches], 1)
        XCTAssertEqual(dict[.launchAgents], 1)
        XCTAssertEqual(dict[.appData], 1)
        XCTAssertEqual(dict[.webData], 1)
        XCTAssertEqual(dict[.savedState], 1)
    }

    /// `.appleScript` 在规则遍中无映射（ruleKind 返回 nil），是验证
    /// "embedding 不可用 → 全落 other" 诚实降级的合法输入。
    /// （brief 原稿用 `.plugin`，但规则遍会把 plugin 归入 plugins，二者矛盾。）
    func testUnknownPathFallsToOtherWhenEmbeddingUnavailable() {
        let groups = ResidueGroupingEngine.group([
            residue(.appleScript, "/nonstandard/odd/path.bin"),
        ], embedding: nil)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.kind, .other)
    }

    func testFixedCategoryOrder() {
        let groups = ResidueGroupingEngine.group([
            residue(.savedState, "/a"),
            residue(.preferences, "/b"),
            residue(.caches, "/c"),
        ], embedding: nil)
        let order = groups.map(\.kind)
        XCTAssertEqual(order, ResidueGroupKind.allCases.filter { order.contains($0) },
                       "分组输出必须按 ResidueGroupKind.allCases 固定排序")
    }

    func testEmptyInputYieldsEmptyOutput() {
        XCTAssertTrue(ResidueGroupingEngine.group([], embedding: nil).isEmpty)
    }
}
