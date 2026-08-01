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
        // container.
        //
        // TDD-Step-2 caveat (documented per review):
        // This assertion was designed to FAIL under the original buggy
        // `(path as NSString).expandingTildeInPath` implementation when
        // run inside a *sandboxed host-app build* (real $HOME ≠ container
        // $HOME). However, the unsigned test host used by
        // `xcodebuild ... CODE_SIGNING_ALLOWED=NO` does not actually
        // exercise the App Sandbox — so `expandingTildeInPath` and
        // `homeDirectoryForCurrentUser` happen to agree, and Part A
        // passes against both buggy and fixed code under this test
        // runner. Part A still serves as a regression guard: if anyone
        // re-introduces `expandingTildeInPath` into `expand(_:)`, this
        // assertion will catch it the moment the test target is built
        // with code signing (i.e. the way users actually run the app).
        // Reviewers should NOT assume a true red-green-refactor was
        // performed here — see also `testExpandMatchesUserPathResolver`
        // below for the parity assertion that *does* hold regardless of
        // test-host sandbox state.
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

        // NOTE: Part B is a behavioural smoke check, NOT a load-bearing
        // assertion against the tilde bug. Under the unsigned
        // `CODE_SIGNING_ALLOWED=NO` test host, the App Sandbox is not
        // actually exercised, so `expandingTildeInPath` and the real
        // `$HOME` happen to agree — Part B passes against both the
        // buggy and fixed `expand`. The actual regression guard for the
        // tilde fix is Part A (sandboxed host-app build only) and the
        // dedicated parity test `testExpandMatchesUserPathResolver`
        // below. Part B stays in to confirm `resolve(path:)` does its
        // job end-to-end through the public API.

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

    /// Guards future drift between `BundleIDResolver.expand` and
    /// `UserPathResolver.expandTilde`.
    ///
    /// Both helpers currently derive the home prefix from the same
    /// passwd-based `$HOME` source, which is why the L1 prefix match
    /// agrees with the orchestrator's enumerator output. If a future
    /// refactor changes `UserPathResolver.expandTilde` to use
    /// `NSHomeDirectory()` (sandbox-aware) while `BundleIDResolver.expand`
    /// keeps the passwd source — or vice versa — the two expand helpers
    /// will silently disagree inside a sandboxed host-app build and the
    /// original "应用缓存 → 应用缓存" duplication bug will re-emerge as a
    /// *different* mismatch (the orchestrator seeing one home, the
    /// resolver seeing another). This test pins the contract: the two
    /// expand helpers must always produce byte-identical results for
    /// the same input, regardless of which `$HOME` source each one is
    /// using underneath.
    func testExpandMatchesUserPathResolver() {
        // Note: bare `"~"` (without the trailing slash) is intentionally
        // excluded. `BundleIDResolver.expand` only handles `~/` prefixes
        // (the shape that appears in cleanPaths), so for the lone `"~"`
        // input the two helpers diverge on purpose — that path never
        // appears in `cleanPaths` so the L1 prefix match cannot
        // exercise it. The contract we actually care about is "given a
        // tilde-prefixed path that L1 *will* see, both helpers expand it
        // to the same absolute path."
        let cases = [
            "~/Library/Caches/com.example",
            "~/Library/Application Support/Slack",
            "~/Library/Containers/com.apple.Safari/Data",
            "~/Documents/report.pdf",
        ]
        for input in cases {
            let fromBundleIDResolver = BundleIDResolver.expand(input)
            let fromUserPathResolver = UserPathResolver.expandTilde(input)
            XCTAssertEqual(
                fromBundleIDResolver,
                fromUserPathResolver,
                "BundleIDResolver.expand and UserPathResolver.expandTilde "
                + "must agree on the expanded path for \(input). "
                + "Got resolver=\(fromBundleIDResolver), "
                + "userPath=\(fromUserPathResolver). If this fails, one of "
                + "the two has drifted off the passwd-based real $HOME "
                + "source and the L1 prefix match can silently miss inside "
                + "a sandboxed host-app build."
            )
        }
    }
}
