import SwiftUI
import MetricsKit

/// The process ranking screen, showing top processes sorted by CPU, memory,
/// or network usage.
///
/// Free users see up to 5 processes with CPU/memory sort only. Pro users see
/// up to 50 processes, full sort options, and a live search filter.
/// Loading, error, and empty states are handled explicitly.
public struct ProcessesView: View {
    @ObservedObject private var viewModel: ProcessesViewModel
    private let onBack: (() -> Void)?
    private let onOpenPaywall: (() -> Void)?

    public init(
        viewModel: ProcessesViewModel,
        onBack: (() -> Void)? = nil,
        onOpenPaywall: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onBack = onBack
        self.onOpenPaywall = onOpenPaywall
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: Top bar
            topBar
                .padding(.horizontal)
                .padding(.top, 8)

            // MARK: Search bar (Pro only)
            if viewModel.isPro {
                searchBar
                    .padding(.horizontal)
                    .padding(.top, 8)
            }

            Divider()
                .padding(.top, 8)

            // MARK: Content
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await viewModel.refresh() }
        .onChange(of: viewModel.selectedSort) { _ in
            Task { await viewModel.refresh() }
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                onBack?()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("Dashboard")
                }
            }
            .buttonStyle(.plain)
            .help("Return to Dashboard")

            Spacer()

            Text("Processes")
                .font(.headline)
                .foregroundStyle(.secondary)

            Spacer()

            Picker("Sort", selection: $viewModel.selectedSort) {
                ForEach(viewModel.availableSorts, id: \.self) { sort in
                    Text(sortLabel(sort)).tag(sort)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
        }
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search processes\u{2026}", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(.callout)
                .onChange(of: viewModel.searchQuery) { _ in
                    Task { await viewModel.refresh() }
                }

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.background)
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.separator, lineWidth: 1)
                }
        )
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading {
            loadingView
        } else if let errorMessage = viewModel.errorMessage {
            errorView(message: errorMessage)
        } else if viewModel.isEmpty {
            emptyView
        } else {
            dataView
        }
    }

    // MARK: Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading processes\u{2026}")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: Error

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)

            Text("Failed to Load Processes")
                .font(.headline)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Retry") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.borderedProminent)

            Spacer()
        }
    }

    // MARK: Empty

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()

            Image(systemName: "tray")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)

            Text("No Processes")
                .font(.headline)

            Text("No processes found. Try adjusting the sort or search criteria.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
    }

    // MARK: Data view (table)

    private var dataView: some View {
        VStack(spacing: 0) {
            // Table header
            tableHeader
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

            Divider()

            // Process rows
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.rows) { row in
                        ProcessRowView(viewModel: row)
                            .padding(.horizontal, 8)
                        Divider()
                    }
                }
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 8) {
            Text("Name")
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("PID")
                .frame(width: 50, alignment: .trailing)

            Text("CPU")
                .frame(width: 50, alignment: .trailing)

            Text("Memory")
                .frame(width: 80, alignment: .trailing)

            Text("Network")
                .frame(width: 90, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    // MARK: - Helpers

    private func sortLabel(_ sort: ProcessSort) -> String {
        switch sort {
        case .cpu:     return "CPU"
        case .memory:  return "Memory"
        case .network: return "Network"
        }
    }
}

// MARK: - Preview

#Preview("Processes with data") {
    let purchaseState = PurchaseState()
    purchaseState.update(isPro: true)

    let vm = ProcessesViewModel(
        processMonitor: nil,
        purchaseState: purchaseState
    )
    ProcessesView(viewModel: vm)
        .frame(width: 700, height: 500)
}

#Preview("Processes free") {
    let vm = ProcessesViewModel(
        processMonitor: nil,
        purchaseState: PurchaseState()
    )
    ProcessesView(viewModel: vm)
        .frame(width: 700, height: 500)
}
