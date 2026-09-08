// kWise/Features/StartupItems/StartupItemsView.swift
//
// 启动项管理 surface (M2, v2.0 Phase 5). User-level items get a real
// toggle (trash + restore); system-level items render an honest
// "需手动处理" guidance row instead of a fake disabled switch (C-5).
import SwiftUI
import AppKit
import DesignSystem
import PowerScope

struct StartupItemsView: View {
    @StateObject private var viewModel: StartupItemsViewModel
    @State private var pendingDisable: LoginItemEntry?

    /// Injectable for the app root; previews use the shared scope.
    init(scope: (any PowerScopeProviding)? = nil,
         persistence: PersistenceController? = nil) {
        _viewModel = StateObject(wrappedValue: StartupItemsViewModel(
            scope: scope, persistence: persistence
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color.bgPrimary)
        .onAppear { viewModel.startScan() }
        .confirmationDialog(
            "停用启动项？",
            isPresented: Binding(
                get: { pendingDisable != nil },
                set: { if !$0 { pendingDisable = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("停用 “\(pendingDisable?.label ?? "")”") {
                if let entry = pendingDisable { viewModel.disable(entry) }
                pendingDisable = nil
            }
            Button("取消", role: .cancel) { pendingDisable = nil }
        } message: {
            Text("该项目的启动配置将移入废纸篓，可随时在 kWise 中恢复。")
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("启动项")
                    .font(AppFont.title2)
                    .foregroundStyle(Color.textPrimary)
                Text("管理登录时自动启动的代理与守护项")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            if viewModel.isScanning {
                ProgressView().controlSize(.small)
            } else {
                Button("重新扫描") { viewModel.startScan() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(AppSpacing.lg)
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                section(title: "用户启动代理", subtitle: "kWise 可以停用并在 30 天内恢复", items: viewModel.userItems)
                section(title: "系统级项目", subtitle: "位于系统目录，需管理员手动处理", items: viewModel.systemItems)
            }
            .padding(AppSpacing.lg)
        }
    }

    private func section(title: String, subtitle: String, items: [LoginItemEntry]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.title3)
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            if items.isEmpty {
                EmptyStateView(
                    icon: "power",
                    title: "没有发现启动项",
                    subtitle: "该类别下当前没有项目。"
                )
            } else {
                ForEach(items) { entry in
                    row(entry)
                }
            }
        }
    }

    private func row(_ entry: LoginItemEntry) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "power")
                .foregroundStyle(entry.isEnabled ? Color.brandPrimary : Color.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.label)
                    .font(AppFont.body)
                    .foregroundStyle(Color.textPrimary)
                if let program = entry.programPath {
                    Text(program)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if let message = viewModel.messages[entry.id] {
                    Text(message)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.success)
                }
            }
            Spacer()
            controls(for: entry)
        }
        .padding(AppSpacing.md)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
    }

    @ViewBuilder
    private func controls(for entry: LoginItemEntry) -> some View {
        switch entry.scope {
        case .user:
            if entry.isEnabled {
                Button("停用") { pendingDisable = entry }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Button("恢复") { viewModel.enable(entry) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        case .system:
            Button("在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([entry.plistURL])
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Text("需手动处理")
                .font(AppFont.caption)
                .foregroundStyle(Color.textSecondary)
        }
    }
}

#Preview {
    StartupItemsView()
        .frame(width: 720, height: 520)
        .preferredColorScheme(.dark)
}
