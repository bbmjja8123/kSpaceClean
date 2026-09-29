@preconcurrency import CoreData
import Foundation
import SwiftUI

@MainActor
public final class CleanupViewModel: ObservableObject {
    @Published public var isCleaning = false
    @Published public var lastResult: TrashResult?
    /// Raw engine outcome of the last structured run — the scan surface's
    /// confirm sheet shows the truthful freed bytes from here (the legacy
    /// `TrashResult` records `fileSize: 0`, so it cannot).
    @Published public private(set) var lastOutcome: CleanupOutcome?
    @Published public var cleanupHistory: [CleanupHistoryItem] = []
    /// Pending cleanup list — set externally (e.g. by the Smart Care
    /// orchestrator's `.confirm()` or the CleanupContentView confirm dialog)
    /// before calling ``cleanupNow()``. Empty list = no-op.
    @Published public var urlsToCleanup: [URL] = []
    /// 归因查询晚绑定（P1 T4）—— RootView `.onAppear` 把它指向归因服务
    /// 的 report；预演 sheet 用它逐项解释「为什么可以回收」。`nil` =
    /// 尚未绑定（预演仍可进行，只是逐项显示「无归因信息」）。
    public var attributionLookup: (() -> [SpaceAttribution])?

    /// 预演暂存（P1 T4）：``makeRehearsal(sizes:urls:)`` 构造并暂存，
    /// ``executeConfirmedCleanup(sizes:)`` 只消费这里的内容 ——
    /// **确认只执行预演过的清单**；sheet 关闭即作废（视图侧丢弃即可，
    /// 下次 makeRehearsal 会整体覆盖）。空 = no-op，绝不兜底。
    @Published public private(set) var pendingTargets: [CleanupTarget] = []

    private let mover = TrashMover()
    private let history = CleanupHistory()
    /// Structured-API engine — used by ``cleanupNow()`` and the
    /// `CleanupContentView` confirmation flow. Defaults to a fresh instance
    /// driven by the shared `PersistenceController`; the app root re-points
    /// it at the graph engine (quota + sinks) in `.onAppear`.
    private(set) var engine: CleanupEngine

    /// Invoked when a run leaves targets behind because the free quota was
    /// exhausted — the root presents the paywall (never the view itself).
    public var onQuotaExhausted: (() -> Void)?

    public init(engine: CleanupEngine? = nil) {
        // Resolve on the main actor so `CleanupEngine.standard()` is legal.
        self.engine = engine ?? CleanupEngine.standard()
    }

    /// Re-point at the shared graph engine (v2.0 Phase 1 DI unification).
    public func useEngine(_ engine: CleanupEngine) {
        self.engine = engine
    }

    public func moveToTrash(urls: [URL]) async {
        isCleaning = true
        let result = await mover.moveToTrash(urls: urls)
        lastResult = result

        // Record each successful move using the actual trash path and file size
        // from the snapshot. The new engine (Task C2) owns history writes for the
        // structured API; this view-model still supports the lightweight
        // TrashMover-driven flow used by some UI surfaces.
        let persistence = PersistenceController.shared
        let context = persistence.newBackgroundContext()
        await context.perform { [persistence] in
            for snapshot in result.snapshots {
                let target = CleanupTarget(
                    url: URL(fileURLWithPath: snapshot.originalPath),
                    size: snapshot.fileSize,
                    risk: .recommended
                )
                persistence.insertHistory(targets: [target], in: context)
            }
            persistence.save(context: context)
        }

        isCleaning = false
        await refreshHistory()
    }

    /// Structured cleanup path — wraps `CleanupEngine.cleanup(targets:)` for
    /// the v1.5 confirmation dialog. Maps `urlsToCleanup` (raw URLs) onto
    /// `CleanupTarget`s, calls into the engine, and refreshes history on
    /// return. Errors are surfaced via `lastResult` for the UI to read.
    ///
    /// - Parameter sizes: scanned size per URL (from the selection), so the
    ///   outcome reports truthful freed bytes without a per-URL syscall
    ///   storm. `nil` = fall back to a per-URL stat.
    ///
    /// P1 T4 — 兼容包装：预演 + 无预演直接执行。不接预演 UI 的调用方
    /// （历史上是 `CleanupContentView.performCleanup()` 一类的旧路径）
    /// 继续可用；接预演的面板改走 ``makeRehearsal(sizes:urls:)`` +
    /// ``executeConfirmedCleanup(sizes:)`` 两段式。
    public func cleanupNow(sizes: [URL: Int64]? = nil) async {
        let urls = urlsToCleanup
        guard !urls.isEmpty else { return }
        _ = await makeRehearsal(sizes: sizes, urls: urls)
        await executeConfirmedCleanup(sizes: sizes)
    }

