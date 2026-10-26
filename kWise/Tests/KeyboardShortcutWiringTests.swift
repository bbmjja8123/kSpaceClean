// kWise/Tests/KeyboardShortcutWiringTests.swift
import XCTest

/// Source-level wiring audit for the rail keyboard shortcuts (Task 4).
/// Follows the existing source-grep audit convention (see
/// `SurfaceRetirementAuditTests`): the assertions read the Swift sources
/// off disk relative to this file, so a refactor that silently drops the
/// ⌘1/2/3 / ⌘, declarations or the RootView install fails the suite.
final class KeyboardShortcutWiringTests: XCTestCase {
    private func source(_ relative: String) -> String {
        let fileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // kWise/
            .appendingPathComponent(relative)
        // `URL.appendingPathComponent` is non-optional, so no `flatMap` —
        // read directly and degrade to "" (assertions then fail loudly).
        return (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
    }

    func testRailShortcutsDeclared() {
        let src = source("Features/Common/KeyboardShortcuts.swift")
        for key in ["1", "2", "3", ","] {
            XCTAssertTrue(src.contains(".keyboardShortcut(\"\(key)\""),
                          "缺少 ⌘\(key) 快捷键声明")
        }
    }

    func testRootViewInstallsRailShortcuts() {
        XCTAssertTrue(source("App/RootView.swift").contains("railKeyboardShortcuts"))
    }
}
