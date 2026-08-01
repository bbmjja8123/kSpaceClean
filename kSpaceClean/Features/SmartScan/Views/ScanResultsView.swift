// kSpaceClean/Features/SmartScan/Views/ScanResultsView.swift
import SwiftUI
import AppKit  // NSWorkspace for the "grant Full Disk Access" deep link

/// Process-wide `ByteCountFormatter` shared by every visible byte label
/// in the scan-results view (header, summary bar, and child rows). One
/// construction is dramatically cheaper than per-render allocation.
private let sharedByteCountFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f
}()

/// Top-level container view that displays the post-scan 4-level tree.
///
/// `ScanResultsView` is the Phase A "main view" milestone: it owns the
/// header, the scrollable tree, and the selection summary bar. The
/// view is purely presentational — every mutation flows through the
/// shared ``ScanResultsViewModel`` via the callbacks passed down into
/// ``ScanTreeRow``.
///
/// Layout (top → bottom):
/// 1. **Header** — large title on the leading edge, selection count +
///    byte size on the trailing edge. Pinned to a 64pt bar with the
///    `bgElevated` surface token so it reads against the scrolling tree.
/// 2. **Divider** — hairline separator using `Color.divider`.
/// 3. **Tree** — `LazyVStack` inside a `ScrollView`, renders each
///    top-level category and recursively renders its children when
///    expanded. Recursion is done manually via ``renderNode(_:level:)``
///    because the v3 cascade algorithm needs the parent to know its
///    own depth for the leading indent.
/// 4. **Summary bar** — ``SummaryBar`` (defined below) shows the
///    aggregate size + count and the primary "清 理" cleanup button.
///
/// C1 fix: the view now accepts an injected `ScanResultsViewModel` so the
/// production call site (RootView) can wire a real `ScanEngine` instead of
/// the placeholder mock data. Previews keep the default-init form.
struct ScanResultsView: View {
    /// Owning view model. `@ObservedObject` so the production call site
    /// (RootView) can own the model lifetime via `@StateObject` and pass
    /// it in; previews use the no-arg init.
    @ObservedObject var viewModel: ScanResultsViewModel

    /// Builds the full screen as a vertical stack of header / divider /
    /// scrollable tree / divider / summary bar.
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView

            Divider().background(Color.divider)

            // Tree — four states:
            // 1. scan in flight  → live progress view
            // 2. never scanned   → pre-scan surface (filters + CTA)
            // 3. scanned, empty  → "nothing to clean" + rescan CTA, or the
            //    Full Disk Access guidance state when the empty result is a
            //    sandbox artifact (no FDA means the walk never saw real files)
            // otherwise the real 4-level tree.
            if viewModel.isScanning {
                ScanProgressView(progress: viewModel.engineProgress)
            } else if !viewModel.hasScanned {
                PreScanPanel(viewModel: viewModel)
            } else if viewModel.categories.isEmpty {
                if viewModel.needsFullDiskAccess {
                    EmptyStateScreen(
                        scenario: .noFDA,
                        primaryAction: ("打开系统设置", openFullDiskAccessSettings)
                    )
                } else {
                    EmptyStateScreen(
                        scenario: .noResults,
                        primaryAction: ("重新扫描", { viewModel.startScan() })
                    )
                }
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Toggle("显示过滤掉的项", isOn: $viewModel.showAllHidden)
                            .font(Typography.regularBody())
                            .foregroundStyle(Color.textSecondary)
                            .toggleStyle(.checkbox)
                            .accessibilityLabel("显示过滤掉的项")
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.xs)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(viewModel.categories) { category in
                                let treeNode = RecursiveTreeNode(
                                    node: category,
                                    level: 0,
                                    expandedIDs: viewModel.expandedIDs,
                                    showAllHidden: viewModel.showAllHidden,
                                    onToggleExpand: viewModel.toggleExpand,
                                    onToggleSelect: viewModel.toggleSelect
                                )
                                if treeNode.isVisibleWhenHidden(showAllHidden: viewModel.showAllHidden) {
                                    treeNode.equatable()
                                }
                            }
                        }
                        .padding(.vertical, Spacing.sm)
                    }
                }
            }

            Divider().background(Color.divider)

            // Summary bar
            SummaryBar(viewModel: viewModel)
        }
        .background(Color.bgCanvas)
    }

    /// Header bar: large title on the leading edge, selection count + total
    /// byte size on the trailing edge. The title tracks the scan lifecycle so
    /// the pre-scan surface does not claim "扫描完成" before anything ran.
    /// Uses the `bgElevated` surface so it reads against the scrolling tree.
    @ViewBuilder
    private var headerView: some View {
        HStack {
            Text(headerTitle)
                .font(Typography.largeTitle())
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Text("\(viewModel.totalSelectedCount) 项 · \(formatBytes(viewModel.totalSelectedSize))")
                .font(Typography.regularBody())
                .foregroundStyle(Color.textSecondary)
        }
        .padding(Spacing.md)
        .frame(height: 64)
        .background(Color.bgElevated)
    }

    /// Lifecycle-aware header title: 准备扫描 → 正在扫描 → 扫描完成.
    private var headerTitle: String {
        if viewModel.isScanning { return "正在扫描" }
        return viewModel.hasScanned ? "扫描完成" : "准备扫描"
    }

    /// Formats `bytes` as a localized file-size string (e.g. `"12.4 MB"`).
    /// Uses `.file` style to favor MB/GB units over the block-count
    /// style of `.binary`. Reads from the process-wide
    /// `sharedByteCountFormatter` so the per-render allocation cost
    /// disappears.
    private func formatBytes(_ bytes: Int64) -> String {
        sharedByteCountFormatter.string(fromByteCount: bytes)
    }

    /// Opens the macOS Full Disk Access privacy pane, where the user can
    /// grant kSpaceClean permission to read the whole filesystem. Uses the
    /// `x-apple.systempreferences:` deep link so the user lands directly on
    /// the TCC settings page instead of hunting through System Settings.
    private func openFullDiskAccessSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

