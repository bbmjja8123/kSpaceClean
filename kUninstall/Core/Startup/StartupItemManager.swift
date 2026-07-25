import Foundation

actor StartupItemManager {
    func listItems() async -> [StartupItem] {
        await withTaskGroup(of: [StartupItem].self) { group in
            group.addTask { await self.listLoginItems() }
            group.addTask { await self.listLaunchAgents() }
            group.addTask { await self.listLaunchDaemons() }

            var all = [StartupItem]()
            for await items in group { all += items }
            return all.sorted { $0.name < $1.name }
        }
    }

    func remove(item: StartupItem) async {
        try? FileManager.default.removeItem(at: item.url)
    }

    private func listLoginItems() async -> [StartupItem] {
        guard let list = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeRetainedValue(), nil)?.takeRetainedValue() else { return [] }
        guard let snapshot = LSSharedFileListCopySnapshot(list, nil) else { return [] }
        let items = snapshot.takeRetainedValue() as! [LSSharedFileListItem]
        return items.compactMap { item -> StartupItem? in
            var url: Unmanaged<CFURL>?
            guard LSSharedFileListItemResolve(item, 0, &url, nil) == noErr,
                  let resolvedURL = url?.takeRetainedValue() as URL? else { return nil }
            let name = LSSharedFileListItemCopyDisplayName(item).takeRetainedValue() as String
            return StartupItem(name: name, type: .loginItem, url: resolvedURL,
                                appURL: resolvedURL, enabled: true,
                                isProtected: false)
        }
    }

    private func listLaunchAgents() async -> [StartupItem] {
        let dirs = [
            URL(fileURLWithPath: "/Library/LaunchAgents"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents"),
        ]
        return itemsFromPlistDirectories(dirs, type: .launchAgent)
    }

    private func listLaunchDaemons() async -> [StartupItem] {
        let dir = URL(fileURLWithPath: "/Library/LaunchDaemons")
        return itemsFromPlistDirectories([dir], type: .launchDaemon)
    }

    private func itemsFromPlistDirectories(_ dirs: [URL], type: StartupItemType) -> [StartupItem] {
        dirs.flatMap { dir in
            guard let plists = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [StartupItem]() }
            return plists.filter { $0.pathExtension == "plist" }.map { url in
                StartupItem(name: url.deletingPathExtension().lastPathComponent,
                            type: type, url: url, appURL: nil,
                            enabled: true, isProtected: url.path.hasPrefix("/System/"))
            }
        }
    }
}
