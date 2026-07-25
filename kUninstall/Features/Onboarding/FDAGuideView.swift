import SwiftUI

struct FDAGuideView: View {
    var onSkip: (() -> Void)?
    var onContinue: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("让 kUninstall 彻底清理 App 残留")
                .font(.title)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 12) {
                GuideStep(number: 1, text: "打开「系统设置 → 隐私与安全性 → 全盘访问权限」")
                GuideStep(number: 2, text: "点击锁图标解锁")
                GuideStep(number: 3, text: "找到 kUninstall 并开启开关")
                GuideStep(number: 4, text: "返回 kUninstall 继续")
            }

            HStack(spacing: 12) {
                Button("跳过") {
                    onSkip?()
                }
                .buttonStyle(.bordered)

                Button("打开系统设置") {
                    FDAuthorizer().requestFDA()
                }
                .buttonStyle(.borderedProminent)

                Button("已授权，继续") {
                    onContinue?()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(40)
        .frame(width: 500)
    }
}

struct GuideStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 14, weight: .bold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))
                .foregroundColor(.white)
            Text(text)
                .font(.body)
        }
    }
}
