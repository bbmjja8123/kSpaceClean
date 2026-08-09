import AppKit

@MainActor
public final class MenuBarManager: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?
    /// Background timer that refreshes the menu-bar status item every
    /// ≤10s — drives C-8 (menu bar live number). Invalidated on `setup()`
    /// re-entry or when the manager deallocates.
    private var refreshTimer: Timer?

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
        menu.addItem(NSMenuItem(title: "快速清理", action: #selector(quickClean), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "快速扫描", action: #selector(quickScan), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "最近清理: 今天 10:30 · 3.2 GB", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "打开主窗口", action: #selector(openMainWindow), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "设置", action: #selector(openSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApp.terminate), keyEquivalent: "q"))
        return menu
    }

    private func updateMenu() {
        statusItem?.menu = buildMenu()
    }

    @objc private func toggleMenu() { statusItem?.button?.performClick(nil) }
    @objc private func quickClean() { /* trigger clean */ }
    @objc private func quickScan() { /* trigger scan */ }
    @objc private func openMainWindow() { NSApp.activate(ignoringOtherApps: true) }
    @objc private func openSettings() { /* show settings */ }
}
