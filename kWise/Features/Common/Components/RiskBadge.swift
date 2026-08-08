// kWise/Features/Common/Components/RiskBadge.swift
import SwiftUI

/// Compact visual badge showing the 4-level risk classification for a scan item.
///
/// The badge renders the icon and (optionally) label for any ``RiskLevel`` and
/// is consumed by `ScanTreeRow`, the suggestions tab, and any cleanup-confirm
/// surfaces that need to communicate severity at a glance.
///
/// Use `compact: true` for inline placement (e.g. next to a row title) where the
/// label would crowd the layout; the default size is reserved for the
/// suggestions header / result summary where the label adds context.
///
/// Layout: a small pill with an SF Symbol on the left and the localized risk
/// label on the right (omitted in `compact` mode). Background is the level's
/// brand color at 18% opacity with a 0.5pt stroke at 40% opacity so the badge
/// reads against any underlying surface.
struct RiskBadge: View {
    let level: RiskLevel
    var compact: Bool = false

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: level.iconName)
                .font(.system(size: compact ? 8 : 10, weight: .semibold))
            if !compact {
                Text(level.label)
                    .font(.system(size: 10, weight: .semibold))
            }
        }
        .foregroundStyle(level.foregroundColor)
        .padding(.horizontal, compact ? 4 : 6)
        .padding(.vertical, 3)
        .background(level.backgroundColor.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm)
                .stroke(level.backgroundColor.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityLabel("风险等级，\(level.label)")
    }
}

#if DEBUG
struct RiskBadge_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            RiskBadge(level: .recommended)
            RiskBadge(level: .optional)
            RiskBadge(level: .caution)
            RiskBadge(level: .dangerous)
            RiskBadge(level: .recommended, compact: true)
        }
        .padding()
        .background(Color.bgCanvas)
    }
}
#endif