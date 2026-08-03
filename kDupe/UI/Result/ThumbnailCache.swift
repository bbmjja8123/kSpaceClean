import AppKit
import Foundation
import QuickLookThumbnailing

/// Caches NSImage thumbnails for FileItem URLs so perceptual groups can show
/// inline previews without blocking the main thread on QuickLook generation.
///
/// Memory-bounded via NSCache (count + totalCost). Failures (non-image files,
/// protected, I/O) return nil so the caller falls back to the generic file icon.
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let cache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 512
        c.totalCostLimit = 32 * 1024 * 1024 // 32 MB of decoded thumbnails
        return c
    }()

    /// Returns a cached thumbnail synchronously when available, otherwise
    /// generates one off-main and returns the result. Callers should invoke
    /// this from a `Task` — generation is async and I/O-bound.
    func thumbnail(for url: URL, size: CGFloat = 128, scale: CGFloat = 2.0) async -> NSImage? {
        let key = url as NSURL
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let pixelSize = CGSize(width: size, height: size)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: pixelSize,
            scale: scale,
            representationTypes: .thumbnail
        )
        do {
            let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            let image = rep.nsImage
            let cost = Int(image.size.width * image.size.height * scale * scale * 4)
            cache.setObject(image, forKey: key, cost: cost)
            return image
        } catch {
            return nil
        }
    }
}
