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
struct PaywallView: View {
    @ObservedObject var store: StoreManager

    var body: some View {
        GlassPanel {
            VStack(spacing: AppSpacing.xl) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.brandAccent)

                Text(String(localized: "pw.buyout.title"))
                    .font(AppFont.title2)
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)

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
        }
        .frame(width: 400)
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
