import SwiftUI
import DesignSystem

struct FileRowView: View {
    let file: FileItem
    var isSelected: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if let image = NSWorkspace.shared.icon(forFile: file.url.path) as NSImage? {
                Image(nsImage: image)
                    .resizable()
                    .frame(width: 24, height: 24)
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
    }
}
