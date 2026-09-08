import Foundation
import PowerScope

/// The unified error taxonomy for kWise.
///
/// Every user-visible failure flows through here so the UI can present a
/// localized message plus a recovery suggestion — the previous state of the
/// art was seven unrelated per-module error enums and bare `String`s.
///
/// Module-specific error enums (`TrashError`, `MoveError`,
/// `CleanExecutorError`, …) converge onto this type: their cases become
/// associated values instead of parallel hierarchies.
public enum AppError: Error, LocalizedError, Sendable {
    /// The current PowerScope level does not cover the requested operation.
    case scopeDenied(ScopeRequirement)
    /// The browser owning a privacy database is still running.
    case browserRunning(app: String)
    /// A filesystem operation failed with an underlying Cocoa error.
    case fileSystem(operation: FSOperation, url: URL, underlying: Error)
    /// An external process exited non-zero or timed out.
    case processFailed(command: String, exitCode: Int32?, stderr: String)
    /// StoreKit failure.
    case store(underlying: Error)
    /// The user (or a parent task) cancelled the operation.
    case cancelled
    /// Anything not yet worth its own case. Prefer adding a case over
    /// stuffing context into the string.
    case unexpected(String)

    public enum FSOperation: String, Sendable {
        case read, write, trash, remove, overwrite
    }

    /// What scope level an operation needed versus what it had.
    public struct ScopeRequirement: Sendable {
        public let path: String
        public let currentLevel: ScopeLevel

        public init(path: String, currentLevel: ScopeLevel) {
            self.path = path
            self.currentLevel = currentLevel
        }
    }

    // MARK: LocalizedError

    public var errorDescription: String? {
        switch self {
        case .scopeDenied:
            return String(localized: "error.scopeDenied.description",
                          defaultValue: "此区域尚未授权访问")
        case .browserRunning(let app):
            return String(localized: "error.browserRunning.description",
                          defaultValue: "\(app) 正在运行，无法清理其数据")
        case .fileSystem(let op, let url, _):
            return String(localized: "error.fileSystem.description",
                          defaultValue: "\(op.rawValue) 操作失败：\(url.lastPathComponent)")
        case .processFailed(let command, _, _):
            return String(localized: "error.processFailed.description",
                          defaultValue: "命令 \(command) 执行失败")
        case .store:
            return String(localized: "error.store.description",
                          defaultValue: "订阅服务暂不可用")
        case .cancelled:
            return String(localized: "error.cancelled.description",
                          defaultValue: "操作已取消")
        case .unexpected(let message):
            return message
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .scopeDenied:
            return String(localized: "error.scopeDenied.recovery",
                          defaultValue: "在设置中授权主目录后重试")
        case .browserRunning:
            return String(localized: "error.browserRunning.recovery",
                          defaultValue: "关闭对应浏览器后重试")
        case .fileSystem:
            return String(localized: "error.fileSystem.recovery",
                          defaultValue: "检查文件是否仍存在，或权限是否足够")
        case .processFailed:
            return String(localized: "error.processFailed.recovery",
                          defaultValue: "稍后重试；如持续失败请反馈日志")
        case .store:
            return String(localized: "error.store.recovery",
                          defaultValue: "请检查网络连接或稍后重试")
        case .cancelled, .unexpected:
            return nil
        }
    }
}

/// Convenience: wrap an arbitrary error into the taxonomy.
public extension AppError {
    static func wrapping(_ error: Error,
                         operation: FSOperation,
                         url: URL) -> AppError {
        if let appError = error as? AppError { return appError }
        return .fileSystem(operation: operation, url: url, underlying: error)
    }
}
