// kWise/Features/Toolbox/ToolboxView.swift
//
// Toolbox (v2.0 Phase 2) — card grid for the deep-cleaning modules.
//
// The icon rail stays fixed at six entries; everything else lives here.
// This is the parity surface for CleanMyMac X's Applications / Files
// columns and BuhoCleaner's feature grid.
import SwiftUI
import DesignSystem

struct ToolboxView: View {
    @EnvironmentObject var appState: AppState

    private let columns = [
        GridItem(.adaptive(minimum: 180), spacing: AppSpacing.md)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                Text("工具箱")
                    .font(AppFont.title2)
                    .foregroundStyle(Color.textPrimary)

                LazyVGrid(columns: columns, spacing: AppSpacing.md) {
                    ToolboxCard(
                        icon: "app.badge.checkmark",
                        title: "应用卸载",
                        subtitle: "应用 + 残留一并清除",
                        destination: .appUninstall
                    )
                    ToolboxCard(
                        icon: "doc.on.doc",
                        title: "重复文件",
                        subtitle: "智能挑选保留原件",
                        destination: .duplicates
                    )
                    ToolboxCard(
                        icon: "arrow.up.left.and.arrow.down.right",
                        title: "大文件",
                        subtitle: "找出占空间的旧文件",
                        destination: .largeOld
                    )
                    ToolboxCard(
                        icon: "photo.on.rectangle",
                        title: "照片清理",
                        subtitle: "缓存与相似照片",
                        destination: .photoClean
                    )
                    ToolboxCard(
                        icon: "document.badge.ellipsis",
                        title: "文件粉碎",
                        subtitle: "覆写后不可恢复",
                        destination: .shredder
                    )
                    ToolboxCard(
                        icon: "power",
                        title: "启动项",
                        subtitle: "登录项与启动代理",
                        destination: .startupItems
                    )
                    ToolboxCard(
                        icon: "circle.hexagongrid.circle",
                        title: "空间地图",
                        subtitle: "可视化磁盘占用",
                        destination: .spaceMap
                    )
                    ToolboxCard(
                        icon: "wrench.and.screwdriver",
                        title: "系统维护",
                        subtitle: "维护任务与引导",
                        destination: .maintenance
                    )
                }
            }
            .padding(AppSpacing.lg)
        }
        .background(Color.bgPrimary)
    }
}

/// One toolbox card. Hover lifts (AppShadow token), press compresses with
/// the mandated animation tokens — no ad-hoc durations.
struct ToolboxCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let destination: AppState.NavigationItem

    @EnvironmentObject var appState: AppState
    @State private var isHovering = false

    var body: some View {
        Button {
            appState.navigation = destination
        } label: {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 26))
                    .foregroundStyle(Color.brandPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(title)
                    .font(AppFont.title3)
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(AppSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
            .appShadow(isHovering ? AppShadow.md : AppShadow.sm)
            .scaleEffect(isHovering ? KFAnimation.scaleHover : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(KFAnimation.easeInOut) {
                isHovering = hovering
            }
        }
    }
}

#Preview {
    ToolboxView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
