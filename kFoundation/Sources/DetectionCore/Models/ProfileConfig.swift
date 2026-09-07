import Foundation

public enum ProfileType: String, Sendable, CaseIterable, Codable {
    case developer
    case photographer
    case designer
    /// No preset directories — only `customDirectories` are scanned.
    case custom

    public var title: String {
        switch self {
        case .developer: return NSLocalizedString("Developer", comment: "Profile name")
        case .photographer: return NSLocalizedString("Photographer", comment: "Profile name")
        case .designer: return NSLocalizedString("Designer", comment: "Profile name")
        case .custom: return NSLocalizedString("Custom", comment: "Profile name")
        }
    }

    public var scanningDirectories: [String] {
        switch self {
        case .developer:
            return ["~/Projects", "~/Desktop", "~/Downloads", "~/Documents", "~/.gradle", "~/.m2"]
        case .photographer:
            return ["~/Pictures", "~/Desktop", "~/Downloads", "~/Documents"]
        case .designer:
            return ["~/Desktop", "~/Downloads", "~/Documents"]
        case .custom:
            return []
        }
    }

    public var additionalExclusions: [String] {
        switch self {
        case .developer:
            return ["**/node_modules/**", "**/Pods/**", "**/.build/**", "**/DerivedData/**"]
        case .photographer:
            return []
        case .designer:
            return []
        case .custom:
            return []
        }
    }
}

public struct ProfileConfig: Sendable, Codable, Equatable {
    public var type: ProfileType
    public var customDirectories: [String]
    public var exclusions: [String]
    public var minFileSize: Int64
    public var enablePerceptualScan: Bool
    public var enableBuildArtifacts: Bool
    /// Strategy the "Auto Keep" affordances apply when picking the copy to
    /// keep. Added after v1.2; older payloads decode to `.keepNewest`.
    public var selectionStrategy: SelectionStrategy
    /// How aggressively similar images are grouped. Added after v1.2;
    /// older payloads decode to `.normal` (the historical engine default).
    public var similarityPreset: SimilarityPreset
    /// Files at or above this size surface in the Large Files section.
    public var largeFileSizeThreshold: Int64

    public static let `default` = ProfileConfig(
        type: .developer,
        customDirectories: [],
        exclusions: ProfileType.developer.additionalExclusions,
        minFileSize: 1024,
        enablePerceptualScan: true,
        enableBuildArtifacts: true,
        selectionStrategy: .keepNewest,
        similarityPreset: .normal,
        largeFileSizeThreshold: 100 * 1024 * 1024
    )

    public init(type: ProfileType, customDirectories: [String], exclusions: [String],
                minFileSize: Int64, enablePerceptualScan: Bool,
                enableBuildArtifacts: Bool = true,
                selectionStrategy: SelectionStrategy = .keepNewest,
                similarityPreset: SimilarityPreset = .normal,
                largeFileSizeThreshold: Int64 = 100 * 1024 * 1024) {
        self.type = type
        self.customDirectories = customDirectories
        self.exclusions = exclusions
        self.minFileSize = minFileSize
        self.enablePerceptualScan = enablePerceptualScan
        self.enableBuildArtifacts = enableBuildArtifacts
        self.selectionStrategy = selectionStrategy
        self.similarityPreset = similarityPreset
        self.largeFileSizeThreshold = largeFileSizeThreshold
    }

    // Forward/backward compat: tolerate older serialized JSON missing newer
    // fields. `enableBuildArtifacts` was added after v0; older payloads still
    // decode by defaulting it to true (matches the prior behavior of always
    // running the build-artifact detector). `selectionStrategy` was added
    // after v1.2 and decodes to the historical `.keepNewest` behavior.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try c.decodeIfPresent(ProfileType.self, forKey: .type) ?? .developer
        self.customDirectories = try c.decodeIfPresent([String].self, forKey: .customDirectories) ?? []
        self.exclusions = try c.decodeIfPresent([String].self, forKey: .exclusions) ?? []
        self.minFileSize = try c.decodeIfPresent(Int64.self, forKey: .minFileSize) ?? 1024
        self.enablePerceptualScan = try c.decodeIfPresent(Bool.self, forKey: .enablePerceptualScan) ?? true
        self.enableBuildArtifacts = try c.decodeIfPresent(Bool.self, forKey: .enableBuildArtifacts) ?? true
        self.selectionStrategy = try c.decodeIfPresent(SelectionStrategy.self, forKey: .selectionStrategy) ?? .keepNewest
        self.similarityPreset = try c.decodeIfPresent(SimilarityPreset.self, forKey: .similarityPreset) ?? .normal
        self.largeFileSizeThreshold = try c.decodeIfPresent(Int64.self, forKey: .largeFileSizeThreshold) ?? 100 * 1024 * 1024
    }
}