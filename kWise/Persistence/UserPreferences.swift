import Foundation
import DetectionCore

public struct UserPreferences: Codable, Equatable {
    public var largeFileThreshold: Int64 = 100 * 1024 * 1024  // 100MB
    public var ignoredPaths: [String] = []
    public var aiClassificationEnabled: Bool = true
    public var defaultCleanAction: CleanAction = .trash
    public var confirmHighRisk: Bool = true
    public var historyRetentionDays: Int = 30
    public var launchAtLogin: Bool = false
    public var showMenuBarDiskUsage: Bool = true
    public var scanSpeed: ScanSpeed = .medium
    /// Post-cleanup local notification (v2.0 Phase 1 — the old Settings
    /// toggle was `.constant(true)` with nothing behind it).
    public var notifyAfterCleanup: Bool = false
    /// Shredder overwrite passes (v2.0 Phase 5). 1 is the honest default on
    /// SSD; 3 is the opt-in "HDD 模式".
    public var shredPasses: Int = 1
    /// Gates the assistant's semantic (NLEmbedding) layer (v2.0 Phase 8).
    public var assistantEnabled: Bool = true
    /// Similar-photo grouping aggressiveness raw value (v2.3 Phase 3).
    /// Optional + computed accessor: absent in pre-v2.3 JSON → decodes nil
    /// → `.normal`, instead of throwing and resetting every preference.
    public var similarityPresetRaw: String?

    public var similarityPreset: SimilarityPreset {
        get { SimilarityPreset(rawValue: similarityPresetRaw ?? "") ?? .normal }
        set { similarityPresetRaw = newValue.rawValue }
    }

    public enum CleanAction: String, Codable, Equatable {
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
