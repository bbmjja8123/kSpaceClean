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

    /// Result of the most recent ``confirmUninstall()`` call. `nil` until the
    /// user confirms; `nil` again whenever the safety check refuses to
    /// install (protected app). Published so the host view can drive the undo
    /// toast and a future error-surfacing path without re-invoking the mover.
    @Published internal(set) var lastUninstallResult: Result<UninstallRecord, TrashError>?

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
    /// The shared, app-wide ``TrashMover`` (C1). Injected from
    /// `AppServices` via ``AppDetailView`` so the audit log and history
    /// repository persist across calls — a per-call fresh mover would
    /// rebuild a fresh repository each time and orphan history records.
    private let mover: TrashMover

    /// True when the safety check passed and the app is not system-protected.
    var canUninstall: Bool {
        safetyCheck == .passed && !app.isProtected
    }

    // MARK: - Init

    init(app: InstalledApp, residueDetector: ResidueDetector, mover: TrashMover) {
        self.app = app
        self.residueDetector = residueDetector
        self.mover = mover
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

    /// Drives the confirmation → trash flow for the currently-described app.
    ///
    /// Returns `nil` when ``canUninstall`` is false (protected app or safety
    /// check not yet passed) — the host view's confirm button should already
    /// be hidden in that case, so a `nil` here means "we reached the call
    /// from a path the UI didn't gate correctly". Otherwise returns the
    /// ``TrashMover`` result verbatim and mirrors it onto
    /// ``lastUninstallResult`` so the view can react without re-running the
    /// mover.
    ///
    /// - Parameter includeResidues: When `true` (the recommended default),
    ///   the currently-scanned residue files are trashed alongside the app
    ///   bundle. When the user unchecks the residue toggle in
    ///   ``UninstallConfirmSheet`` (I1), the residues are filtered out so
    ///   the trash operation touches only the app bundle itself.
    func confirmUninstall(includeResidues: Bool = true) async -> Result<UninstallRecord, TrashError>? {
        guard canUninstall else { return nil }
        let residuesToDelete = includeResidues ? residues : []
        let result = await mover.moveToTrash(app: app, residues: residuesToDelete)
        lastUninstallResult = result
        return result
    }

    /// Looks up the stored history record for `id` through the shared mover.
    /// Used by ``AppDetailView.handleRestore()`` to resolve the undo toast's
    /// `recordID` into a full ``UninstallRecord`` before calling ``restore``.
    func historyRecord(id: UUID) async -> UninstallRecord? {
        await mover.historyRecord(id: id)
    }

    /// Restores a previously-uninstalled app through the shared mover. The
    /// result is returned verbatim so the host view can dismiss the undo
    /// toast on success or surface ``TrashError`` on failure (C2).
    func restore(record: UninstallRecord) async -> Result<URL, TrashError> {
        await mover.restore(record: record)
    }
}
