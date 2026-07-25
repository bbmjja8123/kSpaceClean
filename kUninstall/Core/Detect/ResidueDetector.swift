import Foundation

actor ResidueDetector {
    private let fileManager = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    /// Detect residual files for a given app using bundle ID and app name.
    func detectResidues(bundleID: String, appName: String) async -> [ResidueFile] {
        guard !bundleID.isEmpty else { return [] }
        let templates = pathTemplates(bundleID: bundleID, appName: appName)

        var results = [ResidueFile]()
        for (path, type, confidence, isSystemLevel) in templates {
            let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
            let exists = fileManager.fileExists(atPath: url.path)

            results.append(ResidueFile(
                url: url,
                type: type,
                sizeBytes: exists ? (try? fileManager.allocatedSizeOfDirectory(at: url)) ?? 0 : 0,
                confidence: exists ? confidence : confidence * 0.5,
                description: descriptionForType(type, path: path),
                isSystemLevel: isSystemLevel,
                isProtected: isSystemLevel
            ))
        }
        return results.sorted { $0.confidence > $1.confidence }
    }

    /// Build path templates from bundle ID and app name.
    internal func pathTemplates(bundleID: String, appName: String) -> [(path: String, type: ResidueType, confidence: Double, isSystemLevel: Bool)] {
        let homePath = home.path
        let library = "\(homePath)/Library"
        let systemLibrary = "/Library"

        return [
            ("\(library)/Preferences/\(bundleID).plist",          .preferences,    0.99, false),
            ("\(library)/Caches/\(bundleID)/",                    .caches,         0.99, false),
            ("\(library)/Application Support/\(appName)/",        .appSupport,     0.95, false),
            ("\(library)/Saved Application State/\(bundleID).savedState", .savedState, 0.99, false),
            ("\(library)/Containers/\(bundleID)/",                .container,      0.99, false),
            ("\(library)/WebKit/\(bundleID)/",                    .webKit,         0.85, false),
            ("\(library)/HTTPStorages/\(bundleID)/",              .httpStorage,    0.95, false),
            ("\(library)/Group Containers/\(bundleID)/",          .groupContainer, 0.80, false),
            ("\(library)/Internet Plug-Ins/\(appName).plugin/",   .plugin,         0.80, false),
            ("\(systemLibrary)/LaunchAgents/\(bundleID).plist",   .launchAgent,    0.95, true),
            ("\(systemLibrary)/LaunchDaemons/\(bundleID).plist",  .launchDaemon,   0.95, true),
            ("\(systemLibrary)/PreferencePanes/\(appName).prefPane", .prefPane,    0.85, true),
            ("\(systemLibrary)/StartupItems/\(appName)/",         .startupItem,    0.85, true),
        ]
    }

    private func descriptionForType(_ type: ResidueType, path: String) -> String {
        switch type {
        case .preferences:   return "偏好设置"
        case .caches:        return "缓存文件"
        case .appSupport:    return "应用支持文件"
        case .container:     return "App Sandbox 容器"
        case .savedState:    return "保存的应用状态"
        case .webKit:        return "WebKit 缓存"
        case .httpStorage:   return "HTTP 存储"
        case .groupContainer:return "Group 容器"
        case .plugin:        return "插件"
        case .launchAgent:   return "启动代理"
        case .launchDaemon:  return "启动守护"
        case .prefPane:      return "偏好设置面板"
        case .startupItem:   return "启动项"
        case .other:         return "其他"
        }
    }
}

// MARK: - FileManager helper for directory size

extension FileManager {
    func allocatedSizeOfDirectory(at url: URL) throws -> Int64 {
        guard let enumerator = enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey],
                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }
}
