// kWise/Tests/LocalizationCompletenessTests.swift
//
// 守卫 Localizable.xcstrings 不再出现空译文条目。v2.x 期间 224 个 key 里有
// 162 个只有 key 没有译文（三语全空），en/zh-Hans/ja 任一缺失在目标语言下就会
// 直接露出中文 key 或空白 UI。本测试在 CI 里拦住这种情况。
import XCTest
import Foundation

final class LocalizationCompletenessTests: XCTestCase {

    private struct XCStrings: Decodable {
        let sourceLanguage: String
        let strings: [String: Entry]
    }

    private struct Entry: Decodable {
        let localizations: [String: Localization]?
    }

    private struct Localization: Decodable {
        struct StringUnit: Decodable {
            let value: String?
        }
        let stringUnit: StringUnit?
    }

    private static let requiredLanguages = ["en", "zh-Hans", "ja"]

    private func catalogURL() throws -> URL {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // kWise/
            .appendingPathComponent("Resources/Localizable.xcstrings")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "LocalizationCompletenessTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "missing \(url.path)"])
        }
        return url
    }

    func testEveryKeyHasAllThreeLanguages() throws {
        let data = try Data(contentsOf: try catalogURL())
        let catalog = try JSONDecoder().decode(XCStrings.self, from: data)
        XCTAssertGreaterThan(catalog.strings.count, 0, "Catalog must not be empty")

        var incomplete: [String] = []
        for (key, entry) in catalog.strings {
            for language in Self.requiredLanguages {
                let value = entry.localizations?[language]?.stringUnit?.value?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if value?.isEmpty != false {
                    incomplete.append("\(key) [\(language)]")
                }
            }
        }

        XCTAssertTrue(incomplete.isEmpty,
                      "Missing translations (key [language]):\n"
                        + incomplete.sorted().joined(separator: "\n"))
    }

    /// The catalog's source language must be `en` so untranslated keys fall
    /// back to English rather than to the Chinese key text.
    func testSourceLanguageIsEnglish() throws {
        let data = try Data(contentsOf: try catalogURL())
        let catalog = try JSONDecoder().decode(XCStrings.self, from: data)
        XCTAssertEqual(catalog.sourceLanguage, "en")
    }
}
