import SwiftUI
import DesignSystem

/// Immutable outcome of a pre-scan range estimate.
struct ScanEstimate: Sendable, Equatable {
    /// Number of roots that actually exist on disk, i.e. what the scan will walk.
    var directoryCount: Int
    var fileCount: Int
    var totalBytes: Int64
    /// True when enumeration stopped at `ScanEstimator.fileCountLimit`, so
    /// `fileCount` / `totalBytes` are lower bounds rather than exact figures.
    var isTruncated: Bool

    static let empty = ScanEstimate(directoryCount: 0, fileCount: 0, totalBytes: 0, isTruncated: false)
}

/// Lightweight pre-scan estimator: walks the configured roots counting files
/// and summing sizes, without hashing or reading any content.
///
/// Runs on its own actor executor so a large home directory never blocks the
/// main thread, and bails out at `fileCountLimit` so the idle screen stays
/// responsive no matter how big the target is.
actor ScanEstimator {
    /// Shared instance — the estimator is stateless, so one is enough.
    static let shared = ScanEstimator()

    /// Enumeration stops here; beyond this the UI shows a "50k+" lower bound.
    /// The exact total is not worth the I/O when the point is a rough preview.
    static let fileCountLimit = 50_000

    /// How often to check for cancellation / yield. Checking every file would
    /// cost more than the enumeration itself.
    private static let checkInterval = 256

    /// Expands `~`, standardizes, de-duplicates, and drops roots that are not
    /// existing directories, so the folder count reflects what will really be
    /// scanned rather than what happens to be configured.
    static func resolvedRoots(from directories: [String]) -> [URL] {
        var seen = Set<String>()
        var roots: [URL] = []
        for dir in directories {
            let path = ((dir as NSString).expandingTildeInPath as NSString).standardizingPath
            guard !seen.contains(path) else { continue }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            seen.insert(path)
            roots.append(URL(fileURLWithPath: path))
        }
        return roots
    }

    /// Estimates the scan range for `directories`. Honors task cancellation, so
    /// callers can drop a stale estimate as soon as the directory set changes.
    func estimate(directories: [String]) async -> ScanEstimate {
        let roots = Self.resolvedRoots(from: directories)
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        let keySet = Set(keys)

        var fileCount = 0
        var totalBytes: Int64 = 0
        var isTruncated = false
        var stepsSinceCheck = 0

        walk: for root in roots {
            if Task.isCancelled { break }
            // errorHandler returns true so an unreadable subtree (no Full Disk
            // Access yet, dangling symlink) skips ahead instead of aborting the
            // whole estimate.
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                stepsSinceCheck += 1
                if stepsSinceCheck >= Self.checkInterval {
                    stepsSinceCheck = 0
                    if Task.isCancelled { break walk }
                    // Give the executor a breath so a huge tree cannot starve
                    // other work queued on this actor.
                    await Task.yield()
                }

                guard let values = try? url.resourceValues(forKeys: keySet),
                      values.isRegularFile == true else { continue }

                fileCount += 1
                totalBytes += Int64(values.fileSize ?? 0)

                if fileCount >= Self.fileCountLimit {
                    isTruncated = true
                    break walk
                }
            }
        }

        return ScanEstimate(
            directoryCount: roots.count,
            fileCount: fileCount,
            totalBytes: totalBytes,
            isTruncated: isTruncated
        )
    }
}

/// Idle-screen preview answering "what am I about to scan?" before the user
/// commits to a scan.
struct ScanRangePreview: View {
    let directories: [String]

    @State private var estimate: ScanEstimate?
    @State private var estimateTask: Task<Void, Never>?

    var body: some View {
        GlassPanel {
            content
                .padding(AppSpacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: 600)
        .onAppear { restartEstimate() }
        .onChange(of: directories) { _ in restartEstimate() }
        .onDisappear {
            estimateTask?.cancel()
            estimateTask = nil
        }
    }

    @ViewBuilder
    private var content: some View {
        if let estimate = estimate, estimate.directoryCount == 0 {
            // Nothing resolvable on disk — guide the user to pick a target
            // instead of showing a meaningless "0 folders" line. Height is
            // pinned because EmptyStateView is greedy by design.
            EmptyStateView(
                icon: "folder.badge.questionmark",
                title: NSLocalizedString("No folders to scan", comment: "Scan range preview, nothing configured"),
                subtitle: NSLocalizedString(
                    "Drop a folder here, or choose directories in Settings.",
                    comment: "Scan range preview empty guidance"
                )
            )
            .frame(height: 140)
        } else {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Label("Scan range", systemImage: "folder")
                    .font(AppFont.title3)
                    .foregroundColor(.textPrimary)

                if let estimate = estimate {
                    Text(summary(for: estimate))
                        .font(AppFont.callout)
                        .foregroundColor(.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: AppSpacing.sm) {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                        Text("Estimating scan range…")
                            .font(AppFont.callout)
                            .foregroundColor(.textSecondary)
                    }
                }
            }
        }
    }

    /// Cancels any in-flight estimate and starts a fresh one. Called on appear
    /// and whenever the directory set changes, so the preview never shows a
    /// result for a stale configuration.
    ///
    /// `@MainActor` is load-bearing: it makes the spawned `Task` inherit main
    /// isolation, so the `@State` write below happens on the main thread. The
    /// walk itself still runs off-main inside `ScanEstimator`.
    @MainActor
    private func restartEstimate() {
        estimateTask?.cancel()
        estimate = nil
        let dirs = directories
        estimateTask = Task {
            let result = await ScanEstimator.shared.estimate(directories: dirs)
            guard !Task.isCancelled else { return }
            estimate = result
        }
    }

    /// Builds "Will scan 2 folders · about 1,234 files · about 5.2 GB".
    private func summary(for estimate: ScanEstimate) -> String {
        var parts: [String] = [
            String(
                format: NSLocalizedString("%lld folder(s)", comment: "Scan range preview, folder count"),
                estimate.directoryCount
            )
        ]

        if estimate.fileCount == 0 {
            // Folders exist but hold nothing scannable — say so rather than
            // printing "about 0 files · Zero KB".
            parts.append(NSLocalizedString("no files to scan", comment: "Scan range preview, empty folders"))
        } else if estimate.isTruncated {
            parts.append(NSLocalizedString("50k+ files", comment: "Scan range preview, truncated file count"))
            parts.append(String(
                format: NSLocalizedString("over %@", comment: "Scan range preview, truncated size lower bound"),
                formatBytes(estimate.totalBytes)
            ))
        } else {
            parts.append(String(
                format: NSLocalizedString("about %@ files", comment: "Scan range preview, estimated file count"),
                formatCount(estimate.fileCount)
            ))
            parts.append(String(
                format: NSLocalizedString("about %@", comment: "Scan range preview, estimated total size"),
                formatBytes(estimate.totalBytes)
            ))
        }

        return String(
            format: NSLocalizedString("Will scan %@", comment: "Scan range preview summary line"),
            parts.joined(separator: " · ")
        )
    }

    private func formatCount(_ count: Int) -> String {
        // Built per call rather than cached: NumberFormatter is not Sendable,
        // and this runs only when an estimate lands.
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
