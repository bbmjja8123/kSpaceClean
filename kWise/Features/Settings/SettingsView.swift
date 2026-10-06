import SwiftUI
import DesignSystem
import PowerScope
import UserNotifications
import DetectionCore
import CommonUtils

struct SettingsView: View {
    @State private var prefs = UserPreferences.load()
    @ObservedObject private var appScope = AppScope.shared
    /// Injected graph services (v2.0 Phase 1): one `StoreManager`, real
    /// `LoginItemService` — the old toggle had no implementation behind it.
    @Environment(\.appGraph) private var injectedGraph
    @StateObject private var loginItemService = LoginItemService()
    @State private var subscriptionStatusChecked = false

    /// P2 T8 — 设置吸收：维护 / 隐私 / 归因规则三区迁入。
    /// 维护 VM 走 graph 缓存装配（与旧 `.maintenance` 页同一份常驻 VM，
    /// 引擎 + 配额路由复用）；隐私清理 VM 就地扫描浏览器痕迹；归因规则
    /// 复用 P0 规则清单组件（AttributionRulesView，corpus 从 bundle 读）。
    @State private var maintenanceVM: MaintenanceViewModel?
    @StateObject private var privacyVM = PrivacyViewModel()
    @State private var rulesCorpus: AttributionRuleCorpus?
    @State private var showRulesSheet = false
    @State private var showPaywallSheet = false

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

                // P2 T8 — 设置吸收三区。旧 `.privacy` / `.maintenance` 独立页
                // 在 W4 退役前仍可达；这里的区是吸收后的长期归宿。
                Section("维护") {
                    maintenanceSection
                }

                Section("隐私") {
                    privacySection
                }

                Section("归因规则") {
                    rulesSection
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
            // 维护 VM：graph 缓存装配（引擎已接线），配额超限弹买断墙。
            if maintenanceVM == nil {
                maintenanceVM = graph.maintenanceVM { showPaywallSheet = true }
            }
            // 归因规则语料：与 AnatomyView 的 rulesLink 同源（bundle JSON）。
            if rulesCorpus == nil {
                rulesCorpus = Bundle.main.url(forResource: "attribution_rules",
                                              withExtension: "json")
                    .flatMap { try? Data(contentsOf: $0) }
                    .flatMap { try? AttributionRuleCorpus.load(from: $0) }
            }
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
        // 归因规则清单 sheet（P0 组件复用；corpus 加载失败时不渲染入口，
        // 不出空 sheet）。
        .background(
            Color.clear
                .sheet(isPresented: $showRulesSheet) {
                    if let corpus = rulesCorpus {
                        AttributionRulesView(corpus: corpus)
                            .frame(minWidth: 560, minHeight: 420)
                    }
                }
        )
        // 维护「清理用户日志」免费额度用尽 → 买断墙（与其他清理面同一路由）。
        .background(
            Color.clear
                .sheet(isPresented: $showPaywallSheet) {
                    PaywallView(store: graph.storeManager)
                }
        )
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

    // MARK: - 维护区（P2 T8 吸收自旧 MaintenanceView）

    /// 每张维护任务一行：引导任务给「复制终端命令」，引擎任务
    /// （清理用户日志）给真实清理按钮 —— VM 与引导文案全部复用，
    /// 沙箱诚实说明随行（C-5）。
    @ViewBuilder
    private var maintenanceSection: some View {
        if let vm = maintenanceVM {
            ForEach(MaintenanceTask.allCases) { task in
                maintenanceRow(task, viewModel: vm)
            }
        }
    }

    @ViewBuilder
    private func maintenanceRow(
        _ task: MaintenanceTask,
        viewModel vm: MaintenanceViewModel
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: task.icon)
                    .font(.system(size: 14))
                    .foregroundColor(.brandPrimary)

                Text(task.rawValue)
                    .font(AppFont.body)
                    .foregroundColor(.textPrimary)

                Spacer()

                maintenanceAction(task, viewModel: vm)
            }

            Text(task.detail)
                .font(AppFont.caption)
                .foregroundColor(.textSecondary)

            if let result = vm.results[task.id] {
                Text(result)
                    .font(AppFont.caption)
                    .foregroundColor(.success)
            }