/// Pre-scan surface shown before the first scan of a session.
///
/// Answers the "扫描前没有看到 4 级扫描项" complaint: the user now sees a
/// real call-to-action plus the four filters that shape the result tree,
/// instead of a purely informational empty state that offered no way to
/// start a scan.
///
/// Deliberately minimal — exactly four controls (size floor, unused-age
/// floor, dangerous gate, running-app gate) plus the primary CTA. Anything
/// richer belongs in Settings, not on the scan surface.
struct PreScanPanel: View {
    /// Owning view model. Bound so the toggles/slider write straight into
    /// ``ScanResultsViewModel/filters`` and the CTA can trigger the scan.
    @ObservedObject var viewModel: ScanResultsViewModel

    /// Size-floor slider works in MB; the model stores bytes.
    /// F6 perf sweep: the slider writes into ``viewModel/draftFilters``
    /// (debounced 150 ms → ``viewModel/filters``) so dragging across the
    /// full 0–100 MB range fires the filter pipeline once instead of
    /// 100 times. The size label reads from the draft so the UI stays
    /// snappy during the drag.
    private var minimumSizeMB: Binding<Double> {
        Binding(
            get: { Double(viewModel.draftFilters.minimumSizeBytes) / 1_048_576.0 },
            set: { viewModel.draftFilters.minimumSizeBytes = Int64($0 * 1_048_576.0) }
        )
    }

    /// Hero icon + copy, the four controls, then the full-width CTA.
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Spacer(minLength: 0)

