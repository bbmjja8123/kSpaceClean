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

    /// - Parameter mover: The shared ``TrashMover`` from ``AppServices``
    ///   (C1). Threaded through ``AppListView.detailPane`` so the detail
    ///   pane's uninstall writes into the same history repository the
    ///   History tab and undo-toast restore read from.
    init(app: InstalledApp, mover: TrashMover) {
        _viewModel = StateObject(wrappedValue: DetailViewModel(
            app: app,
            residueDetector: ResidueDetector(ruleStore: BundleRuleStore.loadFromBundledJSON()),
            mover: mover
        ))
    }

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
                Button {
                    showConfirmSheet = true
                } label: {
                    Text("卸载 \(viewModel.app.displayName)")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.destructive)
                .padding(AppSpacing.md)
            }
        }
        .sheet(isPresented: $showConfirmSheet) {
            UninstallConfirmSheet(
                app: viewModel.app,
                residues: viewModel.residues,
                onConfirm: { includeResidues in
                    handleUninstall(includeResidues: includeResidues)
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
            Text(viewModel.app.sizeFormatted)
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

    /// Dismisses the confirm sheet and drives the shared mover, honouring the
    /// sheet's residue toggle (I1): when the user unchecks "残留文件", the
    /// trash operation only touches the app bundle.
    private func handleUninstall(includeResidues: Bool) {
        showConfirmSheet = false
        Task {
            let outcome = await viewModel.confirmUninstall(includeResidues: includeResidues)
            if case .success(let record) = outcome {
                withAnimation(.easeInOut(duration: KFAnimation.durationNormal)) {
                    undoToast = UninstallToast.State(
                        recordID: record.id,
                        appName: viewModel.app.displayName,
                        appSize: viewModel.app.sizeBytes
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
}
