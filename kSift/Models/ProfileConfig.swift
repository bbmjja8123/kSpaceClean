import Foundation

public enum ProfileType: String, Sendable, CaseIterable, Codable {
    case developer
    case photographer
    case designer

    public var title: String {
        switch self {
        case .developer: return NSLocalizedString("Developer", comment: "Profile name")
        case .photographer: return NSLocalizedString("Photographer", comment: "Profile name")
        case .designer: return NSLocalizedString("Designer", comment: "Profile name")
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

    public static let `default` = ProfileConfig(
        type: .developer,
        customDirectories: [],
        exclusions: ProfileType.developer.additionalExclusions,
        minFileSize: 1024,
        enablePerceptualScan: true,
        enableBuildArtifacts: true
    )

    public init(type: ProfileType, customDirectories: [String], exclusions: [String],
                minFileSize: Int64, enablePerceptualScan: Bool,
                enableBuildArtifacts: Bool = true) {
        self.type = type
        self.customDirectories = customDirectories
        self.exclusions = exclusions
        self.minFileSize = minFileSize
        self.enablePerceptualScan = enablePerceptualScan
        self.enableBuildArtifacts = enableBuildArtifacts
    }

    // Forward/backward compat: tolerate older serialized JSON missing newer
    // fields. `enableBuildArtifacts` was added after v0; older payloads still
    // decode by defaulting it to true (matches the prior behavior of always
    // running the build-artifact detector).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try c.decodeIfPresent(ProfileType.self, forKey: .type) ?? .developer
        self.customDirectories = try c.decodeIfPresent([String].self, forKey: .customDirectories) ?? []
        self.exclusions = try c.decodeIfPresent([String].self, forKey: .exclusions) ?? []
        self.minFileSize = try c.decodeIfPresent(Int64.self, forKey: .minFileSize) ?? 1024
        self.enablePerceptualScan = try c.decodeIfPresent(Bool.self, forKey: .enablePerceptualScan) ?? true
        self.enableBuildArtifacts = try c.decodeIfPresent(Bool.self, forKey: .enableBuildArtifacts) ?? true
    }
}