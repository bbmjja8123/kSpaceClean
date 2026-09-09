// kWise/Features/Toolbox/ToolTabBar.swift
//
// Tab 化工具箱 (v2.5) — 顶部 Tab 行：固定的「工具箱」根 Tab + 每个打开
// 的工具一个可关闭 Tab。浏览器式文档模型：Tab 常驻、工具状态不丢失。
import SwiftUI
import DesignSystem

/// 顶部 Tab 行。`tabs` 为打开的工具（顺序即创建顺序）；
/// 「工具箱」根 Tab 固定在最左，永远不可关闭。
struct ToolTabBar: View {
    let tabs: [AppState.ToolTab]
    let activeToolTabID: UUID?
    /// 当前正文是否正显示某个工具页（否则 Tab 不高亮，rail 页优先）。
    let isToolPageActive: Bool
    let onActivate: (UUID) -> Void
    let onClose: (UUID) -> Void
    let onToolbox: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            rootTab
            ForEach(tabs) { tab in
                toolTab(tab)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.xs)
        .background(Color.bgSecondary.opacity(0.7))
    }

    /// 根 Tab —— 永远存在、不可关闭；激活条件：当前不在任何工具页。
    private var rootTab: some View {
        tabLabel(
            icon: "square.grid.2x2",
            title: "工具箱",
            isActive: isToolPageActive == false,
            onClose: nil,
            action: onToolbox
        )
    }

    private func toolTab(_ tab: AppState.ToolTab) -> some View {
        tabLabel(
            icon: tab.icon,
            title: tab.title,
            isActive: isToolPageActive && activeToolTabID == tab.id,
            onClose: { onClose(tab.id) },
            action: { onActivate(tab.id) }
        )
    }

    private func tabLabel(icon: String,
                          title: String,
                          isActive: Bool,
                          onClose: (() -> Void)?,
                          action: @escaping () -> Void) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(isActive ? .brandPrimary : .textSecondary)
            Text(title)
                .font(AppFont.callout)
                .foregroundColor(isActive ? .textPrimary : .textSecondary)
                .lineLimit(1)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.textSecondary)
                }
                .buttonStyle(.plain)
                .help("关闭此工具页")
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .padding(.vertical, AppSpacing.xs)
        .background(isActive ? Color.brandPrimary.opacity(0.15) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .animation(KFAnimation.easeInOut, value: isActive)
    }
}

#if DEBUG
struct ToolTabBar_Previews: PreviewProvider {
    static var previews: some View {
        let appState = AppState()
        appState.openToolTab(.duplicates)
        appState.openToolTab(.largeOld)
        return ToolTabBar(
            tabs: appState.toolTabs,
            activeToolTabID: appState.activeToolTabID,
            isToolPageActive: true,
            onActivate: { appState.activateToolTab($0) },
            onClose: { appState.closeToolTab($0) },
            onToolbox: {}
        )
        .frame(width: 700)
        .preferredColorScheme(.dark)
    }
}
#endif
