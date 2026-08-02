import Foundation

/// Whether the app can read the TCC-protected parts of the user's home folder.
///
/// kFresh scans `~/Library` for the files an uninstalled app leaves behind.
/// Most of `~/Library` is reachable from inside the sandbox, but the
/// directories that matter for a *complete* residue scan sit behind the
/// Full Disk Access privacy control.
public enum FDAStatus: Sendable, Equatable {
    /// No probe has run yet. Never inferred — only ``FDAPermissionProbe/probe()`` clears this.
    case unknown
    /// Full Disk Access is not granted; residue scans will be incomplete.
    case basic
    /// Full Disk Access is granted; residue scans can cover all of `~/Library`.
    case full
}

/// Read-only probe reporting whether kFresh currently holds Full Disk Access.
///
/// The probe attempts to *enumerate* a directory that macOS keeps behind the
/// Full Disk Access TCC control. Enumeration succeeds only once the user grants
/// the permission, which makes it a reliable passive signal.
///
/// This type never prompts the user. Opening System Settings to request the
/// permission is `FDAuthorizer`'s job; the two are used together — the probe
/// reports state, the authorizer asks for a change.
///
/// - Important: Do not probe `~/Library/Application Support` itself. The
///   sandbox grants kFresh read access to it via a home-relative entitlement,
///   so it is enumerable *without* Full Disk Access and would report ``FDAStatus/full``
///   for every user. ``defaultProtectedPaths`` deliberately targets directories
///   that carry no such exception.
public actor FDAPermissionProbe {
    /// Directories that macOS gates behind Full Disk Access.
    ///
    /// Each entry exists on a stock macOS install and cannot be enumerated by a
    /// sandboxed app until the user grants the permission. The probe treats *any*
    /// readable entry as proof of access, so one path being absent on an unusual
    /// system does not produce a false negative.
    public static var defaultProtectedPaths: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Safari", isDirectory: true),
            home.appendingPathComponent("Library/Cookies", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/com.apple.TCC", isDirectory: true)
        ]
    }

    private let fileManager: FileManager
    private let protectedPaths: [URL]
    private var cached: FDAStatus = .unknown

    public init() {
        self.fileManager = .default
        self.protectedPaths = Self.defaultProtectedPaths
    }

    /// Creates a probe over custom TCC-gated paths (tests).
    public init(protectedPaths: [URL]) {
        self.fileManager = .default
        self.protectedPaths = protectedPaths
    }

    /// The most recently probed status, without touching the file system.
    ///
    /// Returns ``FDAStatus/unknown`` until ``probe()`` has run at least once.
    public func currentStatus() -> FDAStatus {
        cached
    }

    /// Re-checks Full Disk Access and caches the result.
    ///
    /// Safe to call repeatedly: the user can grant or revoke the permission
    /// while kFresh is running, so this always performs a fresh check rather
    /// than returning the cached value.
    @discardableResult
    public func probe() -> FDAStatus {
        let status: FDAStatus = protectedPaths.contains(where: canEnumerate) ? .full : .basic
        cached = status
        return status
    }

    /// Whether `url` can be listed. A thrown error means the sandbox or TCC
    /// denied access, which is the signal the probe is looking for — it is
    /// expected, not exceptional, so it maps to `false` rather than propagating.
    private func canEnumerate(_ url: URL) -> Bool {
        do {
            _ = try fileManager.contentsOfDirectory(atPath: url.path)
            return true
        } catch {
            return false
        }
    }
}
