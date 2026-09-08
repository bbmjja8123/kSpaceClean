import Foundation
import AppKit

/// View model for the guidance-only maintenance surface (v2.0 Phase 2).
///
/// Two kinds of tasks:
/// * **Guidance** — copies the Terminal command to the pasteboard; kWise
///   cannot run it inside the sandbox and says so on the card.
/// * **Engine-backed** (`userLogClear`) — moves `~/Library/Logs` contents
///   to the Trash via the shared `CleanupEngine`, so the action lands in
///   the 30-day restorable history and consumes free-tier quota.
@MainActor
public final class MaintenanceViewModel: ObservableObject {
    /// The identifier of the task currently running, if any.
    @Published public var runningTask: MaintenanceTask.ID?

    /// Results keyed by task identifier. A present value indicates the
    /// task has completed (either successfully or with an error).
    @Published public var results: [MaintenanceTask.ID: String] = [:]

    /// `true` once the user copied a Terminal command for the task.
    @Published public var copiedCommands: Set<MaintenanceTask.ID> = []

    private(set) var engine: CleanupEngine
    public var onQuotaExhausted: (() -> Void)?

    public init(engine: CleanupEngine? = nil) {
        self.engine = engine ?? CleanupEngine.standard()
    }

    /// Re-point at the shared graph engine (v2.0 Phase 1 DI unification).
    public func useEngine(_ engine: CleanupEngine) {
        self.engine = engine
    }

    /// Copies the task's Terminal command. Guidance tasks only.
    public func copyCommand(for task: MaintenanceTask) {
        guard let command = task.terminalCommand else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copiedCommands.insert(task.id)
    }

    /// Runs the engine-backed action; guidance tasks report the honest
    /// "needs Terminal" outcome instead of pretending.
    public func execute(_ task: MaintenanceTask) async {
        guard task.isEngineBacked else {
            results[task.id] = "需在终端中执行 — 命令已可复制"
            return
        }
        runningTask = task.id
        defer { runningTask = nil }

        do {
            let outcome = try await cleanUserLogs()
            if outcome.successCount > 0 {
                results[task.id] = "已移入废纸篓 \(outcome.successCount) 项 · 释放约 \(formatBytes(outcome.freedBytes))"
            } else if outcome.quotaExhausted {
                results[task.id] = "免费额度已用完，本次未清理"
                onQuotaExhausted?()
            } else {
                results[task.id] = "没有需要清理的日志"
            }
        } catch {
            results[task.id] = "失败: \(error.localizedDescription)"
        }
    }

    /// Whether any task is currently running.
    public var isRunning: Bool {
        runningTask != nil
    }

    /// Removes the result for the given task identifier.
    public func clearResult(for id: MaintenanceTask.ID) {
        results.removeValue(forKey: id)
    }

    // MARK: - Engine-backed: user logs

    /// Enumerates `~/Library/Logs` (inside the granted home scope) and hands
    /// everything to the shared engine. Files only — app-owned log
    /// directories stay untouched to avoid breaking running apps.
    private func cleanUserLogs() async throws -> CleanupOutcome {
        let logsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs", isDirectory: true)
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(
            at: logsURL,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        let targets = contents.compactMap { url -> CleanupTarget? in
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
                  values.isRegularFile == true else { return nil }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))
                .flatMap { $0.fileSize.map(Int64.init) } ?? 0
            return CleanupTarget(url: url, size: size, risk: .recommended)
        }
        guard !targets.isEmpty else { return .empty }
        return try await engine.cleanup(targets: targets)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, bytes), countStyle: .file)
    }
}
