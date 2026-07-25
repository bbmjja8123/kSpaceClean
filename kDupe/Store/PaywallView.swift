import SwiftUI
import StoreKit
import DesignSystem

struct PaywallView: View {
    @StateObject private var store = StoreManager()
    @State private var isPurchasing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.brandPrimary)

            Text("Unlock Full Power")
                .font(.largeTitle).bold()

            Text("Remove duplicate files, clean build artifacts, and reclaim gigabytes.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            ForEach(store.products, id: \.id) { product in
                ProductView(product: product)
                    .productViewStyle(.compact)
                    .padding(.horizontal)
            }

            Button(action: { Task { await purchase() } }) {
                Text("Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPurchasing)
            .padding(.horizontal)

            Button("Restore Purchases") {
                Task { await store.restorePurchases() }
            }
            .buttonStyle(.plain)
        }
        .padding()
        .task { await store.loadProducts() }
    }

    private func purchase() async {
        isPurchasing = true
        defer { isPurchasing = false }
        guard let product = store.products.first else { return }
        _ = try? await store.purchase(product)
    }
}
