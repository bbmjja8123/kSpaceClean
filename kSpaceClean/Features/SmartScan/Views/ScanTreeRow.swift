// kSpaceClean/Features/SmartScan/Views/ScanTreeRow.swift
import SwiftUI

/// Process-wide `ByteCountFormatter` shared by every scan-result row.
///
/// Constructing a `ByteCountFormatter` loads the user's locale tables;
/// doing it once per render is wasteful. Rows are `.equatable()` and
/// re-render often during a scan, so this is a meaningful win.
private let sharedByteCountFormatter: ByteCountFormatter = {
    let f = ByteCountFormatter()
    f.countStyle = .file
    return f
}()

/// Generic row view used by the 4-level scan-result tree (`ScanResultsView`).
///
/// `ScanTreeRow` renders a single node — `ScanCategory`, `ScanSubCategory`,
/// `ScanAction`, or `ScanResult` — at any depth in the tree. The parent
/// passes in the node plus its currently-displayed indentation depth and the
/// current expand/collapse state; the view itself is purely presentational
/// and surfaces every interaction back through callbacks so the owning view
/// model can mutate the underlying node.
///
/// `ScanTreeRow` conforms to `Equatable` so SwiftUI can skip body
/// evaluation when the rendered output is unchanged. Equality is computed
/// from `(node.id, level, isExpanded)` — the body never depends on the
/// callback identity (closures are stable references for the lifetime of
/// the view tree) so comparing them would defeat the purpose.
///
/// Visual layout, from leading to trailing edge:
///
/// 1. **Indent strip** — one `RowSize.indentPerLevel`-wide transparent block
///    per tree level so children visually nest under their parent.
/// 2. **Expand chevron** — `chevron.down`/`chevron.right` button when the
///    node has children; a fixed-width placeholder when it does not (this
///    keeps every row's leading edge aligned regardless of depth).
/// 3. **Tri-state checkbox** — `IndeterminateCheckbox` showing the aggregate
///    `CheckState` from the cascade algorithm.
/// 4. **Type-specific icon** — picked via `iconView` based on the runtime
///    type of `node`; `ScanResult` honors its per-row override, while the
///    higher levels get category icons.
/// 5. **Title + optional path** — the localized title on top, the file path
///    (or Bundle ID, or action title) underneath when meaningful, truncated
///    in the middle for long paths.
/// 6. **Trailing size** — `ByteCountFormatter`-formatted total size in
///    monospaced digits so columns line up across rows.
/// 7. **Risk badge** — `RiskBadge` (compact for the top-level category row,
///    full size for nested rows).
///
/// Hovering the row swaps the background to `Color.bgSurface` and the
/// transition uses `Animation.accessibleDefault` so motion-sensitive users
/// get the calmer 0.1s linear curve.
struct ScanTreeRow: View, Equatable {
    /// The tree node being rendered. The view dispatches on its runtime type
    /// via `as?` casts to pull node-specific fields (e.g. `ScanResult.path`).
    let node: any ScanTreeNode
    /// Zero-based nesting depth — drives the leading indent strip.
    let level: Int
    /// Whether this row's children are currently expanded in the outline.
    let isExpanded: Bool
    /// User tapped the expand chevron. Parent toggles its expanded state.
    let onToggleExpand: () -> Void
    /// User tapped the checkbox. Parent routes through the cascade algorithm
    /// defined by `SelectionPolicy` so the selection propagates correctly.
    let onToggleSelect: () -> Void

    /// Equatable conformance — SwiftUI uses this when the parent applies
    /// `.equatable()` so a row whose `(node.id, level, isExpanded)` tuple
    /// is unchanged skips body evaluation. The callbacks are stable
    /// references for the view tree's lifetime, so identity changes
    /// there are not a meaningful equality signal.
    static func == (lhs: ScanTreeRow, rhs: ScanTreeRow) -> Bool {
        lhs.node.id == rhs.node.id
            && lhs.level == rhs.level
            && lhs.isExpanded == rhs.isExpanded
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Leading indent — one spacer per nesting level.
            ForEach(0..<level, id: \.self) { _ in
                Color.clear.frame(width: RowSize.indentPerLevel)
            }

            // Expand/collapse affordance — empty spacer when leaf so widths align.
            if !node.children.isEmpty {
                Button(action: onToggleExpand) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 16, height: 16)
            }

            // Tri-state checkbox — drives cascade selection.
            Button(action: onToggleSelect) {
                IndeterminateCheckbox(state: node.state)
            }
            .buttonStyle(.plain)

            // Type-specific leading icon.
            iconView

