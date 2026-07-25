import SwiftUI

// MARK: - Pro Gate ViewModifier

struct ProGateModifier: ViewModifier {
    @State private var isPro = false
    @State private var showPaywall = false

    let featureName: String
    let featureIcon: String

    func body(content: Content) -> some View {
        Group {
            if isPro {
                content
            } else {
                VStack(spacing: 16) {
                    Image(systemName: featureIcon)
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text(featureName)
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("升级 Pro 以解锁此功能")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Button("升级 Pro") {
                        showPaywall = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .task {
            await checkProStatus()
        }
    }

    private func checkProStatus() async {
        isPro = await StoreManager.shared.isPro
    }
}

// MARK: - View Extension

extension View {
    func proGate(featureName: String, featureIcon: String) -> some View {
        modifier(ProGateModifier(featureName: featureName, featureIcon: featureIcon))
    }
}
