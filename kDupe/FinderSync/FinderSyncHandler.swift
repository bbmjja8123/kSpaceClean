import FinderSync
import Foundation

class FinderSyncHandler: FIFinderSync {
    override init() {
        super.init()
        let home = FileManager.default.homeDirectoryForCurrentUser
        FIFinderSyncController.default().directoryURLs = Set([home])
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "kDupe")
        let scanItem = NSMenuItem(title: "Scan with kDupe",
                                  action: #selector(scanFolder(_:)),
                                  keyEquivalent: "")
        scanItem.image = NSImage(systemSymbolName: "doc.on.doc",
                                accessibilityDescription: "Scan")
        menu.addItem(scanItem)
        return menu
    }

    @objc func scanFolder(_ sender: AnyObject?) {
        guard let item = FIFinderSyncController.default().selectedItemURLs?.first else { return }
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("com.kraftly.kdupe.scanFolder" as CFString),
            item.path as CFString,
            nil,
            true
        )
    }

    override func beginObservingDirectory(at url: URL) {
        // Update badge counts
    }

    override func endObservingDirectory(at url: URL) {}
}
