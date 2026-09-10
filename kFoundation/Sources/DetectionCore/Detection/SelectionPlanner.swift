import Foundation

/// Strategies for choosing which copy of a duplicate group to keep.
///
/// Selection is explainable: every plan pairs each file with a
/// `SelectionReason` so the UI can show *why* a copy was chosen for
/// keeping (or removing) — the "explainable Smart Select" differentiator
/// none of the category competitors offer.
public enum SelectionStrategy: String, CaseIterable, Sendable, Codable {
    /// Keep the most recently modified copy (the classic default).
    case keepNewest
    /// Keep the oldest copy — right when earlier exports are the
    /// originals and later ones are re-downloads / re-encodes.
    case keepOldest
    /// Keep the copy with the fewest path components — usually the
    /// "canonical" location (e.g. `~/Pictures/a.jpg` over
    /// `~/Downloads/export (1)/a.jpg`).
    case keepShortestPath
    /// Prefer a copy that lives inside one of the scan roots (e.g. keep
    /// the file in `~/Projects` over one in `~/Downloads`).
    case keepInsideScanRoot
    /// Keep the copy with the highest pixel resolution — for photo groups
    /// where the biggest FILE is not always the best-looking image.
    case keepHighestResolution
    /// For directory duplicates: keep the copy in the lexicographically
    /// first sibling folder so the canonical directory survives.
    case keepDirectoryCanonical

    public var title: String {
        switch self {
        case .keepNewest:
            return NSLocalizedString("Keep Newest", comment: "Selection strategy title")
        case .keepOldest:
            return NSLocalizedString("Keep Oldest", comment: "Selection strategy title")
        case .keepShortestPath:
            return NSLocalizedString("Keep Shortest Path", comment: "Selection strategy title")
        case .keepInsideScanRoot:
            return NSLocalizedString("Keep Inside Scan Folder", comment: "Selection strategy title")
        case .keepDirectoryCanonical:
            return NSLocalizedString("Keep Canonical Folder", comment: "Selection strategy title")
        case .keepHighestResolution:
            return NSLocalizedString("Keep Highest Resolution", comment: "Selection strategy title")
        }
    }

    public var help: String {
        switch self {
        case .keepNewest:
            return NSLocalizedString("Keeps the most recently modified copy and marks the rest for removal.", comment: "Selection strategy help")
        case .keepOldest:
            return NSLocalizedString("Keeps the oldest copy — useful when later files are re-downloads or re-encodes.", comment: "Selection strategy help")
        case .keepShortestPath:
            return NSLocalizedString("Keeps the copy closest to the volume root, typically the canonical location.", comment: "Selection strategy help")
        case .keepInsideScanRoot:
            return NSLocalizedString("Prefers the copy inside the scanned folder, removing stray copies elsewhere.", comment: "Selection strategy help")
        case .keepDirectoryCanonical:
            return NSLocalizedString("Keeps copies in the alphabetically first folder so the canonical directory survives.", comment: "Selection strategy help")
        case .keepHighestResolution:
            return NSLocalizedString("Keeps the copy with the highest pixel resolution.", comment: "Selection strategy help")
        }
    }
}

/// Why a file was placed in a plan's keep or remove set. Shown as a badge
/// line in the group detail view so the automatic choice is auditable.
public enum SelectionReason: String, Sendable, Equatable, Codable {
    case newestCopy
    case oldestCopy
    case shortestPath
    case insideScanRoot
    case canonicalFolder
    case onlyFile
    case duplicateOfKept
    case highestResolution

    public var explanation: String {
        switch self {
        case .newestCopy:
            return NSLocalizedString("Kept — most recently modified copy", comment: "Selection reason explanation")
        case .oldestCopy:
            return NSLocalizedString("Kept — oldest copy (original)", comment: "Selection reason explanation")
        case .shortestPath:
            return NSLocalizedString("Kept — shortest path (canonical location)", comment: "Selection reason explanation")
        case .insideScanRoot:
            return NSLocalizedString("Kept — inside the scanned folder", comment: "Selection reason explanation")
        case .canonicalFolder:
            return NSLocalizedString("Kept — canonical folder copy", comment: "Selection reason explanation")
        case .onlyFile:
            return NSLocalizedString("Kept — the only copy in this group", comment: "Selection reason explanation")
        case .duplicateOfKept:
            return NSLocalizedString("Marked for removal — duplicate of the kept copy", comment: "Selection reason explanation")
        case .highestResolution:
            return NSLocalizedString("Kept — highest resolution", comment: "Selection reason explanation")
        }
    }
}

/// The outcome of running a `SelectionStrategy` against one group.
/// `reasons` covers *every* file in the group: the kept copy explains why
/// it won, removed copies explain that they duplicate the kept one.
public struct SelectionPlan: Sendable, Equatable {
    public let keep: FileItem?
    public let remove: [FileItem]
    public let reasons: [UUID: SelectionReason]

