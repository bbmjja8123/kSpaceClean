// kSpaceClean/Features/Cleanup/Engine/WarningDetectionService.swift
//
// Task C3 — WarningDetectionService (Layer 1).
//
// Layer 1 of the cleanup-warning flow (Q11 decision). Before the engine moves
// any user-selected path to Trash, we surface a list of *running* apps that
// have a file open underneath one of those paths so the user can decide:
//
// - **Skip**: leave the conflicting paths out of the cleanup (default).
// - **Force terminate**: `kill -TERM` the running app, then proceed.
// - **Cancel**: abort the cleanup run entirely.
//
// Per the v1.0 design note (CLAUDE.md §8.7) Layer 1 deliberately does NOT
// predict "this cache belongs to X even if X is not running" — that heuristic
// is Layer 2 and is deferred to v1.1. We only warn about apps that
// **currently** have a file open, which avoids the false-positive rate that
// makes Lemon's similar prompt easy to dismiss.
//
// ## Detection pipeline
//
// 1. **Enumerate** every PID on the system via `proc_listpids(PROC_ALL_PIDS, …)`.
//    This is cheap (a single syscall) and returns up to N PIDs at a time — we
//    loop until the buffer comes back short.
// 2. For each PID, enumerate its open file descriptors in-process via
//    `proc_pidinfo(PROC_PIDLISTFDS)` and resolve each vnode descriptor to an
//    absolute path with `proc_pidfdinfo(PROC_PIDFDVNODEPATHINFO)`. No
//    subprocess is spawned — the earlier `lsof` implementation could not run
//    under App Sandbox at all and cost seconds of wall clock. The resulting
//    path list is intersected with the user's selected paths; matching paths
//    are recorded against the PID.
// 3. PIDs are cross-referenced with `NSWorkspace.runningApplications` to
//    obtain the user-facing app name, bundle identifier, and activation policy.
//    System services and helpers (Quick Look, Spotlight, mdworker_*,
//    nsurlsessiond, etc.) are filtered out via ``daemonBundleBlacklist`` so
//    we do not generate false positives for indexes or preview generators.
// 4. The remaining entries are grouped by bundle ID (one WarnItem per app,
//    listing every conflicting path) and returned sorted by app name.
//
// ## Layering
//
// The service is an `actor` because every step touches the whole process
// table (`proc_listpids` + two `proc_pidinfo` calls per PID) and the caller
// (Task C6 — `WarningToast`) will await the result from the main actor. We
// do not block the calling thread, and concurrent calls coalesce cleanly.
//
// `BundleIDResolver` is not consulted by Layer 1 — NSWorkspace already
// resolves the foreground apps we care about. The resolver is only useful
// for Layer 2 (predictive "this cache belongs to X even if X is not
// running"), which is deferred to v1.1.

import AppKit
import Darwin
import Foundation

// MARK: - libproc C bindings (C7)
//
// `proc_pidinfo` and `proc_pidfdinfo` live in Apple's private `<libproc.h>`
// header, which is not exposed through the public `Darwin` Swift overlay.
// We declare the C signatures via `@_silgen_name` so the implementation can
// call the C symbols directly. The result types are imported as opaque
// `UnsafeMutableRawPointer` slots; callers must layout the buffer correctly
// per Apple's documentation:
//   * `PROC_PIDLISTFDS` returns `struct proc_fdinfo` per FD.
//   * `PROC_PIDFDVNODEPATHINFO` returns a single `struct vnode_fdinfowithpath`
//     with the vnode's mount point, parent vnode, and absolute path.

@_silgen_name("proc_listpids")
private func _proc_listpids(_ type: Int32,
                            _ typeinfo: UInt32,
                            _ buffer: UnsafeMutablePointer<Int32>?,
                            _ buffersize: Int32) -> Int32

