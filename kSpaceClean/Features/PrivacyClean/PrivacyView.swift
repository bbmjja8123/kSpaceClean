import SwiftUI
import DesignSystem
import CommonUtils

// MARK: - PrivacyView

/// The main view for the Privacy Cleaner feature.
///
/// Shows a prominent scan button when idle, then displays discovered
/// privacy items grouped by browser / system category with per-item
/// checkboxes, and a bottom summary bar with a cleanup action.
public struct PrivacyView: View {
    @StateObject private var viewModel = PrivacyViewModel()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ---- Header ----
            headerView
                .padding(.horizontal, AppSpacing.lg)
                .padding(.top, AppSpacing.lg)
                .padding(.bottom, AppSpacing.md)

            // ---- Content ----
            if viewModel.isScanning {
                scanningState
            } else if viewModel.items.isEmpty {
                emptyState
            } else {
                resultsList
            }

            // ---- Summary bar ----
            if !viewModel.items.isEmpty {
                summaryBar
            }
        }
        .background(Color.bgPrimary)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Text("隐私清理")
                .font(AppFont.title2)
                .foregroundColor(.textPrimary)

            Spacer()

            if !viewModel.items.isEmpty {
                Button("全选") { viewModel.selectAll() }
                    .buttonStyle(.borderless)
                    .font(AppFont.callout)
                    .foregroundColor(.brandPrimary)
                    .disabled(viewModel.isCleaning)

                Button("取消全选") { viewModel.deselectAll() }
                    .buttonStyle(.borderless)
                    .font(AppFont.callout)
                    .foregroundColor(.textSecondary)
                    .disabled(viewModel.isCleaning)
            }
        }
    }

    // MARK: - Scanning

    private var scanningState: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
                .controlSize(.large)
            Text("正在扫描隐私数据...")
                .font(AppFont.title3)
                .foregroundColor(.textPrimary)
            Text("浏览器历史、Cookie、缓存、系统日志")
                .font(AppFont.callout)
                .foregroundColor(.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty

    private var emptyState: some View {
        EmptyStateView(
            icon: "hand.raised",
            title: "扫描隐私数据",
            subtitle: "检查浏览器历史、Cookie、缓存、近期项目及过期系统日志",
            action: (title: "开始扫描", handler: { [weak viewModel] in
                viewModel?.startScan()
            })
        )
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: AppSpacing.md) {
                ForEach(viewModel.itemsByCategory, id: \.0) { category, items in
                    categorySection(category: category, items: items)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
        }
    }

    @ViewBuilder
    private func categorySection(
        category: PrivacyItem.PrivacyCategory,
        items: [PrivacyItem]
    ) -> some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                // Section header
                HStack(spacing: AppSpacing.sm) {
                    Image(systemName: category.icon)
                        .font(.system(size: 16))
                        .foregroundColor(.textSecondary)
                        .frame(width: 20)

                    Text(category.rawValue)
                        .font(AppFont.title3)
                        .foregroundColor(.textPrimary)

                    Spacer()

                    Text("\(items.count) 项")
                        .font(AppFont.caption)
                        .foregroundColor(.textSecondary)
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.sm)

                Divider()
                    .padding(.horizontal, AppSpacing.md)

                // Item rows
                ForEach(items) { item in
                    itemRow(item: item)
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.vertical, AppSpacing.xs)

                    if item.id != items.last?.id {
                        Divider()
                            .padding(.horizontal, AppSpacing.md)
                    }
                }
                .padding(.bottom, AppSpacing.xs)
            }
        }
    }

    @ViewBuilder
    private func itemRow(item: PrivacyItem) -> some View {
        HStack(spacing: AppSpacing.sm) {
            // Checkbox
            Toggle(isOn: Binding(
                get: { item.isSelected },
                set: { _ in viewModel.toggleSelection(item.id) }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .disabled(viewModel.isCleaning)

            // Category icon
            Image(systemName: item.category.icon)
                .font(.system(size: 14))
                .foregroundColor(.textSecondary)
                .frame(width: 16)

            // Name
            Text(item.name)
                .font(AppFont.body)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Size
            Text(FileSizeFormatter.abbreviated(from: item.estimatedSize))
                .font(AppFont.monoDigit)
                .foregroundColor(.textSecondary)
        }
    }

    // MARK: - Summary bar

    private var summaryBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: AppSpacing.lg) {
                // Stats
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.brandPrimary)
                        .font(.system(size: 14))

                    Text("已选 \(viewModel.selectedItems.count) 项")
                        .font(AppFont.callout)
                        .foregroundColor(.textPrimary)
                }

                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "arrow.down.circle")
                        .foregroundColor(.brandSecondary)
                        .font(.system(size: 14))

                    Text("可释放 \(FileSizeFormatter.abbreviated(from: viewModel.selectedSize))")
                        .font(AppFont.monoDigit)
                        .foregroundColor(.textPrimary)
                }

                Spacer()

                if let message = viewModel.statusMessage {
                    Text(message)
                        .font(AppFont.caption)
                        .foregroundColor(.textSecondary)
                        .lineLimit(1)
                }

                Button(action: {
                    Task { await viewModel.cleanupSelected() }
                }) {
                    HStack(spacing: AppSpacing.xs) {
                        if viewModel.isCleaning {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.8)
                        }
                        Text(viewModel.isCleaning ? "清理中..." : "立即清理")
                    }
                    .font(AppFont.callout)
                }
                .buttonStyle(.borderedProminent)
                .tint(.danger)
                .controlSize(.small)
                .disabled(viewModel.selectedItems.isEmpty || viewModel.isCleaning)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
            .background(Color.bgSecondary)
        }
    }
}

// MARK: - Preview
#if DEBUG
struct PrivacyView_Previews: PreviewProvider {
    static var previews: some View {
        PrivacyView()
            .frame(width: 600, height: 500)
    }
}
#endif
