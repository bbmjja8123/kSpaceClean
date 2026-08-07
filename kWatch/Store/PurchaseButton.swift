import SwiftUI

/// Tri-state SwiftUI button used in `PaywallView`.
///
/// - **idle** shows the localized price label (e.g. `Buy kWatch Pro — $7.99`).
/// - **loading** swaps the label for an inline spinner and `Processing…`.
/// - **success** shows a checkmark and `Purchased` for a few seconds after the
///   manager confirms the entitlement.
struct PurchaseButton: View {
    /// Localized copy displayed on the button. Provided by the parent so
    /// the same button can render different action labels (e.g. buy vs
    /// upgrade) without coupling to the store manager.
    let label: LocalizedStringKey

    /// Whether the button should display its loading state.
    let isLoading: Bool

    /// Whether the purchase succeeded. Drives the checkmark badge.
    let didSucceed: Bool

    /// Tapped action. The parent is responsible for invoking the manager.
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "Processing…"))
                } else if didSucceed {
                    Image(systemName: "checkmark.circle.fill")
                    Text(String(localized: "Purchased"))
                } else {
                    Text(label)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .disabled(isLoading || didSucceed)
        .accessibilityLabel(Text(label))
    }
}

#if DEBUG
struct PurchaseButton_Idle_Previews: PreviewProvider {
    static var previews: some View {
        PurchaseButton(
            label: "Buy kWatch Pro — $7.99",
            isLoading: false,
            didSucceed: false,
            action: {}
        )
        .padding()
        .frame(width: 280)
    }
}

struct PurchaseButton_Loading_Previews: PreviewProvider {
    static var previews: some View {
        PurchaseButton(
            label: "Buy kWatch Pro — $7.99",
            isLoading: true,
            didSucceed: false,
            action: {}
        )
        .padding()
        .frame(width: 280)
    }
}

struct PurchaseButton_Success_Previews: PreviewProvider {
    static var previews: some View {
        PurchaseButton(
            label: "Buy kWatch Pro — $7.99",
            isLoading: false,
            didSucceed: true,
            action: {}
        )
        .padding()
        .frame(width: 280)
    }
}
#endif
