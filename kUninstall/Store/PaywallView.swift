import SwiftUI
import StoreKit

struct PaywallView: View {
    @State private var products: [Product] = []
    @State private var isPurchasing = false
    @State private var purchaseComplete = false

    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            // Hero
            VStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                Text("升级 kUninstall Pro")
                    .font(.title)
                    .fontWeight(.bold)
                Text("解锁全部高级功能")
                    .foregroundColor(.secondary)
            }

            // Feature list
            VStack(alignment: .leading, spacing: 12) {
                ForEach(ProFeature.allCases, id: \.self) { feature in
                    HStack(spacing: 12) {
                        Image(systemName: feature.icon)
                            .frame(width: 24)
                            .foregroundColor(.accentColor)
                        Text(feature.displayDescription)
                            .font(.body)
                        Spacer()
                        Image(systemName: "checkmark")
                            .foregroundColor(.green)
                    }
                }
            }
            .padding(16)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(12)

            // Price & purchase
            if let product = products.first {
                Button(action: {
                    purchase(product)
                }) {
                    HStack {
                        Text("\(product.displayPrice) — 一次性买断")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .disabled(isPurchasing)
            } else {
                ProgressView()
            }

            Button("恢复购买") {
                Task { await restore() }
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            if purchaseComplete {
                Label("购买成功！欢迎使用 kUninstall Pro", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .padding(32)
        .frame(width: 380)
        .task {
            products = await StoreManager.shared.loadProducts()
        }
    }

    private func purchase(_ product: Product) {
        isPurchasing = true
        Task {
            let success = await StoreManager.shared.purchase(product)
            await MainActor.run {
                isPurchasing = false
                if success {
                    purchaseComplete = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        onDismiss?()
                    }
                }
            }
        }
    }

    private func restore() async {
        let success = await StoreManager.shared.restorePurchases()
        await MainActor.run {
            if success { purchaseComplete = true }
        }
    }
}
