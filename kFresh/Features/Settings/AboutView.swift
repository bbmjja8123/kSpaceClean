import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            // Brand icon
            Image(systemName: "trash.square.fill")
                .font(.system(size: 64))
                .foregroundColor(.brandPrimary)
                .symbolRenderingMode(.hierarchical)

            // App name
            Text("kFresh")
                .font(.largeTitle.weight(.bold))
                .foregroundColor(.textPrimary)

            // Version
            if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                Text("版本 \(version)")
                    .font(.subheadline)
                    .foregroundColor(.textSecondary)
            }

            // Tagline
            Text("彻底卸载，不留痕迹")
                .font(.body)
                .foregroundColor(.textSecondary)

            Divider()
                .frame(width: 200)

            // Privacy commitment — mirrors the onboarding privacy page and the
            // App Store "Data Not Collected" label.
            Text("零网络请求 · 全部本地计算 · 不收集任何数据")
                .font(.caption)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)

            // Copyright
            Text("Copyright © 2026 Kraftly. All rights reserved.")
                .font(.caption)
                .foregroundColor(.textSecondary)

            // Close button
            Button("关闭") {
                dismiss()
            }
            .buttonStyle(.brand)
            .controlSize(.small)
            .padding(.top, 8)
        }
        .padding(40)
        .frame(width: 360)
        .background(Color.bgPrimary)
        .cornerRadius(16)
    }
}
