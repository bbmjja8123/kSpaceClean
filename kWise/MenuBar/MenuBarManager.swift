import AppKit

@MainActor
public final class MenuBarManager: NSObject, ObservableObject {
    private var statusItem: NSStatusItem?

    public func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.button?.action = #selector(toggleMenu)
        statusItem?.button?.target = self
        statusItem?.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateMenu()
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
