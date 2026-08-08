import SwiftUI
import DesignSystem

struct CategoryBreakdownBar: View {
    let groups: [DuplicateGroup]

    private var categoryTotals: [(category: DuplicateCategory, size: Int64, groupCount: Int)] {
        Dictionary(grouping: groups, by: \.category)
            .map { category, groups in
                (category: category,
                 size: groups.reduce(0) { $0 + max($1.totalSize, 0) },
                 groupCount: groups.count)
            }
            .filter { $0.size > 0 }
            .sorted { $0.size > $1.size }
    }

    private var totalSize: Int64 {
        categoryTotals.reduce(0) { $0 + $1.size }
    }

    private var byteFormatter: ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }

    var body: some View {
        if !groups.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.sm) {
                Text(NSLocalizedString("Categories", comment: "Category breakdown heading"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                GeometryReader { geometry in
                    HStack(spacing: 1) {
                        ForEach(categoryTotals, id: \.category) { item in
                            item.category.color
                                .frame(width: segmentWidth(item.size, in: geometry.size.width))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.sm))
                }
                .frame(height: 12)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: AppSpacing.md)],
                    alignment: .leading,
                    spacing: AppSpacing.xs
                ) {
                    ForEach(categoryTotals, id: \.category) { item in
                        HStack(spacing: AppSpacing.xs) {
                            Circle()
                                .fill(item.category.color)
                                .frame(width: 7, height: 7)
                            Text(item.category.displayName)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            Text(byteFormatter.string(fromByteCount: item.size))
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                    }
                }
            }
        }
    }

    private func segmentWidth(_ size: Int64, in width: CGFloat) -> CGFloat {
        guard totalSize > 0 else { return 0 }
        return max(width * CGFloat(size) / CGFloat(totalSize), 1)
    }
}
