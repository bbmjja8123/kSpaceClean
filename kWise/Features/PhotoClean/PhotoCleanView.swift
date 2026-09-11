// kWise/Features/PhotoClean/PhotoCleanView.swift
//
// 照片清理 — 双 Tab（v2.3 Phase 3）：相似照片（感知哈希网格）+ 传统缓存
// （保留原有 PhotoCacheScanner 全部逻辑）。
import SwiftUI
import DesignSystem
import CommonUtils
import DetectionCore
import PowerScope

struct PhotoCleanView: View {
    enum Tab: String, CaseIterable {
        case similar = "相似照片"
        case caches = "传统缓存"
    }

    @StateObject private var viewModel: PhotoCleanViewModel
    @StateObject private var similarityVM: PhotoSimilarityViewModel
    @State private var tab: Tab = .similar
    @State private var previewURL: URL?
    @ObservedObject private var appScope = AppScope.shared

    /// Injectable for the app root (graph engine + quota routing).
    init(viewModel: PhotoCleanViewModel? = nil,
         similarityViewModel: PhotoSimilarityViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? PhotoCleanViewModel())
        _similarityVM = StateObject(wrappedValue: similarityViewModel ?? PhotoSimilarityViewModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("模式", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { t in
                    Text(t.rawValue).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)
            .padding(.horizontal, AppSpacing.lg)
            .padding(.top, AppSpacing.md)

            switch tab {
            case .similar:
                similarityTab
            case .caches:
                legacyCacheTab
            }
        }
        .kwQuickLookPreview($previewURL)
        .onAppear {
            // 相似照片在首次进入时刷新候选目录；不自动扫描（用户触发）。
        }
    }

    // MARK: - Similar Photos Tab

    private var similarityTab: some View {
        VStack(spacing: 0) {
            if similarityVM.isScanning {
                similarityProgress
            } else if similarityVM.groups.isEmpty {
                similarityIdle
            } else {
                similarityResults
            }
        }
    }

    private var similarityIdle: some View {
        VStack(spacing: AppSpacing.lg) {
            Spacer()
            if similarityVM.candidateDirectories.isEmpty, appScope.capability.level == .containerOnly {
                // Scope honesty: container-only users get a grant CTA, never
                // a fake "0 files scanned" result.
                EmptyStateView(
                    icon: "lock.open",
                    title: "授权后开始查找相似照片",
                    subtitle: "授权主目录后，kWise 在本机比对 截图/下载/桌面/图片 目录中的相似照片（不联网）。"
                )
                Button("授权主目录") {
                    Task { await appScope.grant() }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Image(systemName: "photo.stack")
                    .font(.system(size: 56))
                    .foregroundColor(.brandPrimary)
                Text("查找相似照片")
                    .font(AppFont.title3)
                    .foregroundColor(.textPrimary)
                Text("扫描 \(similarityVM.candidateDirectories.count) 个照片目录，找出截图堆积与相似照片。比对完全在本机完成。")
                    .font(AppFont.body)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Button {
                    similarityVM.startScan()
                } label: {
                    Label("开始扫描", systemImage: "sparkles")
                        .font(AppFont.title3)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandPrimary)

                // 截图专项 (v2.6 W4)：一键清 30 天前旧截图。
                Button {
                    similarityVM.startScreenshotQuickClean()
                } label: {
                    Label("清理 30 天前的旧截图", systemImage: "camera.on.rectangle")
                        .font(AppFont.callout)
                }
                .buttonStyle(.bordered)
            }
            if let message = similarityVM.statusMessage {
                Text(message)
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
            }
            Spacer()
        }
        .frame(maxHeight: .infinity)
    }

    private var similarityProgress: some View {
        VStack(spacing: AppSpacing.md) {
            Spacer()
            ProgressView(value: similarityVM.scanProgress)
                .progressViewStyle(.linear)
                .tint(.brandPrimary)
                .frame(maxWidth: 420)
            if let file = similarityVM.currentFile {
                Text(file)
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("取消") { similarityVM.cancelScan() }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Spacer()
        }
        .padding(AppSpacing.lg)
        .frame(maxHeight: .infinity)
    }

    private var similarityResults: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("保留", selection: Binding(
                    get: { similarityVM.keepStrategy },
                    set: { similarityVM.reapplyKeepStrategy($0) }
                )) {
                    Text("保留最新").tag(SelectionStrategy.keepNewest)
                    Text("保留最高分辨率").tag(SelectionStrategy.keepHighestResolution)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                Spacer()
            }
            .padding(.horizontal, AppSpacing.lg)
            .padding(.vertical, AppSpacing.xs)

            ScrollView {
                LazyVStack(spacing: AppSpacing.md) {
                    ForEach(similarityVM.groups) { group in
                        PhotoSimilarityGroupCard(
                            group: group,
                            toggleFile: { similarityVM.toggleFile($0) },
                            toggleGroup: { similarityVM.toggleGroup($0) },
                            swapKeep: { gid, fid in similarityVM.swapKeep(in: gid, to: fid) },
                            preview: { previewURL = $0 }
                        )
                    }
                }
                .padding(AppSpacing.lg)
            }
            similaritySummaryBar
        }
    }