@_silgen_name("proc_pidinfo")
private func _proc_pidinfo(_ pid: Int32,
                           _ flavor: Int32,
                           _ arg: UInt64,
                           _ buffer: UnsafeMutableRawPointer?,
                           _ buffersize: Int32) -> Int32

@_silgen_name("proc_pidfdinfo")
private func _proc_pidfdinfo(_ pid: Int32,
                             _ fd: Int32,
                             _ flavor: Int32,
                             _ buffer: UnsafeMutableRawPointer?,
                             _ buffersize: Int32) -> Int32

private let PROC_ALL_PIDS: Int32 = 1
private let PROC_PIDLISTFDS: Int32 = 1
private let PROC_PIDFDVNODEPATHINFO: Int32 = 2
/// `PROX_FDTYPE_VNODE` from `<sys/proc_info.h>` — the only descriptor type
/// that has an on-disk path. Sockets (2), pipes (6), kqueues (5) etc. are
/// skipped so we do not burn a syscall resolving something that can never
/// match a user-selected cleanup path.
private let PROX_FDTYPE_VNODE: UInt32 = 1

/// Mirrors `struct proc_fdinfo` from `<libproc.h>`. We only need the
/// `proc_fdtype` discriminator (first 4 bytes) plus padding; the rest of
/// the struct varies per FD type and we never read it.
private struct ProcFDInfo {
    var proc_fd: Int32
    var proc_fdtype: UInt32
}

