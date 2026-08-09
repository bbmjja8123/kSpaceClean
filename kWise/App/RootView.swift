import SwiftUI
import DesignSystem

/// RootView with navigation content switching.
/// Displays different content based on appState.navigation.
struct RootView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var cleanupViewModel = CleanupViewModel()

    // C1: production scan pipeline. Owned at the root so the scan state
    // survives navigation switches (e.g. user starts a scan, navigates
    // away, comes back — the categories tree is still there).
    //
    // C3: this is now the *only* scan model the root owns. The legacy
    // `ScanViewModel` used to be wired to the toolbar button and the
    // ⌘N / ⌘R shortcuts while the rendered `ScanResultsView` observed this
    // model, so every user-initiated scan ran a pipeline nothing on screen
    // was watching. All three triggers now route here.
    @StateObject private var scanResultsViewModel = ScanResultsViewModel(engine: ScanEngine())

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Layer 1: Background
                backgroundLayer

                // Layer 2: Top toolbar (Scan / Clean / Warning / Account) — brand
                // mark on the leading edge, four icon-and-label buttons on the
                // trailing edge. Wired in A14 after sitting as dead code since
                // A12 (see A14 report).
                VStack(spacing: 0) {
                    ToolbarView(
                        onScan: {
                            appState.navigation = .scan
                            scanResultsViewModel.startScan()
                        },
                        onClean: {
                            appState.navigation = .cleanup
                        },
                        onWarning: {
                            // Phase C will surface a real warning sheet here
                            // (Task C6 WarningToast). For now, switching to
                            // the cleanup route gives the user the closest
                            // existing surface that surfaces the warnings.
                            appState.navigation = .cleanup
                        },
                        onProfile: {
                            appState.navigation = .settings
                        }
                    )
                    .zIndex(10)

                    // Layer 3: Main content + icon rail side by side
                    HStack(spacing: 0) {
                        // Icon Rail (left sidebar)
                        iconRail
                            .frame(width: 48)
                            .padding(.leading, 8)

                        // Main content area (switches based on navigation)
                        mainContent
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // Right panel (driven solely by rightPanelVisible
                        // since the 3D galaxy visualization was removed in
                        // v1.0 per CLAUDE.md §8.1)
                        if appState.rightPanelVisible {
                            RightPanelView()
                                .frame(width: min(260, geo.size.width * 0.3))
                                .padding(.trailing, 12)
                                .padding(.top, 48)
                                .padding(.bottom, 68)
                        }
                    }
                }
            }
        }
        .scanKeyboardShortcuts(
            onNewScan: {
                // ⌘N — switch to the scan surface and start a fresh scan
                appState.navigation = .scan
                scanResultsViewModel.startScan()
            },
            onRescan: {
                // ⌘R — re-run the scan using the same root paths and filters
                // (ScanResultsViewModel does not differentiate "new" from
                // "rescan"; both delegate to startScan(), which cancels any
                // in-flight orchestrator run before starting a new one.)
                appState.navigation = .scan
                scanResultsViewModel.startScan()
            }
        )
        .modifier(RootKeyboardShortcuts(appState: appState))
    }

    // MARK: - Background
    @ViewBuilder
    private var backgroundLayer: some View {
        Color.bgPrimary.ignoresSafeArea()
    }

    // MARK: - Main Content
    @ViewBuilder
    private var mainContent: some View {
        switch appState.navigation {
        case .scan:
            ScanResultsView(viewModel: scanResultsViewModel)
        case .cleanup:
            CleanupContentView(viewModel: cleanupViewModel)
        case .history:
            HistoryContentView()
        case .settings:
            SettingsView()
        // v1.5 stage B — see `docs/superpowers/plans/2026-08-09-kwise-v1.5-plan.md`.
        // Real module views land in Phase B Task 3+ / Phase C Task 7+ / Phase D Task 11+.
        case .smartCare:
            SmartCareHeroView()
        case .privacy:
            PlaceholderModuleView(title: "隐私清理", subtitle: "Phase C 上线")
        case .diskHealth:
            PlaceholderModuleView(title: "磁盘健康", subtitle: "Phase D 上线")
        }
    }

    // MARK: - Icon Rail
    private var iconRail: some View {
        GlassPanel {
            VStack(spacing: 4) {
                ForEach(AppState.NavigationItem.allCases, id: \.self) { item in
                    IconRailButton(
                        item: item,
                        isSelected: appState.navigation == item,
                        action: { appState.navigation = item }
                    )
                }
                Spacer()
            }
            .padding(.vertical, AppSpacing.sm)
        }
        .frame(width: 42)
    }
}

/// F9 perf sweep: small Equatable helper view that wraps each icon
/// rail button. `.equatable()` on it means a `navigation` change
/// only re-evaluates the two affected buttons (selected and
/// deselected) instead of every button in the rail. Equality is
/// `(item, isSelected)` because the row body depends only on those.
private struct IconRailButton: View, Equatable {
    let item: AppState.NavigationItem
    let isSelected: Bool
    let action: () -> Void

    static func == (lhs: IconRailButton, rhs: IconRailButton) -> Bool {
        lhs.item == rhs.item && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: item.iconName)
                .font(.system(size: 16))
                .frame(width: 36, height: 36)
                .background(isSelected ? Color.brandPrimary.opacity(0.3) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
        }
        .buttonStyle(.plain)
        .help(item.tooltip)
    }
}

// MARK: - v1.5 Placeholder Module View

/// Placeholder view for v1.5 modules pending real implementation.
///
/// Renders title + subtitle in the main content area for Smart Care /
/// Privacy / Disk Health until their Phase B/C/D real module views land
/// (see `docs/superpowers/plans/2026-08-09-kwise-v1.5-plan.md` Tasks 2 / 7 / 11).
///
/// Inlined in this file (not its own Swift file) to avoid touching
/// `kWise.xcodeproj/project.pbxproj` until Phase B wires the real views.
private struct PlaceholderModuleView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: AppSpacing.md) {
            Text(title)
                .font(AppFont.title)
                .foregroundStyle(Color.textPrimary)
            Text(subtitle)
                .font(AppFont.body)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary)
    }
}

// MARK: - Root Keyboard Shortcuts

/// Global keyboard shortcuts for the main app window.
private struct RootKeyboardShortcuts: ViewModifier {
    @ObservedObject var appState: AppState
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    let isCommand = flags == .command

                    guard isCommand else { return event }

                    switch event.charactersIgnoringModifiers {
                    case "f":
                        appState.rightPanelTab = .results
                        appState.rightPanelVisible = true
                        return nil
                    default: return event
                    }
                }
            }
            .onDisappear {
                if let monitor = monitor {
                    NSEvent.removeMonitor(monitor)
                    self.monitor = nil
                }
            }
    }
}
