// kSpaceClean/Features/Common/Models/SelectionPolicy.swift
import Foundation

/// Policy that controls which risk levels are pre-selected in the scan-result tree.
///
/// Mirrors the v3 spec (§1.2 "Cascading Selection") — see also `RiskLevel` for the
/// 4-level classification and `CheckState` for the 3-state checkbox used in the
/// tree UI. Lifted out of `ScanRule.swift` alongside `CheckState` so all shared
/// scan-tree model types live in the `Common/Models/` layer (the A1 layering fix
/// established `Common/` as the canonical home for cross-feature enums).
public enum RecommendPolicy: String, Codable, Sendable, CaseIterable {
    /// Only select `.recommended` items by default.
    case strict
    /// Select `.recommended` and `.optional` items by default.
    case `default`
    /// Select `.recommended`, `.optional`, and `.caution` items by default.
    case autoSelectCaution

    /// Whether a given risk level should be selected by default under this policy.
    public func shouldSelect(_ level: RiskLevel) -> Bool {
        switch (self, level) {
        case (_, .dangerous): return false
        case (_, .recommended): return true
        case (_, .optional): return self != .strict
        case (_, .caution): return self == .autoSelectCaution
        }
    }
}

/// Resolves whether a node should be default-selected based on its risk level and
/// the active `RecommendPolicy`. Pure value type so the cascade-checkbox algorithm
/// in `ScanViewModel.applyDefaultSelection(...)` can run safely on the main actor.
public struct DefaultSelectionPolicy: Sendable {
    public let policy: RecommendPolicy

    public init(policy: RecommendPolicy = .default) {
        self.policy = policy
    }

    public func shouldSelect(_ riskLevel: RiskLevel) -> Bool {
        policy.shouldSelect(riskLevel)
    }

    /// Bridge from the legacy scan-action shape (`recommended` flag + optional
    /// caution id) to the canonical `RiskLevel` API.
    public func shouldSelect(recommended: Bool, cautionID: Int?) -> Bool {
        let level = RiskLevel.from(recommended: recommended, cautionID: cautionID)
        return shouldSelect(level)
    }
}