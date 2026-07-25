import SwiftUI
import DesignSystem

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            if appState.navigation != .onboarding {
                iconRail
                    .frame(width: 48)
                    .padding(.leading, 8)
            }
            mainContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch appState.navigation {
        case .onboarding:
            OnboardingView()
        case .scan:
            MainView()
        case .results:
            ResultView()
        case .history:
            HistoryView()
        case .settings:
            SettingsView()
        }
    }

    private var iconRail: some View {
        GlassPanel {
            VStack(spacing: 4) {
                ForEach(AppState.NavigationItem.allCases.filter { $0 != .onboarding }, id: \.self) { item in
                    Button {
                        appState.navigation = item
                    } label: {
                        Image(systemName: item.iconName)
                            .font(.system(size: 16))
                            .frame(width: 36, height: 36)
                            .background(appState.navigation == item ? Color.brandPrimary.opacity(0.3) : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.vertical, AppSpacing.sm)
        }
        .frame(width: 42)
    }
}
