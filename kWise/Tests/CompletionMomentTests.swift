// kWise/Tests/CompletionMomentTests.swift
//
// Task 2 清理完成时刻 — 数字滚动 + 音效偏好。
// - 旧 preferences.json（无 playCompletionSoundRaw）必须照常解码，默认开
//   （similarityPresetRaw 的 Optional-raw 先例）。
// - 显式关掉后 round-trip 不回弹为默认。
// - Reduce Motion 下滚动直接落终值（静态钉住）；负字节钳 0（诚实零契约，
//   与 QuickCleanResultCopy.doneTitle 的钳 0 口径一致）。
import XCTest
@testable import kWise

final class CompletionMomentTests: XCTestCase {
    // 旧 preferences.json 无新字段 → 解码必须成功（similarityPresetRaw 先例）。
    func testLegacyJSONDecodesWithSoundDefaultOn() throws {
        let legacy = #"{"largeFileThreshold":104857600,"ignoredPaths":[],"defaultCleanAction":"trash","confirmHighRisk":true,"historyRetentionDays":30,"launchAtLogin":false,"showMenuBarDiskUsage":true,"scanSpeed":"medium","notifyAfterCleanup":false,"shredPasses":1}"#
        let prefs = try JSONDecoder().decode(UserPreferences.self, from: Data(legacy.utf8))
        XCTAssertTrue(prefs.playCompletionSound, "默认开（用户可关）")
    }

    func testExplicitOffRoundTrips() throws {
        var prefs = UserPreferences()
        prefs.playCompletionSound = false
        let data = try JSONEncoder().encode(prefs)
        let back = try JSONDecoder().decode(UserPreferences.self, from: data)
        XCTAssertFalse(back.playCompletionSound)
    }

    func testRollerNeverNegativeAndFinishesAtTarget() {
        let roller = FreedBytesRoller(bytes: 5_000_000_000, measured: true)
        // 纯逻辑侧：RM 开启时 displayed 直接落到目标值（无 0→N 动画）。
        XCTAssertTrue(FreedBytesRoller.jumpsToFinalWhenReduceMotion)
        XCTAssertEqual(roller.bytes, 5_000_000_000)
        XCTAssertTrue(roller.measured)
        // 诚实零契约：负字节钳到 0 —— 绝不滚动出负的已释放量。
        XCTAssertEqual(FreedBytesRoller.clamped(-5), 0)
        XCTAssertEqual(FreedBytesRoller.clamped(1_500_000_000), 1_500_000_000)
    }
}
