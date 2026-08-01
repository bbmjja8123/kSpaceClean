import SwiftUI

/// Blurs Pro-locked content and overlays an unlock call-to-action that opens
/// the paywall. Pass the app-wide ``StoreManager`` via ``View/proGate(store:)``.
struct ProGateModifier: ViewModifier {
    @ObservedObject var store: StoreManager
    @State private var showPaywall = false

    init(store: StoreManager) {
        self.store = store
    }

    /// Whether the gate is currently locked (the user has not unlocked Pro).
    var isLocked: Bool { store.state != .pro }

    func body(content: Content) -> some View {
        content
            .blur(radius: isLocked ? 8 : 0)
            .overlay {
                if isLocked {
                    paywallOverlay
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(store: store)
            }
    }

    private var paywallOverlay: some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "lock.fill")
                .font(AppFont.title2)
                .foregroundStyle(Color.warning)
            Text("Pro 功能")
                .font(AppFont.title3)
                .foregroundStyle(Color.textPrimary)
            Text("升级 Pro 解锁深度清理、启动项管理")
                .font(AppFont.body)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
            Button("解锁 Pro") { showPaywall = true }
                .buttonStyle(.brand)
        }
        .padding(AppSpacing.lg)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(AppSpacing.lg)
    }
}

// MARK: - View Extension

extension View {
    /// Applies a Pro gate: shows blurred content plus a paywall overlay when
    /// the user has not unlocked Pro.
    @MainActor
    func proGate(store: StoreManager) -> some View {
        modifier(ProGateModifier(store: store))
    }
}
