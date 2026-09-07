import Foundation

/// Presets for how aggressively the perceptual detector groups similar
/// images. Directly answers the #1 category complaint (over-grouped
/// "similar" photos) by making the sensitivity a user choice instead of
/// a hardcoded engine constant.
public enum SimilarityPreset: String, CaseIterable, Sendable, Codable {
    /// Near-identical frames only — fewest false positives.
    case strict
    /// The historical engine default (hamming ≤ 10, vision ≤ 0.6).
    case normal
    /// Catches same-scene shots; more groups, more false positives.
    case loose

    public var maximumHammingDistance: Int {
        switch self {
        case .strict: return 4
        case .normal: return 10
        case .loose: return 18
        }
    }

    public var visionDistanceThreshold: Float {
        switch self {
        case .strict: return 0.35
        case .normal: return 0.6
        case .loose: return 0.85
        }
    }

    public var title: String {
        switch self {
        case .strict: return NSLocalizedString("Strict", comment: "Similarity preset title")
        case .normal: return NSLocalizedString("Normal", comment: "Similarity preset title")
        case .loose: return NSLocalizedString("Loose", comment: "Similarity preset title")
        }
    }

    public var help: String {
        switch self {
        case .strict:
            return NSLocalizedString("Groups only near-identical images — fewest false positives.", comment: "Similarity preset help")
        case .normal:
            return NSLocalizedString("Balanced matching — the recommended default.", comment: "Similarity preset help")
        case .loose:
            return NSLocalizedString("Groups same-scene shots too — more results, more noise.", comment: "Similarity preset help")
        }
    }
}
