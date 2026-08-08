import XCTest
@testable import FileScanner

/// Coverage for ``BundleIDResolver``:
/// - L1 path-prefix lookup (the happy path)
/// - L2 reverse-DNS token lookup (fallback when no clean path matches)
/// - Negative lookup (generic system path)
/// - Robustness against malformed JSON
///
/// Each test writes a tiny JSON fixture into ``/tmp`` rather than relying on
/// the production ``bundleIDMapping.json`` so the tests stay deterministic and
/// portable across worktrees.
final class BundleIDResolverTests: XCTestCase {

    private func makeFixture(_ json: String) -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bundleid-\(UUID().uuidString).json")
        try? json.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testResolveByCleanPathPrefix() async throws {
        let url = makeFixture("""
        {
          "version": 1,
          "apps": {
            "com.tencent.xinWeChat": {
              "name": "WeChat", "nameCN": "微信", "vendor": "腾讯",
              "type": "chat", "riskLevel": "caution",
              "cleanPaths": [
                "~/Library/Containers/com.tencent.xinWeChat/Data/Library/Caches/com.tencent.xinWeChat"
              ],
              "confidence": "high"
            }
          }
        }
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let resolver = BundleIDResolver()
        await resolver.load(from: url)

        let resolved = await resolver.resolve(
            path: "~/Library/Containers/com.tencent.xinWeChat/Data/Library/Caches/com.tencent.xinWeChat/fsCachedData"
        )
        XCTAssertEqual(resolved?.bundleID, "com.tencent.xinWeChat")
        XCTAssertEqual(resolved?.nameCN, "微信")
        XCTAssertEqual(resolved?.riskLevel, "caution")
    }

    func testResolveByBundleIDTokenInPath() async throws {
        // The path does not start with any cleanPath but contains the bundle
        // ID as a token — L2 should still find it.
        let url = makeFixture("""
        {
          "apps": {
            "com.apple.dt.Xcode": {
              "name": "Xcode", "nameCN": "Xcode", "vendor": "Apple",
              "type": "developer", "riskLevel": "optional",
              "cleanPaths": ["~/Library/Developer/Xcode/DerivedData/"]
            }
          }
        }
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let resolver = BundleIDResolver()
        await resolver.load(from: url)

        let resolved = await resolver.resolve(
            path: "/Users/me/somewhere/unrelated/com.apple.dt.Xcode-build-trash"
        )
        XCTAssertEqual(resolved?.bundleID, "com.apple.dt.Xcode")
    }

    func testResolveReturnsNilForUnknownPath() async throws {
        let url = makeFixture("""
        { "apps": { "com.apple.Safari": {
            "name": "Safari", "nameCN": "Safari", "vendor": "Apple",
            "type": "browser", "riskLevel": "recommended",
            "cleanPaths": ["~/Library/Caches/com.apple.Safari"]
        }}}
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let resolver = BundleIDResolver()
        await resolver.load(from: url)

        let resolved = await resolver.resolve(path: "/private/var/log/system.log")
        XCTAssertNil(resolved)
    }

    func testLoadIsIdempotent() async throws {
        let url = makeFixture("""
        { "apps": { "com.tencent.qq": {
            "name": "QQ", "nameCN": "QQ", "vendor": "腾讯",
            "type": "chat", "riskLevel": "caution",
            "cleanPaths": ["~/Library/Containers/com.tencent.qq"]
        }}}
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let resolver = BundleIDResolver()
        await resolver.load(from: url)
        await resolver.load(from: url)  // second call is a no-op
        let count = await resolver.count
        XCTAssertEqual(count, 1)
    }

    func testMalformedJSONDegradesGracefully() async throws {
        // No "apps" key. The resolver should record the error and refuse to
        // match anything rather than crash the scan pipeline.
        let url = makeFixture("""
        { "totally": "wrong" }
        """)
        defer { try? FileManager.default.removeItem(at: url) }

        let resolver = BundleIDResolver()
        await resolver.load(from: url)

        let isLoaded = await resolver.isLoaded
        let error = await resolver.lastLoadError
        XCTAssertFalse(isLoaded)
        XCTAssertNotNil(error)
        let resolved = await resolver.resolve(path: "/Users/me/whatever")
        XCTAssertNil(resolved)
    }

    func testMissingFileDoesNotCrash() async throws {
        // A path that does not exist should produce no matches, not a throw.
        let resolver = BundleIDResolver()
        let bogus = URL(fileURLWithPath: "/tmp/this-file-does-not-exist-\(UUID().uuidString).json")
        await resolver.load(from: bogus)
        let resolved = await resolver.resolve(path: "/Users/me/anything")
        XCTAssertNil(resolved)
        let err = await resolver.lastLoadError
        XCTAssertNotNil(err)
    }

    func testProductionFixtureLoadsSuccessfully() async throws {
        // Smoke test against the real bundleIDMapping.json shipped with the
        // app. Skipped unless KSPACECLEAN_PROJECT_ROOT points at the worktree
        // root — kFoundation is a standalone package and can be built without
        // the host app's resources.
        let env = ProcessInfo.processInfo.environment
        guard let projectRoot = env["KSPACECLEAN_PROJECT_ROOT"] else {
            throw XCTSkip("Set KSPACECLEAN_PROJECT_ROOT to run the production smoke test.")
        }
        let url = URL(fileURLWithPath: projectRoot)
            .appendingPathComponent("kWise/Resources/bundleIDMapping.json")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("bundleIDMapping.json not present at \(url.path)")
        }

        let resolver = BundleIDResolver()
        await resolver.load(from: url)

        let wechat = await resolver.resolve(
            path: "~/Library/Containers/com.tencent.xinWeChat/Data/Library/Caches/com.tencent.xinWeChat/foo"
        )
        XCTAssertEqual(wechat?.bundleID, "com.tencent.xinWeChat")
        XCTAssertEqual(wechat?.nameCN, "微信")
    }
}