    /// 预演段（P1 T4）：按 ``cleanupNow(sizes:)`` 的原构造逻辑把入选 URL
    /// 映射成 `CleanupTarget`（含存在性过滤——文件消失的路径不再出现在
    /// 预演里），暂存到 ``pendingTargets``，并逐项挂上归因。
    ///
    /// - Parameters:
    ///   - sizes: 扫描期已知的每 URL 大小；缺省回退单次 stat。
    ///   - urls: 显式传入的清理清单 —— **不读 `urlsToCleanup` 外部状态**
    ///     （历史页静默 no-op 的老坑不再复制）。
    /// - Returns: 与 targets 1:1 同序的预演项（spec §10 P1 验收契约）。
    @discardableResult
    public func makeRehearsal(sizes: [URL: Int64]?, urls: [URL]) async -> [RehearsalItem] {
        // 存在性过滤：消失的路径既不预演也不会执行。
        let existing = urls.filter { (try? $0.checkResourceIsReachable()) == true }
        let targets = existing.map { url -> CleanupTarget in
            let size = sizes?[url]
                ?? (try? url.resourceValues(forKeys: [.fileSizeKey])).flatMap { $0.fileSize.map(Int64.init) }
                ?? 0
            return CleanupTarget(url: url, size: size, risk: .recommended)
        }
        pendingTargets = targets
        return CleanupRehearsal.build(targets: targets, attributions: attributionLookup?() ?? [])
    }

    /// 执行段（P1 T4；r1 修订）：执行集合**以传入的 `confirmedTargets` 为准**
    /// （预演 sheet 上用户取消勾选的子集绝不执行）；未传时回退到
    /// ``pendingTargets``（其语义为「上次预演的全部项」）。空集合 = 直接
    /// 返回：绝不把「上次 targets」或 `urlsToCleanup` 当成兜底重新执行。
    ///
    /// 双击守卫（r1 Important 3）：`@MainActor` 保证进入时同步执行 ——
    /// 先捕获执行集合并立即清空 ``pendingTargets``、置位 ``isCleaning``，
    /// 在途期间的第二次调用（以及执行完成后的重放）都拿不到任何清单。
    ///
    /// - Parameters:
    ///   - sizes: 保留参数（与 ``cleanupNow(sizes:)`` 签名同型，便于调用方
    ///     平移）；执行大小以 target 自带 size 为准，本参数不参与。
    ///   - confirmedTargets: 预演 sheet 确认后传出的勾选子集（nil = 未接
    ///     预演 UI 的兼容路径，用暂存的全量）。
    public func executeConfirmedCleanup(sizes: [URL: Int64]? = nil,
                                        confirmedTargets: [CleanupTarget]? = nil) async {
        guard !isCleaning else { return }
        let toRun = confirmedTargets ?? pendingTargets
        pendingTargets = []
        guard !toRun.isEmpty else { return }
        isCleaning = true
        defer {
            isCleaning = false
            Task { await self.refreshHistory() }
        }
        do {
            let outcome = try await engine.cleanup(targets: toRun)
            self.lastOutcome = outcome
            // Best-effort conversion into the legacy TrashResult shape so the
            // history list view keeps rendering through the existing
            // `lastResult` accessor.
            let succeededSnapshots = outcome.succeeded.map { url in
                TrashSnapshot(
                    originalPath: url.path,
                    trashPath: url.path,
                    fileSize: 0,
                    modifiedAt: Date()
                )
            }
            let failed: [(URL, TrashMover.MoveError)] = outcome.failed.map {
                ($0.url, .trashFailed($0.url, NSError(domain: "CleanupEngine", code: 0)))
            }
            self.lastResult = TrashResult(snapshots: succeededSnapshots, failed: failed)
            self.urlsToCleanup = []
            if outcome.quotaExhausted {
                onQuotaExhausted?()
            }
        } catch {
            // Phase B Task 5: best-effort; UI shows the error via `lastResult`.
            self.lastResult = nil
        }
        // （暂存在进入时已同步清空 —— 双击/重放都拿不到清单。）
    }

    public func refreshHistory() async {
        cleanupHistory = history.fetchRecent()
    }
}
