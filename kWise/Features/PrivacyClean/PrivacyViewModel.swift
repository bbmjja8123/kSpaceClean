import Foundation
import SwiftUI

// MARK: - PrivacyViewModel

/// Manages the list of privacy-related items discovered by `PrivacyScanner`,
/// their selection state, and the cleanup lifecycle.
///
/// All published properties are updated on the main actor so SwiftUI views
/// can safely observe them.
@MainActor
public final class PrivacyViewModel: ObservableObject {
    @Published public var items: [PrivacyItem] = []
    @Published public var isScanning = false
    @Published public var isCleaning = false
    /// Human-readable message shown when scan or cleanup finishes.
    @Published public var statusMessage: String?
    /// I5（P2 final）：待预演的清单（非 nil → 宿主呈现统一预演 sheet）。
    /// 确认/取消后置回 nil。隐私清理不再有免预演免门控的第二句式。
    @Published public private(set) var rehearsalItems: [RehearsalItem]?

    private let scanner = PrivacyScanner()
    /// 统一清理链（I5）：预演 → executeConfirmedCleanup（引擎 trash +
    /// 清理历史 + 30 天回滚）。引擎语义完全覆盖旧的 `PrivacyScanner.cleanup`
    /// 逐项 trashItem（普通移废纸篓），无安全擦除等引擎覆盖不了的语义。
    public let cleanupViewModel: CleanupViewModel

    public init(cleanupViewModel: CleanupViewModel? = nil) {
        self.cleanupViewModel = cleanupViewModel ?? CleanupViewModel()
    }

    // MARK: - Scan

    /// Starts a background scan that populates `items`.
    ///
    /// The scan runs synchronously on a detached task to avoid blocking the
    /// main actor, then publishes the results back on the main actor.
    public func startScan() {
        guard !isScanning else { return }
        isScanning = true
        items = []
        statusMessage = nil

        // Hold a local Sendable reference to avoid capturing `self` (non-Sendable)
        // across the isolation boundary of the detached task.
        let scanner = self.scanner

        Task { @MainActor in
            let results = await Task.detached {
                scanner.scan()
            }.value

            self.items = results
            self.isScanning = false

            if results.isEmpty {
                self.statusMessage = "未发现可清理的隐私数据"
            } else {
                self.statusMessage = "扫描完成，共发现 \(results.count) 项"
            }
        }
    }

    // MARK: - Selection

    public func toggleSelection(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isSelected.toggle()
    }

    public func selectAll() {
        for index in items.indices {
            items[index].isSelected = true
        }
    }

    public func deselectAll() {
        for index in items.indices {
            items[index].isSelected = false
        }
    }

    // MARK: - Computed

    /// The subset of items that are currently selected.
    public var selectedItems: [PrivacyItem] {
        items.filter(\.isSelected)
    }

    /// Total estimated bytes of all selected items.
    public var selectedSize: Int64 {
        selectedItems.reduce(0) { $0 + $1.estimatedSize }
    }

    /// Items grouped by category, ordered by `PrivacyCategory.displayOrder`.
    public var itemsByCategory: [(PrivacyItem.PrivacyCategory, [PrivacyItem])] {
        let dict = Dictionary(grouping: items) { $0.category }
        return PrivacyItem.PrivacyCategory.displayOrder.compactMap { category in
            guard let group = dict[category], !group.isEmpty else { return nil }
            return (category, group)
        }
    }

    // MARK: - Cleanup（I5：统一预演链 —— 选中项 → CleanupTarget → 预演 sheet → executeConfirmedCleanup）

    /// 选中项 → 预演段：登录态文件（Cookie 等）标 `.caution`（与 C-5 分级
    /// 确认同语义），其余 `.recommended`。产出清单落在 `rehearsalItems`，
    /// 宿主据此呈现统一预演 sheet；此步不动任何文件。
    public func prepareRehearsal() async {
        let toClean = selectedItems
        guard !toClean.isEmpty else { return }
        statusMessage = nil
        let targets = toClean.map { item in
            CleanupTarget(url: item.url,
                          size: item.estimatedSize,
                          risk: item.isLoginState ? .caution : .recommended)
        }
        rehearsalItems = await cleanupViewModel.makeRehearsal(targets: targets)
    }

    /// 预演确认 → 统一链执行段：引擎 trash + 清理历史 + 回滚；成功后把
    /// 已清理项从列表移除（按路径匹配 —— url 清理后可能已不存在）。
    public func confirmRehearsal(_ confirmed: [CleanupTarget]) async {
        rehearsalItems = nil
        guard !confirmed.isEmpty else { return }
        isCleaning = true
        defer { isCleaning = false }
        let outcome = await cleanupViewModel.executeConfirmedCleanup(
            confirmedTargets: confirmed)
        guard let outcome else {
            statusMessage = "清理未能完成，请重试"
            return
        }
        let cleaned = Set(outcome.succeeded.map(\.path))
        items.removeAll { cleaned.contains($0.url.path) }
        statusMessage = "清理完成，已移除 \(outcome.successCount) 项"
    }

    /// 预演取消：丢弃清单，不动任何文件。
    public func cancelRehearsal() {
        rehearsalItems = nil
    }
}