    public init(keep: FileItem?, remove: [FileItem], reasons: [UUID: SelectionReason]) {
        self.keep = keep
        self.remove = remove
        self.reasons = reasons
    }

    // FileItem is not Equatable (URL resource metadata would be expensive
    // to compare); plans are compared by identity instead.
    public static func == (lhs: SelectionPlan, rhs: SelectionPlan) -> Bool {
        lhs.keep?.id == rhs.keep?.id
            && lhs.remove.map(\.id) == rhs.remove.map(\.id)
            && lhs.reasons == rhs.reasons
    }
}

/// Pure, testable planner behind the "Auto Keep" affordances. Deliberately
/// side-effect free: the view model owns applying a plan to selections.
public enum SelectionPlanner {
    /// Produces the keep/remove split for `group` under `strategy`.
    ///
    /// - Deterministic: ties break on localized path order, so identical
    ///   input always yields an identical plan.
    /// - `scanRoots` only matters for `.keepInsideScanRoot`; other
    ///   strategies ignore it.
    public static func plan(
        for group: DuplicateGroup,
        strategy: SelectionStrategy,
        scanRoots: [URL] = []
    ) -> SelectionPlan {
        let files = group.files
        guard let first = files.first else {
            return SelectionPlan(keep: nil, remove: [], reasons: [:])
        }
        guard files.count > 1 else {
            return SelectionPlan(
                keep: first,
                remove: [],
                reasons: [first.id: .onlyFile]
            )
        }

        let keep: FileItem
        var reasons: [UUID: SelectionReason] = [:]

        switch strategy {
        case .keepNewest:
            keep = pick(files, primary: { $0.modificationDate }, descending: true)
            reasons[keep.id] = .newestCopy
        case .keepOldest:
            keep = pick(files, primary: { $0.modificationDate }, descending: false)
            reasons[keep.id] = .oldestCopy
        case .keepShortestPath:
            keep = pick(files, primary: { $0.url.pathComponents.count }, descending: false)
            reasons[keep.id] = .shortestPath
        case .keepHighestResolution:
            keep = pick(files, primary: { $0.pixelWidth * $0.pixelHeight }, descending: true)
            reasons[keep.id] = .highestResolution
        case .keepInsideScanRoot:
            if let inside = pickInsideScanRoot(files, scanRoots: scanRoots) {
                keep = inside
                reasons[keep.id] = .insideScanRoot
            } else {
                // No copy sits inside a scan root — fall back to the newest
                // copy so the strategy always yields a usable plan.
                keep = pick(files, primary: { $0.modificationDate }, descending: true)
                reasons[keep.id] = .newestCopy
            }
        case .keepDirectoryCanonical:
            // Keep the copy whose parent folder sorts first; copies sharing
            // that folder fall through to `pick`'s path tie-break.
            keep = pick(
                files,
                primary: { $0.url.deletingLastPathComponent().path },
                descending: false
            )
            reasons[keep.id] = .canonicalFolder
        }

        for file in files where file.id != keep.id {
            reasons[file.id] = .duplicateOfKept
        }

        let remove = files.filter { $0.id != keep.id }
        return SelectionPlan(keep: keep, remove: remove, reasons: reasons)
    }

    /// Orders `files` by `primary` (ties broken by localized path order)
    /// and returns the winner. `descending` means the larger/newer value
    /// wins.
    private static func pick(
        _ files: [FileItem],
        primary: (FileItem) -> some Comparable,
        descending: Bool
    ) -> FileItem {
        var best = files[0]
        for candidate in files.dropFirst() {
            if isBetter(candidate: candidate, than: best, primary: primary, descending: descending) {
                best = candidate
            }
        }
        return best
    }

    private static func isBetter(
        candidate: FileItem,
        than current: FileItem,
        primary: (FileItem) -> some Comparable,
        descending: Bool
    ) -> Bool {
        let lhs = primary(candidate)
        let rhs = primary(current)
        if lhs != rhs {
            return descending ? lhs > rhs : lhs < rhs
        }
        return candidate.url.path.localizedStandardCompare(current.url.path) == .orderedAscending
    }

    /// The copy that lives directly inside one of the scan roots, choosing
    /// the shallowest match when several roots overlap. Returns nil when
    /// no copy is inside any root.
    private static func pickInsideScanRoot(
        _ files: [FileItem],
        scanRoots: [URL]
    ) -> FileItem? {
        let roots = scanRoots
            .map { $0.standardizedFileURL.path }
            .filter { !$0.isEmpty }
        guard !roots.isEmpty else { return nil }

        var best: FileItem?
        var bestDepth = Int.max
        for file in files {
            let path = file.url.standardizedFileURL.path
            guard let root = roots.first(where: {
                path.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/")
                    || path == $0
            }) else { continue }
            let depth = file.url.pathComponents.count
            if depth < bestDepth {
                bestDepth = depth
                best = file
            }
        }
        return best
    }
}
