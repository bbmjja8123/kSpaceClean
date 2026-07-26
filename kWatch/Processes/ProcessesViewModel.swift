import Foundation
import Combine
import MetricsKit

// MARK: - ProcessRowViewModel

/// Formatted display data for a single process row.
///
/// All text formatting is performed eagerly from the raw `ProcessInfoSnapshot`
/// so that views never contain formatting logic.
public struct ProcessRowViewModel: Identifiable, Equatable {
    // MARK: Identity

    /// Stable row identity derived from the process PID.
    public let id: Int32

    // MARK: Raw values (used for sort, not display)

    public let pid: Int32
    public let cpuPercent: Double
    public let memoryBytes: UInt64
    public let networkBytesPerSecond: UInt64

    // MARK: Display properties

    /// Process display name.
    public let name: String

    /// Formatted CPU usage (e.g. "12%").
    public let cpuDisplay: String

    /// Formatted memory usage (e.g. "45 MB", "1.2 GB").
    public let memoryDisplay: String

    /// Formatted network rate (e.g. "2.3 KB/s", "0 B/s").
    public let networkDisplay: String

    // MARK: Init

    /// Build a fully formatted row from raw process data.
    public init(
        pid: Int32,
        name: String,
        cpuPercent: Double,
        memoryBytes: UInt64,
        networkBytesPerSecond: UInt64
    ) {
        self.id = pid
        self.pid = pid
        self.name = name
        self.cpuPercent = cpuPercent
        self.memoryBytes = memoryBytes
        self.networkBytesPerSecond = networkBytesPerSecond

        self.cpuDisplay = "\(Int(round(cpuPercent)))%"
        self.memoryDisplay = Self.formatBytes(memoryBytes)
        self.networkDisplay = "\(Self.formatBytes(networkBytesPerSecond))/s"
    }

    /// Convenience conversion from a MetricsKit `ProcessInfoSnapshot`.
    init(from process: ProcessInfoSnapshot) {
        self.init(
            pid: process.pid,
            name: process.name,
            cpuPercent: process.cpuPercent,
            memoryBytes: process.memoryBytes,
            networkBytesPerSecond: process.networkBytesPerSecond
        )
    }

    // MARK: - Formatting helpers

    private static func formatBytes(_ bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024, unitIndex < units.count - 1 {
            value /= 1024
            unitIndex += 1
        }
        if unitIndex == 0 { return "\(bytes) B" }
        return String(format: value < 10 ? "%.1f %@" : "%.0f %@", value, units[unitIndex])
    }
}

// MARK: - ProcessesViewModel

/// Main-actor-bound view model that fetches and filters the top processes.
///
/// Free users see at most 5 processes sorted by CPU or memory (no search, no
/// network sort). Pro users see up to 50 processes, can sort by any criterion,
/// and can filter by process name.
@MainActor
public final class ProcessesViewModel: ObservableObject {
    // MARK: Published state

    /// Formatted process rows ready for display.
    @Published public private(set) var rows: [ProcessRowViewModel] = []

    /// Current sort criterion. Free users are limited to `.cpu` / `.memory`.
    @Published public var selectedSort: ProcessSort = .cpu

    /// Search query. Only applies when `isPro` is true.
    @Published public var searchQuery: String = ""

    /// `true` while the monitor is being queried.
    @Published public private(set) var isLoading = false

    /// A user-presentable error message, or `nil`.
    @Published public private(set) var errorMessage: String?

    /// `true` when the returned result set was empty.
    @Published public private(set) var isEmpty = false

    // MARK: Computed properties

    /// Whether the current user holds a Pro entitlement.
    public var isPro: Bool { purchaseState.isPro }

    /// Maximum number of process rows to display.
    public var limit: Int { isPro ? 50 : 5 }

    /// Sort options available to this user.
    public var availableSorts: [ProcessSort] {
        isPro ? [.cpu, .memory, .network] : [.cpu, .memory]
    }

    // MARK: Dependencies

    private let processMonitor: ProcessMonitor?
    private let purchaseState: PurchaseState
    private var cancellables = Set<AnyCancellable>()

    // MARK: Init

    public init(
        processMonitor: ProcessMonitor?,
        purchaseState: PurchaseState
    ) {
        self.processMonitor = processMonitor
        self.purchaseState = purchaseState

        // React to entitlement changes so the UI stays consistent.
        purchaseState.$isPro
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self else { return }
                if !self.isPro, self.selectedSort == .network {
                    self.selectedSort = .cpu
                }
                if !self.isPro {
                    self.searchQuery = ""
                }
            }
            .store(in: &cancellables)
    }

    // MARK: Public API

    /// Refresh the process list by querying the monitor and applying the
    /// current sort, search, and free/pro limits.
    public func refresh() async {
        isLoading = true
        errorMessage = nil

        // Enforce free-tier restrictions defensively.
        if !isPro, selectedSort == .network {
            selectedSort = .cpu
        }

        do {
            guard let monitor = processMonitor else {
                rows = []
                isEmpty = true
                isLoading = false
                return
            }

            let processes = try monitor.top(limit: limit, sort: selectedSort)
            let filtered = applySearchIfNeeded(to: processes)
            rows = filtered.map(ProcessRowViewModel.init(from:))
            isEmpty = rows.isEmpty
        } catch {
            errorMessage = error.localizedDescription
            rows = []
            isEmpty = true
        }

        isLoading = false
    }

    // MARK: Private helpers

    /// When the user is Pro and has a non-empty search query, filter the
    /// process list by name (case-insensitive). Free users always pass through.
    private func applySearchIfNeeded(to processes: [ProcessInfoSnapshot]) -> [ProcessInfoSnapshot] {
        guard isPro, !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty else {
            return processes
        }
        return processes.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
    }
}
