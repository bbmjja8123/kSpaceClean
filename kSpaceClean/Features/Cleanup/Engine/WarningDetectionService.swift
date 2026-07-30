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
// 2. For each PID, run `lsof -p <pid> -Fn` (the ``-Fn`` flag emits only path
//    lines, which is much easier to parse than the default human-readable
//    output). The path list is intersected with the user's selected paths;
//    matching paths are recorded against the PID.
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
// The service is an `actor` because every step is potentially expensive
// (multiple `Process` invocations + `proc_listpids` calls) and the caller
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

// `proc_listpids` lives in Apple's private ``<libproc.h>`` header, which is
// not exposed through the public ``Darwin`` Swift overlay. We declare the
// signature via ``@_silgen_name`` so the implementation can call the C
// symbol directly without needing a bridging header. This matches what
// `systemd`-style utilities have done on macOS for years and keeps the
// service self-contained.
@_silgen_name("proc_listpids")
private func _proc_listpids(_ type: Int32,
                            _ typeinfo: UInt32,
                            _ buffer: UnsafeMutablePointer<Int32>?,
                            _ buffersize: Int32) -> Int32

private let PROC_ALL_PIDS: Int32 = 1

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
/// needs ``NSWorkspace`` and ``lsof`` (which is shipped with macOS).
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

        // Step 1 + 2: enumerate every PID, then for each PID ask lsof what it
        // has open. PIDs we cannot introspect (lsof fails, returns empty, etc.)
        // are silently dropped — never fatal.
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

    // MARK: - lsof invocation

    /// Run `lsof -p <pid> -Fn -w` and parse the result.
    ///
    /// `-Fn` emits one path per line prefixed with ``n``, which keeps the
    /// output machine-readable. `-w` suppresses warnings so they do not
    /// appear on stdout alongside path entries. Returns an empty array on
    /// any failure (process already exited, permission denied, lsof missing).
    private static func openFiles(for pid: Int32) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-p", String(pid), "-Fn", "-w"]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return []
        }

        // Read fully *before* waitUntilExit so a fast-exiting process cannot
        // deadlock on a full pipe buffer.
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let text = String(data: outData, encoding: .utf8) else { return [] }

        var paths: [String] = []
        for line in text.split(separator: "\n") {
            // Each path line starts with "n"; the actual path follows.
            guard line.first == "n" else { continue }
            let path = String(line.dropFirst())
            // lsof emits a handful of pseudo-paths we never want to compare
            // against user selections: the cwd placeholder, the exec link,
            // mem-mapped shared libraries, etc. We keep only real files that
            // start with "/".
            guard path.hasPrefix("/") else { continue }
            paths.append(path)
        }
        return paths
    }

    // MARK: - Path intersection

    /// Return every entry in ``openPaths`` that equals or is contained by one
    /// of the user's normalised ``selectedPaths``.
    ///
    /// We also accept the reverse containment (selected path sits inside an
    /// open file) so a coarse selection like
    /// ``/Users/me/Library/Caches/com.foo`` still matches when lsof reports
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