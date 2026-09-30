import SwiftUI
import DesignSystem
import PowerScope
import UserNotifications
import DetectionCore

struct SettingsView: View {
    @State private var prefs = UserPreferences.load()
    @ObservedObject private var appScope = AppScope.shared
    /// Injected graph services (v2.0 Phase 1): one `StoreManager`, real
    /// `LoginItemService` — the old toggle had no implementation behind it.
    @Environment(\.appGraph) private var injectedGraph
    @StateObject private var loginItemService = LoginItemService()
    @State private var subscriptionStatusChecked = false

    private var graph: AppGraph { injectedGraph ?? AppGraph() }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            Text("设置")
                .font(AppFont.title2)
                .foregroundColor(.textPrimary)

            Form {
                Section("文件访问") {
                    scopeRow
                }

                Section("通用") {
                    Toggle("登录时启动 kWise", isOn: launchAtLoginBinding)
                    Toggle("菜单栏显示磁盘占用", isOn: $prefs.showMenuBarDiskUsage)
                    Toggle("清理后通知", isOn: $prefs.notifyAfterCleanup)
                }

                Section("扫描") {
                    Picker("扫描速度", selection: $prefs.scanSpeed) {
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

                    Picker("大文件阈值", selection: $prefs.largeFileThreshold) {
                        Text("50 MB").tag(Int64(50_000_000))
                        Text("100 MB").tag(Int64(100_000_000))
                        Text("500 MB").tag(Int64(500_000_000))
                        Text("1 GB").tag(Int64(1_000_000_000))
                    }
                    // C-5 honesty: there is no CoreML model in the bundle —
                    // classification is the local rule engine. The old
                    // "AI 分类启用" label was a lie.
                    Toggle("智能推荐（本机规则）", isOn: $prefs.aiClassificationEnabled)

                    Picker("相似照片灵敏度", selection: $prefs.similarityPresetRaw) {
                        Text("严格（仅几乎相同）").tag(SimilarityPreset.strict.rawValue)
                        Text("标准").tag(SimilarityPreset.normal.rawValue)
                        Text("宽松（找出更多）").tag(SimilarityPreset.loose.rawValue)
                    }
                    .pickerStyle(.menu)
                    .onChange(of: prefs.similarityPresetRaw) { _ in
                        prefs.save()
                    }
                }

                Section("解锁") {
                    subscriptionRow
                }
            }
            .formStyle(.grouped)
            .onChange(of: prefs) { newValue in
                newValue.save()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loginItemService.refreshStatus()
            Task { await graph.storeManager.checkSubscription() }
        }
        .alert(
            "登录项设置失败",
            isPresented: Binding(
                get: { loginItemService.lastError != nil },
                set: { if !$0 { loginItemService.acknowledgeError() } }
            )
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text(loginItemService.lastError ?? "")
        }
        // 清理后通知 — turning the toggle on is the moment we ask for
        // permission (never a prompt at first launch).
        .onChange(of: prefs.notifyAfterCleanup) { enabled in
            if enabled {
                CleanupNotificationSink.requestAuthorization()
            }
        }
    }

    // MARK: - Launch at login (SMAppService)

    /// Two-way binding: toggle → `LoginItemService`, system status → toggle.
    /// The published `isEnabled` is refreshed from SMAppService after every
    /// transition, so a failed register/unregister snaps the toggle back.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { loginItemService.isEnabled },
            set: { newValue in
                loginItemService.setEnabled(newValue)
                prefs.launchAtLogin = loginItemService.isEnabled
            }
        )
    }

    // MARK: - Buyout unlock (single StoreManager)

    @ViewBuilder
    private var subscriptionRow: some View {
        let store = graph.storeManager
        LabeledContent {
            if store.hasPurchased {
                Text("已解锁")
                    .foregroundColor(.success)
            } else {
                Button("恢复购买") {
                    Task { await store.restorePurchases() }
                }
            }
        } label: {
            Text(store.hasPurchased ? "当前: 买断版" : "当前: 免费版")
            Text("扫描、归因、拒答清单永久免费；回收动作一次买断解锁。")
                .font(AppFont.caption)
                .foregroundColor(.textSecondary)
        }
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
