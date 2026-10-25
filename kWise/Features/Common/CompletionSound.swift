// kWise/Features/Common/CompletionSound.swift
//
// Task 2 清理完成时刻 — 完成音效。系统音 Glass：零资产、零网络。
// 触发点在 RootView（cleanupViewModel.$lastOutcome，统一链三入口共达）；
// 用户可在设置关闭（UserPreferences.playCompletionSound，默认开）。
import AppKit

/// 清理完成音效（Task 2 完成时刻）。系统音 Glass——零资产、零网络。
/// 用户可在设置关闭（playCompletionSound）。
enum CompletionSound {
    /// `enabled == false` 时是纯 no-op（不加载、不播放）。
    static func playIfEnabled(_ enabled: Bool) {
        guard enabled else { return }
        NSSound(named: NSSound.Name("Glass"))?.play()
    }
}
