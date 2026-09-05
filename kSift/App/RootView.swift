import SwiftUI
import DesignSystem

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.paidUserFlag) private var paidFlag: PaidUserFlag?

    var body: some View {
        HStack(spacing: 0) {
            if appState.navigation != .onboarding {
                iconRail
                    .frame(width: 72)
                    .padding(.leading, 8)
            }
            // NavigationStack is required so NavigationLink (used by
            // ResultView→GroupDetailView and HistoryView→HistoryDetailView)
            // actually pushes a detail view. Without it the click is a no-op.
            NavigationStack {
                mainContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // Undo failures can be triggered from the Edit menu on any screen,
        // so the alert lives at the root where it is always presentable.
        .alert(
            NSLocalizedString("Some files could not be restored", comment: "Undo failure alert title"),
            isPresented: Binding(
                get: { !appState.lastUndoFailures.isEmpty },
                set: { if !$0 { appState.lastUndoFailures = [] } }
            )
        ) {
            Button("OK", role: .cancel) { appState.lastUndoFailures = [] }
        } message: {
            Text(String(
                format: NSLocalizedString(
                    "%lld file(s) could not be restored:\n\n%@",
                    comment: "Undo failure alert message — count, then per-file reasons"
                ),
                appState.lastUndoFailures.count,
                appState.lastUndoFailures
                    .map { "\($0.url.lastPathComponent) — \($0.reason)" }
                    .joined(separator: "\n")
            ))
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        switch appState.navigation {
        case .onboarding:
            OnboardingView()
        case .scan:
            // Forward the paid flag so MainView can wire IncrementalIndex
            // into its ScanViewModel at construction time.
            MainView(paidFlag: paidFlag)
        case .results:
            ResultView()
        case .history:
            HistoryView()
        case .vault:
            VaultView()
        case .settings:
            SettingsView()
        }
    }

    private var iconRail: some View {
        GlassPanel {
            VStack(spacing: 6) {
                ForEach(AppState.NavigationItem.allCases.filter { $0 != .onboarding }, id: \.self) { item in
                    let isSelected = appState.navigation == item
                    Button {
                        appState.navigation = item
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: item.iconName)
                                .font(.system(size: 16))
                                .frame(width: 36, height: 30)
                            Text(item.title)
                                .font(.system(size: 9))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(width: 60)
                        .padding(.vertical, 4)
                        .background(isSelected ? Color.brandPrimary.opacity(0.3) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(isSelected ? .brandPrimary : .secondary)
                    .help("\(item.title) (\(item.commandDigit.map { "⌘\($0)" } ?? ""))")
                    .accessibilityLabel(Text(item.title))
                    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                }
                Spacer()
            }
            .padding(.vertical, AppSpacing.sm)
        }
        .frame(width: 68)
    }
}
