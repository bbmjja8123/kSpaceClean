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
            HistoryView(
                viewModel: HistoryViewModel(
                    historyRepo: services.history,
                    trashMover: services.mover
                )
            )
        }
        .sheet(isPresented: $coordinator.showSettings) {
            SettingsView(viewModel: SettingsViewModel(coordinator: coordinator))
        }
        .sheet(isPresented: $coordinator.showDeepClean) {
            DeepCleanView()
        }
        .sheet(isPresented: $coordinator.showStartupItems) {
            StartupItemsView(viewModel: StartupItemsViewModel(manager: StartupItemManager()))
        }
        .sheet(isPresented: $coordinator.showPaywall) {
            PaywallView(store: services.store)
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
