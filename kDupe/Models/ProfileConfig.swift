import Foundation

public enum ProfileType: String, Sendable, CaseIterable, Codable {
    case developer
    case photographer
    case simple

    public var title: String {
        switch self {
        case .developer: return "Developer"
        case .photographer: return "Photographer"
        case .simple: return "Simple"
        }
    }

    public var scanningDirectories: [String] {
        switch self {
        case .developer:
            return ["~/Projects", "~/Desktop", "~/Downloads", "~/Documents", "~/.gradle", "~/.m2"]
        case .photographer:
            return ["~/Pictures", "~/Desktop", "~/Downloads", "~/Documents"]
        case .simple:
            return ["~/Desktop", "~/Downloads", "~/Documents"]
        }
    }

    public var additionalExclusions: [String] {
        switch self {
        case .developer:
            return ["**/node_modules/**", "**/Pods/**", "**/.build/**", "**/DerivedData/**"]
        case .photographer:
            return []
        case .simple:
            return []
        }
    }
}

public struct ProfileConfig: Sendable, Codable {
    public var type: ProfileType
    public var customDirectories: [String]
    public var exclusions: [String]
    public var minFileSize: Int64
    public var enablePerceptualScan: Bool

    public static let `default` = ProfileConfig(
        type: .developer,
        customDirectories: [],
        exclusions: ProfileType.developer.additionalExclusions,
        minFileSize: 1024,
        enablePerceptualScan: true
    )

    public init(type: ProfileType, customDirectories: [String], exclusions: [String],
                minFileSize: Int64, enablePerceptualScan: Bool) {
        self.type = type
        self.customDirectories = customDirectories
        self.exclusions = exclusions
        self.minFileSize = minFileSize
        self.enablePerceptualScan = enablePerceptualScan
    }
}
