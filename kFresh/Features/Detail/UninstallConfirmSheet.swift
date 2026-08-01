import SwiftUI

/// Confirmation sheet shown after the user taps "卸载" on
/// ``AppDetailView``. Displays the safety summary (icon, name, running
/// warning, MAS hint), a size breakdown (app body + residue toggle +
/// "共释放" total), and the cancel / confirm-undo buttons.
///
/// All size values render via the local `Int64.kbFormatted` helper that
/// wraps `ByteCountFormatter` — kept file-local so the global formatter
/// never gets a divergent shorthand (e.g. "1 KB" vs "1 kB").
struct UninstallConfirmSheet: View {
    let app: InstalledApp
    let residues: [ResidueFile]
    /// Called with the final `includeResidues` value when the user confirms,
    /// so the host can decide whether the trash operation touches the residue
    /// files at all (I1). A `Bool` argument rather than a bare `() -> Void`
    /// makes the "cosmetic toggle" failure mode structurally impossible.
    let onConfirm: (Bool) -> Void
    let onCancel: () -> Void

    /// When the residue scan found files, the user can opt out of including
    /// them in the trash operation. Defaults to true so the toggle reflects
    /// the recommended action.
    @State private var includeResidues = true

    init(app: InstalledApp,
         residues: [ResidueFile],
         onConfirm: @escaping (Bool) -> Void,
         onCancel: @escaping () -> Void) {
        self.app = app
        self.residues = residues
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            header
            summary
            footer
        }
        .padding(AppSpacing.lg)
        .frame(width: 480)
        .background(Color.bgPrimary)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .center, spacing: AppSpacing.md) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("卸载 \(app.displayName)?")
                    .font(AppFont.title3)
                if app.isRunning {
                    Label("App 正在运行，将先退出再卸载", systemImage: "exclamationmark.triangle")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.warning)
                }
                if app.source == .mas {
                    Label("此 App 来自 App Store，可随时重新下载", systemImage: "info.circle")
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            Spacer()
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            row("App 本体", value: app.sizeBytes.kbFormatted)
            if !residues.isEmpty {
                Toggle(isOn: $includeResidues) {
                    HStack {
                        Text("残留文件 (\(residues.count) 项)")
                            .font(AppFont.body)
                        Spacer()
                        Text(residuesTotalSize.kbFormatted)
                            .font(AppFont.monoDigit)
                    }
                }
                .toggleStyle(.switch)
            }
            Divider()
            HStack {
                Text("共释放").font(AppFont.title3)
                Spacer()
                Text(totalFreedSize.kbFormatted)
                    .font(AppFont.title3)
            }
            Label("移入废纸篓（可回滚 30 天）", systemImage: "arrow.uturn.backward")
                .font(AppFont.caption)
                .foregroundStyle(Color.success)
        }
        .padding(AppSpacing.md)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var footer: some View {
        HStack {
            Button("取消", role: .cancel, action: onCancel)
                .buttonStyle(.bordered)
                .keyboardShortcut(.escape)
            Spacer()
            Button("确认卸载", role: .destructive) { onConfirm(includeResidues) }
                .buttonStyle(.borderedProminent)
                .tint(Color.danger)
        }
    }

    // MARK: - Size math

    private var residuesTotalSize: Int64 {
        residues.reduce(0) { $0 + $1.sizeBytes }
    }

    private var totalFreedSize: Int64 {
        app.sizeBytes + (includeResidues ? residuesTotalSize : 0)
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(AppFont.body)
            Spacer()
            Text(value).font(AppFont.monoDigit)
        }
    }
}

// MARK: - Local formatting helper

/// File-local `Int64` byte formatter wrapper. Intentionally kept private to
/// `UninstallConfirmSheet.swift` so the design system's overall byte-display
/// policy stays controlled — adding a global extension would let other
/// modules diverge from this style without a code-review signal.
private extension Int64 {
    var kbFormatted: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
