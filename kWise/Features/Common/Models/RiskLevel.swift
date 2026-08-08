// kWise/Features/Common/Models/RiskLevel.swift
import Foundation
import SwiftUI

// MARK: - Risk Levels (v3 UX spec §1.2)

/// 4-level risk classification applied to scan results, default-selection policy,
/// and the visual treatment of cleanup actions.
///
/// `RiskLevel` lives under `Features/Common/Models/` because both the design system
/// (`Common/DesignSystem/Colors.swift`) and feature modules (`SmartScan`, `Cleanup`)
/// depend on it — keeping it inside the shared `Common/` layer avoids a layering
/// inversion where lower-level modules would need to import higher-level feature
/// modules.
public enum RiskLevel: Int, Codable, Sendable, CaseIterable, Comparable {
    /// Safe to clean: software/system regenerated automatically. Default selected.
    case recommended = 0
    /// Cleaning has limited effect but no side effects. Usually optional.
    case optional = 1
    /// Cleaning causes minor recovery cost (re-login, rebuild cache). Off by default.
    case caution = 2
    /// Cleaning affects running apps or may cause data loss. Requires double confirm.
    case dangerous = 3

    /// Compare by severity so callers can use `<`/`max(...)` over a collection of levels.
    public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Initialize from scan-action properties (legacy mapping from `ScanAction`).
    public static func from(recommended: Bool, cautionID: Int?) -> RiskLevel {
        if let cid = cautionID, cid != 0 {
            return .caution
        }
        return recommended ? .recommended : .optional
    }

    /// Display name for the Chinese UI surface used throughout kWise.
    /// Equivalent to the canonical `label` property — kept for backwards compatibility
    /// with existing call sites that predate the v3 spec.
    public var displayName: String {
        switch self {
        case .recommended: return "推荐"
        case .optional: return "可选"
        case .caution: return "谨慎"
        case .dangerous: return "危险"
        }
    }

    /// Canonical v3-spec label shown in risk badges and row titles.
    public var label: String {
        switch self {
        case .recommended: return "推荐"
        case .optional: return "可选"
        case .caution: return "谨慎"
        case .dangerous: return "危险"
        }
    }

    /// SF Symbol name representing this risk in the row badge / toolbar.
    public var iconName: String {
        switch self {
        case .recommended: return "checkmark.circle.fill"
        case .optional: return "circle"
        case .caution: return "exclamationmark.triangle.fill"
        case .dangerous: return "flame.fill"
        }
    }

    /// Whether items at this risk level should be selected by default in the tree.
    /// Only `.recommended` is selected on first load — the cascade-checkbox algorithm
    /// then propagates selection to children.
    public var defaultChecked: Bool {
        self == .recommended
    }

    /// Whether cleaning items at this level requires a second confirmation prompt.
    /// Reserved for `.dangerous` per the v3 spec (§1.2). The actual confirmation UI
    /// lives in `CleanupConfirmSheet` and `DangerousConfirmDialog` (Tasks C4 / C5).
    public var requiresDoubleConfirm: Bool {
        self == .dangerous
    }
}

// MARK: - RiskLevel color mapping

extension RiskLevel {
    /// Background color shown behind the risk badge or row.
    /// The palette mirrors Apple HIG risk semantics so users familiar with macOS
    /// get instant recognition (green = safe, orange = caution, red = dangerous).
    public var backgroundColor: Color {
        switch self {
        case .recommended: return .riskRecommended
        case .optional: return .riskOptional
        case .caution: return .riskCaution
        case .dangerous: return .riskDangerous
        }
    }

    /// Foreground (text/icon) color used on top of `backgroundColor`.
    /// Returns black for `.caution` because the orange background lacks contrast
    /// with white at WCAG AA; all other cases use white.
    public var foregroundColor: Color {
        switch self {
        case .caution: return .black
        default: return .white
        }
    }
}
