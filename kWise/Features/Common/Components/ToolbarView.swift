// kWise/Features/Common/Components/ToolbarView.swift
import SwiftUI

/// Top toolbar rendered above the scan results surface.
///
/// The toolbar is split into two halves:
///
/// - **Leading region** — the kWise brand mark (sparkles icon + word
///   mark). Anchors users to the product and gives the toolbar a stable
///   visual identity.
/// - **Trailing region** — four icon-and-label buttons for the four primary
///   navigation destinations: Scan, Clean, Warning, Account.
///
/// Layout, colour, and typography are pulled from the design-system tokens
/// (`Spacing`, `Radius`, `Color`, `Typography`) so the toolbar stays in
/// visual lockstep with the rest of the app shell.
///
/// The toolbar itself is purely presentational — it does not own navigation
/// state. The parent passes closures (`onScan`, `onClean`, …) and the host
/// view model decides what those actions actually do. This keeps the
/// toolbar trivially testable and previewable in isolation.
///
/// ## Usage
///
/// ```swift
/// ToolbarView(
///     onScan:    { viewModel.startScan() },
///     onClean:   { viewModel.startCleanup() },
///     onWarning: { viewModel.showWarnings() },
///     onProfile: { viewModel.showAccount() }
/// )
/// ```
struct ToolbarView: View {
    /// Closure invoked when the user taps the Scan button.
    var onScan: () -> Void
    /// Closure invoked when the user taps the Clean button.
    var onClean: () -> Void
    /// Closure invoked when the user taps the Warning button.
    var onWarning: () -> Void
    /// Closure invoked when the user taps the Account button.
    var onProfile: () -> Void

    /// Renders the toolbar as a horizontal stack with a brand mark on the
    /// left and four action buttons on the right, separated by a spacer.
    var body: some View {
        HStack(spacing: Spacing.md) {
            // Leading brand mark
            HStack(spacing: Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.brandPrimary)
                    .accessibilityHidden(true)

                Text("kWise")
                    .font(Typography.mediumTitle())
                    .foregroundStyle(Color.textPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel(Text("kWise"))

            Spacer()

            // Trailing action buttons
            HStack(spacing: Spacing.sm) {
                ToolbarButton(icon: "magnifyingglass", title: "扫描", action: onScan)
                    .accessibilityLabel(Text("扫描"))
                ToolbarButton(icon: "trash", title: "清理", action: onClean)
                    .accessibilityLabel(Text("清理"))
                ToolbarButton(icon: "exclamationmark.triangle", title: "警告", action: onWarning)
                    .accessibilityLabel(Text("警告"))
                ToolbarButton(icon: "person.circle", title: "账户", action: onProfile)
                    .accessibilityLabel(Text("账户"))
            }
        }
        .padding(.horizontal, Spacing.md)
        .frame(height: 64)
        .background(Color.bgElevated)
        .accessibilityElement(children: .contain)
    }
}

/// Icon-and-label button used inside the toolbar's trailing region.
///
/// Renders a stack of an SF Symbol icon and a small caption below it,
/// inside a 56×40 hit target. The button tracks hover state with the
/// `.onHover` modifier and switches to the `bgSurface` token when the
/// pointer enters its bounds, giving the button a subtle macOS-native
/// feedback feel without resorting to platform-specific control styling.
///
/// Uses `.plain` button style so SwiftUI's default focus rings and
/// pressed-state affordances still work for keyboard users.
struct ToolbarButton: View {
    /// SF Symbol name rendered above the caption.
    let icon: String
    /// Caption displayed beneath the icon.
    let title: String
    /// Action closure invoked on tap.
    let action: () -> Void

    /// Whether the pointer is currently over the button's bounds.
    @State private var isHovered = false

    /// The button is laid out as a VStack inside a fixed-size frame so that
    /// every toolbar button has the same footprint regardless of icon or
    /// caption length.
    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .accessibilityHidden(true)

                Text(title)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(Color.textSecondary)
            .frame(width: 56, height: 40)
            .background(isHovered ? Color.bgSurface : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .contentShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#if DEBUG
/// SwiftUI previews that place the toolbar over a representative scan
/// results background so designers can eyeball its spacing and colour.
struct ToolbarView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 0) {
            ToolbarView(
                onScan: {},
                onClean: {},
                onWarning: {},
                onProfile: {}
            )
            Spacer()
        }
        .frame(width: 800, height: 400)
        .background(Color.bgCanvas)
    }
}
#endif
