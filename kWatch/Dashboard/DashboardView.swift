import SwiftUI
import MetricsKit

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

    public init(
        viewModel: DashboardViewModel,
        onOpenOnboarding: (() -> Void)? = nil,
        onOpenPaywall: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onOpenOnboarding = onOpenOnboarding
        self.onOpenPaywall = onOpenPaywall
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                onboardingBanner
                cardGrid
            }
            .padding()
        }
        .navigationTitle("Dashboard")
        .toolbar {
            ToolbarItemGroup {
                liveIndicator
                navigationControls
            }
        }
    }

    // MARK: - Onboarding banner

    @ViewBuilder
    private var onboardingBanner: some View {
        if viewModel.showOnboardingBanner {
            HStack(spacing: 12) {
                Image(systemName: "hand.wave")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to kWatch")
                        .font(.headline)
                    Text("Complete the setup to customize your experience.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button("Set Up") {
                    onOpenOnboarding?()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    viewModel.dismissOnboardingBanner()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.background)
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(.separator, lineWidth: 1)
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
                Text("Live")
            } else {
                Circle()
                    .fill(Color.gray)
                    .frame(width: 8, height: 8)
                Text("Paused")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .help(viewModel.isMonitoring ? "Monitoring is active" : "Monitoring is paused")
    }

    /// Navigation controls for sub-views required by the plan.
    @ViewBuilder
    private var navigationControls: some View {
        Button("History") { viewModel.navigateToHistory() }
            .help("View metric history")

        Button("Processes") { viewModel.navigateToProcesses() }
            .help("View running processes")

        Button("Alerts") { viewModel.navigateToAlerts() }
            .help("View alerts")
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

#Preview("Dashboard with data") {
    let appState = AppState()
    let purchaseState = PurchaseState()
    appState.update(snapshot: MetricSnapshot(
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

#Preview("Dashboard with onboarding") {
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
