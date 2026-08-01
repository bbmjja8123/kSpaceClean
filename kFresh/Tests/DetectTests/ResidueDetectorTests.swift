import XCTest
@testable import kFresh

final class ResidueDetectorTests: XCTestCase {
    private var tempRulesURL: URL!
    private var tempHomeURL: URL!

    override func setUp() async throws {
        tempRulesURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rules-\(UUID().uuidString).json")
        tempHomeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempHomeURL, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempRulesURL)
        try? FileManager.default.removeItem(at: tempHomeURL)
    }

    func testDetectResiduesForKnownAppReturnsRulePaths() async throws {
        let rules = [
            KFreshBundleRule(
                bundleID: "com.example.KnownApp",
                appName: "KnownApp",
                residuePaths: ["~/Library/Application Support/KnownApp", "~/Library/Preferences/com.example.KnownApp.plist"],
                systemLevelPaths: [],
                zapStanzas: [],
                confidence: 0.95,
                source: "homebrew-cask"
            )
        ]
        let data = try JSONEncoder().encode(rules)
        try data.write(to: tempRulesURL)
        let store = try BundleRuleStore(jsonURL: tempRulesURL)

        let detector = ResidueDetector(ruleStore: store)
        let residues = await detector.detectResidues(
            bundleID: "com.example.KnownApp",
            appName: "KnownApp",
            appURL: URL(fileURLWithPath: "/Applications/KnownApp.app")
        )

        XCTAssertGreaterThanOrEqual(residues.count, 2)
        let paths = residues.map(\.url.path)
        XCTAssertTrue(paths.contains { $0.contains("Application Support/KnownApp") })
        XCTAssertTrue(paths.contains { $0.contains("com.example.KnownApp.plist") })
    }

    func testDetectResiduesForUnknownAppFallsBackToTemplates() async throws {
        let data = try JSONEncoder().encode([KFreshBundleRule]())
        try data.write(to: tempRulesURL)
        let store = try BundleRuleStore(jsonURL: tempRulesURL)
        let detector = ResidueDetector(ruleStore: store)

        let residues = await detector.detectResidues(
            bundleID: "com.unknown.app",
            appName: "UnknownApp",
            appURL: URL(fileURLWithPath: "/Applications/UnknownApp.app")
        )

        // Should still find template-based paths (Preferences, Caches, App Support)
        XCTAssertGreaterThan(residues.count, 0)
    }

    func testDetectResiduesPreservesLiteralSpacesInAppName() async throws {
        let data = try JSONEncoder().encode([KFreshBundleRule]())
        try data.write(to: tempRulesURL)
        let store = try BundleRuleStore(jsonURL: tempRulesURL)
        let detector = ResidueDetector(ruleStore: store)

        let residues = await detector.detectResidues(
            bundleID: "com.example.Spaces In Name",
            appName: "App With Spaces",
            appURL: URL(fileURLWithPath: "/Applications/App With Spaces.app")
        )

        // I-1 fix: the template branch must NOT URL-escape the app name.
        // Real macOS paths are `~/Library/Application Support/App With Spaces/`
        // — literal spaces, not `%20`. URL-encoded paths would miss real
        // residue directories on disk.
        let appSupportPaths = residues.filter { $0.type == .appSupport }.map(\.url.path)
        XCTAssertTrue(appSupportPaths.contains { $0.hasSuffix("/Library/Application Support/App With Spaces") },
                      "Expected a literal-space app support path, got: \(appSupportPaths)")

        let logPaths = residues.filter { $0.type == .log }.map(\.url.path)
        XCTAssertTrue(logPaths.contains { $0.hasSuffix("/Library/Logs/App With Spaces") },
                      "Expected a literal-space log path, got: \(logPaths)")
        for residue in residues {
            XCTAssertFalse(residue.url.path.contains("%20"),
                           "URL-encoded space found in residue path: \(residue.url.path)")
        }
    }
}