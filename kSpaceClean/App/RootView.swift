import SwiftUI
import DesignSystem

/// RootView with navigation content switching.
/// Displays different content based on appState.navigation.
struct RootView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var galaxyViewModel = GalaxyViewModel()
    @StateObject private var scanViewModel = ScanViewModel()
    @StateObject private var cleanupViewModel = CleanupViewModel()

    // C1: production scan pipeline. Owned at the root so the scan state
    // survives navigation switches (e.g. user starts a scan, navigates
    // away, comes back — the categories tree is still there).
    @StateObject private var scanEngine = ScanEngine()
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
                            scanViewModel.startScan()
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

                        // Right panel (only in galaxy/scan views)
                        if appState.rightPanelVisible,
                           appState.navigation == .galaxy || appState.navigation == .scan {
                            RightPanelView(galaxyViewModel: galaxyViewModel, scanViewModel: scanViewModel)
                                .frame(width: min(260, geo.size.width * 0.3))
                                .padding(.trailing, 12)
                                .padding(.top, 48)
                                .padding(.bottom, 68)
                        }
                    }
                }

                // Layer 4: Bottom panel (galaxy view only)
                if appState.navigation == .galaxy {
                    VStack {
                        Spacer()
                        bottomPanel
                            .padding(.horizontal, 68)
                            .padding(.bottom, 10)
                    }
                }

                // Layer 5: Category legend (galaxy view only)
                if appState.navigation == .galaxy {
                    VStack {
                        Spacer()
                        HStack {
                            categoryLegend
                                .padding(.leading, 68)
                            Spacer()
                        }
                        .padding(.bottom, 72)
                    }
                }
            }
        }
        .onChange(of: scanViewModel.scanDidComplete) { completed in
            if completed {
                galaxyViewModel.update(with: scanViewModel.scanResults)
                appState.navigation = .galaxy
            }
        }
        .scanKeyboardShortcuts(
            onNewScan: {
                // ⌘N — switch to the scan surface and start a fresh scan
                appState.navigation = .scan
                scanViewModel.startScan()
            },
            onRescan: {
                // ⌘R — re-run the scan using the same root paths and filters
                // (ScanViewModel does not differentiate "new" from "rescan";
                // both delegate to startScan(). Phase B's ScanOrchestrator
                // will introduce the distinction.)
                appState.navigation = .scan
                scanViewModel.startScan()
            }
        )
        .modifier(RootKeyboardShortcuts(appState: appState))
    }

    // MARK: - Background
    @ViewBuilder
    private var backgroundLayer: some View {
        switch appState.navigation {
        case .galaxy:
            GalaxyView(viewModel: galaxyViewModel)
                .ignoresSafeArea()
        default:
            Color.bgPrimary.ignoresSafeArea()
        }
    }

    // MARK: - Main Content
    @ViewBuilder
    private var mainContent: some View {
        switch appState.navigation {
        case .galaxy:
            galaxyContent
        case .scan:
            ScanResultsView(viewModel: scanResultsViewModel)
        case .cleanup:
            CleanupContentView(viewModel: cleanupViewModel)
        case .history:
            HistoryContentView()
        case .settings:
            SettingsView()
        }
    }

    /// In Galaxy mode, the area behind the right panel is transparent
    /// so the 3D scene shows through. We just place a clear filler.
    private var galaxyContent: some View {
        Color.clear
    }

    // MARK: - Icon Rail
    private var iconRail: some View {
        GlassPanel {
            VStack(spacing: 4) {
                ForEach(AppState.NavigationItem.allCases, id: \.self) { item in
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
                    .help(item.tooltip)
                }
                Spacer()
            }
            .padding(.vertical, AppSpacing.sm)
        }
        .frame(width: 42)
    }

    // MARK: - Bottom Panel
    private var bottomPanel: some View {
        GlassPanel {
            HStack {
                DiskUsageBar(scanViewModel: scanViewModel)
                Spacer()
                HStack(spacing: AppSpacing.sm) {
                    Button(action: {
                        appState.navigation = .scan
                        scanViewModel.startScan()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 12))
                            Text("\u{5FEB}\u{901F}\u{626B}\u{63CF}")
                                .font(AppFont.caption)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.textSecondary)

                    Button(action: {
                        appState.navigation = .scan
                        scanViewModel.startScan()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12))
                            Text("\u{5F00}\u{59CB}\u{626B}\u{63CF}")
                                .font(AppFont.caption)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
                }
            }
            .padding(.horizontal, AppSpacing.lg)
            .frame(height: 48)
        }
    }

    // MARK: - Category Legend
    private var categoryLegend: some View {
        HStack(spacing: 10) {
            ForEach(FileCategory.allCases, id: \.self) { cat in
                HStack(spacing: 4) {
                    Circle()
                        .fill(cat.color)
                        .frame(width: 8, height: 8)
                    Text(verbatim: "\(cat)")
                        .font(AppFont.caption)
                        .foregroundColor(.textSecondary)
                }
                .onTapGesture { appState.selectedCategory = cat }
                .help(cat.rawValue)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.lg))
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
