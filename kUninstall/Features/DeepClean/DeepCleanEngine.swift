import Foundation
import CoreServices

actor DeepCleanEngine {
    private let fileManager = FileManager.default

    struct CleanGroup: Identifiable {
        var id: String { title }
        let title: String
        let icon: String
        let items: [CleanItem]
    }

    struct CleanItem: Identifiable {
        var id: String { url.path }
        let url: URL
        let name: String
        let sizeBytes: Int64
        let type: StartupItemType
        var isSelected: Bool
    }

    func scanSystemWideResidues() async -> [CleanGroup] {
        await withTaskGroup(of: CleanGroup?.self) { group in
            group.addTask { await self.scanDaemons() }
            group.addTask { await self.scanAgents() }
            group.addTask { await self.scanPanes() }
            group.addTask { await self.scanLoginItems() }

            var groups = [CleanGroup]()
            for await g in group {
                if let g = g, !g.items.isEmpty { groups.append(g) }
            }
            return groups
        }
    }

    func cleanSelected(_ groups: [CleanGroup]) async -> Int {
        var totalCleaned: Int64 = 0
        for group in groups {
            for item in group.items where item.isSelected {
                try? fileManager.removeItem(at: item.url)
                totalCleaned += item.sizeBytes
            }
        }
        return Int(totalCleaned)
    }

    private func scanDaemons() async -> CleanGroup? {
        let dir = URL(fileURLWithPath: "/Library/LaunchDaemons")
        let plists = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let items = plists.filter { $0.pathExtension == "plist" }.map { url in
            CleanItem(url: url, name: url.deletingPathExtension().lastPathComponent,
                       sizeBytes: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0),
                       type: .launchDaemon, isSelected: false)
        }
        return CleanGroup(title: "Launch Daemons", icon: "gearshape.2", items: items)
    }

    private func scanAgents() async -> CleanGroup? {
        let home = fileManager.homeDirectoryForCurrentUser
        let dirs = [
            URL(fileURLWithPath: "/Library/LaunchAgents"),
            home.appendingPathComponent("Library/LaunchAgents"),
        ]
        var allItems = [CleanItem]()
        for dir in dirs {
            let plists = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            allItems += plists.filter { $0.pathExtension == "plist" }.map { url in
                CleanItem(url: url, name: url.deletingPathExtension().lastPathComponent,
                           sizeBytes: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0),
                           type: .launchAgent, isSelected: false)
            }
        }
        return CleanGroup(title: "Launch Agents", icon: "power", items: allItems)
    }

    private func scanPanes() async -> CleanGroup? {
        let dirs = [
            URL(fileURLWithPath: "/Library/PreferencePanes"),
            URL(fileURLWithPath: "/System/Library/PreferencePanes"),
        ]
        var allItems = [CleanItem]()
        for dir in dirs {
            let panes = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            allItems += panes.filter { $0.pathExtension == "prefPane" }.map { url in
                CleanItem(url: url, name: url.deletingPathExtension().lastPathComponent,
                           sizeBytes: 0, type: .prefPane, isSelected: false)
            }
        }
        return CleanGroup(title: "Preference Panes", icon: "switch.2", items: allItems)
    }

    private func scanLoginItems() async -> CleanGroup? {
        let list = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil)?.takeRetainedValue()
        guard let list else { return nil }
        let items = LSSharedFileListCopySnapshot(list, nil)?.takeRetainedValue() as! [LSSharedFileListItem]
        let cleanItems = items.compactMap { item -> CleanItem? in
            var url: Unmanaged<CFURL>?
            let name = LSSharedFileListItemCopyDisplayName(item).takeRetainedValue() as String? ?? "Unknown"
            guard LSSharedFileListItemResolve(item, 0, &url, nil) == noErr, let resolvedURL = url?.takeRetainedValue() as URL? else { return nil }
            return CleanItem(url: resolvedURL, name: name, sizeBytes: 0, type: .loginItem, isSelected: false)
        }
        return CleanGroup(title: "Login Items", icon: "person.circle", items: cleanItems)
    }
}
