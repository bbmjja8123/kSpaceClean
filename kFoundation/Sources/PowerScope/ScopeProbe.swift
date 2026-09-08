import Foundation

/// Runtime readability probe for the directories a sandboxed app *might*
/// be able to read without any user grant.
///
/// The set is deliberately probed, never assumed: macOS does not contract
/// which paths a sandbox can touch, so `FileManager.isReadableFile` plus a
/// one-byte read decides at runtime. Scanners must consult the probe result
/// rather than hardcoding "Caches is public".
public struct ScopeProbe: Sendable {

    /// Candidate public directories, as tilde-relative paths.
    public static let candidatePublicDirs: [String] = [
        "~/Library/Caches",
        "~/Library/Logs",
        "/private/var/folders",
        "/System/Library/Caches",
    ]

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Probe every candidate; return the tilde-relative paths that are
    /// actually readable this session.
    public func readablePublicDirs(candidates: [String] = ScopeProbe.candidatePublicDirs) -> Set<String> {
        Set(candidates.filter { isReadable($0) })
    }

    /// `isReadableFile` alone can report true for directories the sandbox
    /// still blocks on open, so confirm with a directory listing.
    private func isReadable(_ tildePath: String) -> Bool {
        let path = NSString(string: tildePath).expandingTildeInPath
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue,
              fileManager.isReadableFile(atPath: path) else { return false }
        // One cheap readdir to confirm real access.
        return (try? fileManager.contentsOfDirectory(atPath: path)) != nil
    }
}
