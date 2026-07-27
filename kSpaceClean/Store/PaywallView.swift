import SwiftUI
import DesignSystem

struct PaywallView: View {
    @StateObject private var store = StoreManager()

    var body: some View {
        GlassPanel {
            VStack(spacing: AppSpacing.xl) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.brandAccent)

                Text("解锁全部 kSpaceClean 功能")
                    .font(AppFont.title2)
                    .foregroundColor(.textPrimary)

                FeatureList(items: [
                    ("无限清理", "免费版仅 1GB"),
                    ("AI 智能分类", "本地 CoreML"),
                    ("3D 磁盘星系图", "Metal 渲染"),
                    ("桌面 Widget + Shortcuts", "macOS 深度集成"),
                ])

                Button("7 天免费试用 · 之后 ¥98/年") {
                    Task { await store.purchase() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.brandPrimary)
                .controlSize(.large)

                Button("恢复购买") {
                    Task { await store.restorePurchases() }
                }
                .buttonStyle(.plain)
                .foregroundColor(.textSecondary)
            }
            .padding(AppSpacing.xxl)
        }
        .frame(width: 400)
    }
}

struct FeatureList: View {
    let items: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            ForEach(items, id: \.0) { item in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.success)
                    Text(item.0)
                        .font(AppFont.body)
                        .foregroundColor(.textPrimary)
                    Text(item.1)
                        .font(AppFont.caption)
                        .foregroundColor(.textSecondary)
                }
            }
        }
    }
}
