import SwiftUI
import DesignSystem
import CommonUtils

/// Photo Cache Cleaner view.
///
/// Matches the layout conventions used throughout kSpaceClean:
/// a scan button (when idle), results grouped by photo-cache category
/// with selection checkboxes, and a summary bar at the bottom.
struct PhotoCleanView: View {
    @StateObject private var viewModel = PhotoCleanViewModel()

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            // Header
            HStack {
                Text("照片缓存")
                    .font(AppFont.title2)
                    .foregroundColor(.textPrimary)
                Spacer()
                if !viewModel.items.isEmpty {
                    Button("全选") { viewModel.selectAll() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button("取消全选") { viewModel.deselectAll() }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, 16)

            // Content
            if viewModel.isScanning {
                scanningState
            } else if viewModel.items.isEmpty {
                idleState
            } else {
                resultsState
            }
        }
    }

    // MARK: - Idle

    private var idleState: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 56))
                .foregroundColor(.brandPrimary)

            Text("扫描照片缓存")
                .font(AppFont.title3)
                .foregroundColor(.textPrimary)

            Text("检查 Photos.app 缓存、iPhoto 图库、iOS 备份与照片流临时文件")
                .font(AppFont.body)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                viewModel.startScan()
            } label: {
                Label("开始扫描", systemImage: AppIcon.scan)
                    .font(AppFont.title3)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandPrimary)
            .controlSize(.large)

            Spacer()
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Scanning

    private var scanningState: some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("正在扫描照片缓存...")
                .font(AppFont.title3)
                .foregroundColor(.textPrimary)
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Results

    private var resultsState: some View {
        VStack(spacing: 0) {
            // Scrollable category list
            ScrollView {
                LazyVStack(spacing: AppSpacing.md) {
                    ForEach(PhotoCacheItem.PhotoCacheCategory.allCases, id: \.self) { category in
                        let categoryItems = viewModel.itemsByCategory[category] ?? []
                        if !categoryItems.isEmpty {
                            PhotoCategorySection(
                                category: category,
                                items: categoryItems,
                                toggleSelection: { viewModel.toggleSelection($0) }
                            )
                        }
                    }
                }
                .padding(.horizontal, AppSpacing.lg)
                .padding(.bottom, AppSpacing.lg)
            }

            // Summary bar
            summaryBar
        }
    }

    // MARK: - Summary

    private var summaryBar: some View {
        VStack(spacing: 0) {
            Divider()
                .foregroundColor(.separatorColor)

            HStack(spacing: AppSpacing.md) {
                // Selected count
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.brandPrimary)
                        .font(.system(size: 14))
                    Text("已选 \(viewModel.selectedItems.count) 项")
                        .font(AppFont.callout)
                        .foregroundColor(.textPrimary)
                }

                // Selected size
                Text(FileSizeFormatter.abbreviated(from: viewModel.selectedSize))
                    .font(AppFont.monoDigit)
                    .foregroundColor(.textSecondary)

                Spacer()

                // Cleanup button
                Button {
                    Task { await viewModel.cleanupSelected() }
                } label: {
                    Label("清理", systemImage: AppIcon.clean)
                        .font(AppFont.callout)
                }
                .buttonStyle(.borderedProminent)
                .tint(.danger)
                .controlSize(.small)
                .disabled(viewModel.selectedItems.isEmpty)
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.md)
            .background(Color.bgPrimary)
        }
    }
}

// MARK: - Category Section

private struct PhotoCategorySection: View {
    let category: PhotoCacheItem.PhotoCacheCategory
    let items: [PhotoCacheItem]
    let toggleSelection: (PhotoCacheItem.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            // Category header
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: category.icon)
                    .font(.system(size: 16))
                    .foregroundColor(.categoryCache)
                Text(category.rawValue)
                    .font(AppFont.title3)
                    .foregroundColor(.textPrimary)
                Spacer()
                Text(FileSizeFormatter.abbreviated(from: totalSize))
                    .font(AppFont.monoDigit)
                    .foregroundColor(.textSecondary)
            }
            .padding(.horizontal, AppSpacing.xs)
            .padding(.top, AppSpacing.xs)

            // Items
            ForEach(items) { item in
                PhotoCacheItemRow(
                    item: item,
                    toggle: { toggleSelection(item.id) }
                )
            }
        }
    }

    private var totalSize: Int64 {
        items.reduce(0) { $0 + $1.estimatedSize }
    }
}

// MARK: - Item Row

private struct PhotoCacheItemRow: View {
    let item: PhotoCacheItem
    let toggle: () -> Void

    var body: some View {
        GlassPanel {
            HStack(spacing: AppSpacing.md) {
                // Checkbox
                Button(action: toggle) {
                    Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundColor(item.isSelected ? .brandPrimary : .textSecondary)
                }
                .buttonStyle(.plain)

                // Category icon
                Image(systemName: item.category.icon)
                    .font(.system(size: 16))
                    .foregroundColor(.categoryCache)
                    .frame(width: 24)

                // Item name
                Text(item.name)
                    .font(AppFont.body)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                Spacer()

                // Size
                Text(FileSizeFormatter.abbreviated(from: item.estimatedSize))
                    .font(AppFont.monoDigit)
                    .foregroundColor(.textSecondary)
            }
            .padding(AppSpacing.md)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }
}

// MARK: - Preview

#if DEBUG
struct PhotoCleanView_Previews: PreviewProvider {
    static var previews: some View {
        PhotoCleanView()
            .frame(width: 600, height: 500)
    }
}
#endif
