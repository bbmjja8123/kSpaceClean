import FinderSync

final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        // Set the directory hierarchy to watch — whole disk
        let topDir = URL(fileURLWithPath: "/")
        FIFinderSyncController.default().directoryURLs = Set([topDir])
    }

    // MARK: - Menu Setup

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "kSpaceClean")
        let scanItem = NSMenuItem(
            title: "Scan with kSpaceClean",
            action: #selector(scanWithKSpaceClean(_:)),
            keyEquivalent: ""
        )
        scanItem.image = NSImage(systemSymbolName: "externaldrive.fill", accessibilityDescription: nil)
        menu.addItem(scanItem)
        return menu
    }

    @objc
    private func scanWithKSpaceClean(_ sender: AnyObject) {
        guard let selectedURLs = FIFinderSyncController.default().selectedItemURLs(),
              let firstURL = selectedURLs.first
        else { return }

        let path = firstURL.path
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        guard let url = URL(string: "kspaceclean://scan?path=\(encodedPath)") else { return }
        NSWorkspace.shared.open(url)
    }
}
