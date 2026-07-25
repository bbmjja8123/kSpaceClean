import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }

            aboutTab
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 450, height: 300)
    }

    private var generalTab: some View {
        Form {
            Toggle("启动时自动扫描", isOn: $viewModel.autoScan)

            HStack {
                Text("备份保留天数")
                Spacer()
                Picker("", selection: $viewModel.backupRetentionDays) {
                    Text("7 天").tag(7)
                    Text("14 天").tag(14)
                    Text("30 天").tag(30)
                }
                .labelsHidden()
            }

            Divider()

            HStack {
                Text("FDA 状态")
                Spacer()
                if viewModel.hasFDA {
                    Label("已授权", systemImage: "checkmark.shield.fill")
                        .foregroundColor(.green)
                } else {
                    Button("授权全盘访问") {
                        viewModel.requestFDA()
                    }
                }
            }

            Divider()

            HStack {
                Text("Pro 状态")
                Spacer()
                if viewModel.isPro {
                    Label("已解锁", systemImage: "crown.fill")
                        .foregroundColor(.orange)
                } else {
                    Button("升级 Pro") {
                        viewModel.showPaywall()
                    }
                }
            }
        }
        .padding()
    }

    private var aboutTab: some View {
        VStack(spacing: 12) {
            Text("kUninstall")
                .font(.title)
                .fontWeight(.bold)
            Text("版本 1.0.0")
                .foregroundColor(.secondary)
            Text("Kraftly — Cleaner Mac tools, made with care.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}
