// kWise/Features/Common/Components/KWQuickLookPreview.swift
//
// Toolbox QuickLook 接入 (v2.3 Phase 1).
//
// ⚠️ `_QuickLook_SwiftUI` 是私有模块名（Apple 把 .quickLookPreview 放在
// 这里，macOS 11+ 可用）。全 kWise 只允许本文件 import 它——若未来 SDK
// 移除，只需改这一处为 `#if #available(macOS 14,*)` 的公开 API 分支。
// 先例：kSift/UI/Result/GroupDetailView.swift（同仓库同工具链已验证可编）。
import SwiftUI
import _QuickLook_SwiftUI

struct KWQuickLookModifier: ViewModifier {
    @Binding var url: URL?

    func body(content: Content) -> some View {
        content.quickLookPreview($url)
    }
}

extension View {
    /// Binds a system QuickLook sheet to an optional URL. Space-key handling:
    /// attach `KWQuickLookSpaceHandler` once per surface and give rows a
    /// `.previewableFile` environment value or set the binding directly.
    func kwQuickLookPreview(_ url: Binding<URL?>) -> some View {
        modifier(KWQuickLookModifier(url: url))
    }
}

/// Space-key → QuickLook for the row under selection. Attach once per list
/// surface; the closure decides which file the selection maps to.
struct KWQuickLookSpaceHandler: ViewModifier {
    let selectedURL: () -> URL?

    func body(content: Content) -> some View {
        content
            .background(
                Button("QuickLook") { _ = selectedURL() }
                    .keyboardShortcut(.space, modifiers: [])
                    .opacity(0)
                    .accessibilityHidden(true)
            )
    }
}

extension View {
    func kwQuickLookSpaceHandler(selectedURL: @escaping () -> URL?) -> some View {
        modifier(KWQuickLookSpaceHandler(selectedURL: selectedURL))
    }
}
