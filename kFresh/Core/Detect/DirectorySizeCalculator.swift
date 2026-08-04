import Foundation

/// Shared recursive directory-size computation used by both
/// `ResidueDetector` (kFresh/Core/Detect) and `AppCatalogService`
/// (kFresh/Core/Detect) to sum the on-disk footprint of a directory tree.
///
/// Prior to the m-4 fix each call site reimplemented its own enumerator +
/// size-summing loop with subtly different depth-handling semantics:
/// `AppCatalogService.sizeOfApp` enforced a `maxDepth` cap (skipping
/// over-deep subtrees with `enumerator.skipDescendants()`), while
/// `ResidueDetector.directorySize` walked the entire tree unconditionally.
/// Two implementations of the same operation invited drift — a future
/// change to one would silently desynchronise the other.
///
/// `DirectorySizeCalculator` provides one entry point and one policy:
/// the caller either passes `depth: .unbounded` for the residue
/// "all of `~/Library/Caches/<bundleID>/`" case, or
/// `depth: .limited(N)` for the app-bundle "skip pathological deep
/// frameworks / node_modules" case. The depth cap is enforced by
/// `enumerator.skipDescendants()` on the offending subtree so sibling
/// walks are not aborted.
///
/// Both call sites in kFresh now route through this helper.
///
/// Note: scoped to the kFresh target rather than promoted to kFoundation
/// because kFresh does not currently link the `FileScanner` product — the
/// kFoundation package dependency declared in `project.yml` is not
/// propagated to the Xcode project's linker phase, and m-4 is too small
/// a refactor to justify the cross-target plumbing change.
enum DirectorySizeCalculator {

    /// Depth policy for the walk.
    enum DepthPolicy {
        /// Walk every descendant of the root.
        case unbounded
        /// Walk at most `max` path components below the root; deeper
        /// subtrees are skipped via `enumerator.skipDescendants()`.
        case limited(max: Int)
    }

    /// Returns the sum of `totalFileAllocatedSize` (or `fileSize` as a
    /// fallback) for every file below `root`.
    ///
    /// Hidden files are skipped (`URL.skipsHiddenFiles`). Symlinks and
    /// unreadable per-file metadata contribute zero rather than aborting
    /// the walk — a single missing file must not collapse the entire
    /// size total.
    ///
    /// - Parameters:
    ///   - root: Directory to measure.
    ///   - depth: Depth policy (unbounded or limited to N components).
    ///   - fileManager: Injectable `FileManager`; tests pass a scoped or
    ///     stubbed instance, production code uses the default.
    /// - Returns: Total size in bytes, or `0` if `root` cannot be
    ///   enumerated.
    static func size(
        of root: URL,
        depth: DepthPolicy = .unbounded,
        fileManager: FileManager = .default
    ) -> Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if case let .limited(max) = depth {
                let depthBelowRoot = fileURL.pathComponents.count - root.pathComponents.count
                if depthBelowRoot > max {
                    enumerator.skipDescendants()
                    continue
                }
            }
            // best-effort: resource values unavailable for some files (e.g. symlinks, broken perms)
            // swiftlint:disable:next no_silent_try_question_mark
            let values = try? fileURL.resourceValues(forKeys: keys)
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }
}