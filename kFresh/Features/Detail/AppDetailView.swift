import SwiftUI

/// Detail pane of the `NavigationSplitView`: hero, size overview, residue
/// list, Pro-locked entries, and the uninstall entry point.
struct AppDetailView: View {
    @EnvironmentObject private var services: AppServices
    @StateObject private var viewModel: DetailViewModel
    @State private var showConfirmSheet = false
    @State private var undoToast: UninstallToast.State?
    @State private var showDeepClean = false
    @State private var showStartupItems = false
    @State private var restoreError: String?
    /// Latest dry-run report produced by tapping the "模拟卸载" button.
    /// When non-nil, the dry-run alert is presented.
    @State private var dryRunReport: DryRunReport?

    /// Creates the detail view for `app`. The displayed size comes from the
    /// `sizeBytes` parameter so a freshly measured value can flow in without
    /// reconstructing the detail viewmodel (which would re-run the safety
    /// check and residue scan).
    ///
    /// - Parameter mover: The shared ``TrashMover`` from ``AppServices``
    ///   (C1). Threaded through ``AppListView.detailPane`` so the detail
    ///   pane's uninstall writes into the same history repository the
    ///   History tab and undo-toast restore read from.
    init(app: InstalledApp, mover: TrashMover, sizeBytes: Int64) {
        _viewModel = StateObject(wrappedValue: DetailViewModel(
            app: app,
            residueDetector: ResidueDetector(ruleStore: BundleRuleStore.loadFromBundledJSON()),
            mover: mover
        ))
        _sizeBytes = State(initialValue: sizeBytes)
    }

