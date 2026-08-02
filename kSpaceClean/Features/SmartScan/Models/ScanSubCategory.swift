// kSpaceClean/Features/SmartScan/Models/ScanSubCategory.swift
import Foundation

/// Level-2 node in the scan-result tree.
///
/// A `ScanSubCategory` typically groups scan results under a single app
/// (e.g. "Xcode DerivedData") or a logical subsystem (e.g. "Browser
/// Cookies"). It has two rendering modes controlled by `showAction`:
///
/// * `showAction == true` — children are `ScanAction` rows; the
///   individual files are nested under the action.
/// * `showAction == false` — children are `ScanResult` files directly
///   (used when there is no meaningful action-level grouping).
///
/// Concurrency: same `@unchecked Sendable` rationale as `ScanCategory`.
public final class ScanSubCategory: ScanTreeNode, @unchecked Sendable {
    public let id: UUID
    public let subCategoryID: String
    /// App Bundle ID when this sub-category is scoped to a single app.
    public let bundleID: String?
    /// Display name when this sub-category is app-scoped.
    public let appName: String?
    public let title: String
    public let tooltip: String?
    public var totalSize: Int64
    public var selectedSize: Int64
    public var state: CheckState
    public var actions: [ScanAction]
    public var directResults: [ScanResult]
    public var showAction: Bool
    public let riskLevel: RiskLevel
    public let isRecommended: Bool
    /// True when this sub-category is a synthesized "pseudo-app" row for an
    /// unmatched top-level folder (Task B1). Pseudo-app rows are always
    /// `.caution` risk (never auto-selected) and exempt from the small-file
    /// fold (see `ScanResultsViewModel.annotateSubHidden`).
    public let isPseudoApp: Bool
    public var isHiddenByFilter: Bool = false

    /// Direct children flattened for SwiftUI outline rendering. Switches
    /// source array based on `showAction` so the parent picker doesn't have
    /// to know about the rendering mode.
    public var children: [any ScanTreeNode] {
        showAction ? (actions as [any ScanTreeNode]) : (directResults as [any ScanTreeNode])
    }

    public init(
        id: UUID = UUID(),
        subCategoryID: String,
        title: String,
        bundleID: String? = nil,
        appName: String? = nil,
        tooltip: String? = nil,
        totalSize: Int64 = 0,
        selectedSize: Int64 = 0,
        state: CheckState = .off,
        actions: [ScanAction] = [],
        directResults: [ScanResult] = [],
        showAction: Bool = true,
        riskLevel: RiskLevel = .recommended,
        isRecommended: Bool = true,
        isPseudoApp: Bool = false,
        isHiddenByFilter: Bool = false
    ) {
        self.id = id
        self.subCategoryID = subCategoryID
        self.title = title
        self.bundleID = bundleID
        self.appName = appName
        self.tooltip = tooltip
        self.totalSize = totalSize
        self.selectedSize = selectedSize
        self.state = state
        self.actions = actions
        self.directResults = directResults
        self.showAction = showAction
        self.riskLevel = riskLevel
        self.isRecommended = isRecommended
        self.isPseudoApp = isPseudoApp
        self.isHiddenByFilter = isHiddenByFilter
    }

    /// Cascade-toggle. Mirrors the v3 spec rule (CLAUDE.md §8.5):
    /// - When the user toggles a sub-category OFF, every descendant is
    ///   forced OFF so the cleanup flow never sees a half-selected subtree.
    /// - When the user toggles a sub-category ON, descendants whose
    ///   `riskLevel.defaultChecked` is `true` (i.e. `.recommended`) are
    ///   auto-selected; non-recommended descendants (`.optional`, `.caution`,
    ///   `.dangerous`) stay OFF. This applies to both the
    ///   `showAction == true` (per-action) and `showAction == false`
    ///   (per-result) cascades — both can contain `.dangerous` leaves.
    public func setState(_ newState: CheckState) {
        guard state != newState else { return }
        state = newState
        guard newState != .mixed else { return }
        if showAction {
            for action in actions {
                if newState == .off {
                    action.setState(.off)
                } else {
                    // The action's `recommend` flag is the historical source
                    // of truth; for actions that carry an explicit `riskLevel`
                    // (e.g. `.dangerous`) we additionally consult
                    // `riskLevel.defaultChecked` so a manually-classified
                    // dangerous action is never auto-selected.
                    let shouldAutoSelect = action.recommend && action.riskLevel.defaultChecked
                    action.setState(shouldAutoSelect ? .on : .off)
                }
            }
        } else {
            for result in directResults {
                if newState == .off {
                    result.setState(.off)
                } else {
                    // Per-result cascade — same rule. A `.dangerous` leaf
                    // under a sub-category that just flipped ON must NOT
                    // be auto-selected (data-loss vector). The user can
                    // still check it manually via the per-row checkbox.
                    result.setState(result.riskLevel.defaultChecked ? .on : .off)
                }
            }
        }
    }

    /// Aggregate child states into the parent row.
    public func refreshState() {
        let states = showAction
            ? actions.map(\.state)
            : directResults.map(\.state)
        let total = states.count
        guard total > 0 else { return }
        let onCount = states.filter { $0 == .on }.count
        if onCount == total { state = .on }
        else if onCount == 0 { state = .off }
        else { state = .mixed }
    }

    /// Flatten every selected URL from the appropriate child array.
    public func collectSelected() -> [URL] {
        showAction
            ? actions.flatMap { $0.collectSelected() }
            : directResults.flatMap { $0.collectSelected() }
    }
}
