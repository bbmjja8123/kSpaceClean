// kWise/Tests/ResidueExplainerTests.swift
import XCTest
import AppCatalogCore
@testable import kWise

final class ResidueExplainerTests: XCTestCase {
    private func residue(_ type: ResidueType, _ path: String) -> ResidueFile {
        ResidueFile(url: URL(fileURLWithPath: path), type: type, sizeBytes: 100,
                    confidence: 0.9, description: "")
    }

    func testPreferencesExplanation() {
        let text = ResidueExplainer.explain(
            residue(.preferences, "/Users/x/Library/Preferences/com.test.app.plist"),
            appName: "TestApp")
        XCTAssertTrue(text.contains("偏好设置"), text)
    }

    func testCachesExplanation() {
        let text = ResidueExplainer.explain(
            residue(.caches, "/Users/x/Library/Caches/com.test.app"),
            appName: "TestApp")
        XCTAssertTrue(text.contains("缓存"), text)
    }

    func testLaunchAgentExplanation() {
        let text = ResidueExplainer.explain(
            residue(.launchAgent, "/Users/x/Library/LaunchAgents/com.test.app.plist"),
            appName: "TestApp")
        XCTAssertTrue(text.contains("启动") || text.contains("自启动"), text)
    }

    func testUnknownPatternGetsGenericText() {
        let text = ResidueExplainer.explain(
            residue(.plugin, "/Users/x/Library/Whatever/odd.bin"),
            appName: "TestApp")
        XCTAssertTrue(text.contains("支撑文件") || text.contains("文件"), text)
    }

    func testChatPathMention() {
        let text = ResidueExplainer.explain(
            residue(.appSupport, "/Users/x/Library/Application Support/com.tencent.xinWeChat/Message"),
            appName: "WeChat")
        XCTAssertTrue(text.contains("聊天") || text.contains("消息"), text)
    }
}
