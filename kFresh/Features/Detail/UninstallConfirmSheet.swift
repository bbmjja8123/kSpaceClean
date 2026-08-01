import SwiftUI

/// Placeholder for the uninstall confirmation sheet.
///
/// Task 4 replaces the body with the full safety-check + size-breakdown +
/// confirmation flow. The `app` / `residues` payload and the `onConfirm` /
/// `onCancel` callbacks are already the final interface so ``AppDetailView``
/// can wire the sheet without rework.
struct UninstallConfirmSheet: View {
    let app: InstalledApp
    let residues: [ResidueFile]
    let onConfirm: () -> Void
    let onCancel: () -> Void

    init(app: InstalledApp,
         residues: [ResidueFile],
         onConfirm: @escaping () -> Void,
         onCancel: @escaping () -> Void) {
        self.app = app
        self.residues = residues
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            Text("卸载 \(app.displayName)?")
                .font(AppFont.title2)
            Text("Stub — Task 4 完成确认流程")
                .font(AppFont.body)
                .foregroundStyle(Color.textSecondary)
            HStack(spacing: AppSpacing.md) {
                Button("取消") { onCancel() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape)
                Button("确认卸载") { onConfirm() }
                    .buttonStyle(.destructive)
            }
        }
        .padding(AppSpacing.xl)
        .frame(width: 400)
    }
}
