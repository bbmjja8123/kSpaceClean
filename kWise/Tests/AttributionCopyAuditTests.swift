import XCTest
@testable import kWise

/// 归因模块文案审计 —— 恐吓禁语 + 诚实措辞（spec §5 / §9，审核 2.3.1(a) 防线）。
final class AttributionCopyAuditTests: XCTestCase {

    private static let bannedPhrases = [
        // 品类通用禁语（与 NewCopyAuditTests 同源口径）
        "立即清理，否则", "您的电脑已感染", "系统严重受损", "垃圾文件正在危害",
        // 归因特有禁语：绝对化承诺 / 制造恐慌
        "彻底释放", "永不复返", "一键彻底", "你的磁盘正在被吞噬", "危在旦夕",
    ]

    private func attributionSourceFiles() throws -> [URL] {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // kWise/
            .appendingPathComponent("Features/Attribution")
        let files = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "Attribution 源码目录必须可读")
        return files
    }

    func testNoScarewareInAttributionModule() throws {
        for file in try attributionSourceFiles() {
            let source = try String(contentsOf: file, encoding: .utf8)
            for phrase in Self.bannedPhrases {
                XCTAssertFalse(source.contains(phrase),
                               "\(file.lastPathComponent) 含禁语「\(phrase)」")
            }
            // 零网络红线落在源码层（与 Assistant 模块同一守卫口径）。
            XCTAssertFalse(source.contains("URLSession"),
                           "\(file.lastPathComponent) must not network")
        }
    }

    /// 「不敢判」必须在三种语言里都是退让措辞 —— 这是拒答清单的诚信底线。
    func testUncertainCopyHedgesInAllLanguages() throws {
        let unit = try XCTUnwrap(try catalogLocalizations()["attr.reclaim.uncertain"])
        XCTAssertTrue(try XCTUnwrap(unit["zh-Hans"]?.stringUnit?.value).contains("不敢判"))
        XCTAssertTrue(try XCTUnwrap(unit["en"]?.stringUnit?.value).contains("Can't judge"))
        XCTAssertTrue(try XCTUnwrap(unit["ja"]?.stringUnit?.value).contains("判定できない"))
    }

    /// 本模块 55 个 `attr.*` 条目的文案不在源码字面里（AttributionCopy.swift 只解析 key），
    /// 而在 xcstrings 的 `localizations` 值里 —— 禁语扫描必须覆盖文案实际所在处，
    /// 否则恐吓短语以本地化值出现时将完全绕过源码扫描（review r1 修复的盲点）。
    func testNoScarewareInCatalogValues() throws {
        let localizations = try catalogLocalizations()
        XCTAssertGreaterThanOrEqual(
            localizations.filter { $0.key.hasPrefix("attr.") }.count, 55,
            "attr.* 条目数守卫：catalog 形状变化时不得静默漏扫")
        for (key, langs) in localizations {
            for (lang, unit) in langs {
                guard let value = unit.stringUnit?.value else { continue }
                for phrase in Self.bannedPhrases {
                    XCTAssertFalse(value.contains(phrase),
                                   "\(key) [\(lang)] 含禁语「\(phrase)」")
                }
            }
        }
    }

    // 实测 catalog 每条 value 是 { extractionState?, comment?, localizations }，
    // 不能直接当 [String: Unit] 解（brief 原码在此红）——只取 localizations，
    // 忽略同级元数据键（对 brief 逐字版的披露偏差）。
    private struct Catalog: Decodable { let strings: [String: Entry] }
    private struct Entry: Decodable { let localizations: [String: Unit]? }
    private struct Unit: Decodable { struct SU: Decodable { let value: String? }; let stringUnit: SU? }

    /// key → 语言 → stringUnit（解析一次，供 hedge 断言与全量禁语扫描共用）。
    private func catalogLocalizations() throws -> [String: [String: Unit]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Localizable.xcstrings")
        let catalog = try JSONDecoder().decode(Catalog.self,
                                               from: Data(contentsOf: url))
        return catalog.strings.compactMapValues { $0.localizations }
    }
}
