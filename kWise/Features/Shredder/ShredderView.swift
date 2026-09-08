// kWise/Features/Shredder/ShredderView.swift
//
// 文件粉碎 surface (M6, v2.0 Phase 5). Consent chain: NSOpenPanel grant →
// staging review → DELETE-token confirmation (DangerousConfirmDialog) →
// overwrite + verify + rename + trash. The tooltip is honest about SSD
// (C-5): one pass is sufficient, multi-pass is opt-in for spinning disks.
import SwiftUI
import DesignSystem
import PowerScope

struct ShredderView: View {
    @StateObject private var viewModel: ShredderViewModel
    @State private var showConfirm = false

    init(scope: (any PowerScopeProviding)? = nil,
         persistence: PersistenceController? = nil) {
        _viewModel = StateObject(wrappedValue: ShredderViewModel(
            scope: scope, persistence: persistence
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color.bgPrimary)
        .sheet(isPresented: $showConfirm) {
            DangerousConfirmDialog(
                onConfirm: {
                    showConfirm = false
                    viewModel.shredStaged()
                },
                onCancel: { showConfirm = false }
            )
            .frame(width: 360, height: 320)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text("文件粉碎")
                    .font(AppFont.title2)
                    .foregroundStyle(Color.textPrimary)
                Text("覆写文件内容后移入废纸篓，确保敏感文件无法恢复")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button("添加文件…") { viewModel.pickFiles() }
                .buttonStyle(.bordered)
                .disabled(viewModel.isShredding)
        }
        .padding(AppSpacing.lg)
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            if viewModel.stagedURLs.isEmpty {
                EmptyStateView(
                    icon: "document.badge.ellipsis",
                    title: "尚未添加文件",
                    subtitle: "添加需要安全删除的文件。文件内容将被覆写，此操作不可逆。"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.stagedURLs, id: \.self) { url in
                        HStack {
                            Image(systemName: "doc")
                                .foregroundStyle(Color.brandPrimary)
                            Text(url.lastPathComponent)
                                .font(AppFont.body)
                                .foregroundStyle(Color.textPrimary)
                            Spacer()
                            Text(Self.formatBytes(size(of: url)))
                                .font(AppFont.caption)
                                .foregroundStyle(Color.textSecondary)
                            if !viewModel.isShredding {
                                Button {
                                    viewModel.remove(url)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(AppFont.caption)
                                        .foregroundStyle(Color.textSecondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }

            Divider()
            footer
        }
    }

    private var footer: some View {
        VStack(spacing: AppSpacing.sm) {
            if !viewModel.progressText.isEmpty {
                HStack(spacing: AppSpacing.sm) {
                    ProgressView().controlSize(.small)
                    Text(viewModel.progressText)
                        .font(AppFont.caption)
                        .foregroundStyle(Color.textSecondary)
                }
            }
            if let message = viewModel.completedMessage {
                Text(message)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.success)
            }
            HStack {
                Text(planNote)
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Button("移除全部") { viewModel.clear() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.stagedURLs.isEmpty || viewModel.isShredding)
                Button("粉碎 (\(viewModel.stagedURLs.count))") {
                    showConfirm = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(viewModel.stagedURLs.isEmpty || viewModel.isShredding)
            }
        }
        .padding(AppSpacing.lg)
    }

    /// Honest C-5 copy: no scareware, no fake "military grade" claims.
    private var planNote: String {
        viewModel.plan.passes > 1
            ? "HDD 模式：\(viewModel.plan.passes) 次覆写 + 校验 + 文件名随机化"
            : "1 次覆写 + 校验 + 文件名随机化（对 SSD 已足够）"
    }

    // MARK: - Helpers

    private func size(of url: URL) -> Int64 {
        (try? url.resourceValues(forKeys: [.fileSizeKey])).flatMap { $0.fileSize.map(Int64.init) } ?? 0
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
}

#Preview {
    ShredderView()
        .frame(width: 680, height: 480)
        .preferredColorScheme(.dark)
}
