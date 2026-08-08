import AppKit
import SwiftUI
import DesignSystem

/// Async thumbnail view: shows a QuickLook-generated NSImage, a ProgressView
/// placeholder while loading, or the generic NSWorkspace icon on failure.
struct ThumbnailView: View {
    let url: URL
    var size: CGFloat = 64

    @State private var image: NSImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else if failed {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: size, height: size)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
        .task(id: url) {
            failed = false
            image = nil
            let result = await ThumbnailCache.shared.thumbnail(for: url, size: size)
            if let result {
                image = result
            } else {
                failed = true
            }
        }
    }
}
