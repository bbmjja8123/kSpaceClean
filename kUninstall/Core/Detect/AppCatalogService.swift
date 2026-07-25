import Foundation
import AppKit

actor AppCatalogService {
    private let fileManager = FileManager.default

    func scan() async -> [InstalledApp] {
        let lsApps = queryLaunchServices()
        let fsApps = await enumerateApplications()
        return deduplicate(merge: lsApps + fsApps)
    }

    // MARK: - LaunchServices

    private func queryLaunchServices() -> [InstalledApp] {
        let workspace = NSWorkspace.shared
        let apps = workspace.runningApplications.compactMap { app -> InstalledApp? in
            guard let url = app.bundleURL else { return nil }
            let bundle = Bundle(url: url)
            return InstalledApp(
                url: url,
                displayName: app.localizedName ?? url.lastPathComponent,
                bundleID: app.bundleIdentifier ?? "unknown",
                version: bundle?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                icon: workspace.icon(forFile: url.path),
                sizeBytes: 0,
                source: .unknown,
                isRunning: true,
                lastUsedDate: nil
            )
        }

        let appDirs = ["/Applications", "/Applications/Utilities",
                       "/System/Applications", "/System/Applications/Utilities"]
        let allApps = apps + appDirs.flatMap { dir -> [InstalledApp] in
            appsInDirectory(dir, workspace: workspace)
        }
        return allApps
    }

    private func appsInDirectory(_ dir: String, workspace: NSWorkspace) -> [InstalledApp] {
        guard let urls = try? fileManager.contentsOfDirectory(at: URL(fileURLWithPath: dir),
                                                               includingPropertiesForKeys: [.applicationIsScriptableKey],
                                                               options: .skipsHiddenFiles) else { return [] }
        return urls.filter { $0.pathExtension == "app" || $0.pathExtension == "app/Contents" }.compactMap { url in
            let bundle = Bundle(url: url)
            let bundleID = bundle?.bundleIdentifier ?? "unknown"
            return InstalledApp(
                url: url,
                displayName: bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
                    ?? bundle?.infoDictionary?["CFBundleDisplayName"] as? String
                    ?? url.deletingPathExtension().lastPathComponent,
                bundleID: bundleID,
                version: bundle?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                icon: workspace.icon(forFile: url.path),
                sizeBytes: 0,
                source: self.classifySource(url: url, bundleID: bundleID),
                isRunning: false,
                lastUsedDate: nil
            )
        }
    }

    // MARK: - FileSystem enumeration (FDA required)

    private func enumerateApplications() async -> [InstalledApp] {
        // Without FDA we rely on LaunchServices; this is a fallback
        // when user grants FDA via Security-Scoped Bookmark
        []
    }

    // MARK: - Dedup

    private func deduplicate(merge apps: [InstalledApp]) -> [InstalledApp] {
        var dict = [String: InstalledApp]()
        for app in apps {
            if let existing = dict[app.bundleID] {
                let merged = InstalledApp(
                    url: existing.isRunning ? existing.url : app.url,
                    displayName: existing.displayName,
                    bundleID: existing.bundleID,
                    version: existing.version.isEmpty ? app.version : existing.version,
                    icon: existing.icon,
                    sizeBytes: max(existing.sizeBytes, app.sizeBytes),
                    source: existing.source == .unknown ? app.source : existing.source,
                    isRunning: existing.isRunning || app.isRunning,
                    lastUsedDate: existing.lastUsedDate ?? app.lastUsedDate
                )
                dict[app.bundleID] = merged
            } else {
                dict[app.bundleID] = app
            }
        }
        return Array(dict.values).sorted { $0.displayName < $1.displayName }
    }

    // MARK: - Source Classification

    nonisolated func classifySource(url: URL, bundleID: String) -> AppSource {
        let path = url.path
        if path.hasPrefix("/System/") { return .system }
        if bundleID == "com.apple.finder" { return .system }
        if hasMASReceipt(url) { return .mas }
        if bundleID.hasPrefix("com.apple.") || bundleID == "com.apple.dt.Xcode" {
            return .appleBuiltIn
        }
        if path.contains("/Applications/") { return .userInstalled }
        return .unknown
    }

    private nonisolated func hasMASReceipt(_ url: URL) -> Bool {
        let receiptURL = url.appendingPathComponent("Contents/_MASReceipt/receipt")
        return FileManager.default.fileExists(atPath: receiptURL.path)
    }
}
