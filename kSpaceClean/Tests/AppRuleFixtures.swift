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

/// Structural + resolve-level audit of the REAL `bundleIDMapping.json` shipped
/// in the app target (not a fixture). Guards the rule-library release gate:
///
/// * Header invariants (`version == 2`, `appCount` matches the real dictionary
///   count) and per-app well-formedness for ALL 108 entries (mixed v1/v2 schema:
///   an entry may carry either v2 `actions[]` or legacy `cleanPaths`).
/// * The 18 AI coding & agent-tool apps added in Task 8 are present and use the
///   v2 actions schema with an explicit `appstoreBundleID: null`.
/// * The 11 browsers/containers/terminals apps added in Task 9 are present with
///   v2 actions, and their cache/container/App-Support paths resolve through the
///   public `resolve(path:)` API without cross-app prefix shadowing.
/// * The 7 communication apps added in Task 10 are present with v2 actions
///   scoped to Electron cache subdirs (never broad chat-data App Support dirs),
///   and their cache paths resolve through the public `resolve(path:)` API.
/// * No bare broad cache prefix (e.g. a bare `~/Library/Caches/`) exists that
///   could vacuum the whole library into one bucket.
/// * The L1 path-boundary fix resolves the Claude pair, Cursor, and Zed
///   deterministically through the public `resolve(path:)` API.
///
/// Deliberately a plain (non-`@MainActor`) `XCTestCase`: the structural checks
/// are synchronous JSON inspection and the resolve-level checks just `await`
/// an actor, so no main-actor hop is needed.
final class AppRuleLibraryAudit: XCTestCase {
    /// Path to the real mapping file, derived from this source file's location:
    /// `kSpaceClean/Tests/AppRuleFixtures.swift` → `kSpaceClean/Resources/...`.
    private var mappingURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/bundleIDMapping.json")
    }

    /// The 18 net-new apps mandated by the Task 8 controller resolution.
    private let newBundleIDs = [
        "com.anthropic.claude",
        "com.anthropic.claudefordesktop",
        "com.todesclient.unicorn",
        "com.codeium.windsurf",
        "com.trae.app",
        "com.openai.chat",
        "com.perplexity.perplexity",
        "com.raycast.macos",
        "com.macgpt.macgpt",
        "com.electron.ollama",
        "com.lmstudio.lmstudio",
        "com.jan.jan",
        "com.nomic.gpt4all",
        "com.jetbrains.toolbox",
        "com.jetbrains.pycharm",
        "com.jetbrains.WebStorm",
        "dev.zed.Zed",
        "com.google.antigravity",
    ]

    /// The 11 net-new apps mandated by the Task 9 controller resolution
    /// (browsers + containers + terminals batch).
    private let task9BundleIDs = [
        "company.thebrowser.daily",
        "com.kagi.kagimacOS",
        "com.sigmaos.macos",
        "com.docker.docker",
        "dev.orbstack.OrbStack",
        "abiosoft.colima",
        "io.podman_desktop.PodmanDesktop",
        "dev.warp.Warp-Stable",
        "com.mitchellh.ghostty",
        "com.raphaelamorim.rio",
        "fig.tools.client",
    ]

    /// The 7 net-new apps mandated by the Task 10 controller resolution
    /// (communication & collaboration batch).
    private let task10BundleIDs = [
        "com.hnc.Discord",
        "com.microsoft.teams",
        "org.telegram.desktop",
        "org.whispersystems.signal-desktop",
        "com.bytedance.lark",
        "com.bytedance.feishu",
        "net.whatsapp.WhatsApp",
    ]

    private var root: [String: Any] {
        let data = try! Data(contentsOf: mappingURL)
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    func testMappingHeaderAndStructuralInvariants() throws {
        let root = root
        XCTAssertEqual(root["version"] as? Int, 2, "mapping version must be 2")

        let apps = try XCTUnwrap(root["apps"] as? [String: [String: Any]])
        let declared = try XCTUnwrap(root["appCount"] as? Int)
        XCTAssertEqual(declared, apps.count,
                       "appCount header must match the real dictionary count")

        let broadPrefixes = [
            "~/", "~/Library/", "~/Library/Caches/", "~/Library/Logs/",
            "~/Library/Application Support/",
        ]
        for (bundleID, app) in apps {
            XCTAssertEqual(app["bundleID"] as? String, bundleID,
                           "dict key must equal bundleID for \(bundleID)")
            for key in ["name", "nameCN", "vendor", "type", "riskLevel", "confidence"] {
                let value = app[key] as? String
                XCTAssertNotNil(value, "\(bundleID) missing \(key)")
                XCTAssertFalse(value!.isEmpty, "\(bundleID) has empty \(key)")
            }

            let actions = app["actions"] as? [[String: Any]]
            let cleanPaths = app["cleanPaths"] as? [String]
            XCTAssertTrue(actions != nil || cleanPaths != nil,
                          "\(bundleID) must carry v2 actions[] or legacy cleanPaths")

            if let actions = actions {
                XCTAssertFalse(actions.isEmpty, "\(bundleID) has empty actions[]")
                for action in actions {
                    for key in ["name", "nameCN", "type"] {
                        let value = action[key] as? String
                        XCTAssertNotNil(value, "\(bundleID) action missing \(key)")
                        XCTAssertFalse(value!.isEmpty, "\(bundleID) action has empty \(key)")
                    }
                    let paths = try XCTUnwrap(action["paths"] as? [String],
                                              "\(bundleID) action missing paths[]")
                    XCTAssertFalse(paths.isEmpty, "\(bundleID) action has empty paths[]")
                    for path in paths {
                        XCTAssertTrue(path.hasPrefix("~/") || path.hasPrefix("/"),
                                      "\(bundleID): path not ~/-rooted or absolute: \(path)")
                        for broad in broadPrefixes {
                            XCTAssertNotEqual(path, broad,
                                              "\(bundleID): bare broad prefix \(path)")
                        }
                    }
                }
            }
        }
    }

    func testTask8NewAppsPresentWithV2Actions() throws {
        let apps = try XCTUnwrap(root["apps"] as? [String: [String: Any]])
        for bundleID in newBundleIDs {
            let app = try XCTUnwrap(apps[bundleID],
                                    "Task 8 app \(bundleID) missing from bundleIDMapping.json")
            // JSONSerialization decodes JSON `null` as NSNull, so check the
            // value IS NSNull (explicit null) rather than merely non-nil.
            XCTAssertTrue(app["appstoreBundleID"] is NSNull,
                          "\(bundleID) must declare appstoreBundleID: null")
            let actions = try XCTUnwrap(app["actions"] as? [[String: Any]],
                                        "\(bundleID) must use the v2 actions schema")
            XCTAssertFalse(actions.isEmpty, "\(bundleID) has empty actions[]")
        }
    }

    func testResolveSpotChecksOverRealMapping() async throws {
        let resolver = BundleIDResolver()
        await resolver.load(from: mappingURL)

        func resolved(_ path: String) async -> String? {
            await resolver.resolve(path: path)?.bundleID
        }

        // Claude pair — the exact collision the boundary fix addresses.
        let claudeCode = await resolved("~/Library/Caches/com.anthropic.claude/Console/a.json")
        XCTAssertEqual(claudeCode, "com.anthropic.claude")
        let claudeDesktop = await resolved("~/Library/Caches/com.anthropic.claudefordesktop/Cache/b.dat")
        XCTAssertEqual(claudeDesktop, "com.anthropic.claudefordesktop")

        // Shared parent `~/Library/Application Support/Claude/` is owned by BOTH
        // Anthropic apps (Claude Code's broad prefix + Claude Desktop's Electron
        // subdirs). Either attribution is legitimate; it must never fall through
        // to a generic bucket or a third-party app.
        let sharedClaude = await resolved("~/Library/Application Support/Claude/Cache/c.bin")
        XCTAssertTrue(
            sharedClaude == "com.anthropic.claude" || sharedClaude == "com.anthropic.claudefordesktop",
            "shared Application Support/Claude path must resolve inside the Anthropic "
            + "pair, got: \(sharedClaude ?? "nil")"
        )

        // VSCode-fork IDE and native editor spot checks.
        let cursor = await resolved("~/Library/Application Support/Cursor/CachedData/d.bin")
        XCTAssertEqual(cursor, "com.todesclient.unicorn")
        let zed = await resolved("~/Library/Caches/dev.zed.Zed/e.bin")
        XCTAssertEqual(zed, "dev.zed.Zed")
    }

    func testTask9NewAppsPresentWithV2Actions() throws {
        let apps = try XCTUnwrap(root["apps"] as? [String: [String: Any]])
        for bundleID in task9BundleIDs {
            let app = try XCTUnwrap(apps[bundleID],
                                    "Task 9 app \(bundleID) missing from bundleIDMapping.json")
            // JSONSerialization decodes JSON `null` as NSNull, so check the
            // value IS NSNull (explicit null) rather than merely non-nil.
            XCTAssertTrue(app["appstoreBundleID"] is NSNull,
                          "\(bundleID) must declare appstoreBundleID: null")
            let actions = try XCTUnwrap(app["actions"] as? [[String: Any]],
                                        "\(bundleID) must use the v2 actions schema")
            XCTAssertFalse(actions.isEmpty, "\(bundleID) has empty actions[]")
        }
    }

    func testTask9ResolveSpotChecksOverRealMapping() async throws {
        let resolver = BundleIDResolver()
        await resolver.load(from: mappingURL)

        func resolved(_ path: String) async -> String? {
            await resolver.resolve(path: path)?.bundleID
        }

        // Arc is a Chromium browser: its cache tree resolves to Arc via the
        // declared `~/Library/Caches/company.thebrowser.daily/` prefix.
        let arcCache = await resolved("~/Library/Caches/company.thebrowser.daily/Default/Cache/f/data_0")
        XCTAssertEqual(arcCache, "company.thebrowser.daily")

        // Docker Desktop is sandboxed — the declared paths live in the app
        // container and the group container, never in Application Support.
        // The VM disk under `Data/vms/` is NOT declared and must NOT shadow
        // these cache/group paths.
        let dockerCache = await resolved("~/Library/Containers/com.docker.docker/Data/Library/Caches/c.bin")
        XCTAssertEqual(dockerCache, "com.docker.docker")
        let dockerGroup = await resolved("~/Library/Group Containers/group.com.docker/settings.json")
        XCTAssertEqual(dockerGroup, "com.docker.docker")

        // Terminal App Support data dirs resolve to their owning app.
        let warp = await resolved("~/Library/Application Support/dev.warp.Warp-Stable/sessions/s.json")
        XCTAssertEqual(warp, "dev.warp.Warp-Stable")
        let ghostty = await resolved("~/Library/Application Support/com.mitchellh.ghostty/config")
        XCTAssertEqual(ghostty, "com.mitchellh.ghostty")
    }

    func testTask10NewAppsPresentWithV2Actions() throws {
        let apps = try XCTUnwrap(root["apps"] as? [String: [String: Any]])
        for bundleID in task10BundleIDs {
            let app = try XCTUnwrap(apps[bundleID],
                                    "Task 10 app \(bundleID) missing from bundleIDMapping.json")
            // JSONSerialization decodes JSON `null` as NSNull, so check the
            // value IS NSNull (explicit null) rather than merely non-nil.
            XCTAssertTrue(app["appstoreBundleID"] is NSNull,
                          "\(bundleID) must declare appstoreBundleID: null")
            let actions = try XCTUnwrap(app["actions"] as? [[String: Any]],
                                        "\(bundleID) must use the v2 actions schema")
            XCTAssertFalse(actions.isEmpty, "\(bundleID) has empty actions[]")
        }
    }

    func testTask10ResolveSpotChecksOverRealMapping() async throws {
        let resolver = BundleIDResolver()
        await resolver.load(from: mappingURL)

        func resolved(_ path: String) async -> String? {
            await resolver.resolve(path: path)?.bundleID
        }

        // Discord is an Electron chat app: the App-Support cache subdirs are
        // declared (broad chat-data dirs are deliberately NOT), and they must
        // resolve to Discord — never to a generic bucket.
        let discordCache = await resolved("~/Library/Application Support/discord/Cache/f/data_0")
        XCTAssertEqual(discordCache, "com.hnc.Discord")

        // Telegram Desktop is a native Qt app: its file cache lives under
        // `tdata/user_data/cache` (the `tdata` root holds the chat DB and is
        // NOT declared).
        let telegramCache = await resolved("~/Library/Application Support/Telegram Desktop/tdata/user_data/cache/g.data")
        XCTAssertEqual(telegramCache, "org.telegram.desktop")

        // Teams sits next to VS Code (`com.microsoft.VSCode`) and Edge
        // (`com.microsoft.edgemac`) in the bundle-ID space, but the cache
        // prefixes are distinct — the L1 path-boundary predicate must keep
        // them separate.
        let teamsCache = await resolved("~/Library/Caches/com.microsoft.teams/Code Cache/js.js")
        XCTAssertEqual(teamsCache, "com.microsoft.teams")
    }

    /// Regression guard for the Task 10 CRITICAL SAFETY CONSTRAINT: for every
    /// messaging app, no cleanable action path may be the broad
    /// `Application Support/<Leaf>/` root — that leaf root holds the chat
    /// database (user data). Actions must be scoped to cache subdirs only.
    /// The shipped data already complies; this test guards future edits.
    func testMessagingAppActionsNeverCoverChatDataRoot() throws {
        let apps = try XCTUnwrap(root["apps"] as? [String: [String: Any]])
        let messagingIDs: Set<String> = [
            "com.slack.Slack", "com.hnc.Discord", "com.microsoft.teams",
            "org.telegram.desktop", "org.whispersystems.signal-desktop",
            "com.bytedance.lark", "com.bytedance.feishu", "net.whatsapp.WhatsApp"
        ]
        for bundleID in messagingIDs {
            let app = try XCTUnwrap(apps[bundleID], "\(bundleID) missing from bundleIDMapping.json")
            let actions = try XCTUnwrap(app["actions"] as? [[String: Any]],
                                        "\(bundleID) must use the v2 actions schema")
            for action in actions {
                let paths = try XCTUnwrap(action["paths"] as? [String])
                for path in paths {
                    let comps = path.split(separator: "/")
                    // Banned shape: "…/Application Support/<Leaf>/" with nothing after it —
                    // the leaf root holds the chat database (user data).
                    for i in 0..<comps.count {
                        if comps[i] == "Application Support", i == comps.count - 2 {
                            XCTFail("\(bundleID) action \(action["name"] ?? "?") declares "
                                + "broad App Support root \(path) — chat data is user data; "
                                + "cache subdirs only")
                        }
                    }
                }
            }
        }
    }

    /// Regression guard for the final-review I4 finding: GPT4All and LM Studio
    /// download GB-scale model files into their App Support root. A cleanable
    /// action at the bare `Application Support/<Leaf>/` root would delete the
    /// model store. Cache/log subdirs are fine; the leaf root is not.
    ///
    /// Deliberately scoped to the two apps whose model store lives in App
    /// Support. Ollama keeps its `Data` soft action (models live at
    /// `~/.ollama`, not App Support) and MacGPT keeps its `Data` soft action
    /// (API-only, no local model store) — both are off-by-default config/data
    /// actions in the same harm class as the other apps' `Data` actions.
    func testModelRunnerActionsNeverCoverAppSupportRoot() throws {
        let apps = try XCTUnwrap(root["apps"] as? [String: [String: Any]])
        let modelRunnerIDs: Set<String> = [
            "com.nomic.gpt4all", "com.lmstudio.lmstudio"
        ]
        for bundleID in modelRunnerIDs {
            let app = try XCTUnwrap(apps[bundleID], "\(bundleID) missing from bundleIDMapping.json")
            let actions = try XCTUnwrap(app["actions"] as? [[String: Any]],
                                        "\(bundleID) must use the v2 actions schema")
            for action in actions {
                let paths = try XCTUnwrap(action["paths"] as? [String])
                for path in paths {
                    let comps = path.split(separator: "/")
                    // Banned shape: "…/Application Support/<Leaf>/" with nothing after it —
                    // the leaf root holds the downloaded model store.
                    for i in 0..<comps.count {
                        if comps[i] == "Application Support", i == comps.count - 2 {
                            XCTFail("\(bundleID) action \(action["name"] ?? "?") declares "
                                + "bare App Support root \(path) — LLM model store is user data; "
                                + "cache/log subdirs only")
                        }
                    }
                }
            }
        }
    }
}
