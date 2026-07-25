import FinderSync

class FinderSync: FIFinderSync {
    override init() {
        super.init()
        let finderSync = FIFinderSyncController.default()
        if let appsURL = URL(string: "file:///Applications/") {
            finderSync.directoryURLs = Set([appsURL])
        }
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "kUninstall")
        let item = NSMenuItem(
            title: "用 kUninstall 深度卸载",
            action: #selector(uninstallItem),
            keyEquivalent: ""
        )
        item.target = self
        menu.addItem(item)
        return menu
    }

    @objc func uninstallItem(_ sender: AnyObject?) {
        guard let item = FIFinderSyncController.default().selectedItemURLs()?.first else { return }
        let appURL = URL(fileURLWithPath: "/Applications/kUninstall.app")
        NSWorkspace.shared.open(
            [item],
            withApplicationAt: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
