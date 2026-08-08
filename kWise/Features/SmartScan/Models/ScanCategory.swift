// kWise/Features/SmartScan/Models/ScanCategory.swift
import Foundation

/// Level-1 node in the scan-result tree.
///
/// `ScanCategory` represents one of the six top-level buckets the user
/// sees before any scan runs (e.g. "System Cache", "App Cache"). It owns
/// 1..N `ScanSubCategory` children and is the visual row labeled with
/// the colored risk badge.
///
/// Concurrency: `final class` with mutable `state`/`selectedSize` because
/// `ScanViewModel` mutates these on the main actor and `@unchecked
/// Sendable` is the project's documented escape hatch for the tree
/// (see `ScanViewModel` notes). All mutations are expected to happen on a
/// single isolation domain.
public final class ScanCategory: ScanTreeNode, @unchecked Sendable {
    public let id: UUID
    /// Stable identifier (e.g. `"system.cache"`, `"app.cache"`).
    public let categoryID: String
    public let title: String
    public let tooltip: String?
    public let totalSize: Int64
    public var selectedSize: Int64
    public var state: CheckState
    public var subItems: [ScanSubCategory]
    public let riskLevel: RiskLevel
    public let isRecommended: Bool
    public var showAction: Bool = false
    public var isHiddenByFilter: Bool = false

    /// Direct children flattened for SwiftUI outline rendering.
    public var children: [any ScanTreeNode] { subItems }

    public init(
        id: UUID = UUID(),
        categoryID: String,
        title: String,
        tooltip: String? = nil,
        totalSize: Int64 = 0,
        selectedSize: Int64 = 0,
        state: CheckState = .off,
        subItems: [ScanSubCategory] = [],
        riskLevel: RiskLevel = .recommended,
        isRecommended: Bool = true,
        isHiddenByFilter: Bool = false
    ) {
        self.id = id
        self.categoryID = categoryID
        self.title = title
        self.tooltip = tooltip
        self.totalSize = totalSize
        self.selectedSize = selectedSize
        self.state = state
        self.subItems = subItems
        self.riskLevel = riskLevel
        self.isRecommended = isRecommended
        self.isHiddenByFilter = isHiddenByFilter
    }

    /// Cascade-toggle: setting `.on`/`.off` flips every child to that exact
    /// state, **except** that on the `.on` path a child whose `riskLevel` does
    /// not have `defaultChecked` (i.e. anything other than `.recommended`)
    /// stays OFF. This enforces CLAUDE.md §8.5 — only `.recommended` items
    /// are auto-selected when a parent flips ON. `.mixed` is never propagated
    /// downward — it only arises from `refreshState()` after child aggregation.
    public func setState(_ newState: CheckState) {
        guard state != newState else { return }
        state = newState
        guard newState != .mixed else { return }
        for child in subItems {
            // When the user flips a parent ON, do not blanket-flip every
            // child to ON — that would auto-select `.optional` / `.caution` /
            // `.dangerous` items, which is a data-loss vector for `.dangerous`.
            // When the user flips a parent OFF, every child must be forced OFF
            // so the cleanup flow never sees a half-selected subtree.
            if newState == .on {
                child.setState(child.riskLevel.defaultChecked ? .on : .off)
            } else {
                child.setState(.off)
            }
        }
    }

    /// Aggregate child states into the parent row. Categories with no
    /// children keep their last assigned state (the row stays in whatever
    /// the most recent user interaction left it).
    public func refreshState() {
        let states = subItems.map(\.state)
        let total = states.count
        guard total > 0 else { return }
        let onCount = states.filter { $0 == .on }.count
        if onCount == total { state = .on }
        else if onCount == 0 { state = .off }
        else { state = .mixed }
    }

    /// Flatten every selected URL from the entire subtree.
    public func collectSelected() -> [URL] {
        subItems.flatMap { $0.collectSelected() }
    }
}