            Image(systemName: "sparkles")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.brandPrimary)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.xs) {
                Text("准备扫描")
                    .font(Typography.largeTitle())
                    .foregroundStyle(Color.textPrimary)
                Text("kSpaceClean 会扫描系统缓存、应用缓存、日志与残留文件，扫描结果按 4 级树展示。")
                    .font(Typography.regularBody())
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            filterControls
                .frame(maxWidth: 420)

            Button {
                viewModel.startScan()
            } label: {
                Text("开始扫描")
                    .font(Typography.largeBody())
                    .frame(maxWidth: 420)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .accessibilityLabel("开始扫描")

            Spacer(minLength: 0)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgCanvas)
    }

    /// The four filter controls, stacked with the design-system rhythm.
    @ViewBuilder
    private var filterControls: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // 1 — minimum size threshold (F6: binds to draftFilters,
            //     debounced 150ms before the pipeline runs).
            VStack(alignment: .leading, spacing: 2) {
                Text("最小文件大小：\(formatSizeLabel(viewModel.draftFilters.minimumSizeBytes))")
                    .font(Typography.regularBody())
                    .foregroundStyle(Color.textPrimary)
                Slider(value: minimumSizeMB, in: 0...100, step: 1)
                    .accessibilityLabel("最小文件大小")
            }

            // 2 — minimum unused age
            Picker("超过多久未使用", selection: $viewModel.filters.minimumUnusedDays) {
                Text("不限").tag(0)
                Text("7 天").tag(7)
                Text("30 天").tag(30)
                Text("90 天").tag(90)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("超过多久未使用")

            // 3 — dangerous gate
            Toggle("跳过高风险项", isOn: $viewModel.filters.skipDangerous)
                .accessibilityLabel("跳过高风险项")

            // 4 — running-app gate
            Toggle("跳过正在运行的应用", isOn: $viewModel.filters.skipRunningApps)
                .accessibilityLabel("跳过正在运行的应用")
        }
        .font(Typography.regularBody())
        .foregroundStyle(Color.textPrimary)
    }

    /// Renders the byte threshold as "不限" at zero, else a file-size string.
    private func formatSizeLabel(_ bytes: Int64) -> String {
        bytes <= 0
            ? "不限"
            : sharedByteCountFormatter.string(fromByteCount: bytes)
    }
}

/// Recursive renderer for a single tree node and (when expanded) its
/// children one level deeper.
///
/// Extracted as its own `View` so the `@ViewBuilder`-opaque-return-type
/// inference problem with recursive `@ViewBuilder` functions is avoided
/// — the recursion happens inside `body`, where each call site produces
/// a fresh `some View` that the parent's `ForEach` consumes.
///
/// Indentation: the parent passes `level` down so `ScanTreeRow` can
/// indent children by `RowSize.indentPerLevel` per level. Dispatch is
/// polymorphic — `ScanTreeRow` uses `as?` casts on `node` to pull
/// level-specific fields.
///
/// `RecursiveTreeNode` conforms to `Equatable` so SwiftUI can skip the
/// body re-evaluation for a whole subtree whose `(node.id, level,
/// expandedIDs, showAllHidden)` tuple is unchanged. The two callbacks are
/// stable references for the view tree's lifetime and would only force
/// equality churn on every parent invalidation.
struct RecursiveTreeNode: View, Equatable {
    /// Tree node being rendered. Polymorphic — `ScanTreeRow` handles the
    /// per-level field access via runtime `as?` checks.
    let node: any ScanTreeNode
    /// Zero-based nesting depth driving the leading indent.
    let level: Int
    /// Set of expanded node ids — mirrors the owning view-model state.
    let expandedIDs: Set<UUID>
    /// When `true`, `isHiddenByFilter` nodes render too (the "显示过滤掉的项"
    /// toggle). Fold-not-delete: hidden nodes stay in the data model and
    /// are skipped by the renderer at every level unless revealed.
    let showAllHidden: Bool
    /// User tapped the chevron. Parent toggles its expanded state.
    let onToggleExpand: (UUID) -> Void
    /// User tapped the checkbox. Parent routes through the cascade.
    let onToggleSelect: (any ScanTreeNode) -> Void

    /// Equatable conformance — drives `.equatable()` on the recursive
    /// children in `body` so subtrees whose `(node.id, level,
    /// expandedIDs, showAllHidden)` tuple is unchanged skip body
    /// evaluation. This is the key win for the leaf-level `.on → .off`
    /// flip case described in the perf brief: a sibling leaf toggling no
    /// longer rebuilds the HStack for every other row in the tree.
    /// `showAllHidden` participates so flipping the "显示过滤掉的项" toggle
    /// invalidates every row and forces a re-render.
    static func == (lhs: RecursiveTreeNode, rhs: RecursiveTreeNode) -> Bool {
        lhs.node.id == rhs.node.id
            && lhs.level == rhs.level
            && lhs.expandedIDs == rhs.expandedIDs
            && lhs.showAllHidden == rhs.showAllHidden
    }

