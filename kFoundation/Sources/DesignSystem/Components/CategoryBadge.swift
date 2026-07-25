import SwiftUI

public struct CategoryBadge: View {
    let category: FileCategory
    let count: Int?

    public init(category: FileCategory, count: Int? = nil) {
        self.category = category
        self.count = count
    }

    public var body: some View {
        HStack(spacing: AppSpacing.xs) {
            Circle()
                .fill(category.color)
                .frame(width: 8, height: 8)
            Text(category.rawValue.capitalized)
                .font(AppFont.caption)
                .foregroundColor(.textSecondary)
            if let count = count {
                Text("(\(count))")
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary.opacity(0.7))
            }
        }
    }
}
