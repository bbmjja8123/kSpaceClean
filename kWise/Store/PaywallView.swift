import SwiftUI
import DesignSystem

/// Paywall sheet. The `StoreManager` is injected (v2.0 Phase 1) so the
/// sheet observes the *same* instance the app graph owns — a purchase made
/// here immediately unblocks the buyout gate everywhere else.
///
/// P1 T7 — the offer is a single non-consumable buyout ($9.90 / ¥68), not a
/// subscription. Copy rules: no "unlimited cleaning / free tier = 1 GB"
/// (the 1 GB quota is retired, R5) and no fabricated AI/CoreML claims.
/// The free tier keeps scanning, attribution and the refusal list forever.
///
/// Fix r1 — the sheet is the only conversion surface, so a confirmed
/// purchase must not dead-end: the CTA flips to an 「已解锁」 row and the
/// sheet dismisses itself (`.onChange(of: store.hasPurchased)`).
struct PaywallView: View {
    @ObservedObject var store: StoreManager
    @StateObject private var success = PaywallSuccessModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GlassPanel {
            VStack(spacing: AppSpacing.xl) {
                Image(systemName: success.unlocked ? "checkmark.circle.fill" : "lock.open.fill")
                    .font(.system(size: 48))
                    .foregroundColor(success.unlocked ? .success : .brandAccent)

                Text(String(localized: success.unlocked ? "pw.buyout.unlocked" : "pw.buyout.title"))
                    .font(AppFont.title2)
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)

                if !success.unlocked {
                    Text(String(localized: "pw.buyout.pitch"))
                        .font(AppFont.caption)
                        .foregroundColor(.textSecondary)
                        .multilineTextAlignment(.center)

                    FeatureList(items: [
                        (String(localized: "pw.buyout.feature.actions"),
                         String(localized: "pw.buyout.feature.actions.sub")),
                        (String(localized: "pw.buyout.feature.quickclean"),
                         String(localized: "pw.buyout.feature.quickclean.sub")),
                    ])

                    Button(String(localized: "pw.buyout.cta")) {
                        Task { await store.purchase() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
                    .controlSize(.large)
                }

                Text(String(localized: "pw.buyout.freeTier"))
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)

                Button(String(localized: "pw.buyout.restore")) {
                    Task { await store.restorePurchases() }
                }
                .buttonStyle(.plain)
                .foregroundColor(.textSecondary)
            }
            .padding(AppSpacing.xxl)
            .animation(.easeInOut(duration: 0.2), value: success.unlocked)
        }
        .frame(width: 400)
        .onChange(of: store.hasPurchased) { purchased in
            guard purchased else { return }
            success.purchaseConfirmed()
            Task { [dismiss] in
                try? await Task.sleep(nanoseconds: PaywallSuccessModel.dismissDelayNanoseconds)
                dismiss()
            }
        }
    }
}

/// Success state for the buyout conversion surface (fix r1). Extracted so
/// the flip-to-unlocked + auto-dismiss behavior is lockable in tests
/// without any StoreKit call.
@MainActor
final class PaywallSuccessModel: ObservableObject {
    /// `true` once the observed store's ownership flips — swaps the CTA for
    /// the unlocked row.
    @Published var unlocked = false

    /// How long the unlocked row stays visible before the sheet dismisses
    /// itself. Non-zero so the user actually sees the confirmation.
    static let dismissDelayNanoseconds: UInt64 = 900_000_000

    func purchaseConfirmed() {
        unlocked = true
    }
}

struct FeatureList: View {
    let items: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            ForEach(items, id: \.0) { item in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.success)
                    Text(item.0)
                        .font(AppFont.body)
                        .foregroundColor(.textPrimary)
                    Text(item.1)
                        .font(AppFont.caption)
                        .foregroundColor(.textSecondary)
                }
            }
        }
    }
}