    /// Always renders the row; the children are wrapped in a single
    /// `Group` so the body shape stays uniform across the recursion.
    var body: some View {
        let isExpanded = expandedIDs.contains(node.id)
        ScanTreeRow(
            node: node,
            level: level,
            isExpanded: isExpanded,
            onToggleExpand: { onToggleExpand(node.id) },
            onToggleSelect: { onToggleSelect(node) }
        )
        .equatable()
        Group {
            if isExpanded {
                ForEach(Array(node.children.enumerated()), id: \.element.id) { _, child in
                    let childNode = RecursiveTreeNode(
                        node: child,
                        level: level + 1,
                        expandedIDs: expandedIDs,
                        showAllHidden: showAllHidden,
                        onToggleExpand: onToggleExpand,
                        onToggleSelect: onToggleSelect
                    )
                    if childNode.isVisibleWhenHidden(showAllHidden: showAllHidden) {
                        childNode.equatable()
                    }
                }
            }
        }
    }
}

extension RecursiveTreeNode {
    /// Hidden nodes stay in the data model (fold-not-delete) but are
    /// skipped by the renderer unless the user reveals them.
    func isVisibleWhenHidden(showAllHidden: Bool) -> Bool {
        if showAllHidden { return true }
        return !node.isHiddenByFilter
    }
}

/// Bottom-pinned summary bar with selection count / size, bulk-select
/// buttons, and the primary cleanup CTA.
///
/// `SummaryBar` is purely presentational; all state and side effects
/// come from the bound ``ScanResultsViewModel``. The cleanup CTA is
/// disabled when ``ScanResultsViewModel/totalSelectedSize`` is zero and
/// dims itself to 50% opacity in the same condition so the disabled
/// state is visible without a hard color flip.
///
/// Layout (left → right): stacked count + size label, spacer, "全选" /
/// "反选" bulk buttons, primary "清 理" button.
struct SummaryBar: View {
    /// Owning view model. `@ObservedObject` because `SummaryBar` is a
    /// child view of `ScanResultsView` and the parent already owns the
    /// model's lifetime via `@StateObject`.
    @ObservedObject var viewModel: ScanResultsViewModel

    /// Renders the summary bar content: stack of two text lines on the
    /// left, two bordered bulk-select buttons, and the primary cleanup
    /// CTA. The cleanup CTA is disabled and dimmed when the selection
    /// is empty.
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("已选 \(formatBytes(viewModel.totalSelectedSize))")
                    .font(Typography.largeBody())
                    .foregroundStyle(Color.textPrimary)
                Text("\(viewModel.totalSelectedCount) 项")
                    .font(Typography.regularBody())
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()

            HStack(spacing: Spacing.sm) {
                Button("全选") { /* TODO */ }
                    .buttonStyle(.bordered)
                Button("反选") { /* TODO */ }
                    .buttonStyle(.bordered)
            }

            Button {
                // TODO: Phase C - cleanup
            } label: {
                Text("清 理")
                    .font(Typography.largeBody())
                    .foregroundStyle(.white)
                    .padding(.horizontal, Spacing.lg)
                    .padding(.vertical, Spacing.sm)
                    .background(Color.brandPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(.plain)
            .disabled(viewModel.totalSelectedSize == 0)
            .opacity(viewModel.totalSelectedSize == 0 ? 0.5 : 1.0)
        }
        .padding(Spacing.md)
        .frame(height: 64)
        .background(Color.bgElevated)
    }

    /// Formats `bytes` as a localized file-size string (e.g. `"12.4 MB"`).
    /// Mirrors ``ScanResultsView/formatBytes(_:)``; duplicated here so
    /// `SummaryBar` can be lifted into a preview or a sibling surface
    /// without taking the parent view with it. Reads from the
    /// process-wide `sharedByteCountFormatter`.
    private func formatBytes(_ bytes: Int64) -> String {
        sharedByteCountFormatter.string(fromByteCount: bytes)
    }
}

#if DEBUG
/// Xcode 14 preview surface — exercises the full screen at the
/// 960×720 design-system canvas size.
struct ScanResultsView_Previews: PreviewProvider {
    static var previews: some View {
        ScanResultsView(viewModel: ScanResultsViewModel(engine: nil))
            .frame(width: 960, height: 720)
    }
}
#endif