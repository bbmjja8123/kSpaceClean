// kWise/Features/Common/UserPathResolver.swift
//
// Sandbox-safe real-user path resolution and Full Disk Access probing.
//
// Why this exists:
// * In an App Sandbox build, `NSHomeDirectory()` returns the *container*
//   path (`~/Library/Containers/app.kraftly.sclean/Data`), and Foundation's
//   `(path as NSString).expandingTildeInPath` expands `~` against that
//   container home. So a category path like `~/Library/Caches` silently
//   points at the container, the walk finds nothing (or only the app's own
//   container data), and the scan reports "clean" even though the user's
//   real `~/Library/Caches` holds gigabytes.
// * The fix is to ask libc for the *real* home directory
//   (`getpwuid(getuid())->pw_dir`), which the sandbox does not virtualise,
//   and resolve `~`/`~/…` prefixes against that.
//
// FDA probing: kWise ships sandboxed and requires the user to grant
// Full Disk Access (TCC) before any real filesystem sweep can see data.
// Without it the scan legitimately enumerates zero files. `hasFullDiskAccess()`
// probes a handful of known TCC-gated paths and returns true when any of
// them is readable — an empty scan result then gets attributed to "no FDA"
// instead of a misleading "your Mac is clean".

import Foundation

enum UserPathResolver {
    /// The real user home directory, resolved via libc rather than
    /// `NSHomeDirectory()` (which returns the sandbox container path in an
    /// App Sandbox build). Falls back to `NSHomeDirectory()` if the passwd
    /// lookup fails.
    static func realHomeDirectory() -> String {
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

    /// True when the user has granted Full Disk Access to kWise.
    ///
    /// Probes a handful of directories that TCC gates (private logs, Mail,
    /// Safari, and system cookies) and returns true if *any* is readable.
    /// Intended for attribution only — an empty scan with FDA missing
    /// should surface a "grant Full Disk Access" state instead of a false
    /// "your Mac is clean".
    static func hasFullDiskAccess() -> Bool {
        let probes = [
            "/private/var/log",
            realHomeDirectory() + "/Library/Mail",
            realHomeDirectory() + "/Library/Safari",
            realHomeDirectory() + "/Library/Cookies",
        ]
        return probes.contains { FileManager.default.isReadableFile(atPath: $0) }
    }
}
