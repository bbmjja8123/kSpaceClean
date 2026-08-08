import Foundation

public struct ScanProgress: Sendable {
    public enum State: Sendable, Equatable { case idle, scanning, analysing, completed, cancelled, failed(String) }
    public var state: State = .idle
    public var filesDiscovered: Int = 0
    public var totalBytes: Int64 = 0
    public var currentDirectory: String = ""
    public var currentCategory: String = ""
    public var currentSubCategory: String = ""
    public var errors: [ScanError] = []
    public var finishedAt: Date?
    public var speed: ScanSpeed = .medium

    /// Per-category scan progress (for Lemon-style progress list)
    public var categoryProgress: [CategoryProgress] = []

    // v3 UX fields
    /// Current stage (drives 8-stage pill bar)
    public var currentStage: ScanStage = .cache
    /// Full path of file currently being scanned (drives current file bar)
    public var currentNodePath: String?
    /// Real-time stats (drives stats panel)
    public var stats: ScanStats = ScanStats()
}

public struct ScanError: Identifiable, Sendable {
    public let id = UUID()
    public let path: String
    public let message: String
}

/// Tracks progress of one scan category (e.g. "日志&缓存文件")
public struct CategoryProgress: Identifiable, Sendable {
    public let id: Int
    public let title: String
    public var status: ScanItemStatus
    public var subCategories: [SubCategoryProgress]
    public var filesFound: Int
    public var totalSize: Int64
}

/// Tracks progress of one sub-category (e.g. "用户缓存")
public struct SubCategoryProgress: Identifiable, Sendable {
    public let id: Int
    public let title: String
    public var status: ScanItemStatus
}

public enum ScanItemStatus: String, Sendable, Equatable {
    /// Not yet started
    case pending
    /// Currently being scanned
    case scanning
    /// Scan completed successfully
    case completed
    /// Scan failed
    case failed
}

/// 8 scan stages matching the 8 built-in categories
public enum ScanStage: Int, Sendable, CaseIterable, Equatable {
    case cache = 1        // 日志&缓存文件
    case devJunk = 2      // 开发残留垃圾
    case binary = 3       // 无用的二进制文件
    case language = 4     // 无用的程序语言包
    case brokenConfig = 5 // 损坏的配置和注册项
    case iosCache = 6     // iOS升级软件&照片缓存
    case appLeftovers = 7 // 应用程序残留
    case browserCache = 8 // 浏览器缓存

    public var title: String {
        switch self {
        case .cache: return "缓存扫描"
        case .devJunk: return "开发残留"
        case .binary: return "二进制文件"
        case .language: return "语言包"
        case .brokenConfig: return "损坏配置"
        case .iosCache: return "iOS 缓存"
        case .appLeftovers: return "应用残留"
        case .browserCache: return "浏览器缓存"
        }
    }

    public var icon: String {
        switch self {
        case .cache: return "archivebox"
        case .devJunk: return "chevron.left.forwardslash.chevron.right"
        case .binary: return "cpu"
        case .language: return "globe"
        case .brokenConfig: return "exclamationmark.triangle"
        case .iosCache: return "iphone"
        case .appLeftovers: return "app.badge"
        case .browserCache: return "safari"
        }
    }

    /// Initialize from category ID (ScanCategory.id)
    public init?(categoryID: Int) {
        self.init(rawValue: categoryID)
    }
}

/// Real-time scan statistics
public struct ScanStats: Sendable {
    public var discoveredSize: Int64 = 0
    public var fileCount: Int = 0
    public var elapsed: TimeInterval = 0
    public var filesPerSecond: Double = 0

    public init(discoveredSize: Int64 = 0, fileCount: Int = 0,
                elapsed: TimeInterval = 0, filesPerSecond: Double = 0) {
        self.discoveredSize = discoveredSize
        self.fileCount = fileCount
        self.elapsed = elapsed
        self.filesPerSecond = filesPerSecond
    }
}

/// One incremental file-discovery event emitted by a category worker.
/// Consumed by the orchestrator's live progress composer (Task A1) so the
/// progress ring / stats move continuously instead of only at category
/// boundaries.
public struct ScanDelta: Sendable {
    public let categoryID: String
    public let filePath: String
    public let bytesIncrement: Int64
    public let filesIncrement: Int

    public init(categoryID: String, filePath: String, bytesIncrement: Int64, filesIncrement: Int = 1) {
        self.categoryID = categoryID
        self.filePath = filePath
        self.bytesIncrement = bytesIncrement
        self.filesIncrement = filesIncrement
    }
}

/// Pure math for the progress ring / ETA (Task A2). Kept as a static enum
/// so the UI and tests share one implementation with no hidden state.
public enum ScanProgressMath {
    /// Above this many in-flight files the scan is "well into" a category and
    /// the inflight ratio stops dominating the ring.
    public static let inflightFileTarget = 3_000
    /// Expected total file count used to scale the stats-based component.
    public static let statsFileTarget = 20_000

    /// 0...1 completion estimate. Combines three signals so the ring moves
    /// continuously instead of freezing between category boundaries:
    /// - 60%: fraction of categories completed
    /// - 25%: files discovered so far vs `inflightFileTarget` (bounded)
    /// - 15%: stats fileCount vs `statsFileTarget` (bounded)
    public static func completionFraction(
        categoryProgress: [CategoryProgress],
        stats: ScanStats
    ) -> Double {
        let total = categoryProgress.count
        guard total > 0 else { return 0 }
        let done = categoryProgress.filter { $0.status == .completed }.count
        if done == total { return 1.0 }
        let categoryRatio = Double(done) / Double(total)
        let inflightRatio = min(Double(stats.fileCount) / Double(inflightFileTarget), 1)
        let statsRatio = min(Double(stats.fileCount) / Double(statsFileTarget), 1)
        return min(categoryRatio * 0.6 + inflightRatio * 0.25 + statsRatio * 0.15, 1)
    }

    /// Estimated seconds remaining, or `nil` when there is not enough signal
    /// (early scan, stalled speed, or already complete).
    public static func estimatedRemainingSeconds(
        categoryProgress: [CategoryProgress],
        stats: ScanStats
    ) -> TimeInterval? {
        let fraction = completionFraction(categoryProgress: categoryProgress, stats: stats)
        guard fraction >= 0.03, fraction <= 0.999 else { return nil }
        guard stats.filesPerSecond > 0, stats.fileCount > 0 else { return nil }
        let remainingFraction = 1.0 - fraction
        let remainingFiles = Double(stats.fileCount) / fraction * remainingFraction
        return remainingFiles / stats.filesPerSecond
    }

    /// Formats seconds as `m:ss` or `h:mm:ss`.
    public static func formatClock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s >= 3600 {
            return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
        }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
