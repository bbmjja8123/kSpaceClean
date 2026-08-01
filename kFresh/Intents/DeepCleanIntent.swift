import AppIntents
import Foundation

/// Shortcuts / Siri action: scans the three system directories
/// (`/Library/LaunchAgents`, `/Library/LaunchDaemons`,
/// `/Library/PreferencePanes`) and cleans every non-protected item it
/// finds, returning a one-line summary.
///
/// Safety mirrors ``DeepCleanEngine``: Apple-owned items are never
/// touched, and every deleted item is first backed up into
/// ``BackupManager`` under `DeepCleanEngine.backupBundleID`.
struct DeepCleanIntent: AppIntent {
    static var title: LocalizedStringResource = "深度清理系统启动项"
    static var description = IntentDescription("扫描并清理 /Library 下的 Launch Agents、Launch Daemons 与系统偏好面板项目")

    /// Default audit location — JSONL under the app's Application Support
    /// directory. A logger that cannot be created is silently dropped so
    /// the intent still runs (audit is best-effort, mirroring the engine).
    private static var defaultAuditLogger: AuditLogger? {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let logURL = appSupport
            .appendingPathComponent("app.kraftly.kfresh", isDirectory: true)
            .appendingPathComponent("audit", isDirectory: true)
            .appendingPathComponent("deepclean.jsonl")
        do {
            return try AuditLogger(logURL: logURL)
        } catch {
            return nil
        }
    }

    func perform() async throws -> some IntentResult {
        guard await StoreManager.isProUnlocked() else {
            throw IntentProGateError.proRequired
        }
        let engine = DeepCleanEngine(
            backupManager: BackupManager(),
            auditLogger: Self.defaultAuditLogger
        )
        let items = try await engine.scan()
        let deletable = items.filter { !$0.isProtected }
        guard !deletable.isEmpty else {
            return .result(value: "没有可清理的系统启动项")
        }
        let deleted = try await engine.clean(deletable)
        let size = deletable.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return .result(
            value: "已清理 \(deleted) 项系统启动项，释放 \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))"
        )
    }
}

/// Error thrown when a Pro-gated intent runs without an unlock.
private enum IntentProGateError: LocalizedError {
    case proRequired

    var errorDescription: String? {
        "此操作需要 kFresh Pro。请先在应用内解锁 Pro 后重试。"
    }
}
