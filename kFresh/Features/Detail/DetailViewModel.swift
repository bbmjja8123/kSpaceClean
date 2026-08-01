import Foundation
import SwiftUI

/// Backing state for the app-detail pane: the 5-step safety check, the
/// residue scan lifecycle, and the uninstall eligibility decision.
///
/// Owned by ``AppDetailView`` as a `@StateObject`. Every mutation runs on the
/// main actor so the `@Published` projections can drive SwiftUI directly.
@MainActor
final class DetailViewModel: ObservableObject {
    // MARK: - Nested types

    enum SafetyCheck: Equatable {
        case pending
        case passed
        case blocked(reason: String)
    }

    // MARK: - Published state

    /// The app this pane describes. Immutable after init.
    @Published internal(set) var app: InstalledApp
    @Published internal(set) var safetyCheck: SafetyCheck = .pending
    @Published internal(set) var isResidueScanRunning: Bool = false

    /// Backing store for `residues`. Wrapping the published property keeps
    /// the "always sorted by confidence descending" invariant on every write
    /// path — including test seeding — instead of only in `rescanResidues`.
    @Published private var residueStore: [ResidueFile] = []

    /// Residue files found by the last scan, always sorted by confidence
    /// descending.
    var residues: [ResidueFile] {
        get { residueStore }
        set { residueStore = newValue.sorted { $0.confidence > $1.confidence } }
    }

    // MARK: - Dependencies

    private let residueDetector: ResidueDetector

    /// True when the safety check passed and the app is not system-protected.
    var canUninstall: Bool {
        safetyCheck == .passed && !app.isProtected
    }

    // MARK: - Init

    init(app: InstalledApp, residueDetector: ResidueDetector) {
        self.app = app
        self.residueDetector = residueDetector
    }

    // MARK: - Actions

    /// Runs the safety check: protected apps are blocked up front; everything
    /// else passes and immediately triggers a residue prescan.
    func performSafetyCheck() async {
        guard !app.isProtected else {
            safetyCheck = .blocked(reason: app.protectionReason ?? "系统组件不可卸载")
            return
        }
        safetyCheck = .passed
        await rescanResidues()
    }

    /// Manually re-runs the residue scan, replacing `residues`.
    func rescanResidues() async {
        isResidueScanRunning = true
        defer { isResidueScanRunning = false }
        let detected = await residueDetector.detectResidues(
            bundleID: app.bundleID,
            appName: app.displayName,
            appURL: app.url
        )
        residues = detected.sorted { $0.confidence > $1.confidence }
    }
}
