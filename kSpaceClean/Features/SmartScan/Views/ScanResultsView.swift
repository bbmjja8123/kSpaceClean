// kSpaceClean/Features/SmartScan/Views/ScanResultsView.swift
import SwiftUI

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

            // Tree — show EmptyStateScreen while the scan is in flight
            // (or no categories have populated yet), the real tree once
            // the engine has finished.
            if viewModel.isScanning || viewModel.categories.isEmpty {
                EmptyStateScreen(
                    scenario: viewModel.isScanning ? .firstLaunch : .noResults
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.categories) { category in
                            RecursiveTreeNode(
                                node: category,
                                level: 0,
                                expandedIDs: viewModel.expandedIDs,
                                onToggleExpand: viewModel.toggleExpand,
                                onToggleSelect: viewModel.toggleSelect
                            )
                        }
                    }
                    .padding(.vertical, Spacing.sm)
                }
            }

            Divider().background(Color.divider)

            // Summary bar
            SummaryBar(viewModel: viewModel)
        }
        .background(Color.bgCanvas)
    }

    /// Header bar: large "扫描完成" title on the leading edge, selection
    /// count + total byte size on the trailing edge. Uses the
    /// `bgElevated` surface so it reads against the scrolling tree.
    @ViewBuilder
    private var headerView: some View {
        HStack {
            Text("扫描完成")
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

    /// Formats `bytes` as a localized file-size string (e.g. `"12.4 MB"`).
    /// Uses `.file` style to favor MB/GB units over the block-count
    /// style of `.binary`.
    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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
private struct RecursiveTreeNode: View {
    /// Tree node being rendered. Polymorphic — `ScanTreeRow` handles the
    /// per-level field access via runtime `as?` checks.
    let node: any ScanTreeNode
    /// Zero-based nesting depth driving the leading indent.
    let level: Int
    /// Set of expanded node ids — mirrors the owning view-model state.
    let expandedIDs: Set<UUID>
    /// User tapped the chevron. Parent toggles its expanded state.
    let onToggleExpand: (UUID) -> Void
    /// User tapped the checkbox. Parent routes through the cascade.
    let onToggleSelect: (any ScanTreeNode) -> Void

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
        Group {
            if isExpanded {
                ForEach(Array(node.children.enumerated()), id: \.element.id) { _, child in
                    RecursiveTreeNode(
                        node: child,
                        level: level + 1,
                        expandedIDs: expandedIDs,
                        onToggleExpand: onToggleExpand,
                        onToggleSelect: onToggleSelect
                    )
                }
            }
        }
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
    /// without taking the parent view with it.
    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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