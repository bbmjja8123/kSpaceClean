// kWise/Features/SmartScan/Models/ScanAction.swift
import Foundation

/// Categorizes the type of cleanup a `ScanAction` performs.
///
/// Used by the cleanup engine to pick the right `CleanActionExecutor`
/// (see `Cleanup/CleanActionExecutors.swift`) and to drive localized
/// labels in the UI. Mirrors the legacy Lemon action taxonomy.
public enum ScanActionType: String, Sendable {
    /// Generic cache files (regenerated automatically).
    case cache = "cache"
    /// Log files that the app rewrites on launch.
    case log = "log"
    /// User preferences / plist overrides.
    case preference = "preference"
    /// Local databases (SQLite, Core Data stores).
    case database = "database"
    /// Temporary files safe to delete.
    case temporary = "temporary"
    /// App history (recent files, undo history).
    case history = "history"
    /// Web cookies.
    case cookie = "cookie"
    /// Mail / chat attachments.
    case attachment = "attachment"
    /// Architecture-specific binary variants.
    case binary = "binary"
    /// Localization (.lproj) files for unused languages.
    case language = "language"
    /// App saved state (window restoration data).
    case savedState = "savedState"
}

/// Level-3 node in the scan-result tree.
///
/// A `ScanAction` represents a single cleanable artifact under a
/// sub-category (e.g. "User Cache", "Log Files"). It owns the actual
/// `ScanResult` rows and carries the `recommend` flag that the v3
/// cascade-checkbox algorithm uses to decide whether to auto-select
/// when the parent flips ON.
///
/// Concurrency: same `@unchecked Sendable` rationale as `ScanCategory`.
public final class ScanAction: ScanTreeNode, @unchecked Sendable {
    public let id: UUID
    public let actionID: String
    public let actionType: ScanActionType
    public let title: String
    public let tooltip: String?
    public var totalSize: Int64
    public var selectedSize: Int64
    public var state: CheckState
    public var results: [ScanResult]
    /// `recommend` is the gating flag for the parent's "auto-select" rule.
    /// When the parent sub-category is toggled ON, only `recommend == true`
    /// actions get checked. This is the original-source flag that gets
    /// folded into `RiskLevel` (see `RiskLevel.from(recommended:cautionID:)`).
    public let recommend: Bool
    public let riskLevel: RiskLevel
    public let isRecommended: Bool
    public let showAction: Bool = false
    public var isHiddenByFilter: Bool = false

    /// Direct children flattened for SwiftUI outline rendering.
    public var children: [any ScanTreeNode] { results }

    public init(
        id: UUID = UUID(),
        actionID: String,
        actionType: ScanActionType,
        title: String,
        tooltip: String? = nil,
        totalSize: Int64 = 0,
        selectedSize: Int64 = 0,
        state: CheckState = .off,
        results: [ScanResult] = [],
        recommend: Bool = true,
        riskLevel: RiskLevel = .recommended,
        isRecommended: Bool = true,
        isHiddenByFilter: Bool = false
    ) {
        self.id = id
        self.actionID = actionID
        self.actionType = actionType
        self.title = title
        self.tooltip = tooltip
        self.totalSize = totalSize
        self.selectedSize = selectedSize
        self.state = state
        self.results = results
        self.recommend = recommend
        self.riskLevel = riskLevel
        self.isRecommended = isRecommended
        self.isHiddenByFilter = isHiddenByFilter
    }

    /// Cascade-toggle: propagate the new state to every result underneath.
    /// Results are gated per-result exactly like the direct-results branch
    /// (`ScanSubCategory.setState`): a `.recommended` result auto-selects on
    /// `.on`, everything else (`.optional`, `.caution`, `.dangerous`) stays
    /// OFF so a cascade never force-selects a data-loss-risk leaf. The user
    /// can still check any result manually via the per-row checkbox.
    public func setState(_ newState: CheckState) {
        guard state != newState else { return }
        state = newState
        guard newState != .mixed else { return }
        for result in results {
            if newState == .on {
                result.setState(result.riskLevel.defaultChecked ? .on : .off)
            } else {
                result.setState(.off)
            }
        }
    }

    /// Aggregate result states into the parent row.
    public func refreshState() {
        let total = results.count
        guard total > 0 else { return }
        let onCount = results.filter { $0.state == .on }.count
        if onCount == total { state = .on }
        else if onCount == 0 { state = .off }
        else { state = .mixed }
    }

    /// Flatten every selected URL from each result, filtering to those
    /// actually checked. (Result-side filtering happens here rather than
    /// inside `ScanResult.collectSelected()` because the action row is the
    /// one driven by user interaction.)
    public func collectSelected() -> [URL] {
        results.filter { $0.state == .on }.flatMap { $0.collectSelected() }
    }
}
