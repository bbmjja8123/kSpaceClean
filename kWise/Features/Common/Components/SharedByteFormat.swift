// kWise/Features/Common/Components/SharedByteFormat.swift
//
// C-3 freed-bytes formatting —— 全 App 唯一的已释放字节口径（P2 T9 快捷
// 回收次级页退役后，助手卡、叙事头、时间线、粉碎窗各自为政的本地实现
// 统一收到这里）。
import Foundation

/// One shared `ByteCountFormatter` entry point so the canvas hero, the menu
/// bar, the history timeline and the assistant answer cards never disagree
/// on the same freed/occupied byte figure.
enum SharedByteFormat {
    /// `.file` count style favors MB/GB units over the block-count style of
    /// `.binary`; negative inputs are clamped to 0 (never render negative
    /// freed bytes — the honest-zero contract).
    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
}
