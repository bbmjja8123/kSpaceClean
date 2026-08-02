import Foundation

/// Single source of truth for persisting the user's scan configuration.
///
/// Onboarding, Settings, and the scan orchestration all read/write the same
/// UserDefaults keys, so a value set in onboarding survives across launches,
/// settings changes take effect on the next scan, and there's no need for an
/// in-memory cache in `AppState`.
public enum ProfileConfigStore {
    private enum Keys {
        static let profileType = "ksift.profile.type"
        static let customDirectories = "ksift.profile.customDirectories"
        static let customExclusions = "ksift.profile.customExclusions"
        static let minFileSize = "ksift.profile.minFileSize"
        static let enablePerceptual = "ksift.profile.enablePerceptual"
        static let enableBuildArtifacts = "ksift.profile.enableBuildArtifacts"
    }

    /// Reads the persisted config, falling back to `.default` for any
    /// missing/legacy keys. Safe to call on first launch.
    public static func load(defaults: UserDefaults = .standard) -> ProfileConfig {
        let type = defaults.string(forKey: Keys.profileType)
            .flatMap(ProfileType.init(rawValue:)) ?? ProfileType.developer
        let customDirs = defaults.stringArray(forKey: Keys.customDirectories) ?? []
        let customExcls = defaults.stringArray(forKey: Keys.customExclusions) ?? []
        let minSize = defaults.object(forKey: Keys.minFileSize) as? Int64 ?? 1024
        // Bool(forKey:) returns false for missing keys, so guard explicitly so
        // a never-set toggle defaults to true (matches ProfileConfig.default).
        let perceptual = defaults.object(forKey: Keys.enablePerceptual) as? Bool ?? true
        let buildArtifacts = defaults.object(forKey: Keys.enableBuildArtifacts) as? Bool ?? true
        return ProfileConfig(
            type: type,
            customDirectories: customDirs,
            exclusions: customExcls,
            minFileSize: minSize,
            enablePerceptualScan: perceptual,
            enableBuildArtifacts: buildArtifacts
        )
    }

    /// Persists every field. Idempotent — safe to call from didSet on every
    /// individual property change.
    public static func save(_ config: ProfileConfig, defaults: UserDefaults = .standard) {
        defaults.set(config.type.rawValue, forKey: Keys.profileType)
        defaults.set(config.customDirectories, forKey: Keys.customDirectories)
        defaults.set(config.exclusions, forKey: Keys.customExclusions)
        defaults.set(config.minFileSize, forKey: Keys.minFileSize)
        defaults.set(config.enablePerceptualScan, forKey: Keys.enablePerceptual)
        defaults.set(config.enableBuildArtifacts, forKey: Keys.enableBuildArtifacts)
    }
}