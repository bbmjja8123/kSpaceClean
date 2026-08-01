import XCTest
@testable import kFresh

final class BundleRuleStoreTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() async throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rules-\(UUID().uuidString).json")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    func testLookupExactBundleID() async throws {
        let rules = [
            KFreshBundleRule(bundleID: "com.example.alpha", appName: "Alpha"),
            KFreshBundleRule(bundleID: "com.example.beta", appName: "Beta"),
        ]
        let json = try JSONEncoder().encode(rules)
        try json.write(to: tempURL)

        let store = try BundleRuleStore(jsonURL: tempURL)
        let found = await store.lookup(bundleID: "com.example.alpha")
        XCTAssertEqual(found?.appName, "Alpha")
    }

    func testFuzzyMatchByName() async throws {
        let rules = [
            KFreshBundleRule(bundleID: "com.google.chrome", appName: "Google Chrome"),
            KFreshBundleRule(bundleID: "com.google.Chrome", appName: "Chrome Beta"),
        ]
        let json = try JSONEncoder().encode(rules)
        try json.write(to: tempURL)

        let store = try BundleRuleStore(jsonURL: tempURL)
        let matches = await store.fuzzyMatch(name: "chrome")
        XCTAssertEqual(matches.count, 2)
    }

    func testCountReflectsLoadedRules() async throws {
        let rules = (0..<100).map { KFreshBundleRule(bundleID: "id-\($0)", appName: "App\($0)") }
        let json = try JSONEncoder().encode(rules)
        try json.write(to: tempURL)

        let store = try BundleRuleStore(jsonURL: tempURL)
        let count = await store.count
        XCTAssertEqual(count, 100)
    }

    /// C-2 fix: `init(jsonData:)` decodes in-memory data. Pre-fix only
    /// `init(jsonURL:)` existed, so tests and `loadFromBundledJSON`
    /// both had to round-trip through disk.
    func testInitFromInMemoryData() async throws {
        let rules = [
            KFreshBundleRule(bundleID: "com.example.alpha", appName: "Alpha"),
        ]
        let data = try JSONEncoder().encode(rules)
        let store = try BundleRuleStore(jsonData: data)
        let found = await store.lookup(bundleID: "com.example.alpha")
        XCTAssertEqual(found?.appName, "Alpha")
    }

    /// C-2 fix: `loadFromBundledJSON()` returns `nil` for a missing
    /// resource rather than throwing — the production scanner relies on
    /// this graceful-degradation behaviour so an early-launch scan that
    /// runs before the resource is staged doesn't crash.
    func testLoadFromBundledJSONReturnsNilForMissingResource() async {
        // Use a deliberately-missing resource name so the lookup fails.
        let store = BundleRuleStore.loadFromBundledJSON(named: "definitely-not-bundled", in: .main)
        XCTAssertNil(store)
    }
}