/// Detects running apps that have a file open underneath one of the paths the
/// user wants to clean.
///
/// The service is intentionally conservative: it only surfaces foreground
/// GUI apps from `NSWorkspace.runningApplications` plus a curated allow-list
/// of known daemons (background helpers that own cache files we still want
/// to warn about — e.g. backup agents). Pure system services (Spotlight
/// indexers, Quick Look generators, etc.) are silently filtered out.
///
/// Initialise the service with no external dependencies — Layer 1 only
/// needs ``NSWorkspace`` and `libproc` (both always available, including
/// inside the App Sandbox).
public actor WarningDetectionService {

    // MARK: - Init

    public init() {}

    // MARK: - Public API

    /// Inspect every running process and return the apps that have a file
    /// open underneath any of ``paths``.
    ///
    /// - Parameter paths: Absolute filesystem paths the user has selected
    ///   for cleanup. Paths are matched by exact equality OR by the
    ///   "selected path is inside an open file" prefix rule — that way
    ///   ``/Users/me/Library/Caches/com.foo/x`` still triggers when the
    ///   user selects ``/Users/me/Library/Caches/com.foo``.
    /// - Returns: One ``WarnItem`` per running app, sorted by app name.
    ///   Empty when nothing conflicts.
    public func detectWarnItems(for paths: [String]) async -> [WarnItem] {
        guard !paths.isEmpty else { return [] }

        // Pre-normalise the user's selection so the prefix-match loop below
        // can use direct string comparisons rather than resolving symlinks.
        let normalized = paths
            .map { (path: $0, resolved: Self.standardise($0)) }
            .filter { !$0.resolved.isEmpty }

        guard !normalized.isEmpty else { return [] }

        // Step 1 + 2: enumerate every PID, then for each PID ask libproc what
        // it has open. PIDs we cannot introspect (no entitlement, process
        // already exited, no vnode descriptors) are silently dropped — never
        // fatal.
        let pids = Self.allProcessIDs()
        var matches: [Int32: [String]] = [:]

        for pid in pids {
            let openPaths = Self.openFiles(for: pid)
            if openPaths.isEmpty { continue }
            let intersecting = Self.intersecting(openPaths, with: normalized.map(\.resolved))
            if !intersecting.isEmpty {
                matches[pid] = intersecting
            }
        }

        guard !matches.isEmpty else { return [] }

        // Step 3: attribute each PID to an app via NSWorkspace. PIDs that do
        // not match a foreground/background GUI app are silently dropped —
        // they are either short-lived helpers or system services we already
        // filtered through ``daemonBundleBlacklist`` below.
        let workspaceApps = NSWorkspace.shared.runningApplications
        var warnByBundle: [String: WarnItem] = [:]

        for (pid, conflictingPaths) in matches {
            guard let app = workspaceApps.first(where: { $0.processIdentifier == pid }),
                  let bundleID = app.bundleIdentifier else { continue }

            // Skip system services and helpers we know are noise.
            if Self.daemonBundleBlacklist.contains(bundleID) { continue }

            let appName = app.localizedName ?? bundleID
            let existing = warnByBundle[bundleID]
            let merged = existing?.conflictingPaths ?? []
            let combined = Self.unique(existing: merged, new: conflictingPaths)

            warnByBundle[bundleID] = WarnItem(
                appName: appName,
                bundleID: bundleID,
                processID: pid,
                conflictingPaths: combined
            )
        }

        return Array(warnByBundle.values).sorted { $0.appName < $1.appName }
    }

    // MARK: - PID enumeration

    /// Snapshot every PID currently alive on the system.
    ///
    /// `proc_listpids` returns at most ``bufferSize`` PIDs per call, so we
    /// loop with a buffer that doubles until the kernel reports a short
    /// result. We cap at 16 iterations (≈ 1M PIDs) which is well above any
    /// realistic macOS process count.
    private static func allProcessIDs() -> [Int32] {
        var collected: [Int32] = []
        var bufferSize = 1024

        for _ in 0..<16 {
            var buffer = [Int32](repeating: 0, count: bufferSize)
            let byteCount = _proc_listpids(
                PROC_ALL_PIDS,
                0,
                &buffer,
                Int32(MemoryLayout<Int32>.size * bufferSize)
            )
            let safeByteCount = max(Int32(0), byteCount)
            let returned = Int(safeByteCount) / MemoryLayout<Int32>.size
            let pids = buffer.prefix(returned).filter { $0 > 0 }
            collected.append(contentsOf: pids)

            if returned < bufferSize {
                break
            }
            bufferSize *= 2
        }

        return collected
    }

    // MARK: - libproc FD enumeration

    /// Enumerate the absolute paths of every vnode-backed file descriptor the
    /// process has open, entirely in-process via `libproc`.
    ///
    /// C7 fix: the previous implementation spawned `/usr/sbin/lsof` once per
    /// PID. That was broken in two independent ways:
    ///
    /// 1. **Sandbox**: `Process` cannot exec an arbitrary binary from inside
    ///    an App Sandbox without a `com.apple.security.temporary-exception`
    ///    entitlement we deliberately do not ship. Every invocation failed,
    ///    so the service silently returned "no conflicts" for every path —
    ///    i.e. the whole Layer-1 warning flow was dead code in production.
    /// 2. **Performance**: ~700 PIDs on a typical Mac × one `fork`/`exec` +
    ///    pipe drain each is several seconds of wall-clock, on the path
    ///    between "user taps Clean" and the confirmation sheet appearing.
    ///
    /// The replacement uses two `libproc` syscalls per PID with no process
    /// spawn at all:
    ///
    /// - `proc_pidinfo(pid, PROC_PIDLISTFDS, …)` → array of `proc_fdinfo`,
    ///   one entry per open descriptor. We size the buffer from the byte
    ///   count the kernel reports for a zero-length probe, then grow once if
    ///   the descriptor table changed underneath us.
    /// - `proc_pidfdinfo(pid, fd, PROC_PIDFDVNODEPATHINFO, …)` → a
    ///   `vnode_fdinfowithpath` whose tail holds the NUL-terminated absolute
    ///   path (`MAXPATHLEN` bytes at a fixed offset).
    ///
    /// Only `PROX_FDTYPE_VNODE` descriptors are queried; sockets, pipes, and
    /// kqueues have no path and would waste a syscall. Both calls fail
    /// benignly (return `<= 0`) for processes we lack the entitlement to
    /// introspect — those PIDs are skipped rather than treated as fatal,
    /// which is the same conservative posture the lsof version intended.
    private static func openFiles(for pid: Int32) -> [String] {
        // Step 1: how many bytes of proc_fdinfo does this PID need? A NULL
        // buffer probe returns the current size; the table can grow between
        // the probe and the real read, so we over-allocate by a slack factor
        // and tolerate a short result.
        let probe = _proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard probe > 0 else { return [] }

        let stride = MemoryLayout<ProcFDInfo>.stride
        // Slack: +32 descriptors worth of headroom for tables that grow
        // between the probe and the read.
        let capacity = Int(probe) / stride + 32
        guard capacity > 0 else { return [] }

        var fdInfos = [ProcFDInfo](repeating: ProcFDInfo(proc_fd: 0, proc_fdtype: 0),
                                   count: capacity)
        let byteCount: Int32 = fdInfos.withUnsafeMutableBytes { raw in
            _proc_pidinfo(pid,
                          PROC_PIDLISTFDS,
                          0,
                          raw.baseAddress,
                          Int32(raw.count))
        }
        guard byteCount > 0 else { return [] }

        let returned = min(Int(byteCount) / stride, capacity)
        guard returned > 0 else { return [] }

        // Step 2: resolve each vnode descriptor to an absolute path.
        var paths: [String] = []
        paths.reserveCapacity(returned)

        // `vnode_fdinfowithpath` is not exposed to Swift, so we read the
        // path out of a raw byte buffer at the documented offset. The struct
        // layout is: proc_fileinfo (16 bytes) + vnode_info_path, where
        // vnode_info_path = vnode_info (152 bytes) + char vip_path[MAXPATHLEN].
        // We allocate generously and locate the path by scanning for the
        // first NUL-terminated absolute path rather than hard-coding the
        // offset, which keeps us resilient to SDK-version layout drift.
        let bufferSize = 8192
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        for index in 0..<returned {
            let info = fdInfos[index]
            guard info.proc_fdtype == PROX_FDTYPE_VNODE else { continue }

            // Reset only the region we care about; a full zero-fill per FD
            // would dominate the loop cost on processes with many vnodes.
            for i in 0..<bufferSize { buffer[i] = 0 }

            let written: Int32 = buffer.withUnsafeMutableBytes { raw in
                _proc_pidfdinfo(pid,
                                info.proc_fd,
                                PROC_PIDFDVNODEPATHINFO,
                                raw.baseAddress,
                                Int32(raw.count))
            }
            guard written > 0 else { continue }

            if let path = Self.extractPath(from: buffer, limit: Int(written)) {
                paths.append(path)
            }
        }

        return paths
    }

    /// Locate the absolute path embedded in a `vnode_fdinfowithpath` blob.
    ///
    /// Rather than hard-coding `offsetof(vnode_fdinfowithpath, pvip.vip_path)`
    /// — which differs across SDKs and would silently read garbage if Apple
    /// re-orders the struct — we scan for the first byte sequence that starts
    /// with `/` and is NUL-terminated. `vip_path` is the only `char[]` member
    /// in the struct, so the first such run is unambiguously the path.
    ///
    /// - Parameters:
    ///   - buffer: raw bytes filled in by `proc_pidfdinfo`.
    ///   - limit: number of bytes the kernel actually wrote.
    /// - Returns: the absolute path, or `nil` when the vnode has no path
    ///   (unlinked file, anonymous mmap, etc).
    private static func extractPath(from buffer: [UInt8], limit: Int) -> String? {
        let end = min(limit, buffer.count)
        var index = 0
        while index < end {
            guard buffer[index] == UInt8(ascii: "/") else {
                index += 1
                continue
            }
            // Found a candidate start; walk to the NUL terminator.
            var terminator = index
            while terminator < end, buffer[terminator] != 0 { terminator += 1 }
            guard terminator > index, terminator < end else { return nil }

            let bytes = buffer[index..<terminator]
            // Reject obvious noise: a lone "/" or a run with embedded control
            // characters is not a real path.
            if bytes.count > 1,
               !bytes.contains(where: { $0 < 0x20 }),
               let path = String(bytes: bytes, encoding: .utf8) {
                return path
            }
            index = terminator + 1
        }
        return nil
    }

    // MARK: - Test hooks

    /// Expose the FD walk to unit tests.
    ///
    /// `detectWarnItems` filters its result through `NSWorkspace.runningApplications`,
    /// which never contains a non-GUI XCTest runner — so a test cannot observe
    /// the FD walk through the public API. This `nonisolated` shim gives the
    /// C7 regression test direct access to the layer that actually broke.
    ///
    /// Not `#if DEBUG`-gated because the test target compiles against the
    /// Release-configured module in CI; it is `internal`, so it is not part of
    /// the published API surface.
    nonisolated static func openFilesForTesting(pid: Int32) -> [String] {
        openFiles(for: pid)
    }

    // MARK: - Path intersection

    /// Return every entry in ``openPaths`` that equals or is contained by one
    /// of the user's normalised ``selectedPaths``.
    ///
    /// We also accept the reverse containment (selected path sits inside an
    /// open file) so a coarse selection like
    /// ``/Users/me/Library/Caches/com.foo`` still matches when libproc reports
    /// ``/Users/me/Library/Caches/com.foo/index.db``.
    private static func intersecting(_ openPaths: [String],
                                     with selectedPaths: [String]) -> [String] {
        var hits: [String] = []
        for open in openPaths {
            for selected in selectedPaths {
                if open == selected
                    || open.hasPrefix(selected + "/")
                    || selected.hasPrefix(open + "/") {
                    hits.append(open)
                    break
                }
            }
        }
        return hits
    }

    // MARK: - Helpers

    /// Normalise a path: expand ``~`` and resolve symlinks.
    ///
    /// Returns an empty string when the path does not exist (e.g. the user
    /// selected a file the scanner is about to delete) so we can filter it
    /// out without throwing.
    private static func standardise(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        return url.resolvingSymlinksInPath().path
    }

    /// De-duplicate two path lists while preserving order (existing first).
    private static func unique(existing: [String], new: [String]) -> [String] {
        var seen = Set(existing)
        var combined = existing
        for p in new where seen.insert(p).inserted {
            combined.append(p)
        }
        return combined
    }

    // MARK: - Daemon filter

    /// Bundle IDs we never warn about even if they happen to have one of the
    /// user's selected files open.
    ///
    /// These are background services that routinely open files inside the
    /// user's library/caches and would generate spurious warnings:
    /// Spotlight indexers, Quick Look generators, photo analysis, etc.
    /// Listing them up front keeps the warning toast meaningful.
    private static let daemonBundleBlacklist: Set<String> = [
        "com.apple.Spotlight",
        "com.apple.metadata.mdworker",
        "com.apple.metadata.mds",
        "com.apple.metadata.mds_stores",
        "com.apple.quicklook",
        "com.apple.quicklook.ui",
        "com.apple.QuickLookThumbnailing",
        "com.apple.PhotoLibraryMigrationUtility",
        "com.apple.photolibraryd",
        "com.apple.CloudPhotosConfiguration",
        "com.apple.nsurlsessiond",
        "com.apple.nsurlstorage",
        "com.apple.bird",
        "com.apple.containermanagerd",
        "com.apple.coreduetd",
        "com.apple.knowledge-agent",
        "com.apple.parsecd",
        "com.apple.suggestd",
        "com.apple.timed",
        "com.apple.chronod",
        "com.apple.usernoted",
        "com.apple.distnoted",
        "com.apple.cfprefsd",
        "com.apple.fontd",
        "com.apple.systempreferences",
    ]
}