import AppKit
import Combine
import SwiftUI
import MetricsKit
import DesignSystem

/// Owns one `NSStatusItem` per metric in multi-icon mode.
///
/// Multi-icon mode cannot be expressed with SwiftUI `Scene` builders on the
/// macOS 13 SDK (no `ForEach` in a `Scene`, no runtime `if`), so the per-metric
/// icons are AppKit status items hosting a SwiftUI popover. The SwiftUI
/// `MenuBarExtra` label renders the FIRST metric in `menuBarOrder`; this
/// controller renders `menuBarOrder.dropFirst()` to avoid duplicates.
@MainActor
public final class MultiIconStatusItemController: NSObject {
    private let menuBarViewModel: MenuBarViewModel
    private let appState: AppState
    private let purchaseState: PurchaseState
    private let onOpenSettings: () -> Void
    private let onOpenHistory: () -> Void
    private let onOpenProcesses: () -> Void
    private let onOpenAlerts: () -> Void
    private let onOpenPaywall: (() -> Void)?

    private var items: [MetricKind: NSStatusItem] = [:]
    private var popovers: [MetricKind: NSPopover] = [:]
    /// Combine storage shared with the app delegate so the settings-driven
    /// subscription can keep the controller's metric set in sync. `internal`
    /// (not `private`) because `kWatchAppDelegate.configureMultiIcon` stores
    /// its sink here.
    internal var cancellables = Set<AnyCancellable>()

    public init(
        menuBarViewModel: MenuBarViewModel,
        appState: AppState,
        purchaseState: PurchaseState,
        onOpenSettings: @escaping () -> Void,
        onOpenHistory: @escaping () -> Void,
        onOpenProcesses: @escaping () -> Void,
        onOpenAlerts: @escaping () -> Void,
        onOpenPaywall: (() -> Void)? = nil
    ) {
        self.menuBarViewModel = menuBarViewModel
        self.appState = appState
        self.purchaseState = purchaseState
        self.onOpenSettings = onOpenSettings
        self.onOpenHistory = onOpenHistory
        self.onOpenProcesses = onOpenProcesses
        self.onOpenAlerts = onOpenAlerts
        self.onOpenPaywall = onOpenPaywall

        super.init()

        // Live-refresh: re-render every status item whenever the shared menu
        // bar view model publishes a new snapshot. `@Published` emits
        // `objectWillChange` at will-set time, so `.receive(on: RunLoop.main)`
        // defers the render to the next runloop cycle when the values have
        // actually landed.
        menuBarViewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateAllIcons()
            }
            .store(in: &cancellables)
    }

    public func setMetrics(_ kinds: [MetricKind]) {
        let desired = Set(kinds)
        for (kind, item) in items where !desired.contains(kind) {
            item.button?.image = nil
            NSStatusBar.system.removeStatusItem(item)
            items[kind] = nil
            popovers[kind] = nil
        }
        for kind in kinds {
            if items[kind] == nil {
                makeItem(for: kind)
            }
        }
        updateAllIcons()
    }

    public func updateAllIcons() {
        for kind in items.keys {
            updateIcon(for: kind)
        }
    }

    private func makeItem(for kind: MetricKind) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = iconImage(for: kind)
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked(_:))
        item.button?.toolTip = displayName(for: kind)
        items[kind] = item
    }

    private func updateIcon(for kind: MetricKind) {
        items[kind]?.button?.image = iconImage(for: kind)
    }

    private func iconImage(for kind: MetricKind) -> NSImage {
        let (values, currentValue, unit) = menuBarViewModel.displayData(for: kind)
        let style = menuBarViewModel.iconStyle(for: kind)
        let renderer = ImageRenderer(content:
            MenuBarIcons.statusIcon(
                kind: kind,
                style: style,
                values: values,
                currentValue: currentValue,
                unit: unit
            )
        )
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        return renderer.nsImage ?? NSImage(size: NSSize(width: 1, height: 1))
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let button = sender as? NSButton,
              let kind = items.first(where: { $0.value.button === button })?.key
        else { return }
        togglePopover(for: kind, from: button)
    }

    private func togglePopover(for kind: MetricKind, from button: NSButton) {
        if let popover = popovers[kind] {
            if popover.isShown {
                popover.performClose(nil)
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
            return
        }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 480)
        let content = MenuBarView(
            viewModel: menuBarViewModel,
            appState: appState,
            purchaseState: purchaseState,
            onOpenDashboard: { AppWindowRouter.openDashboardWindow() },
            onOpenSettings: onOpenSettings,
            onOpenHistory: onOpenHistory,
            onOpenProcesses: onOpenProcesses,
            onOpenAlerts: onOpenAlerts,
            onOpenPaywall: onOpenPaywall
        )
        popover.contentViewController = NSHostingController(rootView: content)
        popovers[kind] = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func displayName(for kind: MetricKind) -> String {
        switch kind {
        case .cpu: return "CPU"
        case .memory: return "Memory"
        case .disk: return "Disk"
        case .network: return "Network"
        case .temperature: return "Temperature"
        case .fan: return "Fan"
        case .battery: return "Battery"
        }
    }

    deinit {
        for item in items.values {
            NSStatusBar.system.removeStatusItem(item)
        }
    }
}
