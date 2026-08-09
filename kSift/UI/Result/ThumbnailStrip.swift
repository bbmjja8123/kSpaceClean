import SwiftUI

/// Horizontal scrolling thumbnail strip for perceptual / directory groups
/// shown inline in result rows. Caps visible count to keep the row compact;
/// overflow renders as a "+N" tile so users see the cluster size at a glance.
///
/// Reused by GroupDetailView (large 80pt) and GroupRowView (compact 36pt).
struct ThumbnailStrip: View {
    let files: [FileItem]
    let size: CGFloat
    let maxVisible: Int

    init(files: [FileItem], size: CGFloat = 36, maxVisible: Int = 4) {
        self.files = files
        self.size = size
        self.maxVisible = maxVisible
    }

    var body: some View {
        let visible = Array(files.prefix(maxVisible))
        let overflow = files.count - visible.count
        HStack(spacing: 4) {
            ForEach(visible) { file in
                ThumbnailView(url: file.url, size: size)
            }
            if overflow > 0 {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.sm)
                        .fill(Color.secondary.opacity(0.15))
                    Text(String(format: NSLocalizedString("+%lld", comment: "More thumbnails overflow"), overflow))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: size, height: size)
            }
        }
    }
}