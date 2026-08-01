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

    // MARK: - I-2 confidence consistency guard

    /// I-2 fix: the rule branch and the template branch must apply the
    /// same "halve confidence if the path doesn't exist on disk" policy.
    /// Pre-fix: rule branch returned the rule's full declared confidence
    /// regardless of existence (so a non-existent rule path was reported
    /// at 0.85 confidence, indistinguishable from an existing one);
    /// template branch halved it. The fix: both branches verify
    /// existence and halve on miss.
    ///
    /// This test exercises the rule branch.
    func testRuleBranchHalvesConfidenceWhenPathMissing() async throws {
        // Path deliberately points at a directory that does NOT exist.
        let rules = [
            KFreshBundleRule(
                bundleID: "com.example.MissingPath",
                appName: "MissingPath",
                residuePaths: ["~/Library/Application Support/MissingPath"],
                systemLevelPaths: [],
                zapStanzas: [],
                confidence: 0.9,
                source: "homebrew-cask"
            )
        ]
        let data = try JSONEncoder().encode(rules)
        try data.write(to: tempRulesURL)
        let store = try BundleRuleStore(jsonURL: tempRulesURL)

        // tempHomeURL is empty — neither App Support nor Preferences exists
        // under it, so every residue path will report `exists == false`.
        let detector = ResidueDetector(ruleStore: store, homeDirectory: tempHomeURL)
        let residues = await detector.detectResidues(
            bundleID: "com.example.MissingPath",
            appName: "MissingPath",
            appURL: URL(fileURLWithPath: "/Applications/MissingPath.app")
        )

        XCTAssertGreaterThanOrEqual(residues.count, 1)
        for residue in residues {
            XCTAssertEqual(residue.confidence, 0.45, accuracy: 0.001,
                           "Non-existent rule path should be reported at half the rule's declared confidence, got \(residue.confidence) for \(residue.url.path)")
        }
    }

    /// I-2 fix (template branch side): when a template path does not
    /// exist, confidence should be halved. Pre-fix: this was already the
    /// template behaviour, but it was inconsistent with the rule branch.
    /// Post-fix: both branches halve consistently. This test pins the
    /// template behaviour so it cannot regress.
    func testTemplateBranchHalvesConfidenceWhenPathMissing() async throws {
        let data = try JSONEncoder().encode([KFreshBundleRule]())
        try data.write(to: tempRulesURL)
        let store = try BundleRuleStore(jsonURL: tempRulesURL)

        let detector = ResidueDetector(ruleStore: store, homeDirectory: tempHomeURL)
        let residues = await detector.detectResidues(
            bundleID: "com.example.MissingTemplate",
            appName: "MissingTemplate",
            appURL: URL(fileURLWithPath: "/Applications/MissingTemplate.app")
        )

        // The declared template confidence for `preferences` is 0.99; if
        // the path is missing it should drop to 0.495.
        let prefPaths = residues.filter { $0.type == .preferences }
        XCTAssertGreaterThan(prefPaths.count, 0)
        for residue in prefPaths {
            XCTAssertEqual(residue.confidence, 0.495, accuracy: 0.001,
                           "Non-existent template path should be reported at half its declared confidence, got \(residue.confidence) for \(residue.url.path)")
        }
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