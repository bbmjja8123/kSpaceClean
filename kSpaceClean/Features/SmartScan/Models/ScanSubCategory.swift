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
    public let showAction: Bool
    public let riskLevel: RiskLevel
    public let isRecommended: Bool

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
        isRecommended: Bool = true
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
    }

    /// Cascade-toggle. Mirrors the v3 spec rule: when the user toggles a
    /// sub-category ON, recommended actions auto-select while non-recommended
    /// ones (Optional/Caution/Dangerous) stay OFF. When toggled OFF, every
    /// descendant is forced OFF.
    public func setState(_ newState: CheckState) {
        guard state != newState else { return }
        state = newState
        guard newState != .mixed else { return }
        if showAction {
            for action in actions {
                if newState == .off {
                    action.setState(.off)
                } else {
                    action.setState(action.recommend ? .on : .off)
                }
            }
        } else {
            for result in directResults {
                result.setState(newState)
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
