import FinderSync
import Foundation

/// Hand-off contract with the main app. The extension writes the folder the
/// user picked into the shared App Group UserDefaults, then fires a bare
/// Darwin notification. The main app reads the path from the same defaults
/// and starts a scan rooted at that folder.
///
/// Payload-in-the-notification-name is fragile (path may contain slashes),
/// and CFNotificationCenter's `object` pointer is awkward to round-trip
/// across processes. Shared UserDefaults is the cheapest reliable channel
/// within a sandboxed App Group.
private enum FinderSyncContract {
    static let pendingPathKey = "ksift.finderSync.pendingPath"
    static let notificationName = CFNotificationName("com.kraftly.ksift.scanFolder" as CFString)
}

class FinderSyncHandler: FIFinderSync {
    /// Scope FinderSync to the folders a user is most likely to want to
    /// "Scan with kSift" on. Watching the whole home directory triggers a
    /// "kSift is monitoring your home" warning in Finder — too invasive for
    /// a duplicate finder.
    private static let watchedDirectories: Set<URL> = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = ["Documents", "Downloads", "Desktop", "Pictures"]
            .map { home.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        return Set(candidates)
    }()

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = Self.watchedDirectories
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "kSift")
        let scanItem = NSMenuItem(
            title: "Scan with kSift",
            action: #selector(scanFolder(_:)),
            keyEquivalent: ""
        )
        scanItem.image = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: "Scan with kSift"
        )
        menu.addItem(scanItem)
        return menu
    }

    @objc func scanFolder(_ sender: AnyObject?) {
        guard let url = FIFinderSyncController.default().selectedItemURLs()?.first else {
            return
        }
        // Stash the path in the App Group suite the main app reads from.
        // Falls back to the standard defaults if the suite is unavailable
        // (e.g., running outside the App Group container).
        let defaults = UserDefaults(suiteName: "group.app.kraftly.ksift")
            ?? .standard
        defaults.set(url.path, forKey: FinderSyncContract.pendingPathKey)
        // Bare Darwin notification — the main app's AppCoordinator reads
        // the path back out of shared UserDefaults when this fires.
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            FinderSyncContract.notificationName,
            nil,
            nil,
            true
        )
    }

    override func beginObservingDirectory(at url: URL) {
        // Badge support intentionally left for a later phase — a useful
        // duplicate count would need a background indexer, which is out of
        // scope here.
    }

    override func endObservingDirectory(at url: URL) {}
}