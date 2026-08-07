import SwiftUI
import MetricsKit
import DesignSystem

/// The main dashboard screen showing live metric cards and an optional
/// onboarding banner.
///
/// Cards are laid out in a responsive grid. Tapping a card selects it for
/// detail inspection. If the user has not completed onboarding, a banner is
/// displayed at the top with a button to open the onboarding window.
///
/// A toolbar provides a live-monitoring indicator and navigation controls
/// for History, Processes, and Alerts sub-views.
public struct DashboardView: View {
    @ObservedObject private var viewModel: DashboardViewModel

    private let onOpenOnboarding: (() -> Void)?
    private let onOpenPaywall: (() -> Void)?
    private let historyRepo: (any HistoryRepositoryProtocol)?
    private let purchaseState: PurchaseState?
    private let processMonitor: ProcessMonitor?

    public init(
        viewModel: DashboardViewModel,
        onOpenOnboarding: (() -> Void)? = nil,
        onOpenPaywall: (() -> Void)? = nil,
        historyRepo: (any HistoryRepositoryProtocol)? = nil,
        purchaseState: PurchaseState? = nil,
        processMonitor: ProcessMonitor? = nil
    ) {
        self.viewModel = viewModel
        self.onOpenOnboarding = onOpenOnboarding
        self.onOpenPaywall = onOpenPaywall
        self.historyRepo = historyRepo
        self.purchaseState = purchaseState
        self.processMonitor = processMonitor
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                onboardingBanner
                cardGrid
            }
            .padding()
        }
        .navigationTitle(String(localized: "Dashboard"))
        .toolbar {
            ToolbarItemGroup {
                liveIndicator
                navigationControls
            }
        }
        .sheet(item: $viewModel.selectedKind) { kind in
            MetricDetailView(
                viewModel: MetricDetailViewModel(
                    kind: kind,
                    historyRepo: historyRepo ?? InMemoryHistoryRepository(),
                    purchaseState: purchaseState ?? PurchaseState(),
                    processMonitor: processMonitor
                )
            )
        }
    }

    // MARK: - Onboarding banner

    @ViewBuilder
    private var onboardingBanner: some View {
        if viewModel.showOnboardingBanner {
            HStack(spacing: 12) {
                Image(systemName: "hand.wave")
                    .font(.title2)
                    .foregroundStyle(Color.brandSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Welcome to kWatch"))
                        .font(.headline)
                    Text(String(localized: "Complete the setup to customize your experience."))
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }

                Spacer(minLength: 0)

                Button(String(localized: "Set Up")) {
                    onOpenOnboarding?()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    viewModel.dismissOnboardingBanner()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(Color.textSecondary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Dismiss"))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.bgPrimary)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.separatorColor, lineWidth: 1)
                    }
            )
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var liveIndicator: some View {
        HStack(spacing: 6) {
            if viewModel.isMonitoring {
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "Live"))
            } else {
                Circle()
                    .fill(Color.textSecondary)
                    .frame(width: 8, height: 8)
                Text(String(localized: "Paused"))
            }
        }
        .font(.caption)
        .foregroundStyle(Color.textSecondary)
        .help(viewModel.isMonitoring ? String(localized: "Monitoring is active") : String(localized: "Monitoring is paused"))
    }

    /// Navigation controls for sub-views required by the plan.
    @ViewBuilder
    private var navigationControls: some View {
        Button(String(localized: "History")) { viewModel.navigateToHistory() }
            .help(String(localized: "View metric history"))

        Button(String(localized: "Processes")) { viewModel.navigateToProcesses() }
            .help(String(localized: "View running processes"))

        Button(String(localized: "Alerts")) { viewModel.navigateToAlerts() }
            .help(String(localized: "View alerts"))
    }

    // MARK: - Card grid

    private var cardGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 12)],
            spacing: 12
        ) {
            ForEach(viewModel.cards) { card in
                MetricCardView(viewModel: card, onOpenPaywall: onOpenPaywall)
                    .onTapGesture {
                        viewModel.selectedKind = card.kind
                    }
            }
        }
    }
}

// MARK: - Preview

struct DashboardView_Data_Previews: PreviewProvider {
    static var previews: some View {
        let appState = AppState()
        let purchaseState = PurchaseState()
        let _ = appState.update(snapshot: MetricSnapshot(
            timestamp: Date(),
            values: [
                .cpu: .percentage(72),
                .memory: .percentage(85),
                .disk: .percentage(44),
                .network: .bytesPerSecond(1_024_000),
                .temperature: .degreesCelsius(68),
                .fan: .revolutionsPerMinute(2200),
                .battery: .percentage(91)
            ],
            availability: [
                .temperature: .available,
                .fan: .available
            ]
        ))
        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: true
        )
        DashboardView(viewModel: vm)
            .frame(width: 720, height: 480)
    }
}

struct DashboardView_Onboarding_Previews: PreviewProvider {
    static var previews: some View {
        let appState = AppState()
        let purchaseState = PurchaseState()
        let vm = DashboardViewModel(
            appState: appState,
            purchaseState: purchaseState,
            onboardingCompleted: false
        )
        DashboardView(viewModel: vm)
            .frame(width: 720, height: 480)
    }
}
