// kWise/Features/Common/UserPathResolver.swift
//
// Sandbox-safe real-user path resolution.
//
// Why this exists:
// * In an App Sandbox build, `NSHomeDirectory()` returns the *container*
//   path (`~/Library/Containers/app.kraftly.klaris/Data`), and Foundation's
//   `(path as NSString).expandingTildeInPath` expands `~` against that
//   container home. So a category path like `~/Library/Caches` silently
//   points at the container, the walk finds nothing (or only the app's own
//   container data), and the scan reports "clean" even though the user's
//   real `~/Library/Caches` holds gigabytes.
// * The fix is to ask libc for the *real* home directory
//   (`getpwuid(getuid())->pw_dir`), which the sandbox does not virtualise,
//   and resolve `~`/`~/…` prefixes against that.
//
// Access attribution: whether a scan can see real files is answered by the
// PowerScope capability level (containerOnly → grant flow; homeGranted /
// fullAccess → real sweep), not by a TCC filesystem probe. The former
// `hasFullDiskAccess()` path-probing hack was removed with the P3
// dual-channel split — it conflated "sandbox lacks a grant" with "direct
// edition TCC state" and silently lied in both directions.

import Foundation

/// Sandbox-safe real-user path resolution.
///
/// `public` so it can appear as a default argument value on public APIs
/// (e.g. `AttributionService.live(home:)`) — default arguments are evaluated
/// at the call site and therefore see only public symbols.
public enum UserPathResolver {
    /// The real user home directory, resolved via libc rather than
    /// `NSHomeDirectory()` (which returns the sandbox container path in an
    /// App Sandbox build). Falls back to `NSHomeDirectory()` if the passwd
    /// lookup fails.
    public static func realHomeDirectory() -> String {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            let home = String(cString: dir)
            if !home.isEmpty { return home }
        }
        return NSHomeDirectory()
    }

    /// Resolves a `~` / `~/…` path against the *real* home directory.
    /// Non-tilde paths are returned unchanged. Use this instead of
    /// `(path as NSString).expandingTildeInPath` anywhere a category path
    /// must reach the user's actual files under App Sandbox.
    static func expandTilde(_ path: String) -> String {
        if path == "~" { return realHomeDirectory() }
        if path.hasPrefix("~/") {
            return realHomeDirectory() + path.dropFirst(1)
        }
        return path
    }
}
