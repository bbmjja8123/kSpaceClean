import XCTest
@testable import kFresh

/// Tests for the production ``ResidueScanner.scanAll()`` wiring.
///
/// The C-2 fix asserts that `ResidueScanner.scanAll()` uses the
/// bundled `cask_rules.json` rules — pre-fix the scanner was
/// constructed with `ResidueDetector(ruleStore: nil)` and every app
/// fell through to the template branch, silently missing the curated
/// rule residue paths for popular apps.
final class ResidueScannerTests: XCTestCase {
    private var tempHomeURL: URL!

    override func setUp() async throws {
        tempHomeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempHomeURL, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempHomeURL)
    }

    /// C-2 fix: when a built `BundleRuleStore` containing a known rule
    /// is injected, `detectResiduesForApp` returns a residue list that
    /// contains the rule's curated path. This isolates the wiring
    /// concern from the bundled JSON loader (which has its own test).
    func testScanUsesInjectedRuleStore() async throws {
        // Build a rule store in memory: a fictitious bundle ID that the
        // template branch would NOT generate a curated path for.
        let customBundleID = "com.kfresh.test.scanner-\(UUID().uuidString)"
        let rules = [
            KFreshBundleRule(
                bundleID: customBundleID,
                appName: "TestScannerCurated",
                residuePaths: ["~/Library/Application Support/TestScannerCurated"],
                systemLevelPaths: [],
                zapStanzas: [],
                confidence: 0.95,
                source: "test-fixture"
            )
        ]
        let store = try BundleRuleStore(jsonData: try JSONEncoder().encode(rules))

        let scanner = ResidueScanner(ruleStore: store)

        let appURL = URL(fileURLWithPath: "/Applications/TestScannerCurated.app")
        let residues = await scanner.detectResiduesForApp(
            bundleID: customBundleID,
            appName: "TestScannerCurated",
            appURL: appURL
        )

        // Curated rule path should appear in the result.
        let pathStrings = residues.map(\.url.path)
        XCTAssertTrue(pathStrings.contains(where: { $0.hasSuffix("/Library/Application Support/TestScannerCurated") }),
                      "Expected curated rule path in: \(pathStrings)")
    }

    /// C-2 fix (default init): a scanner constructed with `init()`
    /// loads `cask_rules.json` from the bundle so the production scan
    /// picks up curated rules without an explicit init argument.
    /// Pre-fix the default init used `ResidueDetector(ruleStore: nil)`
    /// and every app fell through to the template branch.
    ///
    /// This test simply verifies that the default init does not crash
    /// and returns a working scanner. Curated-rule coverage is asserted
    /// by `testScanUsesInjectedRuleStore`.
    func testDefaultInitProducesWorkingScanner() async {
        let scanner = ResidueScanner()
        let bundleID = "com.kfresh.test.scanner-\(UUID().uuidString)"
        let residues = await scanner.detectResiduesForApp(
            bundleID: bundleID,
            appName: "TestScanner",
            appURL: URL(fileURLWithPath: "/Applications/TestScanner.app")
        )
        // With a fictitious bundle ID, no curated rule matches, so the
        // template branch produces the standard residue list.
        XCTAssertGreaterThan(residues.count, 0)
    }
}