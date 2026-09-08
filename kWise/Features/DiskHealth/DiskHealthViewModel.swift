import Foundation
import Combine

/// View-model backing `DiskHealthCard` and `DiskHealthDetailView`.
///
/// Owns both ``SMARTReader`` and ``VolumeDiagnostics`` and synthesizes the
/// health grade used by the small card on the home screen.
///
/// Health grade rules (deliberately simple — Phase D scope):
/// * SMART `.failing`              → `.danger` (red badge)
/// * SMART `.verified` + volume OK → `.good`   (green badge)
/// * SMART `.unknown` / `.notSupported` → `.unknown` (grey badge) — Apple
///   Silicon without FDA falls here by design (graceful degradation).
///
/// - SeeAlso: `docs/superpowers/plans/2026-08-09-kwise-v1.5-plan.md` Task 11
@MainActor
public final class DiskHealthViewModel: ObservableObject {
    public enum HealthGrade: String, Sendable {
        case good
        case caution
        case danger
        case unknown

        public var friendlyTitle: String {
            switch self {
            case .good:    return "健康"
            case .caution: return "注意"
            case .danger:  return "异常"
            case .unknown: return "未知"
            }
        }
    }

    @Published public private(set) var grade: HealthGrade = .unknown
    @Published public private(set) var volume: VolumeSnapshot = .empty
    @Published public private(set) var smart: SMARTReport = .unavailable
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastRefreshedAt: Date?

    private let smartReader: SMARTReader
    private let volumeReader: VolumeDiagnostics

    public init(smartReader: SMARTReader = SMARTReader(),
                volumeReader: VolumeDiagnostics = VolumeDiagnostics()) {
        self.smartReader = smartReader
        self.volumeReader = volumeReader
    }

    /// Refresh both readers in parallel; recompute the grade when done.
    public func refresh() async {
        isLoading = true
        defer { isLoading = false }
        async let smartRefresh: Void = smartReader.refresh()
        async let volumeRefresh: Void = volumeReader.refresh()
        _ = await (smartRefresh, volumeRefresh)
        smart = smartReader.report
        volume = volumeReader.snapshot
        grade = Self.deriveGrade(smart: smart, volume: volume)
        lastRefreshedAt = Date()
    }

    /// Static for testability.
    static func deriveGrade(smart: SMARTReport, volume: VolumeSnapshot) -> HealthGrade {
        switch smart.status {
        case .failing:           return .danger
        case .notSupported,
             .unknown:           return .unknown
        case .verified:          break
        }
        // SMART OK — check volume pressure (≥95% used is a caution signal).
        guard let total = volume.totalBytes, total > 0,
              let free  = volume.freeBytes else { return .good }
        let usedRatio = Double(total - free) / Double(total)
        if usedRatio >= 0.95 { return .caution }
        return .good
    }
}