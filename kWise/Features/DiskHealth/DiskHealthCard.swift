import SwiftUI
import DesignSystem

/// Small Disk Health card surfaced on the home grid (per Q11).
///
/// Renders the grade badge + a 1-line friendly summary. Tap-through to
/// ``DiskHealthDetailView`` is wired by the parent card grid.
///
/// - SeeAlso: ``DiskHealthDetailView``, `docs/superpowers/plans/2026-08-09-kwise-v1.5-plan.md` Tasks 11 / 12
public struct DiskHealthCard: View {
    @ObservedObject var viewModel: DiskHealthViewModel
    let onOpen: () -> Void

    public init(viewModel: DiskHealthViewModel, onOpen: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onOpen = onOpen
    }

    public var body: some View {
        Button(action: onOpen) {
            GlassPanel {
                VStack(alignment: .leading, spacing: AppSpacing.sm) {
                    HStack {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.brandPrimary)
                        Spacer()
                        badge
                    }
                    Spacer(minLength: 0)
                    Text("磁盘健康")
                        .font(AppFont.title3)
                        .foregroundStyle(Color.textPrimary)
                    Text(summary)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(AppSpacing.md)
            }
        }
        .buttonStyle(.plain)
    }

    private var badge: some View {
        let color: Color = {
            switch viewModel.grade {
            case .good:    return .success
            case .caution: return .warning
            case .danger:  return .danger
            case .unknown: return .textSecondary
            }
        }()
        return Text(viewModel.grade.friendlyTitle)
            .font(AppFont.caption)
            .foregroundStyle(color)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
    }

    /// C-1 friendly name + 1-line source (no raw paths).
    /// C-5 honest FDA split when SMART is unavailable.
    private var summary: String {
        switch viewModel.grade {
        case .good:
            return "S.M.A.R.T. 正常 · 容量充足"
        case .caution:
            if let total = viewModel.volume.totalBytes,
               let free = viewModel.volume.freeBytes,
               total > 0 {
                let usedPercent = Int(Double(total - free) / Double(total) * 100)
                return "已用 \(usedPercent)% · 考虑清理"
            }
            return "已用 ≥ 95% · 考虑清理"
        case .danger:
            return "S.M.A.R.T. 报告异常"
        case .unknown:
            // C-5 honest FDA: drive unreadable without Full Disk Access.
            return "已读 容量 · 需 FDA 读取 SMART"
        }
    }
}

#if DEBUG
#Preview {
    DiskHealthCard(viewModel: DiskHealthViewModel(), onOpen: { })
        .frame(width: 220, height: 140)
        .padding(AppSpacing.md)
}
#endif