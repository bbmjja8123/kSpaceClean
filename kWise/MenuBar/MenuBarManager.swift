import AppKit

/// Menu bar status item (C-8).
///
/// v2.0 Phase 3: the three action menu items used to be empty `/* trigger */`
/// stubs and the "最近清理" row showed hardcoded fake data. Actions now route
/// through closures the app root installs (single source of navigation
/// authority via `AppCoordinator`), and the last-cleanup row is fed by the
/// same `CleanupEventSink` stream as the quota ledger.
@MainActor
public final class MenuBarManager: NSObject, ObservableObject, CleanupEventSink {
    private var statusItem: NSStatusItem?
    /// Background timer that refreshes the menu-bar status item every
    /// ≤10s — drives C-8 (menu bar live number). Invalidated on `setup()`
    /// re-entry or when the manager deallocates.
    private var refreshTimer: Timer?

    // MARK: Action routing (installed by the app root / RootView)

    /// Opens the main window and starts a fresh scan.
    public var onQuickScan: (() -> Void)?
    /// Opens the main window and runs the Smart Care flow
    /// (scan → recommend → confirm recommended picks).
    public var onQuickClean: (() -> Void)?
    /// Opens the main window on the settings surface.
    public var onOpenSettings: (() -> Void)?

    // MARK: Live state

    /// Real "最近清理" summary — never a placeholder string (C-5).
    @Published public private(set) var lastCleanupSummary: String = "暂无清理记录"

    public func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.action = #selector(toggleMenu)
        statusItem?.button?.target = self
        statusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateMenu()
        // C-8: kick off the live refresh. Capture-and-replace any prior
        // timer so duplicate setup() calls don't accumulate observers.
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: 10.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDiskUsage()
            }
        }
        // First paint happens immediately rather than waiting 10 s.
        refreshDiskUsage()
    }

    // MARK: - CleanupEventSink

    /// Fed by the shared graph sinks — the "最近清理" row updates from real
    /// engine outcomes, in the menu bar process and nowhere else. Zero-byte
    /// runs are ignored so the row never shows "0 B" noise.
    public nonisolated func cleanupDidFinish(_ event: CleanupEvent) async {
        guard event.freedBytes > 0 else { return }
        let formatted = ByteCountFormatter.string(fromByteCount: event.freedBytes, countStyle: .file)
        let summary = String(localized: "menu.lastCleanup \(formatted)")
        await MainActor.run { [weak self] in
            self?.lastCleanupSummary = summary
            self?.updateMenu()
        }
    }

    public func updateDiskUsage(used: Int64, total: Int64) {
        let percentage = total > 0 ? Double(used) / Double(total) : 0
        let color: NSColor = percentage < 0.7 ? .systemGreen : percentage < 0.9 ? .systemYellow : .systemRed

        let formatted = ByteCountFormatter.string(fromByteCount: used, countStyle: .file)
        statusItem?.button?.attributedTitle = NSAttributedString(
            string: "\(formatted)",
            attributes: [.foregroundColor: color]
        )
    }

    /// Re-read the boot volume's used/total bytes from the system and pipe
    /// them into ``updateDiskUsage(used:total:)``. Runs on the main actor
    /// because the menu-bar item's button touches AppKit.
    private func refreshDiskUsage() {
        let homeURL = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? homeURL.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        ) else {
            return
        }
        let total = Int64(values.volumeTotalCapacity ?? 0)
        let available = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        let used = max(0, total - available)
        updateDiskUsage(used: used, total: total)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "快速清理", action: #selector(quickClean), keyEquivalent: "")
        menu.addItem(withTitle: "快速扫描", action: #selector(quickScan), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: lastCleanupSummary, action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "打开主窗口", action: #selector(openMainWindow), keyEquivalent: "")
        menu.addItem(withTitle: "设置", action: #selector(openSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApp.terminate), keyEquivalent: "q")
        // Retain targets for the lifetime of the menu build (self is the
        // target; the menu item needs the selector + target pair).
        for item in menu.items {
            item.target = self
        }
        return menu
    }

    private func updateMenu() {
        statusItem?.menu = buildMenu()
    }

    @objc private func toggleMenu() { statusItem?.button?.performClick(nil) }

    @objc private func quickClean() {
        onQuickClean?()
    }

    @objc private func quickScan() {
        onQuickScan?()
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.isVisible {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        onOpenSettings?()
    }
}
