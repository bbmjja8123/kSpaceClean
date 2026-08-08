import AppKit
import Foundation
import UniformTypeIdentifiers

/// Caches NSWorkspace icons for file URLs. Replaces the previous main-thread
/// `NSWorkspace.shared.icon(forFile:)` call inside FileRowView, which blocked
/// scrolling on large result lists.
final class FileIconCache: @unchecked Sendable {
    static let shared = FileIconCache()

    private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 1024
        return c
    }()

    private init() {}

    /// Synchronous lookup; returns nil when the icon isn't yet cached.
    func cachedIcon(for path: String) -> NSImage? {
        cache.object(forKey: path as NSString)
    }

    /// Async icon load: cache-hit returns immediately, cache-miss hops to a
    /// background queue to call NSWorkspace. Completion runs on the main
    /// queue so callers can publish to `@State` directly.
    func loadIcon(for url: URL, completion: @escaping @MainActor (NSImage) -> Void) {
        let path = url.path
        if let cached = cache.object(forKey: path as NSString) {
            Task { @MainActor in completion(cached) }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [cache] in
            let icon = NSWorkspace.shared.icon(forFile: path)
            // Resize to a standard row size so the cache stays small.
            let target = NSImage(size: NSSize(width: 24, height: 24))
            target.lockFocus()
            icon.draw(in: NSRect(origin: .zero, size: target.size),
                      from: NSRect(origin: .zero, size: icon.size),
                      operation: .copy,
                      fraction: 1.0)
            target.unlockFocus()
            cache.setObject(target, forKey: path as NSString)
            Task { @MainActor in completion(target) }
        }
    }

    // MARK: - P1-6 UTType → SF Symbol mapping

    /// Returns an SF Symbol NSImage representing the file's broad type.
    /// Used by FileRowView as a fast first-render placeholder so the row
    /// doesn't show a generic doc icon while NSWorkspace loads.
    func icon(for fileType: UTType?) -> NSImage? {
        guard let symbol = sfSymbolName(for: fileType),
              let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        else { return nil }
        image.size = NSSize(width: 24, height: 24)
        return image
    }

    private func sfSymbolName(for fileType: UTType?) -> String? {
        guard let fileType else { return nil }
        if fileType.conforms(to: .image) { return "photo" }
        if fileType.conforms(to: .movie) || fileType.conforms(to: .video) { return "video" }
        if fileType.conforms(to: .audio) { return "waveform" }
        if fileType.conforms(to: .pdf) { return "doc.richtext" }
        if fileType.conforms(to: .archive) { return "archivebox" }
        if fileType.conforms(to: .sourceCode) { return "terminal" }
        if fileType.conforms(to: .plainText) || fileType.conforms(to: .text) { return "doc.plaintext" }
        if fileType.conforms(to: .executable) { return "applescript" }
        return "doc"
    }
}