    /// Size to render in the "占用" row. Decoupled from ``viewModel.app``
    /// so the background size pass can update it without rebuilding the
    /// detail viewmodel.
    @State private var sizeBytes: Int64

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                hero
                Divider()
                sizeOverview
                Divider()
                ResidueSectionView(
                    residues: viewModel.residues,
                    isLoading: viewModel.isResidueScanRunning
                )
                Divider()
                proEntries
            }
            .padding(AppSpacing.lg)
        }
        .navigationTitle(viewModel.app.displayName)
        .task { await viewModel.performSafetyCheck() }
        .safeAreaInset(edge: .bottom) {
            if viewModel.canUninstall {
                VStack(spacing: AppSpacing.sm) {
                    Button {
                        runDryUninstall()
                    } label: {
                        Label("模拟卸载", systemImage: "eye")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showConfirmSheet = true
                    } label: {
                        Text("卸载 \(viewModel.app.displayName)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.destructive)
                }
                .padding(AppSpacing.md)
            }
        }
        .sheet(isPresented: $showConfirmSheet) {
            UninstallConfirmSheet(
                app: viewModel.app,
                residues: viewModel.residues,
                onConfirm: { selectedResidues in
                    handleUninstall(selectedResidues: selectedResidues)
                },
                onCancel: { showConfirmSheet = false }
            )
        }
        .sheet(isPresented: $showDeepClean) {
            DeepCleanView()
        }
        .sheet(isPresented: $showStartupItems) {
            StartupItemsView(viewModel: StartupItemsViewModel(manager: StartupItemManager()))
        }
        .alert(
            "恢复失败",
            isPresented: Binding(
                get: { restoreError != nil },
                set: { if !$0 { restoreError = nil } }
            )
        ) {
            Button("好", role: .cancel) { restoreError = nil }
        } message: {
            Text(restoreError ?? "")
        }
        .alert(
            "预览卸载",
            isPresented: Binding(
                get: { dryRunReport != nil },
                set: { if !$0 { dryRunReport = nil } }
            ),
            presenting: dryRunReport
        ) { _ in
            Button("好", role: .cancel) { dryRunReport = nil }
        } message: { report in
            Text(dryRunSummary(for: report))
        }
        .overlay(alignment: .bottom) {
            if let toast = undoToast {
                UninstallToast(state: toast) {
                    handleRestore()
                }
            }
        }
    }

    // MARK: - Sections

    private var hero: some View {
        HStack(spacing: AppSpacing.md) {
            Image(nsImage: viewModel.app.icon)
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(viewModel.app.displayName)
                    .font(AppFont.title2)
                Text("v\(viewModel.app.version)")
                    .font(AppFont.callout)
                    .foregroundStyle(Color.textSecondary)
                Text(viewModel.app.source.displayName)
                    .font(AppFont.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(viewModel.app.source.tint.opacity(0.15))
                    .foregroundStyle(viewModel.app.source.tint)
                    .clipShape(Capsule())
            }
            Spacer()
        }
    }

    private var sizeOverview: some View {
        HStack {
            Text("占用")
                .font(AppFont.body)
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file))
                .font(AppFont.body.monospacedDigit())
        }
    }

    /// Pro-locked feature rows, gated by the app-wide ``StoreManager``. When
    /// the user is Pro, tapping a row opens the matching sheet (C3); when
    /// locked, ``ProGateModifier`` blurs the row and overlays the paywall
    /// call-to-action, and the `.onTapGesture` no-ops because
    /// `store.state != .pro`.
    private var proEntries: some View {
        VStack(spacing: AppSpacing.sm) {
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Color.warning)
                Text("深度清理（Pro）")
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding()
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .onTapGesture {
                if services.store.state == .pro { showDeepClean = true }
            }
            .proGate(store: services.store)

            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Color.warning)
                Text("启动项管理（Pro）")
                    .foregroundStyle(Color.textSecondary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(AppFont.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding()
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .onTapGesture {
                if services.store.state == .pro { showStartupItems = true }
            }
            .proGate(store: services.store)
        }
    }

    // MARK: - Actions

    /// Dismisses the confirm sheet and drives the shared mover with the exact
    /// residue subset the user approved in the 4-level sheet. An empty array
    /// means "uninstall the app body only" (every residue bucket unchecked).
    private func handleUninstall(selectedResidues: [ResidueFile]) {
        showConfirmSheet = false
        // Compute the headline "已释放 X" total up front — the toast needs
        // it for the Wave 2 P1 (G-KF-04) payoff readout. App body + sum of
        // approved residue sizes, matching the v1.x-B UninstallConfirmSheet
        // totalFreedSize math. We snapshot here rather than re-deriving
        // inside the Task because view state must be set synchronously
        // for the bounce animation to start cleanly on the main actor.
        let residueTotal = selectedResidues.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let totalFreedBytes = sizeBytes + residueTotal
        let snapshotAppName = viewModel.app.displayName
        let snapshotSizeBytes = sizeBytes
        Task {
            let outcome = await viewModel.confirmUninstall(selectedResidues: selectedResidues)
            if case .success(let record) = outcome {
                withAnimation(.easeInOut(duration: KFAnimation.durationNormal)) {
                    undoToast = UninstallToast.State(
                        recordID: record.id,
                        appName: snapshotAppName,
                        appSize: snapshotSizeBytes,
                        totalFreedBytes: totalFreedBytes
                    )
                }
            }
            // `.failure` and `nil` outcomes: surface to UI is Wave 1.1 polish.
        }
    }

    /// Restores the just-uninstalled app from the undo toast.
    ///
    /// C2: previously a no-op that only dismissed the toast. Now looks the
    /// record up by the toast's `recordID` through the shared mover, drives
    /// `restore(record:)`, dismisses the toast on success, and surfaces the
    /// ``TrashError`` via the `restoreError` alert on failure (the toast is
    /// dismissed either way so it cannot be re-triggered mid-restore).
    private func handleRestore() {
        guard let toast = undoToast else { return }
        undoToast = nil
        Task {
            guard let record = await viewModel.historyRecord(id: toast.recordID) else {
                restoreError = "未找到该卸载记录，无法恢复"
                return
            }
            let result = await viewModel.restore(record: record)
            if case .failure(let error) = result {
                restoreError = error.localizedDescription
            }
        }
    }

    /// Runs ``TrashMover/dryRun(app:residues:)`` against the current app
    /// and current residue set, then surfaces the report in an alert. The
    /// dry-run never touches the file system; the user can review the
    /// "what would happen" before tapping the real destructive button.
    private func runDryUninstall() {
        dryRunReport = services.mover.dryRun(
            app: viewModel.app,
            residues: viewModel.residues
        )
    }

    /// Builds the alert body for the dry-run preview. Kept file-local so
    /// the message text and risk-bucket wording stay aligned with
    /// ``UninstallConfirmSheet``'s 4-level display.
    private func dryRunSummary(for report: DryRunReport) -> String {
        let bytes = ByteCountFormatter.string(fromByteCount: report.totalFreedBytes, countStyle: .file)
        var lines: [String] = []
        lines.append("将释放 \(bytes)")
        let groups = report.residuesByRisk.filter { !$0.items.isEmpty }
        if groups.isEmpty {
            lines.append("未发现残留文件")
        } else {
            for (level, items) in groups {
                let itemBytes = items.reduce(0) { $0 + $1.sizeBytes }
                let pretty = ByteCountFormatter.string(fromByteCount: itemBytes, countStyle: .file)
                lines.append("\(level.sectionTitle)：\(items.count) 项 · \(pretty)")
            }
        }
        lines.append("备份将写入 \(report.backupRoot.path)")
        return lines.joined(separator: "\n")
    }
}
