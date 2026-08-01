import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel

    /// - Parameter viewModel: Injected by ``RootView`` so the view can reach
    ///   ``AppCoordinator`` for the paywall sheet (C3).
    init(viewModel: SettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }

            aboutTab
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 450, height: 300)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await viewModel.refreshFDAStatus() }
        }
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
                switch viewModel.fdaStatus {
                case .full:
                    Label("已授权", systemImage: "checkmark.shield.fill")
                        .foregroundColor(.success)
                case .basic, .unknown:
                    Button("授权全盘访问") {
                        viewModel.requestFDA()
                    }
                }
            }
            .task { await viewModel.refreshFDAStatus() }

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
            Image(systemName: "trash.square.fill")
                .font(.system(size: 48))
                .foregroundColor(.brandPrimary)
                .symbolRenderingMode(.hierarchical)

            Text("kFresh")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.textPrimary)
            Text("版本 1.0.0")
                .foregroundColor(.textSecondary)
            Text("Kraftly — Cleaner Mac tools, made with care.")
                .font(.caption)
                .foregroundColor(.textSecondary)

            Divider()
                .frame(width: 200)

            Text("详细关于信息请点击菜单栏 → kFresh → 关于 kFresh")
                .font(.caption)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
