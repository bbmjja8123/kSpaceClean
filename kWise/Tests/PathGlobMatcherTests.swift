import XCTest
@testable import kWise

final class PathGlobMatcherTests: XCTestCase {
    private let home = "/Users/tester"

    func testExactPathMatches() {
        XCTAssertTrue(PathGlobMatcher.matches(
            path: "/Users/tester/Library/Logs", glob: "~/Library/Logs", home: home))
    }

    func testDoubleStarMatchesDescendantsAndSelf() {
        let glob = "~/Library/Developer/Xcode/DerivedData/**"
        XCTAssertTrue(PathGlobMatcher.matches(
            path: "/Users/tester/Library/Developer/Xcode/DerivedData", glob: glob, home: home),
            "trailing ** must match the directory itself (0 segments)")
        XCTAssertTrue(PathGlobMatcher.matches(
            path: "/Users/tester/Library/Developer/Xcode/DerivedData/MyApp-abc/Build/x.o",
            glob: glob, home: home))
        XCTAssertFalse(PathGlobMatcher.matches(
            path: "/Users/tester/Library/Developer/Xcode/Archives/x.xcarchive",
            glob: glob, home: home))
    }

    func testSingleStarStaysWithinSegment() {
        XCTAssertTrue(PathGlobMatcher.matches(
            path: "/Users/tester/Library/Caches/com.apple.Safari/Cache.db",
            glob: "~/Library/Caches/*/**", home: home))
        XCTAssertFalse(PathGlobMatcher.matches(
            path: "/Users/tester/Library/Caches/a/b/Cache.db",
            glob: "~/Library/Caches/*/*.db", home: home),
            "* must not cross '/'")
    }

    func testTildeExpansionAndCaseInsensitivity() {
        XCTAssertTrue(PathGlobMatcher.matches(
            path: "/users/TESTER/library/caches/x", glob: "~/Library/Caches/x", home: home))
    }

    func testLeadingDoubleStarMatchesAnyDepth() {
        XCTAssertTrue(PathGlobMatcher.matches(
            path: "/Users/tester/Deep/Nest/Docker.raw", glob: "**/Docker.raw", home: home))
    }

    func testHomeInjectionMattersInTests() {
        // home 必须是注入的，不许偷偷读 NSHomeDirectory（可测试性红线）。
        XCTAssertFalse(PathGlobMatcher.matches(
            path: "/Users/tester/Library/Caches/x", glob: "~/Library/Caches/x", home: "/home/other"))
    }
}
