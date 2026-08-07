// kSpaceClean/Features/Common/DesignSystem/Spacing.swift
import Foundation

/// Spacing scale tokens for kSpaceClean.
///
/// A 7-step scale (2pt → 48pt) used for margins, padding, and gaps.
/// Picked from an 8-point base grid so layouts align to pixel boundaries at 1x/2x.
enum Spacing {
    /// 2pt — micro insets, optical adjustments inside icon buttons.
    static let xxs: CGFloat = 2
    /// 4pt — tight inline spacing, separator-to-label distance.
    static let xs: CGFloat = 4
    /// 8pt — compact stack spacing between sibling elements.
    static let sm: CGFloat = 8
    /// 16pt — default content padding / gap between major blocks.
    static let md: CGFloat = 16
    /// 24pt — generous padding around cards and panels.
    static let lg: CGFloat = 24
    /// 32pt — section spacing inside scrollable content.
    static let xl: CGFloat = 32
    /// 48pt — page-level spacing between hero and content.
    static let xxl: CGFloat = 48
}

/// Corner-radius tokens for surfaces and controls.
enum Radius {
    /// 4pt — small surfaces, inline controls (chips, badges).
    static let sm: CGFloat = 4
    /// 8pt — default for cards and buttons.
    static let md: CGFloat = 8
    /// 12pt — larger surfaces, panels.
    static let lg: CGFloat = 12
    /// 16pt — large modals, hero surfaces.
    static let xl: CGFloat = 16
}

/// Row geometry tokens used by the 4-level tree rows so every level looks identical.
enum RowSize {
    /// Height of a tree row; applies uniformly across all 4 levels.
    static let height: CGFloat = 48
    /// Diameter of the checkbox / indicator inside each row.
    static let checkboxSize: CGFloat = 18
    /// Edge length of the leading icon in each row.
    static let iconSize: CGFloat = 24
    /// Horizontal indent added per tree level for nested rows.
    static let indentPerLevel: CGFloat = 24
}
