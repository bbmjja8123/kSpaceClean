import SwiftUI

/// Row view for a single uninstall record in the History list.
///
/// Type name is `HistoryRowView` (not `HistoryRow`) to avoid clashing
/// with the read-only `HistoryRow` defined in
/// `Features/AppList/HistoryRow.swift` which surfaces restorable
/// records beneath the app list. Both types live in the same module,
/// so Swift would reject a redeclaration.
struct HistoryRowView: View {
    let record: UninstallRecord
    let restoreState: HistoryViewModel.RestoreState
    let onRestore: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            VStack(alignment: .leading, spacing: AppSpacing.xs / 2) {
                Text(record.appName)
                    .font(AppFont.body)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.textPrimary)

                Text(record.uninstalledAt, style: .date)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)

                Text("\(record.appSize.kbFormatted) · \(record.residueCount) 项残留")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary.opacity(0.7))
            }
            Spacer()
            actionButton
        }
        .padding(.vertical, AppSpacing.xs)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch restoreState {
        case .restoring(let id) where id == record.id:
            ProgressView().scaleEffect(0.7)
        case .restored(let id) where id == record.id:
            Label("已恢复", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(AppFont.caption)
                .foregroundStyle(Color.success)
        case .failed(let id, let msg) where id == record.id:
            Label(msg, systemImage: "exclamationmark.triangle")
                .labelStyle(.titleAndIcon)
                .font(AppFont.caption)
                .foregroundStyle(Color.danger)
                .lineLimit(1)
        default:
            Button("恢复", action: onRestore)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }
}

// MARK: - Helpers

/// File-local byte formatter. Kept private to avoid leaking a global
/// `Int64.formattedAsFileSize` extension into the module — mirrors the
/// pattern used in `Features/Detail/UninstallConfirmSheet.swift`.
private extension Int64 {
    var kbFormatted: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}