            Text(task.sandboxNote)
                .font(AppFont.caption)
                .foregroundColor(.textSecondary)
        }
        .padding(.vertical, AppSpacing.xs)
    }

    @ViewBuilder
    private func maintenanceAction(
        _ task: MaintenanceTask,
        viewModel vm: MaintenanceViewModel
    ) -> some View {
        if vm.runningTask == task.id {
            HStack(spacing: AppSpacing.xs) {
                ProgressView()
                    .controlSize(.small)
                Text("运行中...")
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
            }
        } else if task.isEngineBacked {
            Button("清理") {
                Task { await vm.execute(task) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(vm.isRunning)
        } else {
            Button(vm.copiedCommands.contains(task.id) ? "已复制 ✓" : "复制终端命令") {
                vm.copyCommand(for: task)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - 隐私区（P2 T8 吸收自旧 PrivacyView / PrivacyClean）

    /// 入口：扫描浏览器痕迹 → 分类结果（逐项可勾选）→ 汇总行清理。
    /// 扫描、勾选与清理全部走既有 `PrivacyViewModel`（PrivacyScanner
    /// 不变）；登录态（Cookie）选中时的后果说明保留。
    @ViewBuilder
    private var privacySection: some View {
        if privacyVM.isScanning {
            HStack(spacing: AppSpacing.sm) {
                ProgressView()
                    .controlSize(.small)
                Text("正在扫描浏览器痕迹...")
                    .font(AppFont.body)
                    .foregroundColor(.textSecondary)
            }
        } else if privacyVM.items.isEmpty {
            LabeledContent {
                Button("扫描") { privacyVM.startScan() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            } label: {
                Text("浏览器痕迹")
                Text("扫描浏览器历史、Cookie、缓存与过期系统日志，全部在本机完成。")
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
            }
        } else {
            privacyResults
        }
    }

    @ViewBuilder
    private var privacyResults: some View {
        ForEach(privacyVM.itemsByCategory, id: \.0) { category, items in
            privacyCategoryHeader(category, count: items.count)
            ForEach(items) { item in
                privacyItemRow(item)
            }
        }
        privacySummaryRow
    }

    private func privacyCategoryHeader(
        _ category: PrivacyItem.PrivacyCategory,
        count: Int
    ) -> some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: category.icon)
                .font(.system(size: 12))
                .foregroundColor(.textSecondary)
            Text(category.rawValue)
                .font(AppFont.caption)
                .foregroundColor(.textSecondary)
            Text("\(count) 项")
                .font(AppFont.caption)
                .foregroundColor(.textSecondary)
            Spacer()
        }
        .padding(.top, AppSpacing.xs)
    }

    private func privacyItemRow(_ item: PrivacyItem) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Toggle(isOn: Binding(
                get: { item.isSelected },
                set: { _ in privacyVM.toggleSelection(item.id) }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .disabled(privacyVM.isCleaning)

            Text(item.name)
                .font(AppFont.body)
                .foregroundColor(.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text(FileSizeFormatter.abbreviated(from: item.estimatedSize))
                .font(AppFont.monoDigit)
                .foregroundColor(.textSecondary)
        }
    }

    private var privacySummaryRow: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.sm) {
                Text("已选 \(privacyVM.selectedItems.count) 项 · 可释放 \(FileSizeFormatter.abbreviated(from: privacyVM.selectedSize))")
                    .font(AppFont.callout)
                    .foregroundColor(.textPrimary)

                Spacer()

                Button("重新扫描") { privacyVM.startScan() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(privacyVM.isCleaning)

                Button(privacyVM.isCleaning ? "清理中..." : "清理已选") {
                    Task { await privacyVM.cleanupSelected() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.danger)
                .controlSize(.small)
                .disabled(privacyVM.selectedItems.isEmpty || privacyVM.isCleaning)
            }

            // C-5：登录态分级确认 — 选中 Cookie 时必须看到后果说明。
            if privacyVM.selectedItems.contains(where: \.isLoginState) {
                Text("包含 Cookie：清理后将退出这些网站的登录状态")
                    .font(AppFont.caption)
                    .foregroundColor(.warning)
            }

            if let message = privacyVM.statusMessage {
                Text(message)
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
            }
        }
        .padding(.vertical, AppSpacing.xs)
    }

    // MARK: - 归因规则区（P2 T8 复用 P0 规则清单组件）

    /// 规则开放：一条链接行 → `AttributionRulesView`（sheet 呈现，与主画布
    /// 「+」菜单的规则入口同一组件、同一 corpus 来源）。
    @ViewBuilder
    private var rulesSection: some View {
        if rulesCorpus != nil {
            LabeledContent {
                Button("查看") { showRulesSheet = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } label: {
                Text("归因规则清单")
                Text("逐条查看每条归因判断依据的规则：匹配路径、归属与回收方式。")
                    .font(AppFont.caption)
                    .foregroundColor(.textSecondary)
            }
        }
    }
}
