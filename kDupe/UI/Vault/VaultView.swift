import SwiftUI
import DesignSystem

struct VaultView: View {
    @StateObject private var viewModel = VaultViewModel()
    @State private var restoreConflict: VaultItem?

    var body: some View {
        VStack(spacing: 0) {
            header
            if viewModel.isLoading && viewModel.items.isEmpty {
                Spacer()
                LoadingStateView(title: NSLocalizedString("Loading vault...", comment: "Vault loading"))
                Spacer()
            } else if viewModel.items.isEmpty {
                Spacer()
                EmptyStateView(
                    icon: "shippingbox",
                    title: NSLocalizedString("Vault is empty", comment: "Vault empty title"),
                    subtitle: NSLocalizedString("Files you clean will be kept here for 30 days so you can restore them.", comment: "Vault empty subtitle")
                )
                Spacer()
            } else {
                itemList
            }
        }
        .task { await viewModel.load() }
        .alert(
            NSLocalizedString("Cannot restore", comment: "Restore conflict title"),
            isPresented: Binding(
                get: { restoreConflict != nil },
                set: { if !$0 { restoreConflict = nil } }
            ),
            presenting: restoreConflict
        ) { item in
            Button(NSLocalizedString("Show in Finder", comment: "Show in Finder")) {
                viewModel.revealInFinder(item)
            }
            Button(NSLocalizedString("Cancel", comment: "Cancel"), role: .cancel) {}
        } message: { item in
            Text(String(format: NSLocalizedString("'%@' already exists at the original location. Move it aside, then try again.", comment: "Restore conflict message"),
                        item.originalURL.path))
        }
        .alert(
            NSLocalizedString("Vault error", comment: "Vault error title"),
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            ),
            presenting: viewModel.errorMessage
        ) { _ in
            Button(NSLocalizedString("OK", comment: "OK"), role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Header

    private var header: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(NSLocalizedString("Vault", comment: "Vault title"))
                        .font(.title2).bold()
                    Spacer()
                    Button {
                        Task { await viewModel.purgeExpired() }
                    } label: {
                        Label(NSLocalizedString("Purge expired", comment: "Purge expired"),
                              systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(viewModel.items.isEmpty || viewModel.isProcessing)
                }
                Text(NSLocalizedString("Files are kept for 30 days after cleanup. Restore or purge them at any time.", comment: "Vault retention policy"))
                    .font(.callout)
                    .foregroundColor(.textSecondary)
                HStack(spacing: AppSpacing.xl) {
                    stat(title: NSLocalizedString("Items", comment: "Vault items count"),
                         value: "\(viewModel.items.count)")
                    stat(title: NSLocalizedString("Total size", comment: "Vault total size"),
                         value: formatBytes(viewModel.totalSize))
                }
            }
            .padding(AppSpacing.lg)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.top, AppSpacing.lg)
    }

    private func stat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundColor(.textSecondary)
            Text(value)
                .font(.headline)
        }
    }

    // MARK: - List

    private var itemList: some View {
        List {
            ForEach(viewModel.items) { item in
                VaultItemRow(
                    item: item,
                    isProcessing: viewModel.isProcessing,
                    onRestore: { Task { await viewModel.restore(item) } },
                    onReveal: { viewModel.revealInFinder(item) }
                )
                .listRowSeparator(.visible)
            }
        }
        .listStyle(.inset)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct VaultItemRow: View {
    let item: VaultItem
    let isProcessing: Bool
    let onRestore: () -> Void
    let onReveal: () -> Void

    var body: some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: item.status == .vaulted ? "shippingbox.fill" : "shippingbox")
                .foregroundColor(item.status == .vaulted ? .brandPrimary : .textSecondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.originalURL.lastPathComponent)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.originalURL.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: AppSpacing.sm)
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatBytes(item.originalSize))
                    .font(.subheadline)
                    .monospacedDigit()
                Text(item.vaultedAt, style: .date)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
            }
            statusBadge
            restoreButton
        }
        .padding(.vertical, AppSpacing.xs)
        .contextMenu {
            Button(NSLocalizedString("Reveal in Finder", comment: "Reveal in Finder")) { onReveal() }
        }
    }

    private var statusBadge: some View {
        Text(item.status == .vaulted
             ? NSLocalizedString("Vaulted", comment: "Vaulted status")
             : NSLocalizedString("Restored", comment: "Restored status"))
            .font(.caption2)
            .foregroundColor(item.status == .vaulted ? .brandPrimary : .textSecondary)
            .padding(.horizontal, AppSpacing.sm)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.full)
                    .fill((item.status == .vaulted ? Color.brandPrimary : Color.textSecondary).opacity(0.12))
            )
    }

    @ViewBuilder
    private var restoreButton: some View {
        if item.status == .vaulted {
            Button(NSLocalizedString("Restore", comment: "Restore from vault"), action: onRestore)
                .buttonStyle(.bordered)
                .disabled(isProcessing)
        } else {
            Button(NSLocalizedString("Show", comment: "Show in Finder"), action: onReveal)
                .buttonStyle(.bordered)
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
