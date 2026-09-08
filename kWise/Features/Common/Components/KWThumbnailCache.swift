// kWise/Features/Common/Components/KWThumbnailCache.swift
//
// Toolbox 缩略图缓存 (v2.3 Phase 1) — lifted from kSift's ThumbnailCache.
// QLThumbnailGenerator 生成、NSCache 内存约束、失败回退 nil（调用方落
// NSWorkspace 图标）。Generation is I/O bound — always await from a Task.
import AppKit
import Foundation
import QuickLookThumbnailing

final class KWThumbnailCache: @unchecked Sendable {
    static let shared = KWThumbnailCache()

    private let cache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 512
        c.totalCostLimit = 32 * 1024 * 1024 // 32 MB of decoded thumbnails
        return c
    }()

    /// Returns a cached thumbnail when available, otherwise generates one
    /// off-main. Non-image / unreadable files return nil — the caller falls
    /// back to the generic file icon.
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
