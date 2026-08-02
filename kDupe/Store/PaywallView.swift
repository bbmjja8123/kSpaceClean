import SwiftUI
import StoreKit
import DesignSystem

struct PaywallView: View {
    @EnvironmentObject var store: StoreManager
    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false
    @State private var purchaseError: String?

    var body: some View {
        VStack(spacing: 20) {
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

            // Feature list
            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "infinity", title: "Unlimited cleanup",
                           detail: "Remove the 2 GB free-tier cap and free as much space as you need.")
                featureRow(icon: "bolt.fill", title: "Incremental index",
                           detail: "Re-scans only the files that actually changed — typically 10x faster.")
                featureRow(icon: "puzzlepiece.extension.fill", title: "Finder Sync extension",
                           detail: "Right-click any folder in Finder → \"Scan with kSift\".")
                featureRow(icon: "sparkles", title: "Future Pro features",
                           detail: "Every paid feature we ship from now on, included.")
            }
            .padding(.horizontal, 4)

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
        .frame(width: 440)
        .task {
            await store.loadProducts()
        }
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

