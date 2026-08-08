import SwiftUI

struct DiskStatusView: View {
    let used: Int64
    let total: Int64

    var body: some View {
        HStack(spacing: 8) {
            let percentage = total > 0 ? Double(used) / Double(total) : 0
            let color: Color = percentage < 0.7 ? .success : percentage < 0.9 ? .warning : .danger

            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(ByteCountFormatter.string(fromByteCount: used, countStyle: .file))
                .font(.system(.body, design: .monospaced))

            Text("of")
                .foregroundColor(.secondary)

            Text(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))
                .font(.system(.body, design: .monospaced))
        }
    }
}
