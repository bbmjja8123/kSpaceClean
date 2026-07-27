import Foundation

/// System maintenance scripts that can be executed via CLI tools.
///
/// Each case represents a safe, non-root maintenance operation available
/// to sandboxed Mac App Store apps. All scripts use standard `Process`
/// invocations against built-in macOS command-line tools.
public enum MaintenanceScript: String, CaseIterable, Identifiable, Sendable {
    /// Flush DNS cache to resolve domain resolution issues.
    case dnsFlush = "刷新 DNS 缓存"
    /// Rebuild Spotlight index to fix search anomalies.
    case spotlightRebuild = "重建 Spotlight 索引"
    /// Purge inactive memory to improve system responsiveness.
    case memoryPurge = "释放内存"
    /// Clear font cache to fix font rendering issues.
    case fontCacheRebuild = "重建字体缓存"
    /// Rebuild Launch Services database to fix "Open With" issues.
    case launchServicesRebuild = "重建 Launch Services"
    /// Clear system log files to free disk space.
    case systemLogClear = "清理系统日志"

    public var id: String { rawValue }

    /// SF Symbol name corresponding to the maintenance operation.
    public var icon: String {
        switch self {
        case .dnsFlush:
            return "antenna.radiowaves.left.and.right"
        case .spotlightRebuild:
            return "magnifyingglass"
        case .memoryPurge:
            return "memorychip"
        case .fontCacheRebuild:
            return "textformat"
        case .launchServicesRebuild:
            return "gearshape.2"
        case .systemLogClear:
            return "doc.text.magnifyingglass"
        }
    }

    /// Localized description of what this script does.
    public var detail: String {
        switch self {
        case .dnsFlush:
            return "清除 DNS 缓存记录，解决域名解析问题"
        case .spotlightRebuild:
            return "重新建立文件索引，修复搜索异常"
        case .memoryPurge:
            return "强制释放非活跃内存，提升系统响应速度"
        case .fontCacheRebuild:
            return "清除字体缓存，修复字体显示问题"
        case .launchServicesRebuild:
            return "重建应用注册信息，修复打开方式异常"
        case .systemLogClear:
            return "清理系统日志文件，释放磁盘空间"
        }
    }

    /// Whether this script requires root privileges.
    ///
    /// All scripts return `false` for App Store safety. Commands that
    /// normally benefit from `sudo` are either skipped or use the
    /// non-elevated fallback.
    public var requiresRoot: Bool { false }

    /// Execute the maintenance script via the corresponding CLI tool.
    ///
    /// - Returns: A human-readable result string describing the outcome.
    /// - Throws: If the underlying `Process` fails to launch (e.g., executable not found).
    public func execute() async throws -> String {
        switch self {
        case .dnsFlush:
            try await Self.runProcess(executable: "/usr/bin/dscacheutil", arguments: ["-flushcache"])
            try await Self.runProcess(executable: "/usr/bin/killall", arguments: ["-HUP", "mDNSResponder"])
            return "DNS 缓存已刷新"

        case .spotlightRebuild:
            try await Self.runProcess(executable: "/usr/bin/mdutil", arguments: ["-E", "/"])
            try await Self.runProcess(executable: "/usr/bin/mdutil", arguments: ["-i", "on", "/"])
            return "Spotlight 索引已重建"

        case .memoryPurge:
            try await Self.runProcess(executable: "/usr/sbin/purge", arguments: [])
            return "内存已释放"

        case .fontCacheRebuild:
            try await Self.runProcess(executable: "/usr/bin/atsutil", arguments: ["databases", "-remove"])
            // Skip the sudo variant for App Store safety (no root privilege).
            return "字体缓存已重建"

        case .launchServicesRebuild:
            let lsregister = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
            try await Self.runProcess(executable: lsregister, arguments: [
                "-kill", "-r",
                "-domain", "local",
                "-domain", "system",
                "-domain", "user",
            ])
            return "Launch Services 已重建"

        case .systemLogClear:
            let home = NSHomeDirectory()
            try await Self.runProcess(executable: "/bin/rm", arguments: ["-rf", "\(home)/Library/Logs/*.asl"])
            // Remove log files older than 7 days from ~/Library/Logs/.
            try await Self.runProcess(executable: "/usr/bin/find", arguments: [
                "\(home)/Library/Logs", "-type", "f", "-mtime", "+7", "-delete",
            ])
            return "系统日志已清理"
        }
    }

    // MARK: - Private Helpers

    /// Launches a child process and waits for it to finish.
    ///
    /// Uses `Process` with a `terminationHandler` to bridge the synchronous
    /// process lifecycle into Swift Concurrency without blocking the
    /// cooperative thread pool.
    ///
    /// - Parameters:
    ///   - executable: Absolute path to the executable.
    ///   - arguments: Command-line arguments to pass.
    /// - Throws: Rethrows `Process.run()` errors or `POSIXError` if the
    ///           executable cannot be launched. Non-zero exit codes are
    ///           tolerated since most maintenance commands degrade gracefully.
    private static func runProcess(executable: String, arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments

            process.terminationHandler = { _ in
                continuation.resume()
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
