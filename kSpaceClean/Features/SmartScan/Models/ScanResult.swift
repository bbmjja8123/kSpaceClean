// kSpaceClean/Features/SmartScan/Models/ScanResult.swift
import Foundation

/// Categorizes the type of cleanup a `ScanResult` represents.
///
/// Extends `ScanActionType` with two scanner-specific cases that only
/// appear at the leaf level: `snapshot` (Time Machine local snapshots)
/// and `keychain` (certificate / password artifacts). Drives the
/// appropriate `CleanActionExecutor` in the cleanup engine.
public enum CleanType: String, Sendable {
    case cache = "cache"
    case log = "log"
    case preference = "preference"
    case database = "database"
    case temporary = "temporary"
    case history = "history"
    case cookie = "cookie"
    case attachment = "attachment"
    case binary = "binary"
    case language = "language"
    case savedState = "savedState"
    /// Time Machine local snapshots — disabling them is reversible but
    /// temporarily removes the rollback safety net.
    case snapshot = "snapshot"
    /// Keychain items — cleaning requires explicit user prompt.
    case keychain = "keychain"
}

/// Level-4 leaf node in the scan-result tree.
///
/// `ScanResult` represents a single file or directory that the scan
/// found and the cleanup engine can act on. It carries the file's URL,
/// size, modification date, and a `CleanType` so the right executor
/// picks it up. A `ScanResult` may recursively nest other `ScanResult`
/// items (e.g. a folder containing individual cache files) — the
/// effective `totalSize` is the sum of `fileSize` plus all descendants.
///
/// Concurrency: same `@unchecked Sendable` rationale as `ScanCategory`.
public final class ScanResult: ScanTreeNode, @unchecked Sendable {
    public let id: UUID
    public let url: URL
    /// Cached filesystem path for display (avoids re-computing
    /// `url.path` in every row render).
    public let path: String
    public let title: String
    public let tooltip: String?
    public let iconSystemName: String?
    public let fileSize: Int64
    public let modificationDate: Date?
    public let cleanType: CleanType
    /// Optional caution identifier — when non-nil, the UI shows the
    /// "Caution" risk badge and the cleanup flow demands extra confirmation.
    public let cautionID: String?
    public var nestedResults: [ScanResult]
    public var state: CheckState
    public var selectedSize: Int64
    public let riskLevel: RiskLevel
    public let isRecommended: Bool
    public let showAction: Bool = false

    /// Total size including nested results. Computed on read so the
    /// scanner can append to `nestedResults` after the row is already
    /// mounted in the tree.
    public var totalSize: Int64 {
        fileSize + nestedResults.reduce(0) { $0 + $1.totalSize }
    }

    /// Direct children flattened for SwiftUI outline rendering.
    public var children: [any ScanTreeNode] { nestedResults }

    public init(
        id: UUID = UUID(),
        url: URL,
        path: String,
        title: String,
        tooltip: String? = nil,
        iconSystemName: String? = nil,
        fileSize: Int64,
        modificationDate: Date? = nil,
        cleanType: CleanType,
        cautionID: String? = nil,
        nestedResults: [ScanResult] = [],
        state: CheckState = .off,
        riskLevel: RiskLevel = .recommended,
        isRecommended: Bool = true
    ) {
        self.id = id
        self.url = url
        self.path = path
        self.title = title
        self.tooltip = tooltip
        self.iconSystemName = iconSystemName
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.cleanType = cleanType
        self.cautionID = cautionID
        self.nestedResults = nestedResults
        self.state = state
        self.selectedSize = state == .on ? fileSize : 0
        self.riskLevel = riskLevel
        self.isRecommended = isRecommended
    }

    /// Cascade-toggle: flip own state, mirror `selectedSize` to `fileSize`
    /// when selected, and propagate to nested results.
    public func setState(_ newState: CheckState) {
        guard state != newState else { return }
        state = newState
        selectedSize = (newState == .on) ? fileSize : 0
        for nested in nestedResults {
            nested.setState(newState)
        }
    }

    /// Leaf node: `state` is set directly by the user (or by parent
    /// cascade), nothing to aggregate up from children.
    public func refreshState() {
        // Leaf node: state set by user directly
    }

    /// Collect this row's URL (when checked) plus every checked nested URL.
    public func collectSelected() -> [URL] {
        if state == .on {
            var urls = [url]
            urls.append(contentsOf: nestedResults.filter { $0.state == .on }.flatMap { $0.collectSelected() })
            return urls
        }
        return []
    }
}
