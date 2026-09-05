import SwiftUI
import DesignSystem
import PowerScope

struct SettingsView: View {
    @State private var prefs = UserPreferences.load()
    @ObservedObject private var appScope = AppScope.shared

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text("\u{8BBE}\u{7F6E}")
                .font(AppFont.title2)
                .foregroundColor(.textPrimary)

            Form {
                Section("文件访问") {
                    scopeRow
                }

                Section("\u{901A}\u{7528}") {
                    Toggle("\u{542F}\u{52A8}\u{65F6}\u{81EA}\u{52A8}\u{626B}\u{63CF}", isOn: $prefs.launchAtLogin)
                    Toggle("\u{83DC}\u{5355}\u{680F}\u{663E}\u{793A}\u{78C1}\u{76D8}\u{5360}\u{7528}", isOn: $prefs.showMenuBarDiskUsage)
                    Toggle("\u{6E05}\u{7406}\u{540E}\u{901A}\u{77E5}", isOn: .constant(true))
                }

                Section("\u{626B}\u{63CF}") {
                    Picker("\u{626B}\u{63CF}\u{901F}\u{5EA6}", selection: $prefs.scanSpeed) {
                        ForEach(ScanSpeed.allCases, id: \.self) { speed in
                            VStack(alignment: .leading) {
                                Text(speed.displayName).tag(speed)
                                Text(speed.description)
                                    .font(AppFont.caption)
                                    .foregroundColor(.textSecondary)
                            }
                            .tag(speed)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("\u{5927}\u{6587}\u{4EF6}\u{9608}\u{503C}", selection: $prefs.largeFileThreshold) {
                        Text("50 MB").tag(Int64(50_000_000))
                        Text("100 MB").tag(Int64(100_000_000))
                        Text("500 MB").tag(Int64(500_000_000))
                        Text("1 GB").tag(Int64(1_000_000_000))
                    }
                    Toggle("AI \u{5206}\u{7C7B}\u{542F}\u{7528}", isOn: $prefs.aiClassificationEnabled)
                }

                Section("\u{8BA2}\u{9605}") {
                    Text("\u{5F53}\u{524D}: Pro")
                        .font(AppFont.body)
                        .foregroundColor(.textPrimary)
                    Button("\u{7BA1}\u{7406}\u{8BA2}\u{9605}") { /* open App Store */ }
                }
            }
            .formStyle(.grouped)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - File Access (PowerScope)

    /// Honest scope row: what kWise can read right now, plus grant/revoke.
    @ViewBuilder
    private var scopeRow: some View {
        switch appScope.capability.level {
        case .homeGranted:
            LabeledContent {
                Button("撤销授权", role: .destructive) {
                    Task { await appScope.revoke() }
                }
            } label: {
                Text("已授权主目录")
                Text("kWise 可以扫描家目录下的缓存、日志与应用残留。")
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
            }
        case .containerOnly:
            LabeledContent {
                Button("授权主目录") {
                    Task { await appScope.grant() }
                }
                .buttonStyle(.borderedProminent)
            } label: {
                Text("仅容器访问")
                Text("授权主目录后，kWise 才能发现并清理大部分垃圾文件。")
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
            }
        }
    }
}
