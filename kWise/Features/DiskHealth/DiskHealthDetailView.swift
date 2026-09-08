import SwiftUI
import DesignSystem

/// Full Disk Health detail surface (Phase D Task 12).
///
/// Two sections: S.M.A.R.T. status + Volume diagnostics. Falls back to a
/// "unavailable" banner on Apple Silicon when `diskutil info` does not
/// surface SMART data — C-5 (精品 honest FDA boundary) shows the user
/// exactly which signals are real and which need Full Disk Access.
///
/// - SeeAlso: ``SMARTReader``, ``VolumeDiagnostics``,
///   `docs/superpowers/plans/2026-08-09-kwise-v1.5-plan.md` Task 12
public struct DiskHealthDetailView: View {
    @StateObject private var viewModel = DiskHealthViewModel()
    @EnvironmentObject var appState: AppState

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            headerView
            smartSection
            volumeSection
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary)
        .task {
            await viewModel.refresh()
        }
    }

    // MARK: - Sub-views

    private var headerView: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("磁盘健康")
                    .font(AppFont.title2)
                    .foregroundStyle(Color.textPrimary)
                Text(headline)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button("刷新") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isLoading)
        }
    }

    private var headline: String {
        switch viewModel.grade {
        case .good:    return "一切正常"
        case .caution: return "容量偏高，建议清理"
        case .danger:  return "S.M.A.R.T. 报告异常 — 备份并联系 Apple 支持"
        case .unknown: return "无法读取 S.M.A.R.T. 数据 — 通常需要完整磁盘访问"
        }
    }

    private var smartSection: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text("S.M.A.R.T. 状态")
                    .font(AppFont.title3)
                    .foregroundStyle(Color.textPrimary)
                HStack {
                    smartBadge
                    Spacer()
                    if !viewModel.smart.deviceNode.isEmpty {
                        Text(viewModel.smart.deviceNode)
                            .font(AppFont.caption)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
                Text(smartSubtitle)
                    .font(AppFont.body)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.md)
        }
    }

    private var smartBadge: some View {
        let color: Color = {
            switch viewModel.grade {
            case .good:    return .success
            case .caution: return .warning
            case .danger:  return .danger
            case .unknown: return .textSecondary
            }
        }()
        return Text(viewModel.smart.status.friendlyTitle)
            .font(AppFont.title3)
            .foregroundStyle(color)
    }

    private var smartSubtitle: String {
        switch viewModel.smart.status {
        case .verified:
            return "存储控制器自检通过。无需立即操作。"
        case .failing:
            return "存储控制器自检失败。建议立即备份重要数据并联系 Apple 支持。"
        case .notSupported:
            return "当前控制器不提供 S.M.A.R.T. 数据。"
        case .unknown:
            return "未读取到 S.M.A.R.T. 数据。在 Apple Silicon 上常见；可授予完整磁盘访问以获取更详细信息。"
        }
    }

    private var volumeSection: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text("卷诊断")
                    .font(AppFont.title3)
                ForEach(viewModel.volume.diagnostics) { diagnostic in
                    rowFor(diagnostic)
                    Divider().background(Color.separatorColor.opacity(0.5))
                }
            }
            .padding(AppSpacing.md)
        }
    }

    private func rowFor(_ diagnostic: VolumeDiagnostic) -> some View {
        HStack {
            Text(diagnostic.title)
                .font(AppFont.body)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Text(prettyValue(for: diagnostic))
                .font(AppFont.monoDigit)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.vertical, AppSpacing.xs)
    }

    private func prettyValue(for diagnostic: VolumeDiagnostic) -> String {
        switch diagnostic.id {
        case .totalBytes, .freeBytes, .purgeableBytes:
            if let bytes = Int64(diagnostic.detail) {
                return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            }
            return diagnostic.detail
        default:
            return diagnostic.detail
        }
    }
}

#if DEBUG
#Preview {
    DiskHealthDetailView()
        .environmentObject(AppState())
        .frame(width: 720, height: 600)
}
#endif