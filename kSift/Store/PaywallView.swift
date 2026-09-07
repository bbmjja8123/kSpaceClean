import SwiftUI
import StoreKit
import DesignSystem

struct PaywallView: View {
    @EnvironmentObject var store: StoreManager
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false
    @State private var purchaseError: String?
    @State private var expandedFAQ: Int?

    var body: some View {
        VStack(spacing: 18) {
            // Hero
            VStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 56))
                    .foregroundStyle(.linearGradient(
                        colors: [.brandPrimary, .brandSecondary ?? .brandPrimary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Text("Unlock kSift Pro")
                    .font(.largeTitle).bold()
                Text("One-time purchase. Lifetime updates. No subscription.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Feature list — leads with the platform integrations that no
            // duplicate-finder competitor ships (menu bar, Shortcuts,
            // Finder extension), then the cleanup capacities.
            VStack(alignment: .leading, spacing: 10) {
                featureRow(icon: "infinity", title: "Unlimited cleanup",
                           detail: "Remove the 2 GB free-tier cap and free as much space as you need.")
                featureRow(icon: "bolt.fill", title: "Incremental index",
                           detail: "Re-scans only the files that actually changed — typically 10x faster.")
                featureRow(icon: "menubar.dock.rectangle", title: "Menu bar quick scan",
                           detail: "Scan folders and check reclaimed space from the menu bar.")
                featureRow(icon: "square.3.layers.3d", title: "Shortcuts automation",
                           detail: "Build scans and cleanups into your own Shortcuts workflows.")
                featureRow(icon: "puzzlepiece.extension.fill", title: "Finder Sync extension",
                           detail: "Right-click any folder in Finder → \"Scan with kSift\".")
                featureRow(icon: "wand.and.stars", title: "Explainable Smart Select",
                           detail: "Five keep strategies with a visible reason for every copy.")
            }
            .padding(.horizontal, 4)

            // Pricing-model comparison — states the one-time advantage
            // without naming any competitor (App Store guideline 2.3.10).
            pricingComparison

            // FAQ
            VStack(alignment: .leading, spacing: 0) {
                faqRow(
                    index: 0,
                    question: "Is this a subscription?",
                    answer: "No. You pay once and kSift Pro is yours forever, including all future Pro features. There is no recurring charge of any kind."
                )
                faqRow(
                    index: 1,
                    question: "How many Macs can I use it on?",
                    answer: "Your purchase covers every Mac signed into the same Apple ID — install it on your desktop and your laptop at no extra cost."
                )
                faqRow(
                    index: 2,
                    question: "What happens to files I already cleaned?",
                    answer: "Every cleaned file stays restorable in the vault for 30 days regardless of tier, and deleting files never requires Pro — Pro removes the 2 GB quota on how much you can clean."
                )
            }

            // Product + CTA
            VStack(spacing: 8) {
                if let product = store.products.first(where: { $0.id == StoreManager.proProductID })
                    ?? store.products.first {
                    HStack {
                        Text(product.displayName).font(.headline)
                        Spacer()
                        Text(product.displayPrice)
                            .font(.title3).bold()
                            .foregroundColor(.brandPrimary)
                    }
                    .padding(12)
                    .background(Color.brandPrimary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))

                    Button(action: { Task { await purchase(product) } }) {
                        HStack {
                            if isPurchasing {
                                ProgressView().controlSize(.small)
                            }
                            Text(isPurchasing ? "Processing…" : "Buy \(product.displayPrice)")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
                    .disabled(isPurchasing || store.products.isEmpty)
                } else if store.products.isEmpty {
                    Text("Loading product…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let purchaseError {
                    Text(purchaseError)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Button("Restore Purchases") {
                    Task { await store.restorePurchases() }
                }
                .buttonStyle(.plain)
                .font(.footnote)
                .foregroundColor(.secondary)
            }

            Text("Free tier includes up to 2 GB of cleanup. Quota resets after purchase.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(width: 460)
        .task {
            await store.loadProducts()
        }
    }

    private var pricingComparison: some View {
        GlassPanel {
            VStack(spacing: 10) {
                comparisonRow(
                    label: "Price",
                    free: "Free",
                    oneTime: "Pay once",
                    subscription: "Pay every month"
                )
                comparisonRow(
                    label: "After 1 year",
                    free: "2 GB cleaned",
                    oneTime: "Still yours",
                    subscription: "Billed 12×"
                )
                comparisonRow(
                    label: "Stop paying",
                    free: "—",
                    oneTime: "Keep everything",
                    subscription: "Lose Pro features"
                )
            }
            .padding(12)
        }
    }

    private func comparisonRow(label: String, free: String, oneTime: String, subscription: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(free)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
            Text(oneTime)
                .font(.caption).bold()
                .foregroundColor(.brandPrimary)
                .frame(maxWidth: .infinity)
            Text(subscription)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func faqRow(index: Int, question: String, answer: String) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expandedFAQ == index },
            set: { expandedFAQ = $0 ? index : nil }
        )) {
            Text(answer)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)
        } label: {
            Text(question)
                .font(.subheadline)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.brandPrimary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).bold()
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func purchase(_ product: Product) async {
        isPurchasing = true
        purchaseError = nil
        defer { isPurchasing = false }
        do {
            let success = try await store.purchase(product)
            if success { dismiss() }
        } catch {
            purchaseError = error.localizedDescription
        }
    }
}
