import SwiftUI

struct UninstallConfirmSheet: View {
    @ObservedObject var viewModel: DetailViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(nsImage: viewModel.app.icon)
                    .resizable()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("卸载 \(viewModel.app.displayName)?")
                    .font(.title2)
                    .fontWeight(.bold)

                safetyChecks
            }

            Divider()

            // Size breakdown
            VStack(spacing: 8) {
                sizeRow(label: "App 本体", size: viewModel.app.sizeBytes)
                sizeRow(label: "残留文件 (\(viewModel.selectedResidues.count) 项)", size: viewModel.app.residues.filter { viewModel.selectedResidues.contains($0.id) }.reduce(0) { $0 + $1.sizeBytes })
                Divider()
                sizeRow(label: "共释放", size: viewModel.totalFreedBytes, bold: true)
                    .foregroundColor(.green)
            }

            // Notes
            VStack(alignment: .leading, spacing: 4) {
                Label("移入废纸篓（可回滚 30 天）", systemImage: "checkmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if viewModel.app.isRunning {
                    Label("App 正在运行，将先退出再卸载", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                if viewModel.app.source == .mas {
                    Label("此 App 来自 App Store，可重新下载", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            HStack(spacing: 12) {
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
                    .keyboardShortcut(.escape)

                Button("确认卸载") {
                    Task {
                        await viewModel.uninstall()
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(viewModel.isUninstalling)
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private var safetyChecks: some View {
        VStack(alignment: .leading, spacing: 4) {
            SafetyCheckRow(icon: "checkmark.shield", text: "安全检查", passed: !viewModel.app.isProtected)
            SafetyCheckRow(icon: "power", text: "运行检查", passed: !viewModel.app.isRunning)
            SafetyCheckRow(icon: "doc.text.magnifyingglass", text: "残留预扫描", passed: !viewModel.app.residues.isEmpty)
        }
        .padding(8)
    }

    private func sizeRow(label: String, size: Int64, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(bold ? .headline : .subheadline)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                .font(bold ? .headline : .subheadline)
                .fontWeight(bold ? .bold : .regular)
        }
    }
}

struct SafetyCheckRow: View {
    let icon: String
    let text: String
    let passed: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(passed ? .green : .red)
                .font(.system(size: 12))
            Text(text)
                .font(.caption)
                .foregroundColor(passed ? .primary : .red)
        }
    }
}