    private var similaritySummaryBar: some View {
        HStack(spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.xs) {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.brandPrimary)
                    .font(.system(size: 14))
                Text("已选 \(similarityVM.selectedFiles.count) 张 · 可释放约 \(FileSizeFormatter.abbreviated(from: similarityVM.selectedSize))")
                    .font(AppFont.callout)
                    .foregroundColor(.textPrimary)
            }
            Spacer()
            Button("取消全选") { similarityVM.deselectAll() }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button {
                Task { await similarityVM.cleanupSelected() }
            } label: {
                Label("清理所选", systemImage: AppIcon.clean)
                    .font(AppFont.callout)
            }
            .buttonStyle(.borderedProminent)
            .tint(.danger)
            .controlSize(.small)
            .disabled(similarityVM.selectedFiles.isEmpty)
        }
        .padding(.horizontal, AppSpacing.lg)
        .padding(.vertical, AppSpacing.md)
        .background(Color.bgPrimary)
    }

    // MARK: - Legacy Cache Tab (pre-v2.3 surface, preserved)

    private var legacyCacheTab: some View {
        VStack(spacing: AppSpacing.lg) {
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

            if viewModel.isScanning {
                scanningState
            } else if viewModel.items.isEmpty {
                idleState
            } else {
                resultsState
            }
        }
    }

    // MARK: - Idle (legacy)

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

    // MARK: - Scanning (legacy)

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

    // MARK: - Results (legacy)

    private var resultsState: some View {
        VStack(spacing: 0) {
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

            summaryBar
        }
    }

    // MARK: - Summary (legacy)

    private var summaryBar: some View {
        VStack(spacing: 0) {
            Divider()
                .foregroundColor(.separatorColor)

            HStack(spacing: AppSpacing.md) {
                HStack(spacing: AppSpacing.xs) {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.brandPrimary)
                        .font(.system(size: 14))
                    Text("已选 \(viewModel.selectedItems.count) 项")
                        .font(AppFont.callout)
                        .foregroundColor(.textPrimary)
                }

                Text(FileSizeFormatter.abbreviated(from: viewModel.selectedSize))
                    .font(AppFont.monoDigit)
                    .foregroundColor(.textSecondary)

                Spacer()

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

// MARK: - Similarity Group Card

private struct PhotoSimilarityGroupCard: View {
    let group: ToolboxGroup
    let toggleFile: (UUID) -> Void
    let toggleGroup: (UUID) -> Void
    let swapKeep: (UUID, UUID) -> Void
    let preview: (URL) -> Void

    var body: some View {
        GlassPanel {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                HStack(spacing: AppSpacing.sm) {
                    Toggle(isOn: Binding(
                        get: { group.files.allSatisfy(\.isSelected) },
                        set: { _ in toggleGroup(group.id) }
                    )) { }
                    .toggleStyle(.checkbox)
                    .controlSize(.small)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(group.files.first?.url.lastPathComponent ?? "相似组")
                            .font(AppFont.body)
                            .fontWeight(.medium)
                            .foregroundColor(.textPrimary)
                            .lineLimit(1)
                        HStack(spacing: AppSpacing.sm) {
                            Text(group.evidenceSummary)
                                .font(AppFont.caption)
                                .foregroundColor(.brandPrimary)
                            Text("\(group.files.count) 张 · 可释放约 \(FileSizeFormatter.abbreviated(from: group.honestlyReclaimable))")
                                .font(AppFont.caption)
                                .foregroundColor(.textSecondary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.top, AppSpacing.md)

                // Thumbnail grid — at least one photo per group stays.
                // A/B 互换 (v2.6 W4 收尾)：点未保留缩略图的星标 → 互换保留。
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.sm) {
                        ForEach(group.files) { file in
                            let isKept = !file.isSelected
                            VStack(spacing: AppSpacing.xs) {
                                Button {
                                    toggleFile(file.id)
                                } label: {
                                    ZStack(alignment: .topTrailing) {
                                        KWThumbnailView(url: file.url, size: 120)
                                        Image(systemName: file.isSelected
                                              ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 18))
                                            .foregroundColor(file.isSelected ? .brandPrimary : .white)
                                            .shadow(radius: 2)
                                            .padding(4)
                                    }
                                }
                                .buttonStyle(.plain)
                                // A/B 互换：非保留件的星标 → 设为保留原件。
                                Button {
                                    swapKeep(group.id, file.id)
                                } label: {
                                    Label(isKept ? "保留中" : "设为保留", systemImage: isKept ? "crown.fill" : "crown")
                                        .font(AppFont.caption)
                                        .foregroundColor(isKept ? .brandPrimary : .textSecondary)
                                }
                                .buttonStyle(.plain)
                                .disabled(isKept)
                                Text(FileSizeFormatter.abbreviated(from: file.size))
                                    .font(AppFont.caption)
                                    .foregroundColor(.textSecondary)
                            }
                            .onTapGesture(count: 2) { preview(file.url) }
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                }

                HStack {
                    Spacer()
                    Button("查看大图") {
                        if let first = group.files.first { preview(first.url) }
                    }
                    .buttonStyle(.borderless)
                    .font(AppFont.caption)
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.sm)
            }
            .padding(.vertical, AppSpacing.sm)
        }
    }
}

// MARK: - Category Section (legacy)

private struct PhotoCategorySection: View {
    let category: PhotoCacheItem.PhotoCacheCategory
    let items: [PhotoCacheItem]
    let toggleSelection: (PhotoCacheItem.ID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
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

// MARK: - Item Row (legacy)

private struct PhotoCacheItemRow: View {
    let item: PhotoCacheItem
    let toggle: () -> Void

    var body: some View {
        GlassPanel {
            HStack(spacing: AppSpacing.md) {
                Button(action: toggle) {
                    Image(systemName: item.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundColor(item.isSelected ? .brandPrimary : .textSecondary)
                }
                .buttonStyle(.plain)

                Image(systemName: item.category.icon)
                    .font(.system(size: 16))
                    .foregroundColor(.categoryCache)
                    .frame(width: 24)

                Text(item.name)
                    .font(AppFont.body)
                    .foregroundColor(.textPrimary)
                    .lineLimit(1)

                Spacer()

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

#if DEBUG
struct PhotoCleanView_Previews: PreviewProvider {
    static var previews: some View {
        PhotoCleanView()
            .frame(width: 600, height: 500)
    }
}
#endif
