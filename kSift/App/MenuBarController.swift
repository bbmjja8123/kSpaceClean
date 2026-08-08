import AppKit
import Foundation

/// Owns kSift's menu-bar status item and routes menu actions into the app.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let coordinator: AppCoordinator
    private weak var appState: AppState?
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let recentResultsItem = NSMenuItem(title: NSLocalizedString("Recent Results", comment: "Menu bar recent results"), action: nil, keyEquivalent: "")
    private var recentRecords: [ScanRecord] = []

    init(coordinator: AppCoordinator, appState: AppState) {
        self.coordinator = coordinator
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        configureMenu()
        loadRecentResults()
    }

    deinit {
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusItem() {
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: NSLocalizedString("kSift", comment: "App name"))
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.target = self
        statusItem.button?.action = #selector(openApp)
        statusItem.button?.sendAction(on: [.leftMouseUp])
        statusItem.button?.toolTip = NSLocalizedString("Open kSift", comment: "Menu bar tooltip")
    }

    private func configureMenu() {
        menu.delegate = self
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem(title: NSLocalizedString("Open kSift", comment: "Menu bar open action"), action: #selector(openApp), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: NSLocalizedString("Quick Scan…", comment: "Menu bar quick scan action"), action: #selector(quickScan), keyEquivalent: ""))
        recentResultsItem.submenu = NSMenu()
        menu.addItem(recentResultsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: NSLocalizedString("Show Vault", comment: "Menu bar vault action"), action: #selector(showVault), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: NSLocalizedString("Quit kSift", comment: "Menu bar quit action"), action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items where item.action != nil { item.target = self }
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        loadRecentResults()
    }

    @objc private func openApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    @objc private func quickScan() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = NSLocalizedString("Quick Scan…", comment: "Menu bar quick scan action")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        coordinator.handleFinderScanRequest(path: url.path)
        openApp()
    }

    @objc private func showVault() {
        _ = coordinator.handleDeepLink(URL(string: "ksift://vault")!)
        openApp()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func loadRecentResults() {
        Task { [weak self] in
            let records = (try? await DuplicateRepositoryCoreData().loadScanRecords()) ?? []
            await MainActor.run {
                self?.recentRecords = Array(records.prefix(5))
                self?.updateRecentMenu()
                if let latest = records.first {
                    self?.statusItem.button?.attributedTitle = NSAttributedString(string: ByteCountFormatter.string(fromByteCount: latest.totalWasteSize, countStyle: .file) + " " + NSLocalizedString("freed", comment: "Menu bar freed subtitle"), attributes: [.font: NSFont.menuFont(ofSize: 10)])
                }
            }
        }
    }

    private func updateRecentMenu() {
        let submenu = NSMenu()
        if recentRecords.isEmpty {
            let item = NSMenuItem(title: NSLocalizedString("No scans yet", comment: "Empty recent results"), action: nil, keyEquivalent: "")
            submenu.addItem(item)
        } else {
            for record in recentRecords {
                let title = ByteCountFormatter.string(fromByteCount: record.totalWasteSize, countStyle: .file)
                let item = NSMenuItem(title: "\(title) · \(record.timestamp.formatted(date: .abbreviated, time: .shortened))", action: #selector(openResults), keyEquivalent: "")
                item.target = self
                submenu.addItem(item)
            }
        }
        recentResultsItem.submenu = submenu
    }

    @objc private func openResults() {
        coordinator.navigate(to: .results)
        openApp()
    }
}
