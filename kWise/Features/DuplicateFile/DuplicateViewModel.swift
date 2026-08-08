import Foundation
import SwiftUI

// MARK: - DuplicateViewModel

/// Main actor-bound view model that drives the duplicate file scanning UI.
///
/// Manages scan lifecycle, user selection state, and delegates cleanup to
/// ``TrashMover``.
@MainActor
public final class DuplicateViewModel: ObservableObject {
    // MARK: Published state

    /// Duplicate groups discovered during the scan.
    @Published public var groups: [DuplicateGroup] = []

    /// Whether a scan is currently running.
    @Published public var isScanning = false

    /// Progress fraction in [0.0, 1.0] reported by the scanner.
    @Published public var scanProgress: Double = 0

    /// Root paths to scan. Defaults to the user's home directory.
    @Published public var scanPaths: [URL] = [
        URL(fileURLWithPath: NSHomeDirectory())
    ]

    // MARK: Private state

    private let scanner = DuplicateScanner()
    private let mover = TrashMover()
    private var scanTask: Task<Void, Never>?

    // MARK: Lifecycle

    public init() {}

    deinit {
        scanTask?.cancel()
    }

    // MARK: Scanning

    /// Starts (or restarts) a full two-stage duplicate scan.
    ///
    /// Automatically cancels any in-flight scan, clears previous results, and
    /// selects all but the newest file in every group found.
    public func startScan() {
        scanTask?.cancel()
        groups = []
        isScanning = true
        scanProgress = 0

        scanTask = Task { [weak self] in
            guard let self else { return }

            // Create a boxed continuation so we can pass it to the scanner.
            final class Box {
                var continuation: AsyncStream<Double>.Continuation?
            }
            let box = Box()
            let progressStream = AsyncStream<Double> { continuation in
                box.continuation = continuation
            }

            guard let progressContinuation = box.continuation else { return }

            // Kick off the scanner
            let resultStream = scanner.scan(
                paths: scanPaths,
                progress: progressContinuation
            )

            // Observe progress on a detached child so we don't block the stream.
            let progressTask = Task { [weak self] in
                for await value in progressStream {
                    await MainActor.run { [weak self] in
                        self?.scanProgress = value
                    }
                }
            }

            // Collect duplicate groups as they arrive.
            for await group in resultStream {
                if Task.isCancelled { break }
                // Auto-select all files except the newest one.
                let autoSelected = autoSelectDuplicates(in: group)
                await MainActor.run { [weak self] in
                    self?.groups.append(autoSelected)
                }
            }

            progressTask.cancel()

            if !Task.isCancelled {
                await MainActor.run { [weak self] in
                    self?.isScanning = false
                    self?.scanProgress = 1.0
                }
            }
        }
    }

    /// Cancels the current scan if one is running.
    public func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    // MARK: Computed properties

    /// Total wasted space across all groups.
    public var totalWasted: Int64 {
        groups.reduce(0) { $0 + $1.totalWasted }
    }

    /// Number of files currently selected for removal.
    public var selectedCount: Int {
        groups.reduce(0) { $0 + $1.files.filter(\.isSelected).count }
    }

    /// Total size of all selected files.
    public var selectedSize: Int64 {
        groups.reduce(0) { $0 + $1.files.filter(\.isSelected).reduce(0) { $0 + $1.size } }
    }

    // MARK: Selection

    /// Toggles the selection state of a single file.
    public func toggleFile(_ id: UUID) {
        for gi in groups.indices {
            for fi in groups[gi].files.indices where groups[gi].files[fi].id == id {
                groups[gi].files[fi].isSelected.toggle()
                return
            }
        }
    }

    /// Toggles the selection state of every file in a group.
    public func toggleGroup(_ id: UUID) {
        guard let gi = groups.firstIndex(where: { $0.id == id }) else { return }
        let allSelected = groups[gi].files.allSatisfy(\.isSelected)
        for fi in groups[gi].files.indices {
            groups[gi].files[fi].isSelected = !allSelected
        }
    }

    /// Selects every file in every group (all duplicates selected).
    public func selectAllDuplicates() {
        for gi in groups.indices {
            for fi in groups[gi].files.indices {
                groups[gi].files[fi].isSelected = true
            }
        }
    }

    /// Deselects every file in every group.
    public func deselectAll() {
        for gi in groups.indices {
            for fi in groups[gi].files.indices {
                groups[gi].files[fi].isSelected = false
            }
        }
    }

    /// Toggles the expanded/collapsed state of a group.
    public func toggleExpanded(_ id: UUID) {
        guard let gi = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[gi].isExpanded.toggle()
    }

    // MARK: Cleanup

    /// Moves all currently-selected duplicate files to the Trash.
    ///
    /// - Throws: Errors from ``TrashMover`` if any file cannot be trashed.
    public func cleanupSelected() async throws {
        let urls = groups
            .flatMap(\.files)
            .filter(\.isSelected)
            .map(\.url)

        guard !urls.isEmpty else { return }

        let result = await mover.moveToTrash(urls: urls)

        // Remove successfully-trashed files from their groups.
        let trashedPaths = Set(result.snapshots.map(\.originalPath))
        for gi in groups.indices.reversed() {
            groups[gi].files.removeAll { trashedPaths.contains($0.path) }
        }
        // Remove empty groups.
        groups.removeAll { $0.files.isEmpty }

        // If any files failed, we could surface them, but for now just throw the first error.
        if let firstFailure = result.failed.first {
            throw TrashMover.MoveError.trashFailed(firstFailure.0, firstFailure.1)
        }
    }

    // MARK: Helpers

    /// Returns a copy of `group` with every file selected **except** the one
    /// with the most recent modification date.
    private func autoSelectDuplicates(in group: DuplicateGroup) -> DuplicateGroup {
        var updated = group
        // Find the newest file so we keep it as the "original".
        guard let newest = updated.files.max(by: { $0.modificationDate < $1.modificationDate }) else {
            return updated
        }
        for fi in updated.files.indices {
            updated.files[fi].isSelected = updated.files[fi].id != newest.id
        }
        return updated
    }
}

// MARK: - TrashMover.MoveError conformance

extension TrashMover.MoveError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found: \(url.lastPathComponent)"
        case .snapshotFailed(let url):
            return "Failed to record trash snapshot for: \(url.lastPathComponent)"
        case .trashFailed(let url, let underlying):
            return "Failed to move \"\(url.lastPathComponent)\" to Trash: \(underlying.localizedDescription)"
        }
    }
}