            // Title + optional secondary line (path / bundleID / action title).
            VStack(alignment: .leading, spacing: 2) {
                Text(node.title)
                    .font(Typography.largeBody())
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                if let path = pathForNode() {
                    Text(path)
                        .font(Typography.filePath())
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: Spacing.sm)

            // Right-aligned size, monospaced digits so columns stay aligned.
            Text(formatBytes(node.totalSize))
                .font(Typography.sizeNumber())
                .foregroundStyle(Color.textPrimary)
                .monospacedDigit()

            // Risk badge — compact on the top-level category row, full otherwise.
            RiskBadge(level: node.riskLevel, compact: level == 0)
        }
        .frame(height: RowSize.height)
        .padding(.horizontal, Spacing.md)
        .background(isHovered ? Color.bgSurface : Color.clear)
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .animation(.accessibleDefault(.easeOut(duration: 0.24)), value: isHovered)
    }

    /// Tracks whether the cursor is currently over the row — drives the
    /// surface tint in `body`.
    @State private var isHovered = false

    /// Picks the SF Symbol shown to the left of the title based on the
    /// runtime type of `node`. Order of `if let` / `is` checks mirrors the
    /// level order (level-4 leaf first so its custom icon wins, then
    /// level-1..3 fall through to category icons).
    ///
    /// - `ScanResult` — uses its `iconSystemName` override when provided.
    /// - `ScanCategory` — folder glyph in brand accent.
    /// - `ScanSubCategory` — app glyph in brand primary.
    /// - `ScanAction` — tray glyph in secondary text color.
    /// - Anything else — generic document glyph.
    @ViewBuilder
    private var iconView: some View {
        if let result = node as? ScanResult, let icon = result.iconSystemName {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(Color.textSecondary)
                .frame(width: RowSize.iconSize, height: RowSize.iconSize)
        } else if node is ScanCategory {
            Image(systemName: "folder.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.brandAccent)
                .frame(width: RowSize.iconSize, height: RowSize.iconSize)
        } else if node is ScanSubCategory {
            Image(systemName: "app.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.brandPrimary)
                .frame(width: RowSize.iconSize, height: RowSize.iconSize)
        } else if node is ScanAction {
            Image(systemName: "tray.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.textSecondary)
                .frame(width: RowSize.iconSize, height: RowSize.iconSize)
        } else {
            Image(systemName: "doc.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.textSecondary)
                .frame(width: RowSize.iconSize, height: RowSize.iconSize)
        }
    }

    /// Resolves the secondary line shown under the title for the given node
    /// type. Returns `nil` when the node level has no meaningful secondary
    /// descriptor (e.g. top-level categories show only their title).
    ///
    /// - `ScanResult` — filesystem path of the matched file.
    /// - `ScanAction` — repeats the action title as the secondary line so
    ///   the user always sees the action's descriptor alongside its parent.
    /// - `ScanSubCategory` — prefers the app `bundleID` (e.g. `com.apple.Safari`)
    ///   and falls back to the title if no bundle ID is set.
    /// - `ScanCategory` — no secondary line.
    private func pathForNode() -> String? {
        if let result = node as? ScanResult {
            return result.path
        } else if let action = node as? ScanAction {
            return action.title
        } else if let sub = node as? ScanSubCategory {
            return sub.bundleID ?? sub.title
        }
        return nil
    }

    /// Formats a byte count as a localized file-size string (e.g.
    /// `"12.4 MB"`). Uses `.file` style to favor MB/GB units over the
    /// block-count style of `.binary`. Reads from the process-wide
    /// `sharedByteCountFormatter` so construction cost is paid once.
    private func formatBytes(_ bytes: Int64) -> String {
        sharedByteCountFormatter.string(fromByteCount: bytes)
    }
}

#if DEBUG
/// Xcode preview surface that exercises the row across all four node types
/// and across both compact and full risk-badge modes.
struct ScanTreeRow_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScanTreeRow(
                node: PreviewTreeNodes.category,
                level: 0,
                isExpanded: true,
                onToggleExpand: {},
                onToggleSelect: {}
            )
            ScanTreeRow(
                node: PreviewTreeNodes.subCategory,
                level: 1,
                isExpanded: true,
                onToggleExpand: {},
                onToggleSelect: {}
            )
            ScanTreeRow(
                node: PreviewTreeNodes.action,
                level: 2,
                isExpanded: true,
                onToggleExpand: {},
                onToggleSelect: {}
            )
            ScanTreeRow(
                node: PreviewTreeNodes.result,
                level: 3,
                isExpanded: false,
                onToggleExpand: {},
                onToggleSelect: {}
            )
        }
        .padding()
        .background(Color.bgCanvas)
    }
}

/// Lightweight fixture nodes used by the preview canvas so the canvas
/// compiles without dragging in the full scan-engine wiring.
private enum PreviewTreeNodes {
    static let category = ScanCategory(
        categoryID: "system.cache",
        title: "System Cache",
        totalSize: 1_245_000_000,
        state: .mixed
    )
    static let subCategory = ScanSubCategory(
        subCategoryID: "browser.cookies",
        title: "Browser Cookies",
        bundleID: "com.apple.Safari",
        totalSize: 23_500_000,
        state: .on
    )
    static let action = ScanAction(
        actionID: "user.cache",
        actionType: .cache,
        title: "User Cache",
        totalSize: 8_400_000,
        state: .off
    )
    static let result = ScanResult(
        url: URL(fileURLWithPath: "/tmp/example/com.example.app/cache.db"),
        path: "/tmp/example/com.example.app/cache.db",
        title: "cache.db",
        fileSize: 4_200_000,
        cleanType: .database,
        riskLevel: .caution
    )
}
#endif
