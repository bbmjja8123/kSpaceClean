import StoreKit
import SwiftUI

/// Pro purchase sheet: feature bullets, purchase/restore actions, and a
/// graceful empty-products state with a retry affordance — no endless spinner.
struct PaywallView: View {
    @ObservedObject var store: StoreManager
    @Environment(\.dismiss) private var dismiss
    @State private var didAttemptLoad = false
    @State private var purchaseError: String?

    init(store: StoreManager) {
        self.store = store
    }

    var body: some View {
        VStack(spacing: AppSpacing.lg) {
            header
            featureList
            actionArea

            if let purchaseError {
                Text(purchaseError)
                    .font(AppFont.callout)
                    .foregroundStyle(Color.danger)
            }

            Button("恢复购买") {
                Task {
                    do {
                        try await store.restorePurchases()
                        dismiss()
                    } catch {
                        present(error)
                    }
                }
            }
            .buttonStyle(.borderless)

            Button("取消", role: .cancel) { dismiss() }
        }
        .padding(AppSpacing.lg)
        .frame(width: 420)
        .task {
            await store.refresh()
            didAttemptLoad = true
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: AppSpacing.sm) {
            Text("升级到 kFresh Pro")
                .font(AppFont.largeTitle)
                .foregroundStyle(Color.textPrimary)
            Text("一次买断，永久使用")
                .font(AppFont.body)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            bullet("深度清理 — LaunchAgents / Daemons / PrefPanes")
            bullet("启动项管理 — 启用 / 禁用 / 删除")
            bullet("Wave 2: 批量卸载 / Widget / Shortcuts")
            bullet("30 天可回滚")
        }
        .padding(AppSpacing.lg)
        .background(Color.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var actionArea: some View {
        if let product = store.products.first {
            Button {
                Task { await purchase() }
            } label: {
                Text("购买 — \(product.displayPrice)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.brand)
            .disabled(store.purchaseInProgress)
        } else if didAttemptLoad {
            // Products failed to load — offer retry instead of an endless spinner.
            VStack(spacing: AppSpacing.sm) {
                Text("无法加载商品信息，请检查网络后重试")
                    .font(AppFont.callout)
                    .foregroundStyle(Color.textSecondary)
                Button("重试") {
                    didAttemptLoad = false
                    Task {
                        await store.refresh()
                        didAttemptLoad = true
                    }
                }
                .buttonStyle(.borderless)
            }
        } else {
            ProgressView()
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.sm) {
            Text("✓")
                .foregroundStyle(Color.success)
            Text(text)
                .font(AppFont.body)
                .foregroundStyle(Color.textPrimary)
        }
    }

    // MARK: - Actions

    private func purchase() async {
        do {
            try await store.purchase(.proUnlock)
            dismiss()
        } catch {
            present(error)
        }
    }

    /// Surfaces a purchase/restore error in the paywall, unless the user
    /// simply cancelled the StoreKit sheet — that is not an error worth
    /// showing.
    private func present(_ error: Error) {
        if (error as? StoreError)?.isCancellation == true { return }
        purchaseError = error.localizedDescription
    }
}
