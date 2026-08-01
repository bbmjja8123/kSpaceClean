import SwiftUI

/// Read-only row for a recent uninstall record shown beneath the app list in
/// the "recently uninstalled" section. Restore is owned by the History flow;
/// this row only surfaces that a record exists and is restorable.
struct HistoryRow: View {
    let record: UninstallRecord

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: "app.badge.checkmark")
                .font(AppFont.title3)
                .foregroundStyle(Color.brandSecondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.appName)
                    .font(AppFont.body.weight(.medium))
                    .foregroundStyle(Color.textPrimary)
                Text("\(record.bundleID) · \(record.uninstalledAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            if !record.isRestored {
                Label("可恢复", systemImage: "arrow.uturn.backward")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.success)
            } else {
                Text("已恢复")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }
}
