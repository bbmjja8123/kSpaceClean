import XCTest
@testable import kWise

@MainActor
final class ScanTreeRowC1AuditTests: XCTestCase {
    // MARK: - Friendly path conversion

    func testFriendlyPathBasenameOnly() {
        let result = ScanTreeRow.friendlyPath(for: "/Users/jane/cache.db")
        XCTAssertEqual(result, "cache.db · jane/")
    }

    func testFriendlyPathDeepNesting() {
        let raw = "/Users/jane/Library/Developer/Xcode/DerivedData/Project-xxx/cache.db"
        let result = ScanTreeRow.friendlyPath(for: raw)
        XCTAssertEqual(result, "cache.db · DerivedData/")
    }

    func testFriendlyPathCacheDataStyle() {
        let raw = "/Users/jane/Library/Caches/Google/Chrome/Default/Cache_Data/data_1"
        let result = ScanTreeRow.friendlyPath(for: raw)
        XCTAssertEqual(result, "data_1 · Cache_Data/")
    }

    func testFriendlyPathNoParent() {
        let result = ScanTreeRow.friendlyPath(for: "/file.txt")
        XCTAssertEqual(result, "file.txt")
    }

    func testFriendlyPathBareBasename() {
        let result = ScanTreeRow.friendlyPath(for: "plain.db")
        XCTAssertEqual(result, "plain.db")
    }

    // MARK: - C-1 audit invariants

    func testFriendlyPathNeverLeaksAbsolutePrefix() {
        // C-1 invariant: friendly output NEVER starts with '/' (raw absolute path).
        let fixtures = [
            "/Users/jane/Library/Application Support/Google/Chrome/Default/Cookies",
            "/private/var/log/asl.log",
            "/tmp/build/very/deep/path/output.dylib",
            "/System/Library/Caches/com.apple.LaunchServices-1111.cs"
        ]
        for raw in fixtures {
            let friendly = ScanTreeRow.friendlyPath(for: raw)
            XCTAssertFalse(friendly.hasPrefix("/"),
                           "Friendly path '\(friendly)' leaks raw absolute prefix from '\(raw)'")
            XCTAssertFalse(friendly.contains("/Users/"),
                           "Friendly path '\(friendly)' contains '/Users/' from '\(raw)'")
            XCTAssertFalse(friendly.contains("/private/var/"),
                           "Friendly path '\(friendly)' contains '/private/var/' from '\(raw)'")
        }
    }

    func testFriendlyPathPreservesBasename() {
        let result = ScanTreeRow.friendlyPath(for: "/x/y/z/some.very.long.file.suffix")
        XCTAssertTrue(result.hasPrefix("some.very.long.file.suffix"),
                      "Friendly output must keep the basename for recognizability: \(result)")
    }

    func testFriendlyPathEmptyInput() {
        let result = ScanTreeRow.friendlyPath(for: "")
        XCTAssertEqual(result, "")
    }
}