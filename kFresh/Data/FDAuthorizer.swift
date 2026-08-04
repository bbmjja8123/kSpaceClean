import AppKit
import Foundation
import os

actor FDAuthorizer {
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "app.kraftly.kfresh", category: "FDAuthorizer")

    /// Check if FDA is granted by testing ~/Library accessibility
    func checkFDA() -> Bool {
        let testPath = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        return fileManager.isReadableFile(atPath: testPath.path)
    }

    /// Open System Settings → Privacy → Full Disk Access
    nonisolated func requestFDA() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Create a Security-Scoped Bookmark for persistent access
    func createBookmark(for url: URL) -> Data? {
        do {
            return try url.bookmarkData(options: .withSecurityScope,
                                        includingResourceValuesForKeys: nil,
                                        relativeTo: nil)
        } catch {
            logger.error("Failed to create bookmark for \(url.path): \(error.localizedDescription)")
            return nil
        }
    }

    /// Resolve a Security-Scoped Bookmark
    func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: data,
                              options: .withSecurityScope,
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            _ = url.startAccessingSecurityScopedResource()
            return url
        } catch {
            logger.error("Failed to resolve bookmark: \(error.localizedDescription)")
            return nil
        }
    }
}
