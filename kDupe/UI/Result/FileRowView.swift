import SwiftUI
import DesignSystem

struct FileRowView: View {
    let file: FileItem
    var isSelected: Bool = false

    @State private var icon: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            // Async icon: placeholder is a generic doc icon so the row is
            // never blank. The cached NSWorkspace icon replaces it once loaded.
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 24, height: 24)
            } else {
                Image(systemName: "doc")
                    .resizable()
                    .frame(width: 24, height: 24)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(file.url.lastPathComponent)
                    .font(.body)
                    .lineLimit(1)
                Text(file.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: file.url) {
            // Cache-hit short-circuit keeps re-renders cheap; first render
            // does the one-time NSWorkspace lookup on a background queue.
            if let cached = FileIconCache.shared.cachedIcon(for: file.url.path) {
                icon = cached
                return
            }
            FileIconCache.shared.loadIcon(for: file.url) { image in
                icon = image
            }
        }
    }
}
