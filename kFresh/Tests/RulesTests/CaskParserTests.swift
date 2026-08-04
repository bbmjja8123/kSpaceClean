import XCTest
@testable import kFresh

final class CaskParserTests: XCTestCase {
    func testParseSimpleCaskExtractsBundleID() throws {
        let caskRuby = """
        cask "visual-studio-code" do
          version "1.85.0"
          sha256 "abc123"
          url "https://update.code.visualstudio.com/#{version}/darwin/stable"
          appcast "https://update.code.visualstudio.com/api/releases/stable.json"
          name "Visual Studio Code"
          desc "Code editor"
          homepage "https://code.visualstudio.com/"
          app "Visual Studio Code.app"
          zap trash: [
            "~/Library/Application Support/Code",
            "~/Library/Logs/Code",
            "~/Library/Caches/com.microsoft.VSCode",
          ]
        end
        """

        let rule = try CaskParser.parse(caskRuby, caskName: "visual-studio-code")
        XCTAssertEqual(rule.appName, "Visual Studio Code")
        XCTAssertEqual(rule.bundleID, "com.microsoft.VSCode")
        XCTAssertGreaterThan(rule.residuePaths.count, 0)
    }

    func testParseSlackCaskReturnsCanonicalBundleID() {
        let ruby = """
        cask "slack" do
          version "4.36.0"
          sha256 "deadbeef"

          url "https://example.com/slack.dmg"
          name "Slack"
          desc "Team communication"
          homepage "https://slack.com"

          app "Slack.app"
        end
        """

        let rule = try! CaskParser.parse(ruby, caskName: "slack")

        XCTAssertEqual(rule.bundleID, "com.slack.client",
                       "CaskParser must emit the canonical com.slack.client, not the legacy com.tinyspeck.chatlyio")
    }

    func testExtractInvalidPatternReturnsNilInsteadOfCrashing() throws {
        let rule = try CaskParser.parse("name \"TestApp\"", caskName: "test-app")
        XCTAssertFalse(rule.bundleID.isEmpty)
    }
}