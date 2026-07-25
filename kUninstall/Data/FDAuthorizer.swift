import Foundation
import AppKit

actor FDAuthorizer {
    private let fileManager = FileManager.default

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
        try? url.bookmarkData(options: .withSecurityScope,
                              includingResourceValuesForKeys: nil,
                              relativeTo: nil)
    }

    /// Resolve a Security-Scoped Bookmark
    func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        let url = try? URL(resolvingBookmarkData: data,
                           options: .withSecurityScope,
                           relativeTo: nil,
                           bookmarkDataIsStale: &isStale)
        _ = url?.startAccessingSecurityScopedResource()
        return url
    }
}
