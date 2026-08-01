import XCTest
@testable import kSpaceClean
import FileScanner

/// Regression coverage for ``BundleIDResolver``'s L1 prefix match against
/// tilde-prefixed clean paths.
///
/// Bug history:
/// - 2026-08-01 — In App Sandbox builds, `expandingTildeInPath` resolves
///   `~` against the sandbox container home, so a cleanPath like
///   `~/Library/Application Support/Slack` was pre-expanded against the
///   container, not the real user home. The orchestrator's enumerator
///   uses `UserPathResolver.expandTilde` (which uses the real `$HOME`
///   via `getpwuid`), so the L1 prefix match silently missed and every
///   app lookup fell through to the generic `def.id` bucket — producing
///   the "应用缓存 → 应用缓存" duplication.
///
/// The test writes a tiny JSON fixture into ``/tmp`` so it stays
/// deterministic and portable across worktrees.
final class BundleIDResolverTests: XCTestCase {

    private func makeFixture(_ json: String) -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bundleid-\(UUID().uuidString).json")
        try? json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func realHomeForTesting() throws -> String {
        // Mirrors `UserPathResolver.realHomeDirectory()` (passwd-based).
        // The kSpaceClean test target cannot import its own
        // `UserPathResolver` via @testable because the package product
        // boundary would force extra leakage, so we re-derive the same
        // value here. The two must stay in sync for the bug to remain
        // fixed; the assertions below cover the contract on both sides.
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else {
            throw XCTSkip("Cannot resolve real $HOME via getpwuid on this platform")
        }
        let home = String(cString: dir)
        if home.isEmpty {
            throw XCTSkip("Empty real $HOME from getpwuid on this platform")
        }
        return home
    }

    func testL1PrefixMatchIgnoresSandboxContainer() async throws {
        // Regression for the 2026-08-01 "应用缓存 → 应用缓存" duplication bug.

        // Part A — direct unit check on `BundleIDResolver.expand(_:)`:
        // we exercise it with a cleanPath and verify the resolved prefix
        // is rooted at the *real* $HOME and never points at the sandbox
        // container. This assertion is what would have caught the
        // original `expandingTildeInPath` regression in a sandboxed
        // host-app build.
        let realHome = try realHomeForTesting()
        let resolvedPrefix = BundleIDResolver.expand(
            "~/Library/Application Support/Slack"
        )
        XCTAssertTrue(
            resolvedPrefix.hasPrefix(realHome + "/"),
            "expand(_:) must produce a path rooted at the real $HOME, "
            + "not the sandbox container. Got: \(resolvedPrefix)"
        )
        XCTAssertFalse(
            resolvedPrefix.contains("/Containers/"),
            "expand(_:) must not point at the sandbox container"
            + " (/Containers/<bundleID>/Data). Got: \(resolvedPrefix)"
        )

        // Part B — end-to-end prefix match through the public
        // `resolve(path:)` API: with the fix, `BundleIDResolver`
        // pre-expands the cleanPath against the real $HOME, so calling
        // `resolve(path:)` with a real-home-rooted path must hit.
        let url = makeFixture("""
        {
          "version": 1,
          "apps": {
            "com.tinyspeck.chatlytic": {
              "name": "Slack",
              "nameCN": "Slack",
              "vendor": "Slack",
              "type": "chat",
              "riskLevel": "caution",
              "cleanPaths": ["~/Library/Application Support/Slack"],
              "confidence": "high"
            }
          }
        }
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let resolver = BundleIDResolver()
        await resolver.load(from: url)

        let path = realHome
            + "/Library/Application Support/Slack/Cookies/localstorage.json"

        let resolved = await resolver.resolve(path: path)
        XCTAssertEqual(
            resolved?.bundleID,
            "com.tinyspeck.chatlytic",
            "L1 prefix match must hit real-home expansion, not sandbox container"
        )
    }
}
