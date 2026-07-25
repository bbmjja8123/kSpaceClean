import SwiftUI

struct SystemCleanGroupView: View {
    let group: DeepCleanEngine.CleanGroup

    var body: some View {
        Section {
            ForEach(group.items) { item in
                HStack {
                    Image(systemName: group.icon)
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading) {
                        Text(item.name)
                            .font(.system(size: 13))
                        Text(item.url.path)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            HStack {
                Text(group.title)
                    .font(.headline)
                Spacer()
                Text("\(group.items.count) 项")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
