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
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Localizable.xcstrings")
        // 实测 catalog 每条 value 是 { extractionState?, comment?, localizations }，
        // 不能直接当 [String: Unit] 解（brief 原码在此红）——只取 localizations，
        // 忽略同级元数据键（对唯一披露的偏差）。
        struct Catalog: Decodable { let strings: [String: Entry] }
        struct Entry: Decodable { let localizations: [String: Unit]? }
        struct Unit: Decodable { struct SU: Decodable { let value: String? }; let stringUnit: SU? }
        let catalog = try JSONDecoder().decode(Catalog.self,
                                               from: Data(contentsOf: url))
        let unit = try XCTUnwrap(catalog.strings["attr.reclaim.uncertain"]?.localizations)
        XCTAssertTrue(try XCTUnwrap(unit["zh-Hans"]?.stringUnit?.value).contains("不敢判"))
        XCTAssertTrue(try XCTUnwrap(unit["en"]?.stringUnit?.value).contains("Can't judge"))
        XCTAssertTrue(try XCTUnwrap(unit["ja"]?.stringUnit?.value).contains("判定できない"))
    }
}
