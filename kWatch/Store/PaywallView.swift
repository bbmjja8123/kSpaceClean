import SwiftUI

/// Sheet content shown by the dashboard when the user opens the Pro gate.
///
/// Pulls together a hero header, the bullet list of unlocked capabilities
/// (history trend, custom alerts, platform integrations, advanced sensors),
/// a `PurchaseButton`, and a Restore Purchases affordance. The `dismiss`
/// closure is invoked once the user has either bought Pro, restored it, or
/// explicitly tapped "Not Now" — the parent decides what to do with the
/// closure (typically closing the sheet).
public struct PaywallView: View {
    @StateObject private var viewModel: PaywallViewModel

    private let onDismiss: () -> Void

    public init(viewModel: PaywallViewModel, onDismiss: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 16) {
            hero
            Divider()
            featureList
            Divider()
            priceLine
            if let errorMessage = viewModel.errorMessage {
                errorBanner(message: errorMessage)
            }
            PurchaseButton(
                label: LocalizedStringKey(stringLiteral: viewModel.priceLine),
                isLoading: viewModel.isPurchasing,
                didSucceed: viewModel.isPro,
                action: { Task { await viewModel.purchase() } }
            )
            restoreButton
            dismissButton
        }
        .padding(24)
        .frame(width: 360)
        .task { await viewModel.refresh() }
        .onChange(of: viewModel.didCompletePurchase) { newValue in
            if newValue {
                onDismiss()
            }
        }
    }

    // MARK: - Subviews

    private var hero: some View {
        VStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text("kWatch Pro")
                .font(.title)
                .fontWeight(.bold)

            Text("Unlock the full monitoring experience.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 6) {
            featureRow(icon: "chart.xyaxis.line", title: "24h / 7d / 30d history & trends")
            featureRow(icon: "bell.badge", title: "Custom threshold alerts")
            featureRow(icon: "square.stack.3d.up", title: "Shortcuts & Spotlight integrations")
            featureRow(icon: "fanblades.fill", title: "Advanced sensors where this Mac supports them")
        }
    }

    private func featureRow(icon: String, title: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
                .accessibilityHidden(true)
            Text(title)
                .font(.callout)
                .foregroundStyle(.primary)
        }
    }

    private var priceLine: some View {
        VStack(spacing: 2) {
            Text(viewModel.priceLine)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Sensor availability depends on your Mac hardware.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer()
            Button("Dismiss") {
                viewModel.clearError()
            }
            .controlSize(.small)
        }
        .padding(8)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var restoreButton: some View {
        Button {
            Task { await viewModel.restore() }
        } label: {
            HStack(spacing: 6) {
                if viewModel.isRestoring {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(viewModel.isRestoring ? "Restoring…" : "Restore Purchases")
            }
        }
        .controlSize(.small)
        .disabled(viewModel.isRestoring)
        .help("Restore a previous Pro purchase tied to your Apple ID.")
    }

    private var dismissButton: some View {
        Button("Not Now") {
            onDismiss()
        }
        .keyboardShortcut(.cancelAction)
        .padding(.top, 4)
    }
}
