// kWise/Tests/ResidueExplainerTests.swift
import XCTest
import AppCatalogCore
@testable import kWise

final class ResidueExplainerTests: XCTestCase {
    private func residue(_ type: ResidueType, _ path: String) -> ResidueFile {
        ResidueFile(url: URL(fileURLWithPath: path), type: type, sizeBytes: 100,
                    confidence: 0.9, description: "")
    }

    private func mapping(name: String, bundleID: String) -> ZhAppMapping {
        ZhAppMapping(displayName: name, bundleID: bundleID,
                     verifiedAt: Date(), verifiedBy: "manual",
                     sources: ["manual"], deprecated: false)
    }

    // MARK: - explain(_:appName:)

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

    /// `.plugin` 有专属文案（不是 default 兜底）。
    func testPluginExplanation() {
        let text = ResidueExplainer.explain(
            residue(.plugin, "/Users/x/Library/Whatever/odd.bin"),
            appName: "TestApp")
        XCTAssertTrue(text.contains("插件"), text)
    }

    /// `.other` 无专属规则 → 真正走 default 兜底分支（review Important #1）。
    func testDefaultFallbackForUnknownType() {
        let text = ResidueExplainer.explain(
            residue(.other, "/Users/x/Library/Whatever/odd.bin"),
            appName: "TestApp")
        XCTAssertTrue(text.contains("支撑文件"), text)
        XCTAssertTrue(text.contains("TestApp"), text)
    }

    /// `.appleScript` 专属文案（review Minor #7）。
    func testAppleScriptExplanation() {
        let text = ResidueExplainer.explain(
            residue(.appleScript, "/Users/x/Library/Application Scripts/com.test.app"),
            appName: "TestApp")
        XCTAssertTrue(text.contains("自动化脚本"), text)
    }

    func testChatPathMention() {
        let text = ResidueExplainer.explain(
            residue(.appSupport, "/Users/x/Library/Application Support/com.tencent.xinWeChat/MessageStore"),
            appName: "WeChat")
        XCTAssertTrue(text.contains("聊天") || text.contains("消息"), text)
    }

    /// review Minor #4：普通含 "message" 的目录名不得误触发聊天数据警告。
    func testGenericMessageDirectoryDoesNotTriggerChatWarning() {
        let text = ResidueExplainer.explain(
            residue(.appSupport, "/Users/torsys/Library/Application Support/com.otherapp/SavedMessages"),
            appName: "OtherApp")
        XCTAssertFalse(text.contains("聊天记录数据"), text)
    }

    // MARK: - ownerHint(forLabel:mappings:)

    /// review Important #2a：ownerHint 持久化测试（原 /tmp harness 验证转正）。
    func testOwnerHintMatchesMapping() {
        let mappings = [mapping(name: "微信", bundleID: "com.tencent.xinWeChat")]
        let hint = ResidueExplainer.ownerHint(
            forLabel: "com.tencent.xinWeChat.helper", mappings: mappings)
        XCTAssertEqual(hint, "这是「微信」的后台助手")
    }

    func testOwnerHintReturnsNilWhenNoMatch() {
        let mappings = [mapping(name: "微信", bundleID: "com.tencent.xinWeChat")]
        let hint = ResidueExplainer.ownerHint(forLabel: "zzz-unknown", mappings: mappings)
        XCTAssertNil(hint)
    }

    /// review Important #2b：清洗后超短（<3 字符）的 label 直接返回 nil，防误报。
    func testOwnerHintReturnsNilForVeryShortLabel() {
        let mappings = [mapping(name: "微信", bundleID: "com.tencent.xinWeChat")]
        XCTAssertNil(ResidueExplainer.ownerHint(forLabel: "x", mappings: mappings))
        XCTAssertNil(ResidueExplainer.ownerHint(forLabel: "helper", mappings: mappings))
    }
}
