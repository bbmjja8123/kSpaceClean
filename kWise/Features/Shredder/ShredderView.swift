// kWise/Features/Shredder/ShredderView.swift
//
// 文件粉碎 surface (M6, v2.0 Phase 5). Consent chain: NSOpenPanel grant →
// staging review → DELETE-token confirmation (DangerousConfirmDialog) →
// overwrite + verify + rename + trash. The tooltip is honest about SSD
// (C-5): one pass is sufficient, multi-pass is opt-in for spinning disks.
import SwiftUI
import UniformTypeIdentifiers
import DesignSystem
import PowerScope

struct ShredderView: View {
    @StateObject private var viewModel: ShredderViewModel
    @State private var showConfirm = false
    @State private var isDropTargeted = false

    /// Injectable VM for the tabbed toolbox (state persists across tab
    /// switches); previews fall back to a default-constructed VM.
    init(viewModel: ShredderViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? ShredderViewModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(Color.bgPrimary)
        .onAppear { viewModel.refreshHistory() }
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
                emptyDropZone
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(viewModel.stagedURLs, id: \.self) { url in
                        HStack {
                            KWThumbnailView(url: url, size: 28)
                                .clipShape(RoundedRectangle(cornerRadius: AppRadius.xs))
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

            if !viewModel.history.isEmpty {
                historyBlock
            }
            Divider()
            footer
        }
    }

    // MARK: - Drop Zone (empty state doubles as drop target)

    private var emptyDropZone: some View {
        VStack(spacing: AppSpacing.md) {
            EmptyStateView(
                icon: "document.badge.ellipsis",
                title: isDropTargeted ? "松开以添加文件" : "拖入文件或点击添加",
                subtitle: "文件内容将被覆写，此操作不可逆。仅支持用户文件。"
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDropTargeted ? Color.brandPrimary.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    /// Resolves dropped file-URL providers and stages them via the VM.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { lock.lock(); urls.append(url); lock.unlock() }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak viewModel] in
            viewModel?.handleDrop(urls: urls)
        }
        return true
    }

    // MARK: - History Block

    private var historyBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("最近粉碎记录")
                .font(AppFont.caption)
                .foregroundColor(.textSecondary)
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.sm)
            ForEach(viewModel.history.prefix(5), id: \.objectID) { row in
                HStack {
                    Image(systemName: "checkmark.seal")
                        .foregroundColor(.success)
                    Text(row.path ?? "")
                        .font(AppFont.caption)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: row.size, countStyle: .file))
                        .font(AppFont.caption)
                        .foregroundColor(.textSecondary)
                }
                .padding(.horizontal, AppSpacing.lg)
            }
        }
        .padding(.bottom, AppSpacing.xs)
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
