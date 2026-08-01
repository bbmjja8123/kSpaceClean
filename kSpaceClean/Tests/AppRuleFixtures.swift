// kSpaceClean/Tests/AppRuleFixtures.swift
//
// E2E test for the v2 scan-pipeline grouping fix (Task 5):
//
//   * ONE sub-category per app even when the app's files appear under
//     multiple rootPaths of the same category (the old per-rootPath bucket
//     emitted a duplicate sub-category per path — the "scan results are
//     sparse and mis-grouped" complaint).
//   * The level-3 action rows are built from the `BundleIDResolver`
//     rule actions (`ResolvedAction`), not left empty.
//
// The fixture deliberately uses an absolute `/tmp`-rooted path (not `~/`)
// so the walk, the L1 prefix match, and the action-path prefix grouping all
// agree without any tilde expansion ambiguity. Paths in the category
// definitions and in the action paths point at the same on-disk files.
import XCTest
import FileScanner
@testable import kSpaceClean

@MainActor
final class AppRuleFixtures: XCTestCase {
    /// Multi-rootPath category with one known app expected to surface
    /// under TWO rootPaths (~/Library/Application Support +
    /// ~/Library/Containers). Asserts (a) one sub-category per app,
    /// (b) action level built.
    func testSlackSurfacesOnceAcrossTwoRootPaths() async throws {
        let root = URL(fileURLWithPath: "/tmp")
            .appendingPathComponent("ksc-fixture-slack-\(UUID().uuidString)",
                                    isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // App Support: ~/Library/Application Support/Slack/Cookies/localstorage.json
        let appSupport = root.appendingPathComponent("AppSupp/Slack/Cookies", isDirectory: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try Data(repeating: 0xAA, count: 2048).write(to: appSupport.appendingPathComponent("localstorage.json"))

        // Containers: ~/Library/Containers/com.tinyspeck.chatlytic/Library/Caches/fsCachedData
        let containers = root.appendingPathComponent("Containers/com.tinyspeck.chatlytic/Library/Caches/fsCachedData",
                                                     isDirectory: true)
        try FileManager.default.createDirectory(at: containers, withIntermediateDirectories: true)
        try Data(repeating: 0xBB, count: 4096).write(to: containers.appendingPathComponent("abc.dat"))

        let mappingJSON = """
        {
          "version": 2,
          "apps": {
            "com.tinyspeck.chatlytic": {
              "bundleID": "com.tinyspeck.chatlytic",
              "name": "Slack",
              "nameCN": "Slack",
              "actions": [
                {"name": "Slack Cache", "nameCN": "Slack 缓存",
                 "paths": ["\(root.path)/AppSupp/Slack"]},
                {"name": "Sandbox Cache", "nameCN": "沙盒缓存",
                 "paths": ["\(root.path)/Containers/com.tinyspeck.chatlytic"]}
              ]
            }
          }
        }
        """.data(using: .utf8)!
        let mappingURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mapping-\(UUID().uuidString).json")
        try mappingJSON.write(to: mappingURL)
        defer { try? FileManager.default.removeItem(at: mappingURL) }

        // Pre-load the fixture mapping BEFORE constructing the
        // orchestrator: its init eagerly fires a detached `load(from:
        // Bundle.main URL)`, and `load(from:)` is once-only — pre-loading
        // the fixture mapping makes that no-op.
        let resolver = BundleIDResolver()
        await resolver.load(from: mappingURL)

        let cats = [
            CategoryDefinition(
                id: "fixture.appcache",
                title: "Fixture App Cache",
                paths: [
                    root.appendingPathComponent("AppSupp").path,
                    root.appendingPathComponent("Containers").path
                ],
                riskLevel: .recommended
            )
        ]
        let orchestrator = ScanOrchestrator(
            categoryDefinitions: cats,
            bundleIDResolver: resolver
        )

        // Drive the scan exactly like ScanOrchestratorIntegrationTests:
        // attach the category-stream consumer AFTER startScan() (the
        // stream snapshots the scan epoch at attach time), break on the
        // terminal progress snapshot, then read the captured category.
        let stream = await orchestrator.startScan()

        var emittedCategories: [ScanCategory] = []
        let consumer = Task { @MainActor in
            for await event in await orchestrator.categoryStream() {
                switch event {
                case .category(let catEvent):
                    emittedCategories.append(catEvent.category)
                case .terminal(let progress):
                    if case .failed = progress.state {
                        XCTFail("scan should not fail against a real fixture")
                    }
                }
            }
        }
        for await p in stream {
            if case .completed = p.state { break }
            if case .failed = p.state { XCTFail("scan failed") }
        }
        await consumer.value

        let category = try XCTUnwrap(emittedCategories.first,
                                     "orchestrator must publish the scan category to its stream")
        XCTAssertEqual(category.subItems.count, 1,
                       "Slack must appear as ONE sub-category across both rootPaths")
        let slack = try XCTUnwrap(category.subItems.first)
        XCTAssertEqual(slack.bundleID, "com.tinyspeck.chatlytic")
        XCTAssertGreaterThan(slack.actions.count, 1,
                             "action level must be built when resolver provides multiple actions")
    }
}
