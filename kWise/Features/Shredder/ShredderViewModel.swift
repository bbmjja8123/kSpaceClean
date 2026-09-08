// kWise/Features/Shredder/ShredderViewModel.swift
import Foundation
import AppKit
import Combine
import PowerScope

/// Drives the 文件粉碎 surface (M6, v2.0 Phase 5).
@MainActor
public final class ShredderViewModel: ObservableObject {
    @Published public private(set) var isShredding = false
    @Published public private(set) var progressText: String = ""
    @Published public private(set) var completedMessage: String?
    /// Files staged for shredding (picked via NSOpenPanel).
    @Published public private(set) var stagedURLs: [URL] = []

    /// Passes from preferences (1 = SSD default, 3 = HDD mode).
    public var plan: ShredPlan {
        ShredPlan(passes: UserPreferences.load().shredPasses)
    }

    private let shredder: FileShredder

    public init(scope: (any PowerScopeProviding)? = nil,
                persistence: PersistenceController? = nil) {
        self.shredder = FileShredder(
            scope: scope ?? AppScope.shared.scope,
            persistence: persistence ?? .shared
        )
    }

    // MARK: - Staging

    /// Opens a file picker and stages the selection. The sandbox panel is
    /// the consent mechanism — only files the user explicitly grants are
    /// ever candidates.
    public func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "选择要粉碎的文件（内容将被覆写，不可恢复）"
        guard panel.runModal() == .OK else { return }
        stagedURLs += panel.urls.filter { !stagedURLs.contains($0) }
    }

    public func remove(_ url: URL) {
        stagedURLs.removeAll { $0 == url }
    }

    public func clear() {
        stagedURLs.removeAll()
    }

    // MARK: - Shred

    public func shredStaged() {
        guard !isShredding, !stagedURLs.isEmpty else { return }
        isShredding = true
        completedMessage = nil
        let plan = plan
        let urls = stagedURLs

        Task {
            for await progress in await shredder.shred(urls: urls, plan: plan) {
                await MainActor.run { [weak self] in
                    self?.absorb(progress, total: urls.count)
                }
            }
            await MainActor.run { [weak self] in
                self?.isShredding = false
            }
        }
    }

    private func absorb(_ progress: ShredProgress, total: Int) {
        switch progress.phase {
        case .overwriting(let pass):
            progressText = "正在覆写（第 \(pass) 遍）：\(progress.currentURL.lastPathComponent)"
        case .verifying:
            progressText = "正在校验：\(progress.currentURL.lastPathComponent)"
        case .renaming:
            progressText = "正在随机化文件名：\(progress.currentURL.lastPathComponent)"
        case .trashing:
            progressText = "移入废纸篓：\(progress.currentURL.lastPathComponent)"
        case .done:
            completedMessage = "已完成粉碎 \(total) 个文件"
            stagedURLs.removeAll()
            progressText = ""
        case .failed(let message):
            completedMessage = message
            progressText = ""
        }
    }
}
