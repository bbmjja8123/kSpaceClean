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
