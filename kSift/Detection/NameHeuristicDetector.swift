import Foundation

/// Detects files that share the same base name (stem + extension) across
/// distinct folders, with macOS-style "(1)", "(2)" duplicate suffixes
/// normalized. Catches the common "I re-downloaded this and the browser
/// renamed the local copy" case where the user wants to consolidate
/// duplicates that perceptual hashing won't pair (different sizes due to
/// re-encoding) and byte hashing won't pair (genuinely different bytes),
/// but the filenames strongly suggest the same logical file.
///
/// Examples that get grouped together:
///   /Downloads/IMG_1234.jpg
///   /Downloads/IMG_1234 (1).jpg
///   /Pictures/Holiday/IMG_1234.jpg
public actor NameHeuristicDetector {
    /// Minimum number of files sharing a stem before we report them as a
    /// duplicate group. Two is enough to be actionable (user can pick
    /// one to delete); three+ is much rarer so the bar stays low.
    private let minimumGroupSize: Int

    public init(minimumGroupSize: Int = 2) {
        self.minimumGroupSize = max(2, minimumGroupSize)
    }

    public func detect(files: [FileItem], controller: ScanController) async -> [DuplicateGroup] {
        var byStem: [String: [FileItem]] = [:]
        for file in files {
            guard !isCancelled(controller) else { return [] }
            let stem = normalizedStem(for: file.url.lastPathComponent)
            guard !stem.isEmpty else { continue }
            byStem[stem, default: []].append(file)
        }

        var groups: [DuplicateGroup] = []
        for (stem, candidates) in byStem where candidates.count >= minimumGroupSize {
            guard !isCancelled(controller) else { return groups }
            // Two files with the same stem living in the same directory is
            // usually a real (byte-level) duplicate that other detectors
            // will already catch. Only report cross-directory matches so
            // we don't shadow the byte detector with noisier groupings.
            let distinctDirectories = Set(candidates.map { $0.url.deletingLastPathComponent().standardizedFileURL.path })
            guard distinctDirectories.count >= 2 else { continue }
            guard distinctDirectories.count == candidates.count else { continue }

            let sorted = candidates.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
            let totalSize = sorted.reduce(Int64(0)) { $0 + $1.size }
            let reclaimable = sorted.dropFirst().reduce(Int64(0)) { $0 + $1.size }

            groups.append(DuplicateGroup(
                id: UUID(),
                category: .nameHeuristic,
                totalSize: reclaimable,
                fileCount: sorted.count,
                files: sorted,
                categoryEvidence: .nameHeuristic(stem: stem, variantCount: sorted.count)
            ))
        }

        return groups.sorted { $0.totalSize > $1.totalSize }
    }

    /// Strips macOS's " (N)" duplicate suffix from a filename and
    /// returns the lowercase stem. "IMG_1234 (1).jpg" → "img_1234",
    /// "DSC_0001.heic" → "dsc_0001".
    ///
    /// Lowercased so case-only variants (e.g. "Report.pdf" and
    /// "report.pdf" on different filesystems) still pair.
    static func normalizedStem(for filename: String) -> String {
        let stripped = filename.replacingOccurrences(
            of: #" \(\d+\)$"#,
            with: "",
            options: .regularExpression
        )
        return (stripped as NSString).deletingPathExtension.lowercased()
    }

    private func isCancelled(_ controller: ScanController) -> Bool {
        controller.isCancelled || Task.isCancelled
    }
}