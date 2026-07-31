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
}