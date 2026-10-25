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
                Text(String(localized: String.LocalizationValue("shred.title")))
                    .font(AppFont.title2)
                    .foregroundStyle(Color.textPrimary)
                Text(String(localized: String.LocalizationValue("shred.subtitle")))
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button(String(localized: String.LocalizationValue("shred.addFiles"))) { viewModel.pickFiles() }
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
                title: isDropTargeted
                    ? String(localized: String.LocalizationValue("shred.drop.release"))
                    : String(localized: String.LocalizationValue("shred.drop.idle")),
                subtitle: String(localized: String.LocalizationValue("shred.drop.subtitle"))
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isDropTargeted ? Color.brandPrimary.opacity(0.08) : Color.clear)
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    /// Resolves dropped file-URL providers and stages them via the VM
    /// (P2 T4: resolution moved into the shared `FileURLDropResolver` so the
    /// window-wide drag-to-shred overlay uses the same code path).
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        FileURLDropResolver.resolve(providers) { [weak viewModel] urls in
            viewModel?.performDrop(urls: urls)
        }
    }

    // MARK: - History Block

    private var historyBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(String(localized: String.LocalizationValue("shred.history.title")))
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
                    // v2.6 R2-5：环形进度 + pass 计数（复用 DesignSystem ProgressRing）。
                    ZStack {
                        Circle()
                            .stroke(Color.bgSecondary, lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: viewModel.progressFraction)
                            .stroke(Color.brandPrimary, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(KFAnimation.easeInOut, value: viewModel.progressFraction)
                    }
                    .frame(width: 22, height: 22)
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
                Button(String(localized: String.LocalizationValue("shred.removeAll"))) { viewModel.clear() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.stagedURLs.isEmpty || viewModel.isShredding)
                Button(String(format: String(localized: String.LocalizationValue("shred.start")), Int64(viewModel.stagedURLs.count))) {
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
            ? String(format: String(localized: String.LocalizationValue("shred.plan.hdd")), Int64(viewModel.plan.passes))
            : String(localized: String.LocalizationValue("shred.plan.ssd"))
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
