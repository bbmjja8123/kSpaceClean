import SwiftUI

/// Detail pane of the `NavigationSplitView`: hero, size overview, residue
/// list, Pro-locked entries, and the uninstall entry point.
struct AppDetailView: View {
    @StateObject private var viewModel: DetailViewModel
    @State private var showConfirmSheet = false
    @State private var undoToast: UninstallToast.State?

    init(app: InstalledApp) {
        _viewModel = StateObject(wrappedValue: DetailViewModel(
            app: app,
            residueDetector: ResidueDetector(ruleStore: BundleRuleStore.loadFromBundledJSON())
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
                onConfirm: { handleUninstall() },
                onCancel: { showConfirmSheet = false }
            )
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

    /// Pro-locked feature rows. Task 8 swaps the no-op `.proGate()` for the
    /// real paywall-gated modifier.
    private var proEntries: some View {
        VStack(spacing: AppSpacing.sm) {
            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Color.warning)
                Text("深度清理（Pro）")
                    .foregroundStyle(Color.textSecondary)
                Spacer()
            }
            .padding()
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .proGate()

            HStack {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Color.warning)
                Text("启动项管理（Pro）")
                    .foregroundStyle(Color.textSecondary)
                Spacer()
            }
            .padding()
            .background(Color.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .proGate()
        }
    }

    // MARK: - Actions

    private func handleUninstall() {
        showConfirmSheet = false
        Task {
            let outcome = await viewModel.confirmUninstall()
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

    /// Placeholder restore: dismisses the toast. Task 4 looks the record up
    /// by `recordID` and drives `TrashMover.restore(record:)`.
    private func handleRestore() {
        undoToast = nil
    }
}
