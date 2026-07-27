import SwiftUI
import DesignSystem

/// Main view for the maintenance tools feature.
///
/// Displays a grid of available maintenance scripts. Each card shows
/// an icon, name, description, and a "Run" button. While a script is
/// executing a `ProgressView` is shown. Completed results auto-dismiss
/// after 5 seconds.
public struct MaintenanceView: View {
    @StateObject private var viewModel = MaintenanceViewModel()

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                header
                scriptGrid
            }
            .padding(AppSpacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgPrimary)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text("维护工具")
                .font(AppFont.title2)
                .foregroundColor(.textPrimary)

            Text("运行系统维护脚本以修复常见问题")
                .font(AppFont.callout)
                .foregroundColor(.textSecondary)
        }
    }

    // MARK: - Script Grid

    private var scriptGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: AppSpacing.lg),
                GridItem(.flexible(), spacing: AppSpacing.lg),
            ],
            spacing: AppSpacing.lg
        ) {
            ForEach(MaintenanceScript.allCases) { script in
                MaintenanceCard(script: script, viewModel: viewModel)
            }
        }
    }
}

// MARK: - Maintenance Card

private struct MaintenanceCard: View {
    let script: MaintenanceScript
    @ObservedObject var viewModel: MaintenanceViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            headerRow
            descriptionText
            Spacer()
            actionArea
        }
        .padding(AppSpacing.lg)
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(Color.bgSecondary)
        .cornerRadius(AppRadius.lg)
        .task(id: viewModel.results[script.id]) {
            await autoClearResult()
        }
    }

    // MARK: - Subviews

    private var headerRow: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: script.icon)
                .font(.title3)
                .foregroundColor(.brandPrimary)

            Text(script.rawValue)
                .font(AppFont.title3)
                .foregroundColor(.textPrimary)
        }
    }

    private var descriptionText: some View {
        Text(script.detail)
            .font(AppFont.callout)
            .foregroundColor(.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var actionArea: some View {
        if viewModel.runningScript == script.id {
            runningIndicator
        } else if let result = viewModel.results[script.id] {
            completionIndicator(result: result)
        } else {
            runButton
        }
    }

    private var runningIndicator: some View {
        HStack(spacing: AppSpacing.sm) {
            ProgressView()
                .controlSize(.small)
            Text("运行中...")
                .font(AppFont.caption)
                .foregroundColor(.textSecondary)
        }
    }

    private func completionIndicator(result: String) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "checkmark.circle")
                .foregroundColor(.success)
            Text(result)
                .font(AppFont.caption)
                .foregroundColor(.success)
                .lineLimit(2)
        }
    }

    private var runButton: some View {
        Button("运行") {
            Task {
                await viewModel.execute(script)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(viewModel.isRunning)
    }

    // MARK: - Auto-Clear

    /// Waits 5 seconds then removes the result for this script,
    /// so the card returns to its idle state automatically.
    private func autoClearResult() async {
        guard viewModel.results[script.id] != nil else { return }
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        guard !Task.isCancelled else { return }
        await MainActor.run {
            viewModel.clearResult(for: script.id)
        }
    }
}
