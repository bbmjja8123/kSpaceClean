// kSpaceClean/Features/SmartScan/Models/ScanTreeNode.swift
import Foundation

/// Shared interface for the four-level scan-result tree.
///
/// `ScanTreeNode` is the v3 (post-2026-07-29 redesign) abstraction over the
/// category → sub-category → action → result cascade. Concrete types live
/// in their own files (`ScanCategory`, `ScanSubCategory`, `ScanAction`,
/// `ScanResult`). The tree powers the results UI in `ScanResultsView` and
/// the cascading selection policy implemented in `ScanViewModel`.
///
/// All nodes are value-equivalent by `id` — `Hashable`/`Equatable` collapse
/// to UUID comparison so the SwiftUI `OutlineGroup` can diff the tree by
/// identity without paying per-field cost.
public protocol ScanTreeNode: Identifiable, Hashable, Sendable {
    /// Stable identifier for diffing across the SwiftUI tree.
    var id: UUID { get }
    /// Localized title shown in the row.
    var title: String { get }
    /// Optional tooltip — surfaced as a Help tag on hover.
    var tooltip: String? { get }
    /// Total size in bytes including all descendants.
    var totalSize: Int64 { get }
    /// Size in bytes that will actually be cleaned when this node is selected.
    var selectedSize: Int64 { get }
    /// Tri-state checkbox for the row.
    var state: CheckState { get set }
    /// Direct children flattened as an existential array (handy for SwiftUI).
    var children: [any ScanTreeNode] { get }
    /// Risk grade that drives the default-selection policy and the badge.
    var riskLevel: RiskLevel { get }
    /// Whether the row should be auto-checked by the default-selection algorithm.
    var isRecommended: Bool { get }
    /// Whether the sub-category row exposes an intermediate "Action" level.
    /// `true` only for `ScanSubCategory`; the other three types always return `false`.
    var showAction: Bool { get }

    /// Propagate a user-driven state change from this node down to every descendant.
    /// Implementations must NOT mutate upward — the parent re-aggregates via `refreshState()`.
    func setState(_ newState: CheckState)
    /// Recompute `state` from the children's current `state` values.
    /// Called after child mutations to bubble up a parent `.mixed`/`.on`/`.off`.
    func refreshState()
    /// Walk the subtree and collect every `URL` whose row is in the `.on` state.
    /// Used by the cleanup engine to build the actual delete list.
    func collectSelected() -> [URL]
}

public extension ScanTreeNode {
    /// Hash by `id` only — content-based hashing would invalidate the
    /// `OutlineGroup` cache when only `totalSize`/`selectedSize` change.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Two nodes are equal iff their `id`s match. This intentionally ignores
    /// transient fields like `totalSize`/`state` so the SwiftUI diff stays
    /// cheap as the scan progresses.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
