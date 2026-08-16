import XCTest
@testable import kWise

/// C-6 (精品 反恐营销) audit guard.
///
/// Phase E Task 15. These tests scan the production source tree for
/// high-pressure copy that the top-cleaners gap analysis identified as
/// "scareware-adjacent" (e.g. "save your Mac", "danger!"). A future
/// commit that re-introduces any banned phrase breaks the build via
/// `swift test`.
///
/// Coverage: the tests themselves walk the filesystem, not a regex
/// over a single string, so they survive non-determinism in the
/// SwiftLint / build pipeline.
@MainActor
final class ScarewareCopyAuditTests: XCTestCase {
    /// Path is hard-coded to the canonical repo layout at writing time
    /// (see CLAUDE.md §2.1). When CI moves to a different sandbox the
    /// path is overridden via the `KWISE_REPO_ROOT` env var.
    private var repoRoot: String {
        if let env = ProcessInfo.processInfo.environment["KWISE_REPO_ROOT"] {
            return env
        }
        // Tests/ lives at kWise/Tests/. Two levels up is the repo root.
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
    }

    /// Sub-trees that count as user-visible marketing surfaces.
    /// (Excludes Tests/, .git/, and any auto-generated outputs.)
    private var auditedDirs: [String] {
        [
            "\(repoRoot)/kWise/Features",
            "\(repoRoot)/kWise/App",
            "\(repoRoot)/kWise/Store",
            "\(repoRoot)/kWise/MenuBar"
        ]
    }

    private var auditedExtensions: Set<String> {
        ["swift", "md"]
    }

    /// High-pressure phrases that C-6 forbids. Insensitive case, anchored
    /// on the phrase only (not the surrounding word). Each entry carries
    /// the banned literal; the file scan looks for substring matches.
    private let bannedPhrases: [String] = [
        "save your mac",
        "virus",
        "malware",
        "trojan",
        "你的 mac 正在",
        "救你的 mac",
        "立即修复",
        "紧急",
        "马上清理",
        "马上修复",
        "崩溃!"
    ]

    // MARK: - Audit walk

    func testNoBannedPhrasesInProductionSources() throws {
        let fm = FileManager.default
        var violations: [String] = []
        for dir in auditedDirs {
            guard let enumerator = fm.enumerator(atPath: dir) else { continue }
            while let path = enumerator.next() as? String {
                // Skip tests, hidden dirs, generated outputs.
                if path.contains("/Tests/") || path.hasPrefix(".") { continue }
                let ext = (path as NSString).pathExtension
                guard auditedExtensions.contains(ext) else { continue }
                let fullPath = "\(dir)/\(path)"
                guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { continue }
                for phrase in bannedPhrases {
                    if content.lowercased().contains(phrase) {
                        violations.append("\(path): contains banned phrase '\(phrase)'")
                    }
                }
            }
        }
        XCTAssertTrue(
            violations.isEmpty,
            "C-6 violations found:\n  - " + violations.joined(separator: "\n  - ")
        )
    }

    /// Sanity: every audited directory actually exists. Guards against
    /// typo'd paths in the auditedDirs list.
    func testAuditedDirsExist() {
        for dir in auditedDirs {
            var isDir: ObjCBool = false
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: dir, isDirectory: &isDir),
                "auditedDirs entry '\(dir)' does not exist"
            )
            XCTAssertTrue(isDir.boolValue, "auditedDirs entry '\(dir)' is not a directory")
        }
    }
}