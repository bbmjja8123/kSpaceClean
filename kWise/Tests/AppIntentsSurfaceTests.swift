// kWise/Tests/AppIntentsSurfaceTests.swift
//
// Task 10 — App Shortcuts 全家桶表面测试：
// ① Spotlight/Siri 免配置入口必须注册（AppShortcutsProvider）；
// ② 三个核心 intent 必须全部上架；
// ③ 清理意图必须用 dialog 汇报释放字节（不能静默）；
// ④ 零网络审计（项目红线）。
import XCTest

final class AppIntentsSurfaceTests: XCTestCase {
    private func source(_ relative: String) -> String {
        // #filePath 在 kWise/Tests/ 下——先退到 kWise/ 再拼相对路径
        // （Intents/ 与 Tests/ 是兄弟目录）。
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // kWise/
        return (try? String(contentsOf: root.appendingPathComponent(relative),
                            encoding: .utf8)) ?? ""
    }

    func testShortcutsProviderRegistered() {
        let src = source("Intents/KlarisShortcuts.swift")
        XCTAssertTrue(src.contains("AppShortcutsProvider"), "Spotlight/Siri 入口必须注册")
        XCTAssertTrue(src.contains("ScanIntent") && src.contains("CleanCacheIntent")
                      && src.contains("AskStatusIntent"), "三个核心 intent 上架")
        // 零网络审计（项目红线）。
        XCTAssertFalse(src.contains("URLSession"))
    }

    func testCleanIntentReportsDialog() {
        XCTAssertTrue(source("Intents/ScanIntent.swift").contains("ProvidesDialog"),
                      "清理意图必须用 dialog 汇报释放字节（不能静默）")
    }
}
