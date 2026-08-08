import Foundation

public struct UserPreferences: Codable {
    public var largeFileThreshold: Int64 = 100 * 1024 * 1024  // 100MB
    public var ignoredPaths: [String] = []
    public var aiClassificationEnabled: Bool = true
    public var defaultCleanAction: CleanAction = .trash
    public var confirmHighRisk: Bool = true
    public var historyRetentionDays: Int = 30
    public var launchAtLogin: Bool = false
    public var showMenuBarDiskUsage: Bool = true
    public var scanSpeed: ScanSpeed = .medium

    public enum CleanAction: String, Codable {
        case trash, permanent
    }

    public static func load() -> UserPreferences {
        guard let data = try? Data(contentsOf: preferencesURL),
              let prefs = try? JSONDecoder().decode(UserPreferences.self, from: data) else {
            return UserPreferences()
        }
        return prefs
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.preferencesURL, options: .atomic)
    }

    private static var preferencesURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("app.kraftly.sclean/preferences.json")
    }
}
