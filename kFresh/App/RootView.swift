import SwiftUI

struct RootView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @EnvironmentObject private var services: AppServices

    var body: some View {
        AppListView(
            viewModel: AppListViewModel(
                catalog: services.catalog,
                historyRepo: services.history,
                fdaProbe: services.fdaProbe
            )
        )
        .sheet(isPresented: $coordinator.showHistory) {
            HistoryView()
        }
        .sheet(isPresented: $coordinator.showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $coordinator.showAbout) {
            AboutView()
        }
        .sheet(isPresented: $coordinator.showOnboarding) {
            FDAGuideView(
                controller: coordinator.makeOnboardingController(),
                onFinished: { coordinator.onboardingFinished() }
            )
        }
    }
}
