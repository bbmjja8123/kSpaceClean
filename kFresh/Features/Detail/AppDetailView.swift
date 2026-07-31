import SwiftUI

struct AppDetailView: View {
    let app: InstalledApp
    @StateObject private var viewModel: DetailViewModel
    @EnvironmentObject private var coordinator: AppCoordinator

    init(app: InstalledApp) {
        self.app = app
        _viewModel = StateObject(wrappedValue: DetailViewModel(app: app, coordinator: AppCoordinator()))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroSection
                sizeSection
                    .cardStyle()
                if !app.residues.isEmpty {
                    ResidueSectionView(residues: app.residues, selectedResidues: $viewModel.selectedResidues)
                }
                Spacer()
                uninstallButton
            }
            .padding(24)
        }
        .sheet(isPresented: $viewModel.showConfirmSheet) {
            UninstallConfirmSheet(viewModel: viewModel)
        }
        .overlay(alignment: .bottom) {
            if viewModel.showUninstallToast {
                uninstallToast
            } else if let restoreError = viewModel.lastRestoreError {
                // I3a: persistent retry banner replaces the countdown toast
                // when the last `restore()` attempt failed. Tapping the
                // button re-invokes `restore()`, which uses the still-
                // preserved `lastUninstallRecord` to retry against the
                // intact backup directory. The toast is suppressed via
                // `showUninstallToast = false` (set by the success branch
                // of `restore`); until then, this banner is the user's
                // only affordance to retry the restore.
                restoreErrorBanner(for: restoreError)
            }
        }
    }

    private var heroSection: some View {
        HStack(spacing: 16) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(app.displayName)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    if app.isProtected {
                        Label("系统", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundColor(.warning)
                    }
                }
                Text("\(app.bundleID) • v\(app.version)")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
                sourceLabel
                analysisBadge
            }
        }
    }

    @ViewBuilder private var sourceLabel: some View {
        switch app.source {
        case .mas:
            Label("来自 App Store", systemImage: "bag")
                .font(.caption)
                .foregroundColor(.brandSecondary)
        case .userInstalled:
            Label("第三方 App", systemImage: "arrow.down.app")
                .font(.caption)
                .foregroundColor(.textSecondary)
        case .system:
            Label("系统组件", systemImage: "gearshape.2")
                .font(.caption)
                .foregroundColor(.danger)
        case .appleBuiltIn:
            Label("Apple 内置", systemImage: "applelogo")
                .font(.caption)
                .foregroundColor(.textSecondary)
        case .unknown:
            EmptyView()
        }
    }

    @ViewBuilder private var analysisBadge: some View {
        if let action = viewModel.analysis?.suggestedAction {
            HStack(spacing: 4) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.caption)
                switch action {
                case "never_used":
                    Text("很少使用")
                        .font(.caption)
                case "uninstall":
                    Text("超过 90 天未使用")
                        .font(.caption)
                default:
                    EmptyView()
                }
            }
            .foregroundColor(action == "never_used" ? Color.warning : .danger)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((action == "never_used" ? Color.warning : Color.danger).opacity(0.12))
            .cornerRadius(6)
        }
    }

    private var sizeSection: some View {
        HStack(spacing: 40) {
            VStack(spacing: 4) {
                Text(app.sizeFormatted)
                    .font(.system(size: 24, weight: .bold))
                Text("App 本体")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            VStack(spacing: 4) {
                Text(ByteCountFormatter.string(fromByteCount: app.residues.reduce(0) { $0 + $1.sizeBytes }, countStyle: .file))
                    .font(.system(size: 24, weight: .bold))
                Text("残留文件")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if app.isRunning {
                Label("运行中", systemImage: "play.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }

    private var uninstallButton: some View {
        Button(action: {
            viewModel.showConfirmSheet = true
        }) {
            HStack {
                Image(systemName: "trash")
                Text("卸载 \(app.displayName)")
            }
        }
        .buttonStyle(.destructive)
        .controlSize(.large)
        .disabled(app.isProtected)
    }

    private var uninstallToast: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("已卸载 \(app.displayName)")
                .fontWeight(.medium)
            Spacer()
            Button("撤销 (\(viewModel.undoRemainingSeconds)s)") {
                Task { await viewModel.restore() }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding()
    }

    /// I3a: persistent banner shown when the last `restore()` attempt
    /// failed. Distinct from the 10-second undo countdown toast — this
    /// banner stays on screen until either the user retries successfully
    /// or they navigate away. The retry button re-invokes `restore()`,
    /// which uses the still-preserved `lastUninstallRecord` against the
    /// intact backup directory (see `TrashMover.restore` `.restoreResidueFailed`
    /// branch — the backup is never cleaned up on a failed restore).
    private func restoreErrorBanner(for error: TrashError) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("恢复部分失败")
                    .fontWeight(.medium)
                Text(restoreErrorMessage(for: error))
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            Spacer()
            Button("重试") {
                Task { await viewModel.restore() }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding()
    }

    /// Maps a `TrashError` to a user-readable message for the retry banner.
    /// The soft cases (which the user can act on) get specific copy; the
    /// hard cases fall back to a generic "unexpected error" so we don't
    /// leak OS internals.
    private func restoreErrorMessage(for error: TrashError) -> String {
        switch error {
        case .restoreResidueFailed:
            return "残留文件未完全恢复 — 备份已保留，可重试"
        case .restoreRefusedOverwrite:
            return "原始路径已被占用，无法恢复"
        case .trashedItemMissing:
            return "原 App 已在废纸篓中消失，无法恢复"
        case .trashFailed, .terminateFailed, .protected, .auditLogFailed:
            return "意外错误，请稍后重试"
        }
    }
}
