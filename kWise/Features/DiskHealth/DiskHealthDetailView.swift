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
    /// P3：注入画布 DiskHealthCard 的同一 VM —— 详情 sheet 与卡片共享
    /// 一份状态（修复两实例各自独立拉取、状态可能互相矛盾的问题）。
    @ObservedObject private var viewModel: DiskHealthViewModel
    @EnvironmentObject var appState: AppState

    /// `nil` 时自建（preview / 无图测试）；生产由 RootView 传入画布同款。
    public init(viewModel: DiskHealthViewModel? = nil) {
        _viewModel = .init(wrappedValue: viewModel ?? DiskHealthViewModel())
    }

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
                Text(String(localized: String.LocalizationValue("diskhealth.title")))
                    .font(AppFont.title2)
                    .foregroundStyle(Color.textPrimary)
                Text(headline)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button(String(localized: String.LocalizationValue("diskhealth.refresh"))) {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(viewModel.isLoading)
        }
    }

    private var headline: String {
        switch viewModel.grade {
        case .good:
            return String(localized: String.LocalizationValue("diskhealth.headline.good"))
        case .caution:
            return String(localized: String.LocalizationValue("diskhealth.headline.caution"))
        case .danger:
            return String(localized: String.LocalizationValue("diskhealth.headline.danger"))
        case .unknown:
            return String(localized: String.LocalizationValue("diskhealth.headline.unknown"))
        }
    }

    private var smartSection: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                Text(String(localized: String.LocalizationValue("diskhealth.section.smart")))
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
            return String(localized: String.LocalizationValue("diskhealth.smart.subtitle.verified"))
        case .failing:
            return String(localized: String.LocalizationValue("diskhealth.smart.subtitle.failing"))
        case .notSupported:
            return String(localized: String.LocalizationValue("diskhealth.smart.subtitle.notSupported"))
        case .unknown:
            return String(localized: String.LocalizationValue("diskhealth.smart.subtitle.unknown"))
        }
    }

    private var volumeSection: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(String(localized: String.LocalizationValue("diskhealth.section.volume")))
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