import SwiftUI

/// Tri-state checkbox that renders unchecked, checked, or mixed selection.
///
/// Used by the 4-level scan tree (Task A4 / A7) to reflect aggregate selection
/// state at the category / sub-category / action levels. The view resolves to
/// one of three renderings:
/// - `.off` — empty rounded square with a thin border.
/// - `.on` — filled rounded square with a `checkmark` SF Symbol.
/// - `.mixed` — filled rounded square with a `minus` SF Symbol.
///
/// The component animates state transitions through
/// `Animation.accessibleDefault(_:)` so users with reduce-motion enabled see
/// the substitution fade described by the v3 spec.
struct IndeterminateCheckbox: View {
    /// Selection state the checkbox should render.
    let state: CheckState
    /// Side length of the rendered square in points; defaults to the design-system checkbox token.
    var size: CGFloat = RowSize.checkboxSize

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.sm)
                .fill(state == .off ? Color.clear : Color.brandPrimary)
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .stroke(state == .off ? Color.textTertiary : Color.clear, lineWidth: 1.5)
                )
            if state == .mixed {
                Image(systemName: "minus")
                    .font(.system(size: size * 0.66, weight: .bold))
                    .foregroundStyle(.white)
            } else if state == .on {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.66, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .animation(.accessibleDefault(.easeOut(duration: 0.15)), value: state)
        .accessibilityLabel(currentAccessibilityLabel)
    }

    /// SF Symbol rendered for the given state, or `nil` when no symbol is shown.
    ///
    /// Exposed as `internal` so the test target can assert the rendered
    /// semantics without having to introspect the opaque SwiftUI `Image`
    /// view tree via reflection.
    func symbolName(for state: CheckState) -> String? {
        switch state {
        case .on, .checked: return "checkmark"
        case .mixed: return "minus"
        case .off, .unchecked: return nil
        }
    }

    /// Localized spoken label for VoiceOver; mirrors the visual state.
    func accessibilityLabelText(for state: CheckState) -> String {
        switch state {
        case .off: return "未勾选"
        case .on: return "已勾选"
        case .mixed: return "部分勾选"
        case .unchecked: return "未勾选"
        case .checked: return "已勾选"
        }
    }

    /// Convenience accessor used by `body` to fetch the current state's label.
    private var currentAccessibilityLabel: String {
        accessibilityLabelText(for: state)
    }
}

#if DEBUG
struct IndeterminateCheckbox_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 16) {
            IndeterminateCheckbox(state: .off)
            IndeterminateCheckbox(state: .on)
            IndeterminateCheckbox(state: .mixed)
        }
        .padding()
        .background(Color.bgCanvas)
    }
}
#endif
