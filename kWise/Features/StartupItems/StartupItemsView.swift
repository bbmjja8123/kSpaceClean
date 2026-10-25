// kWise/Features/StartupItems/StartupItemsView.swift
//
// 启动项管理 surface（M2）。引擎（Scanner / Toggler / VM）自 v2.0 Phase 5
// 交付，UI 随 P2 T9 工具表面退役 —— 本视图按单一画布 IA 重建：主家 =
// Settings「启动项」分区，「+」菜单提供发现入口。
//
// 红线：用户级项 disable 走 Toggler（plist 移废纸篓 + 30 天历史可还原）；
// 系统级项只读 + 引导文案（诚实拒绝，C-5）。本文件零清理动作之外的新逻辑。
import SwiftUI
import DesignSystem
import PowerScope

struct StartupItemsView: View {
    @StateObject private var viewModel: StartupItemsViewModel
    @ObservedObject private var appScope = AppScope.shared

    /// Injectable VM for previews/tests; default construction otherwise.
    init(viewModel: StartupItemsViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? StartupItemsViewModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color.bgPrimary)
        // P3 UI 冒烟：sheet 根标识（SmokeUITests 按 identifier 查询）。
        .accessibilityIdentifier("startup.sheet")
        .onAppear {
            let scanned = viewModel.userItems.isEmpty
                && viewModel.systemItems.isEmpty
                && viewModel.malformedItems.isEmpty
            if scanned, !viewModel.isScanning {
                viewModel.startScan()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(String(localized: String.LocalizationValue("startup.title")))
                    .font(AppFont.title2)
                    .foregroundStyle(Color.textPrimary)
                Text(String(localized: String.LocalizationValue("startup.subtitle")))
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button {
                viewModel.startScan()
            } label: {
                Label(String(localized: String.LocalizationValue("common.rescan")), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isScanning)
        }
        .padding(AppSpacing.lg)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if appScope.capability.level == .containerOnly {
            // MAS 未授权：用户 LaunchAgents 读不到 —— 诚实空态，不装作扫过。
            scopeGate
        } else if viewModel.isScanning && viewModel.userItems.isEmpty
                    && viewModel.systemItems.isEmpty {
            scanningState
        } else {
            List {
                if !viewModel.userItems.isEmpty {
                    Section(String(localized: String.LocalizationValue("startup.section.user"))) {
                        ForEach(viewModel.userItems) { entry in
                            userRow(entry)
                        }
                    }
                }
                if !viewModel.systemItems.isEmpty {
                    Section(String(localized: String.LocalizationValue("startup.section.system"))) {
                        ForEach(viewModel.systemItems) { entry in
                            systemRow(entry)
                        }
                    }
                }
                if !viewModel.malformedItems.isEmpty {
                    Section(String(localized: String.LocalizationValue("startup.section.malformed"))) {
                        ForEach(viewModel.malformedItems, id: \.id) { item in
                            malformedRow(item)
                        }
                    }
                }
                if viewModel.userItems.isEmpty && viewModel.systemItems.isEmpty
                    && viewModel.malformedItems.isEmpty {
                    Section {
                        Text(String(localized: String.LocalizationValue("startup.empty.none")))
                            .font(AppFont.callout)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var scopeGate: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "lock")
                .font(.system(size: 32))
                .foregroundStyle(Color.warning)
            Text(String(localized: String.LocalizationValue("startup.grant.title")))
                .font(AppFont.title3)
                .foregroundStyle(Color.textPrimary)
            Text(String(localized: String.LocalizationValue("startup.grant.subtitle")))
                .font(AppFont.callout)
                .foregroundStyle(Color.textSecondary)
            Button(String(localized: String.LocalizationValue("startup.grant.button"))) {
                Task { await appScope.grant() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanningState: some View {
        VStack(spacing: AppSpacing.md) {
            ProgressView()
                .controlSize(.large)
            Text(String(localized: String.LocalizationValue("startup.scanning")))
                .font(AppFont.callout)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Rows

    private func userRow(_ entry: LoginItemEntry) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.brandPrimary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.label)
                        .font(AppFont.body)
                        .foregroundStyle(Color.textPrimary)
                    if let hint = viewModel.usageHints[entry.id] {
                        Text(hint)
                            .font(AppFont.caption)
                            .foregroundStyle(Color.textSecondary)
                    } else if let program = entry.programPath {
                        Text(program)
                            .font(AppFont.caption)
                            .foregroundStyle(Color.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer()
                Button(String(localized: String.LocalizationValue("startup.disable.button"))) {
                    viewModel.disable(entry)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if let message = viewModel.messages[entry.id] {
                Text(message)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private func systemRow(_ entry: LoginItemEntry) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textSecondary)
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
                }
                Spacer()
                // 系统级项：只读 —— Toggler 会诚实拒绝，这里不给假开关。
                Text(String(localized: String.LocalizationValue("startup.system.manualGuidance")))
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private func malformedRow(_ item: LaunchPlistParser.MalformedItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.plistURL.lastPathComponent)
                .font(AppFont.body)
                .foregroundStyle(Color.textPrimary)
            Text(item.reason)
                .font(AppFont.caption)
                .foregroundStyle(Color.warning)
        }
        .padding(.vertical, AppSpacing.xs)
    }
}
